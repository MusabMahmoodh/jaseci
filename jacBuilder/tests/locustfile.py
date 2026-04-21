"""
JacBuilder Load Test — Locust

All Jaseci walker responses are wrapped:
  {"ok": true, "data": {"reports": [{...actual data...}]}}

Use _unwrap(resp) to get the first report dict.

Run:
    pip install locust
    locust -f locustfile.py --host=https://jac-builder-dev.jaseci.org

Headless:
    locust -f locustfile.py --host=https://jac-builder-dev.jaseci.org \
           --headless -u 3 -r 1 --run-time 5m
"""

import time
import random
import string
import threading
import json
import os
from datetime import datetime, timezone, UTC
from locust import HttpUser, task, between, events
from locust.exception import StopUser

# ---------------------------------------------------------------------------
# Response logger — writes one JSON line per request to test_responses.log
# ---------------------------------------------------------------------------

_run_ts = datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
LOG_FILE = os.path.join(os.path.dirname(__file__), f"test_responses_{_run_ts}.log")
_log_lock = threading.Lock()


def _log(entry: dict):
    entry["ts"] = datetime.now(UTC).isoformat()
    line = json.dumps(entry)
    with _log_lock:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")


def _record(resp, name: str):
    """Log a requests response — call after every client.post()."""
    try:
        report = _unwrap(resp)
    except Exception:
        report = {}
    _log({
        "endpoint": name,
        "status": resp.status_code,
        "elapsed_ms": round(resp.elapsed.total_seconds() * 1000, 1),
        "success": report.get("success"),
        "error": report.get("error"),
        "report": report,
    })


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _rand_suffix(n=6) -> str:
    return "".join(random.choices(string.ascii_lowercase, k=n))


def _unwrap(resp, debug=False) -> dict:
    """Extract the final walker report from Jaseci response envelope.

    Envelope shape:
      {"ok": true, "data": {"reports": [{...}, {...}]}}

    Some walkers emit multiple reports (e.g. ai_chat emits a session creation
    report first, then the actual result). We always want the LAST report which
    is the walker's final `report {}` call and always contains `success`.
    """
    try:
        outer = resp.json()
        reports = outer.get("data", {}).get("reports", [])
        if not reports:
            if debug:
                print(f"[_unwrap] empty reports — full response: {outer}")
            return {}
        # Find the last report that has a 'success' key (the walker result).
        # Fall back to the very last report if none have 'success'.
        for r in reversed(reports):
            if "success" in r:
                return r
        return reports[-1]
    except Exception as e:
        if debug:
            print(f"[_unwrap] exception: {e} — raw: {resp.text[:300]}")
        return {}


# All available templates from assets/templates/manifest.json
# Weighted to reflect realistic usage — frontend templates dominate
TEMPLATES = [
    ("fullstack",        "fullstack"),   # highest priority — 3x weight
    ("fullstack",        "fullstack"),
    ("fullstack",        "fullstack"),
    ("client",           "fullstack"),   # 2x weight
    ("client",           "fullstack"),
    ("preview-template", "fullstack"),
    ("little-x",         "fullstack"),
    ("shadcn-themed",    "fullstack"),
    ("backend-api",      "backend"),
    ("script",           "script"),
]

CHAT_MESSAGES = [
    "Add a button that says Hello World to the main page",
    "Create a simple counter component with increment and decrement buttons",
    "Add a text input that shows what you type in real time",
    "Create a card component with a title and description",
    "Add a navigation bar with Home and About links",
]



# ---------------------------------------------------------------------------
# JacBuilder user flow
# ---------------------------------------------------------------------------

class JacBuilderUser(HttpUser):
    """
    Simulates a single user who:
      1. Registers once on startup
      2. Creates PROJECT_COUNT projects
      3. Continuously runs preview, ai_chat, and file op tasks
    """

    wait_time = between(0.5, 1)

    PROJECT_COUNT = 1     # total projects created (sit in dashboard); increase once server handles load
    ACTIVE_PROJECT_IDX = 0  # index of the one project the user is actively working in
    AI_POLL_TIMEOUT = 120
    AI_POLL_INTERVAL = 0.5  # matches frontend setTimeout(pollOnce, 500)

    def on_start(self):
        self.token = None
        self.user_id = None
        self.projects = []
        self._lock = threading.Lock()

        self.active_project = None   # the one project the user has open in the IDE
        self.preview_running = False  # True only after preview_control [start] + status=running
        self.workspace_ready = False  # True only after ide_file_ops [setup] succeeds

        self._register_and_login()
        self._init_profile()
        self._create_projects()
        _log({
            "endpoint": "credentials",
            "username": self.username,
            "password": self.password,
            "user_id": self.user_id,
            "projects": [p["id"] for p in self.projects],
        })
        print(f"[on_start] Ready — {len(self.projects)} projects | user={self.username} pass={self.password}")

    # -----------------------------------------------------------------------
    # Auth
    # -----------------------------------------------------------------------

    def _register_and_login(self):
        suffix = _rand_suffix()
        self.username = f"loadtest-{suffix}@test.local"
        self.password = "LoadTest123!"

        resp = self.client.post(
            "/user/register",
            json={"username": self.username, "password": self.password},
            name="/user/register",
        )
        _log({"endpoint": "/user/register", "status": resp.status_code,
              "elapsed_ms": round(resp.elapsed.total_seconds() * 1000, 1),
              "username": self.username})
        if resp.status_code in (200, 201):
            self.token = resp.json().get("data", {}).get("token")
            if self.token:
                return

        # Fallback login
        resp = self.client.post(
            "/user/login",
            json={"username": self.username, "password": self.password},
            name="/user/login",
        )
        _log({"endpoint": "/user/login", "status": resp.status_code,
              "elapsed_ms": round(resp.elapsed.total_seconds() * 1000, 1)})
        resp.raise_for_status()
        self.token = resp.json().get("data", {}).get("token")
        if not self.token:
            raise StopUser("Login failed — no token")

    def _auth_headers(self) -> dict:
        return {"Authorization": f"Bearer {self.token}"}

    # -----------------------------------------------------------------------
    # Profile
    # -----------------------------------------------------------------------

    def _init_profile(self):
        resp = self.client.post(
            "/walker/me",
            json={"display_name_hint": "LoadTestUser"},
            headers=self._auth_headers(),
            name="/walker/me",
        )
        resp.raise_for_status()
        report = _unwrap(resp)
        _record(resp, "/walker/me")
        user = report.get("user", {})
        self.user_id = user.get("user_id", "")
        if not self.user_id:
            raise StopUser(f"Could not get user_id from /walker/me: {report}")

    # -----------------------------------------------------------------------
    # Project creation
    # -----------------------------------------------------------------------

    def _create_projects(self):
        for i in range(self.PROJECT_COUNT):
            (template_id, project_type) = random.choice(TEMPLATES)
            name = f"lt-{_rand_suffix()}-{i}"
            # Retry project create up to 3 times — it's slow and prone to 504 under load
            resp = None
            for attempt in range(3):
                if attempt > 0:
                    time.sleep(5 * attempt)  # back off: 5s, 10s
                resp = self.client.post(
                    "/walker/project_ops",
                    json={"action": "create", "name": name, "template_id": template_id},
                    headers=self._auth_headers(),
                    name="/walker/project_ops [create]",
                )
                _record(resp, "/walker/project_ops [create]")
                if resp.status_code == 200:
                    break
                print(f"[create_projects] HTTP {resp.status_code} (attempt {attempt+1})")
            if resp is None or resp.status_code != 200:
                continue
            report = _unwrap(resp)
            if report.get("success") and report.get("project"):
                project = report["project"]
                project["_lt_type"] = project_type   # store for task routing
                self.projects.append(project)
                print(f"[create_projects] Created: {project['id']} ({template_id})")
                # Setup all projects (mirrors _setupProjectWorkspace on mount)
                project["_setup_ok"] = self._setup_project(project["id"])

        # Pick the active project — prefer fullstack/client with successful setup
        priority = [p for p in self.projects if p.get("_setup_ok") and (
                    any(t in p.get("template_id", "") for t in ("fullstack", "client", "preview-template", "little-x", "shadcn-themed")))]
        frontend = [p for p in self.projects if p.get("_setup_ok") and p.get("_lt_type") not in ("backend", "script")]
        any_ready = [p for p in self.projects if p.get("_setup_ok")]
        self.active_project = (priority[0] if priority else None) or (frontend[0] if frontend else None) or (any_ready[0] if any_ready else None) or (self.projects[0] if self.projects else None)

        if self.active_project:
            self.workspace_ready = bool(self.active_project.get("_setup_ok"))
            print(f"[create_projects] Active project: {self.active_project['id']} (workspace_ready={self.workspace_ready})")

        # Start preview only for the active project (user has it open in the IDE)
        if self.active_project and self.active_project.get("_lt_type") not in ("backend", "script"):
            self._start_preview(self.active_project["id"])

    def _setup_project(self, project_id: str) -> bool:
        """Called once per project — mirrors _setupProjectWorkspace() on IDE mount.
        Returns True if setup succeeded (staging dir created server-side)."""
        r = self.client.post(
            "/walker/ide_file_ops",
            json={"action": "setup", "project_id": project_id},
            headers=self._auth_headers(),
            name="/walker/ide_file_ops [setup]",
        )
        _record(r, "/walker/ide_file_ops [setup]")
        ok = r.status_code == 200 and _unwrap(r).get("success", False)
        if ok and self.active_project and self.active_project.get("id") == project_id:
            self.workspace_ready = True
        return ok

    def _start_preview(self, project_id: str):
        """Called once per project — mirrors user clicking Run."""
        resp = self.client.post(
            "/walker/preview_control",
            json={"action": "start", "project_id": project_id},
            headers=self._auth_headers(),
            name="/walker/preview_control [start]",
        )
        _record(resp, "/walker/preview_control [start]")
        report = _unwrap(resp)
        if report.get("success"):
            # Poll status until running (mirrors startWsPolling/pollStatus every 2s)
            for _ in range(10):
                time.sleep(2)
                sr = self.client.post(
                    "/walker/preview_control",
                    json={"action": "status", "project_id": project_id},
                    headers=self._auth_headers(),
                    name="/walker/preview_control [status]",
                )
                _record(sr, "/walker/preview_control [status]")
                if _unwrap(sr).get("status") == "running":
                    self.preview_running = True
                    print(f"[start_preview] {project_id} running")
                    break
        else:
            print(f"[start_preview] failed: {report.get('error')}")

    # -----------------------------------------------------------------------
    # Tasks
    # -----------------------------------------------------------------------

    @task(3)
    def task_preview_status(self):
        """Poll preview status — mirrors the frontend's continuous pollStatus/pollLog loop."""
        if not self.active_project:
            return
        if self.active_project.get("_lt_type") in ("backend", "script"):
            return
        if not self.preview_running:
            return

        r = self.client.post(
            "/walker/preview_control",
            json={"action": "status", "project_id": self.active_project["id"]},
            headers=self._auth_headers(),
            name="/walker/preview_control [status]",
        )
        _record(r, "/walker/preview_control [status]")

    @task(2)
    def task_ai_chat(self):
        """Send AI message to active project → poll until done."""
        if not self.active_project:
            return

        project_id = self.active_project["id"]

        # If workspace setup failed during on_start (e.g. 503 burst), retry once now.
        # ai_chat checks get_preview_dir() which requires ide_file_ops [setup] to have run.
        if not self.workspace_ready:
            ok = self._setup_project(project_id)
            if not ok:
                return  # setup still failing, skip this iteration

        # If preview failed during on_start (e.g. 503 burst), retry once now
        if not self.preview_running and self.active_project.get("_lt_type") not in ("backend", "script"):
            self._start_preview(project_id)
            if not self.preview_running:
                return  # still not up, skip this task iteration

        message = random.choice(CHAT_MESSAGES)

        # Start AI turn
        resp = self.client.post(
            "/walker/ai_chat",
            json={
                "action": "start",
                "project_id": project_id,
                "message": message,
                "current_file_path": "main.jac",
            },
            headers=self._auth_headers(),
            name="/walker/ai_chat [start]",
        )
        _record(resp, "/walker/ai_chat [start]")
        report = _unwrap(resp)
        if not report.get("success"):
            error = report.get("error", "")
            if "already processing" in str(error):
                print(f"[ai_chat] already processing on {project_id}, polling to drain")
                self._poll_ai_until_done(project_id)
            else:
                print(f"[ai_chat] start failed: {error!r} | full report: {report}")
            return

        self._poll_ai_until_done(project_id)

    @task(1)
    def task_file_ops(self):
        """List and read files from the active project."""
        if not self.active_project:
            return

        project_id = self.active_project["id"]

        resp = self.client.post(
            "/walker/ide_file_ops",
            json={"action": "list", "project_id": project_id, "path": "."},
            headers=self._auth_headers(),
            name="/walker/ide_file_ops [list]",
        )
        _record(resp, "/walker/ide_file_ops [list]")
        report = _unwrap(resp)
        files = report.get("files", [])
        if not files:
            return

        target = random.choice(files)
        path = target if isinstance(target, str) else target.get("path", "main.jac")
        r = self.client.post(
            "/walker/ide_file_ops",
            json={"action": "read", "project_id": project_id, "path": path},
            headers=self._auth_headers(),
            name="/walker/ide_file_ops [read]",
        )
        _record(r, "/walker/ide_file_ops [read]")

    @task(1)
    def task_list_projects(self):
        """Dashboard load — list all projects."""
        r = self.client.post(
            "/walker/project_ops",
            json={"action": "list"},
            headers=self._auth_headers(),
            name="/walker/project_ops [list]",
        )
        _record(r, "/walker/project_ops [list]")

    @task(1)
    def task_version_list(self):
        """List versions for the active project."""
        if not self.active_project:
            return

        r = self.client.post(
            "/walker/version_ops",
            json={"action": "list", "project_id": self.active_project["id"]},
            headers=self._auth_headers(),
            name="/walker/version_ops [list]",
        )
        _record(r, "/walker/version_ops [list]")

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _pick_project(self, frontend_only=False):
        with self._lock:
            if not self.projects:
                return None
            pool = [p for p in self.projects if p.get("_lt_type") not in ("backend", "script")] if frontend_only else self.projects
            return random.choice(pool) if pool else None

    def _poll_ai_until_done(self, project_id: str):
        deadline = time.time() + self.AI_POLL_TIMEOUT
        while time.time() < deadline:
            time.sleep(self.AI_POLL_INTERVAL)
            resp = self.client.post(
                "/walker/ai_chat",
                json={"action": "poll", "project_id": project_id},
                headers=self._auth_headers(),
                name="/walker/ai_chat [poll]",
            )
            _record(resp, "/walker/ai_chat [poll]")
            report = _unwrap(resp)
            if report.get("done") or not report.get("processing", True):
                break


# ---------------------------------------------------------------------------
# Smoke test — single user, single project
# ---------------------------------------------------------------------------

class SingleUserSmoke(HttpUser):
    wait_time = between(2, 5)
    weight = 0  # excluded from default runs

    def on_start(self):
        self.token = None
        self.project_id = None

        suffix = _rand_suffix()
        resp = self.client.post(
            "/user/register",
            json={"username": f"smoke-{suffix}@test.local", "password": "Smoke123!"},
        )
        self.token = resp.json().get("data", {}).get("token")

        self.client.post(
            "/walker/me",
            json={"display_name_hint": "Smoke"},
            headers={"Authorization": f"Bearer {self.token}"},
        )

        resp = self.client.post(
            "/walker/project_ops",
            json={"action": "create", "name": f"smoke-{suffix}", "template_id": "preview-template"},
            headers={"Authorization": f"Bearer {self.token}"},
        )
        report = _unwrap(resp)
        self.project_id = report.get("project", {}).get("id")
        print(f"[smoke] project_id={self.project_id}")

    @task
    def smoke_preview_and_chat(self):
        if not self.project_id:
            return

        h = {"Authorization": f"Bearer {self.token}"}
        pid = self.project_id

        self.client.post("/walker/ide_file_ops", json={"action": "setup", "project_id": pid}, headers=h, name="/walker/ide_file_ops [setup]")
        self.client.post("/walker/preview_control", json={"action": "start", "project_id": pid}, headers=h, name="/walker/preview_control [start]")
        time.sleep(3)
        self.client.post("/walker/preview_control", json={"action": "status", "project_id": pid}, headers=h, name="/walker/preview_control [status]")
        resp = self.client.post("/walker/ai_chat", json={"action": "start", "project_id": pid, "message": "Add a hello world heading"}, headers=h, name="/walker/ai_chat [start]")
        report = _unwrap(resp)
        if report.get("success"):
            time.sleep(5)
            self.client.post("/walker/ai_chat", json={"action": "poll", "project_id": pid}, headers=h, name="/walker/ai_chat [poll]")
