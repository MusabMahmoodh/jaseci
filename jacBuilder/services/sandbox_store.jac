"""Sandbox Store — Graph-based sandbox state management.

Replaces all in-memory dicts (_sandbox_id_map, _staging_dirs, _preview_registry,
_sandbox_deploy_id_map, _sandbox_deploy_staging) with SandboxInstance graph nodes
that auto-persist to MongoDB via Jac's built-in node persistence.

Every pod can discover every sandbox by querying [-->(?:SandboxInstance)] on the
global root. No populate_from_shared() needed — the graph IS the shared state.
"""

import os;
import time;
import hashlib;
import shutil;
import from typing { Any }

# ---------------------------------------------------------------------------
# Lazy sandbox backend (stateless K8s operations only)
# ---------------------------------------------------------------------------

glob _sandbox_backend: Any = None;
glob _is_k8s: bool = False;
glob _domain_template: str = "";

def _get_backend() -> Any {
    global _sandbox_backend;
    global _is_k8s;
    global _domain_template;
    if _sandbox_backend is None {
        try {
            import from sandbox.factories.sandbox_factory { SandboxFactory }
            import from jac_scale.config_loader { get_scale_config }
            scale_config = get_scale_config();
            cfg = scale_config._config if hasattr(scale_config, "_config") else scale_config;
            sandbox_cfg: dict = dict(cfg.get("sandbox", {})) if isinstance(cfg, dict) else {};
            if sandbox_cfg and sandbox_cfg.get("enabled", False) {
                sandbox_type = str(sandbox_cfg.get("type", "local"));
                env_type = str(os.environ.get("JAC_SANDBOX_TYPE", "")).strip();
                if env_type {
                    sandbox_type = env_type;
                }
                _sandbox_backend = SandboxFactory.create(sandbox_type, sandbox_cfg);
                _is_k8s = sandbox_type in ("kubernetes", "docker");
                _domain_template = str(sandbox_cfg.get("domain_template", ""));
            } else {
                _sandbox_backend = SandboxFactory.create("local", {});
            }
        } except (ImportError, Exception) as e {
            print(f"[sandbox_store] Backend init failed: {e}, using local fallback");
            try {
                import from sandbox.providers.local_sandbox { LocalSandbox }
                import from sandbox.abstractions.models.sandbox_config { SandboxConfig }
                _sandbox_backend = LocalSandbox(config=SandboxConfig());
            } except (ImportError, Exception) as e2 {
                print(f"[sandbox_store] Local fallback also failed: {e2}");
                _sandbox_backend = None;
            }
        }
    }
    return _sandbox_backend;
}

# ---------------------------------------------------------------------------
# Configuration from jac.toml (via jac-scale config_loader)
# ---------------------------------------------------------------------------

def _get_sandbox_config() -> dict {
    try {
        import from jac_scale.config_loader { get_scale_config }
        scale_config = get_scale_config();
        cfg = scale_config._config if hasattr(scale_config, "_config") else scale_config;
        return cfg.get("sandbox", {}) if isinstance(cfg, dict) else {};
    } except Exception {
        return {};
    }
}

def _max_per_user(purpose: str) -> int {
    cfg = _get_sandbox_config();
    if purpose == "deploy" {
        return int(cfg.get("max_per_user_deploy", 5));
    }
    return int(cfg.get("max_per_user", 3));
}

def _default_ttl(purpose: str) -> int {
    if purpose == "deploy" {
        return 604800;
    }
    return 1800;
}

# ---------------------------------------------------------------------------
# Env Merge (global + project → staging .env)
# ---------------------------------------------------------------------------

"""Merge user's global.env and project .env into the staging directory.
Global vars load first, project vars override. Result written to {staging_dir}/.env.
Reads from shared EFS — stateless, works from any pod."""
def _merge_env_to_staging(user_id: str, staging_dir: str) -> None {
    import from pathlib { Path }
    merged: dict = {};
    # Read global env (lowest priority)
    global_path = os.path.join(str(Path.home()), ".jac-ide", "users", user_id, "global.env");
    if os.path.isfile(global_path) {
        try {
            with open(global_path, "r") as gf {
                for line in gf.readlines() {
                    line = line.strip();
                    if line and not line.startswith("#") and "=" in line {
                        (k, v) = line.split("=", 1);
                        merged[k.strip()] = v.strip();
                    }
                }
            }
        } except Exception {
            x = 0;
        }
    }
    # Read project env (overrides global)
    project_env = os.path.join(staging_dir, ".env");
    if os.path.isfile(project_env) {
        try {
            with open(project_env, "r") as pf {
                for line in pf.readlines() {
                    line = line.strip();
                    if line and not line.startswith("#") and "=" in line {
                        (k, v) = line.split("=", 1);
                        merged[k.strip()] = v.strip();
                    }
                }
            }
        } except Exception {
            x = 0;
        }
    }
    # Write merged env to staging (ConfigMap will pick it up)
    if merged {
        with open(os.path.join(staging_dir, ".env"), "w") as mf {
            for k in merged {
                mf.write(f"{k}={merged[k]}\n");
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Deterministic Sandbox ID
# ---------------------------------------------------------------------------

"""Same inputs always produce same ID. Retry-safe, no UUID randomness."""
def sandbox_id_for(user_id: str, project_id: str, purpose: str) -> str {
    raw = f"{user_id}:{project_id}:{purpose}";
    h = hashlib.sha256(raw.encode()).hexdigest()[:12];
    return f"jac-sbx-{purpose[0]}-{h}";
}

# ---------------------------------------------------------------------------
# URL Builder
# ---------------------------------------------------------------------------

def build_sandbox_url(sandbox_id: str) -> str {
    if not _domain_template {
        _get_backend();
    }
    if not _domain_template {
        return "";
    }
    url = _domain_template.replace("{sandbox_id}", sandbox_id);
    if not url.startswith("http") {
        url = f"https://{url}";
    }
    return url;
}

# ---------------------------------------------------------------------------
# Local read-through cache (per-pod, 15s TTL)
# ---------------------------------------------------------------------------

glob _cache: dict = {};
glob _CACHE_TTL: float = 15.0;

def _cache_get(sid: str) -> dict {
    entry: Any = _cache.get(sid);
    if entry is not None {
        ts: float = float(entry["ts"]);
        if (time.time() - ts) < _CACHE_TTL {
            return dict(entry["data"]);
        }
    }
    return {};
}

def _cache_put(sid: str, data: dict) -> None {
    _cache[sid] = {"data": data, "ts": time.time()};
}

def _cache_invalidate(sid: str) -> None {
    _cache.pop(sid, None);
}

# ---------------------------------------------------------------------------
# Graph Query Helpers (called from walker context)
# ---------------------------------------------------------------------------

"""Find a SandboxInstance by sandbox_id from a pre-fetched list."""
def find_sandbox_node(all_instances: list, sandbox_id: str) -> Any {
    import from services.ideServer { SandboxInstance }
    for raw in all_instances {
        inst: SandboxInstance = raw;
        if inst.sandbox_id == sandbox_id and inst.desired_state != "destroyed" {
            return inst;
        }
    }
    return None;
}

"""Find a SandboxInstance for a specific user/project/purpose triple.
Prefers running > starting/creating > stopped. Old stopped nodes
pile up in the graph and must not shadow the active sandbox."""
def find_sandbox_for_project(all_instances: list, user_id: str, project_id: str, purpose: str) -> Any {
    import from services.ideServer { SandboxInstance }
    best: Any = None;
    best_rank: int = -1;
    for raw in all_instances {
        inst: SandboxInstance = raw;
        if inst.user_id == user_id and inst.project_id == project_id and inst.purpose == purpose and inst.desired_state != "destroyed" {
            state = str(inst.desired_state);
            if state == "running" {
                return inst;
            }
            rank: int = 0;
            if state in ("starting", "creating") {
                rank = 2;
            } elif state == "stopped" {
                rank = 1;
            }
            if rank > best_rank {
                best = inst;
                best_rank = rank;
            }
        }
    }
    return best;
}

"""Count active (non-destroyed) sandboxes for a user with given purpose."""
def count_user_sandboxes(all_instances: list, user_id: str, purpose: str) -> int {
    import from services.ideServer { SandboxInstance }
    cnt: int = 0;
    for raw in all_instances {
        inst: SandboxInstance = raw;
        if inst.user_id == user_id and inst.purpose == purpose and inst.desired_state != "destroyed" {
            cnt = int(cnt) + 1;
        }
    }
    return cnt;
}

# ---------------------------------------------------------------------------
# Core Operations (called from walker context with graph access)
# ---------------------------------------------------------------------------

"""Get or create a sandbox. Idempotent — returns existing if found.

Creates K8s resources SYNCHRONOUSLY so the URL is available immediately.
The caller (walker) must create the SandboxInstance graph node using the
returned `_create_params` dict: `here ++> SandboxInstance(**result["_create_params"])`.

Returns dict: success, sandbox_id, url, port, status, message, _create_params (if new)."""
def ensure_sandbox(all_instances: list,
                   user_id: str, project_id: str,
                   purpose: str = "preview",
                   source_dir: str = "",
                   worktree_path: str = "",
                   ttl_seconds: int = 0) -> dict {
    ttl = ttl_seconds if ttl_seconds > 0 else _default_ttl(purpose);

    # Always create a fresh sandbox — no reuse of existing ones.
    # The graph node idempotency check was causing cross-user leaks because
    # the Jac WS execution context doesn't properly isolate user roots.

    # --- Sweep stale nodes before limit check ---
    # Verify pods still exist for this user's active nodes. Batch K8s query
    # (one API call) then mark orphaned nodes as destroyed so they don't
    # count against the per-user limit.
    if _is_k8s {
        try {
            backend_check = _get_backend();
            if backend_check is not None {
                backend_check._init_k8s();
                import from kubernetes { client as k8s_client }
                core_v1_check = k8s_client.CoreV1Api();
                ns_check = os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");
                live_pods = core_v1_check.list_namespaced_pod(
                    ns_check,
                    label_selector=f"jac-sandbox=true,jac-sandbox-user={user_id}"
                );
                live_sids: set = set();
                for lp in live_pods.items {
                    lp_labels = lp.metadata.labels or {};
                    lp_sid = lp_labels.get("jac-sandbox-id", "");
                    if lp_sid {
                        live_sids.add(lp_sid);
                    }
                }
                import from services.ideServer { SandboxInstance }
                for raw_inst in all_instances {
                    si_check: SandboxInstance = raw_inst;
                    if si_check.user_id == user_id and si_check.purpose == purpose and si_check.desired_state != "destroyed" {
                        if si_check.sandbox_id not in live_sids {
                            si_check.desired_state = "destroyed";
                            si_check.observed_state = "stopped";
                            si_check.error_message = "Pod no longer exists";
                        }
                    }
                }
            }
        } except Exception as e {
            import logging;
            logging.getLogger("sandbox_store").warning(f"Stale node sweep failed: {e}");
        }
    }

    # --- Enforce per-user limit ---
    max_allowed = _max_per_user(purpose);
    current_count = count_user_sandboxes(all_instances, user_id, purpose);
    if current_count >= max_allowed {
        return {
            "success": False, "sandbox_id": "", "url": "", "port": 0,
            "status": "rejected",
            "message": f"Limit reached: {current_count}/{max_allowed} {purpose} sandboxes"
        };
    }

    # --- Resolve source directory ---
    effective_dir = "";
    is_wt = False;
    if worktree_path and os.path.isdir(worktree_path) {
        effective_dir = worktree_path;
        is_wt = True;
    } elif source_dir and os.path.isdir(source_dir) {
        effective_dir = source_dir;
    }
    if not effective_dir {
        return {
            "success": False, "sandbox_id": "", "url": "", "port": 0,
            "status": "error", "message": "No valid project directory provided"
        };
    }

    # --- Staging dir for deploy sandboxes (copy project) ---
    staging = effective_dir;
    if purpose == "deploy" {
        staging = f"/tmp/jac-sandbox-deploy-{user_id}-{project_id}";
        if os.path.exists(staging) {
            shutil.rmtree(staging, ignore_errors=True);
        }
        shutil.copytree(effective_dir, staging,
            ignore=shutil.ignore_patterns(".git", ".jac-ide", "__pycache__", ".jac"));
    }

    # --- Merge global + project env vars into staging .env ---
    # Global vars are user-scoped on shared EFS; project vars are in repo.
    # Merged file goes into staging dir so the ConfigMap carries it to the pod.
    _merge_env_to_staging(user_id, staging);

    # --- Create K8s resources synchronously ---
    backend = _get_backend();
    if backend is None {
        return {
            "success": False, "sandbox_id": "", "url": "", "port": 0,
            "status": "error", "message": "Sandbox backend not available"
        };
    }

    # Each user always gets their own sandbox — no K8s pre-check.
    # Idempotency is handled by the graph node check above (user-root scoped).
    result = backend.create(user_id, project_id, staging);
    if not result.is_successful() {
        return {
            "success": False, "sandbox_id": "", "url": "", "port": 0,
            "status": "error", "message": result.message or "Failed to create sandbox"
        };
    }

    # Build URL — use the actual sandbox_id from the backend (not deterministic)
    actual_sid = str(result.sandbox_id or "");
    url = result.url or "";
    if not url and _is_k8s {
        url = build_sandbox_url(actual_sid);
    }
    port = result.port or 8000;

    owner_pod = os.environ.get("HOSTNAME", os.environ.get("POD_NAME", "local"));
    _cache_invalidate(actual_sid);
    print(f"[sandbox_store] Created sandbox sid={actual_sid} purpose={purpose} url={url}");

    # Return creation params for the walker to create the graph node
    return {
        "success": True,
        "sandbox_id": actual_sid,
        "url": url,
        "port": port,
        "status": "starting",
        "message": "created",
        "_create_params": {
            "sandbox_id": actual_sid,
            "user_id": user_id,
            "project_id": project_id,
            "purpose": purpose,
            "namespace": os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes"),
            "desired_state": "running",
            "observed_state": "starting",
            "url": url,
            "port": port,
            "staging_dir": staging,
            "source_dir": effective_dir,
            "is_worktree": is_wt,
            "worktree_path": worktree_path if is_wt else "",
            "created_at": time.time(),
            "last_heartbeat": time.time(),
            "owner_pod": owner_pod,
            "ttl_seconds": ttl
        }
    };
}

"""Stop a sandbox — destroys K8s resources synchronously and marks node stopped."""
def stop_sandbox(all_instances: list, sandbox_id: str) -> dict {
    sbx_node = find_sandbox_node(all_instances, sandbox_id);
    backend = _get_backend();
    # Even if no graph node, try to clean up K8s resources
    if backend is not None {
        try {
            backend.stop(sandbox_id);
        } except Exception as e {
            print(f"[sandbox_store] K8s stop failed for {sandbox_id}: {e}");
        }
    }
    if sbx_node is not None {
        sbx_node.desired_state = "stopped";
        sbx_node.observed_state = "stopped";
    }
    _cache_invalidate(sandbox_id);
    print(f"[sandbox_store] Stopped sandbox sid={sandbox_id}");
    return {"success": True, "status": "stopped"};
}

"""Destroy a sandbox — deletes K8s resources synchronously and marks node destroyed."""
def destroy_sandbox(all_instances: list, sandbox_id: str) -> dict {
    sbx_node = find_sandbox_node(all_instances, sandbox_id);
    backend = _get_backend();
    if backend is not None {
        try {
            if _is_k8s {
                backend.destroy(sandbox_id);
            } else {
                backend.stop(sandbox_id);
            }
        } except Exception as e {
            print(f"[sandbox_store] K8s destroy failed for {sandbox_id}: {e}");
        }
    }
    if sbx_node is not None {
        sbx_node.desired_state = "destroyed";
        sbx_node.observed_state = "stopped";
    }
    _cache_invalidate(sandbox_id);
    print(f"[sandbox_store] Destroyed sandbox sid={sandbox_id}");
    return {"success": True, "status": "destroyed"};
}

"""Get current sandbox status from graph. If node says 'starting', checks K8s directly
and updates the node inline (the calling walker has write access)."""
def get_status(all_instances: list, sandbox_id: str) -> dict {
    cached = _cache_get(sandbox_id);
    if cached {
        return cached;
    }

    sbx_node = find_sandbox_node(all_instances, sandbox_id);
    if sbx_node is None {
        return {"running": False, "url": "", "port": 0, "status": "none"};
    }

    obs = str(sbx_node.observed_state);

    # Verify pod state with K8s for any non-terminal state.
    # For "running": only checked when cache expires (15s TTL) — no extra API load.
    # For "starting"/"creating": checked every poll (no cache entry exists yet).
    if obs in ("starting", "creating", "running") and sbx_node.desired_state != "destroyed" {
        backend = _get_backend();
        if _is_k8s {
            try {
                if backend is not None {
                    backend._init_k8s();
                    import from kubernetes { client }
                    core_v1 = client.CoreV1Api();
                    namespace = os.environ.get("SANDBOX_NAMESPACE", "jac-sandboxes");
                    pods = core_v1.list_namespaced_pod(
                        namespace,
                        label_selector=f"jac-sandbox-id={sandbox_id}"
                    );
                    if len(pods.items) == 0 {
                        # Pod no longer exists — mark node as destroyed
                        sbx_node.desired_state = "destroyed";
                        sbx_node.observed_state = "stopped";
                        sbx_node.error_message = "Pod no longer exists";
                        obs = "stopped";
                    } else {
                        for pod in pods.items {
                            phase = str(pod.status.phase) if pod.status else "Unknown";
                            if phase == "Running" {
                                ready = True;
                                if pod.status.container_statuses {
                                    for cs in pod.status.container_statuses {
                                        if not cs.ready {
                                            ready = False;
                                            break;
                                        }
                                    }
                                }
                                if ready {
                                    sbx_node.observed_state = "running";
                                    if not sbx_node.pod_name {
                                        sbx_node.pod_name = pod.metadata.name;
                                    }
                                    obs = "running";
                                }
                            } elif phase in ("Failed", "Succeeded") {
                                sbx_node.observed_state = "error";
                                sbx_node.error_message = f"Pod phase: {phase}";
                                obs = "error";
                            }
                            break;
                        }
                    }
                }
            } except Exception as e {
                import logging;
                logging.getLogger("sandbox_store").error(f"K8s status check failed for {sandbox_id}: {e}");
            }
        } elif obs in ("starting", "creating") {
            # Local sandbox — check backend registry for state transitions
            try {
                if backend is not None {
                    local_status = backend.status(sandbox_id);
                    if hasattr(local_status, "state") {
                        local_state_val = str(local_status.state.value) if hasattr(local_status.state, "value") else str(local_status.state);
                        if local_state_val == "running" {
                            sbx_node.observed_state = "running";
                            obs = "running";
                        } elif local_state_val in ("error", "stopped") {
                            sbx_node.observed_state = "error";
                            sbx_node.error_message = "Sandbox process stopped";
                            obs = "error";
                        }
                    }
                }
            } except Exception as e {
                import logging;
                logging.getLogger("sandbox_store").error(f"Local status check failed for {sandbox_id}: {e}");
            }
        }
        _cache_invalidate(sandbox_id);
    }

    url = sbx_node.url;
    if not url and _is_k8s {
        url = build_sandbox_url(sandbox_id);
    }

    result = {
        "running": obs == "running",
        "url": url,
        "port": sbx_node.port,
        "api_port": 0,
        "status": obs,
        "desired_state": sbx_node.desired_state,
        "error_message": sbx_node.error_message,
        "created_at": sbx_node.created_at,
        "ttl_seconds": sbx_node.ttl_seconds,
        "purpose": sbx_node.purpose,
        "sandbox_id": sandbox_id
    };
    if obs == "running" {
        _cache_put(sandbox_id, result);
    }
    return result;
}

"""Get sandbox status for a user/project/purpose triple."""
def get_status_for_project(all_instances: list, user_id: str, project_id: str, purpose: str = "preview") -> dict {
    sbx_node = find_sandbox_for_project(all_instances, user_id, project_id, purpose);
    if sbx_node is None {
        return {"running": False, "url": "", "port": 0, "status": "none"};
    }
    return get_status(all_instances, str(sbx_node.sandbox_id));
}

"""List all active sandboxes for a user."""
def list_user_sandboxes(all_instances: list, user_id: str) -> list {
    import from services.ideServer { SandboxInstance }
    results: list = [];
    for raw_inst in all_instances {
        inst: SandboxInstance = raw_inst;
        if inst.user_id == user_id and inst.desired_state != "destroyed" {
            url = inst.url;
            if not url and _is_k8s {
                url = build_sandbox_url(inst.sandbox_id);
            }
            results.append({
                "sandbox_id": inst.sandbox_id,
                "project_id": inst.project_id,
                "purpose": inst.purpose,
                "status": inst.observed_state,
                "url": url,
                "created_at": inst.created_at,
                "ttl_seconds": inst.ttl_seconds
            });
        }
    }
    return results;
}

"""Get the staging directory for a sandbox. Used for file ops."""
def get_staging_dir(all_instances: list, user_id: str, project_id: str, purpose: str = "preview") -> str {
    sbx_node = find_sandbox_for_project(all_instances, user_id, project_id, purpose);
    if sbx_node is not None {
        return sbx_node.staging_dir;
    }
    return "";
}

"""Get the original source directory for a sandbox."""
def get_source_dir(all_instances: list, user_id: str, project_id: str, purpose: str = "preview") -> str {
    sbx_node = find_sandbox_for_project(all_instances, user_id, project_id, purpose);
    if sbx_node is not None {
        return sbx_node.source_dir;
    }
    return "";
}

"""Update the last_heartbeat timestamp. Called from WS polling."""
def update_heartbeat(all_instances: list, sandbox_id: str) -> None {
    sbx_node = find_sandbox_node(all_instances, sandbox_id);
    if sbx_node is not None {
        sbx_node.last_heartbeat = time.time();
    }
}

# ---------------------------------------------------------------------------
# Warm Pool Initialization (delegates to backend)
# ---------------------------------------------------------------------------

"""Eagerly initialize K8s sandbox and warm pool at server startup."""
def init_warmpool() -> None {
    import threading;
    backend = _get_backend();
    if backend is None {
        return;
    }
    if hasattr(backend, "_ensure_warm_pool") {
        t = threading.Thread(target=_warmpool_startup, args=(backend,), daemon=True);
        t.start();
        print("[sandbox_store] Warm pool prefill started");
    }
}

"""Wait for SA token then initialize K8s and warm pool."""
def _warmpool_startup(backend: Any) -> None {
    token_path = "/var/run/secrets/kubernetes.io/serviceaccount/token";
    kubeconfig_path = "/root/.kube/config";
    max_wait = 300;
    waited = 0;
    while waited < max_wait {
        if os.path.exists(token_path) or os.path.exists(kubeconfig_path) {
            break;
        }
        time.sleep(5);
        waited = int(waited) + 5;
    }
    if waited >= max_wait {
        print("[sandbox_store] Warm pool skipped — no K8s credentials found");
        return;
    }
    try {
        if hasattr(backend, "_init_k8s") {
            backend._init_k8s();
        }
        if hasattr(backend, "_ensure_namespace") {
            backend._ensure_namespace();
        }
        if hasattr(backend, "_ensure_warm_pool") {
            backend._ensure_warm_pool();
        }
        print("[sandbox_store] K8s warm pool initialized successfully");
    } except Exception as e {
        print(f"[sandbox_store] Warm pool init failed: {e}");
    }
}

# ---------------------------------------------------------------------------
# Backend accessor (for reconciler and file_sync to call K8s operations)
# ---------------------------------------------------------------------------

"""Public accessor for the sandbox backend (SandboxFactory instance)."""
def get_backend() -> Any {
    return _get_backend();
}

"""Check if the sandbox backend is K8s or Docker."""
def is_k8s_sandbox() -> bool {
    _get_backend();
    return _is_k8s;
}

"""Query MongoDB directly for a SandboxInstance — bypasses stale Jac graph cache.
Used as fallback when [-->(?:SandboxInstance)] returns empty due to L1 cache
holding a stale edge list (edges created by other request contexts are invisible)."""
def find_sandbox_id_from_db(user_id: str, project_id: str, purpose: str = "preview") -> dict {
    try {
        import pymongo;
        mongo_uri = os.environ.get("MONGODB_URI", "");
        if not mongo_uri {
            return {};
        }
        client = pymongo.MongoClient(mongo_uri, serverSelectionTimeoutMS=3000);
        db = client["jac_db"];
        doc = db["_anchors"].find_one({
            "data.archetype.__type__": "SandboxInstance",
            "data.archetype.user_id": user_id,
            "data.archetype.project_id": project_id,
            "data.archetype.purpose": purpose,
            "data.archetype.desired_state": {"$nin": ["destroyed"]}
        }, sort=[("data.archetype.created_at", -1)]);
        if doc {
            a = doc["data"]["archetype"];
            return {
                "sandbox_id": a.get("sandbox_id", ""),
                "url": a.get("url", ""),
                "observed_state": a.get("observed_state", ""),
                "desired_state": a.get("desired_state", "")
            };
        }
    } except Exception as e {
        print(f"[sandbox_store] MongoDB direct query failed: {e}");
    }
    return {};
}
