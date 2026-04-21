"""Backend server for Jac IDE - file ops, templates, projects, and versions."""

import os;
import time;
import shutil;
import threading;
import base64;
import tempfile;
import subprocess;
import from datetime {datetime}
import from jaclang { JacRuntime as Jac }
import from services.preview_manager {
    setup_preview,
    write_preview_file,
    write_preview_file_binary,
    preview_mkdir,
    start_preview,
    stop_preview,
    get_preview_status,
    cleanup_preview,
    list_preview_files,
    search_preview_files,
    replace_in_preview_files,
    read_preview_file,
    delete_preview_file,
    get_preview_log,
    rename_preview_item,
    mark_needs_install,
    get_preview_dir,
    _preview_key,
    _preview_registry
}
import from services.project_manager {
    list_templates,
    get_template,
    list_user_templates,
    get_user_template,
    save_user_template,
    create_project_workspace,
    create_project_from_jacpack,
    delete_project_workspace,
    autosave_version,
    create_project_snapshot,
    record_project_version,
    list_project_versions,
    checkout_project_commit,
    export_project_jacpack,
    get_project_status,
    read_project_env,
    write_project_env,
    save_project_thumbnail,
    get_project_thumbnail,
    has_project_thumbnail,
    get_projects_root,
    create_project_from_zip
}
import from services.jaccoder_adapter {
    get_or_create_session,
    start_jaccoder_async,
    stop_jaccoder,
    drain_events,
    is_ai_processing,
    clear_session
}
import from services.community_manager {
    list_community_templates,
    get_community_template,
    submit_community_template,
    get_community_jacpack_path,
    increment_clone_count,
    remove_community_template
}
import from services.deploy_manager {
    deploy_async,
    destroy_deployment,
    get_deployment_status,
    generate_deploy_identifiers,
    get_deploy_result
}
import from services.screenshot_service {
    take_screenshot,
    MCP_SERVER_URL
}
import from services.lsp_manager {
    start_lsp,
    stop_lsp,
    send_lsp_message,
    wait_lsp_response,
    drain_lsp_notifications,
    get_lsp_status,
    cleanup_stale_lsp,
    stop_all_lsp_except
}
import from services.file_watcher {
    start_watcher,
    stop_watcher,
    drain_file_events
}
import from services.claude_adapter {
    send_claude_turn,
    drain_claude_events,
    is_claude_processing,
    interrupt_claude,
    stop_claude_session,
    clear_claude_session,
    get_claude_session_info,
    check_claude_availability
}
import from services.git_service {
    git_status,
    git_branches,
    git_create_branch,
    git_checkout,
    git_diff,
    git_diff_working,
    git_diff_staged,
    git_diff_last_commit,
    git_commit,
    git_stage_file,
    git_unstage_file,
    git_commit_staged,
    git_push,
    git_pull,
    git_log,
    git_remote_add,
    git_remote_remove,
    git_remotes,
    git_create_checkpoint,
    git_restore_checkpoint,
    git_checkpoint_diff,
    git_create_worktree,
    git_remove_worktree,
    git_list_worktrees,
    git_merge,
    git_delete_branch,
    git_head_sha,
    git_revert_to_commit,
    is_git_repo,
    git_show_file,
    git_read_working_file
}
import from services.github_service {
    github_exchange_code,
    github_get_user,
    github_list_repos,
    github_create_repo,
    github_create_pr,
    github_push,
    github_pull,
    github_clone,
    run_git_authenticated,
    github_revoke_token,
    github_check_repo_exists,
    github_refresh_user_token,
    encrypt_token,
    decrypt_token
}
import from uuid { uuid4 }
import re;
import from services.session_manager { touch_session, remove_session }

# WS auth tokens — maps user_id -> dict[token -> creation_timestamp].
# Multiple tokens per user allow concurrent browser tabs.
# Tokens expire after _WS_TOKEN_TTL seconds and are cleaned up on validation.
# Generated in `me` walker (JWT-authenticated), validated in pub WS walkers.
glob _ws_auth_tokens: dict = {};
glob _WS_TOKEN_TTL: float = 86400.0;  # 24 hours
glob _WS_MAX_TOKENS_PER_USER: int = 20;

# Project count cache — maps user_id -> int.
# Initialized from filesystem on first access, then tracked in memory.
# Needed because graph traversal doesn't persist in local dev (Anchor.persistent=False).
glob _project_counts: dict = {};
glob MAX_PROJECTS_PER_USER: int = 3;

"""Get the current project count for a user. Initializes from filesystem if not cached."""
def _get_project_count(user_id: str) -> int {
    if user_id in _project_counts {
        return _project_counts[user_id];
    }
    projects_root = get_projects_root();
    user_dir = os.path.join(projects_root, user_id);
    count = 0;
    if os.path.isdir(user_dir) {
        for entry in os.listdir(user_dir) {
            if entry.startswith("prj_") and os.path.isdir(os.path.join(user_dir, entry)) {
                count += 1;
            }
        }
    }
    _project_counts[user_id] = count;
    return count;
}

"""Validate a WS token for a user. Checks local cache first, falls back to Redis.
Multi-pod safe: tokens stored in Redis with TTL."""
def _validate_ws_token(user_id: str, ws_token: str) -> bool {
    if not ws_token or not user_id {
        return False;
    }
    now = time.time();

    # Check local cache first (fast path — same pod)
    tokens = _ws_auth_tokens.get(user_id);
    if tokens {
        token_time = tokens.get(ws_token);
        if token_time is not None and (now - token_time) <= _WS_TOKEN_TTL {
            return True;
        }
    }

    # Fallback: check Redis (cross-pod)
    try {
        r = _get_redis();
        if r is not None {
            redis_key = f"ws_token:{user_id}:{ws_token}";
            val = r.get(redis_key);
            if val is not None {
                # Populate local cache
                _ws_auth_tokens.setdefault(user_id, {})[ws_token] = now;
                return True;
            }
        }
    } except Exception as e {
        print(f"[ws_token] Redis fallback failed: {e}");
    }

    return False;
}

glob _redis_client: Any = None;

def _get_redis() -> Any {
    global _redis_client;
    if _redis_client is not None {
        return _redis_client;
    }
    try {
        import redis;
        host = os.environ.get("REDIS_HOST", "jac-builder-dev-redis-service");
        port = int(os.environ.get("REDIS_PORT", "6379"));
        _redis_client = redis.Redis(host=host, port=port, decode_responses=True, socket_timeout=2);
        _redis_client.ping();
        return _redis_client;
    } except Exception as e {
        print(f"[ws_token] Redis connect failed: {e}");
        return None;
    }
}

"""Register a new WS token for a user. Stores in local cache AND Redis.
Multi-pod safe: any pod can validate via Redis."""
def _register_ws_token(user_id: str, profile: Any = None) -> str {
    ws_token = str(uuid4());
    now = time.time();

    # Local cache
    tokens = _ws_auth_tokens.setdefault(user_id, {});
    while len(tokens) >= _WS_MAX_TOKENS_PER_USER {
        oldest_token = min(tokens, key=lambda t: tokens[t]);
        tokens.pop(oldest_token, None);
    }
    tokens[ws_token] = now;

    # Persist to Redis (cross-pod, with TTL)
    try {
        r = _get_redis();
        if r is not None {
            redis_key = f"ws_token:{user_id}:{ws_token}";
            r.setex(redis_key, int(_WS_TOKEN_TTL), "1");
        }
    } except Exception as e {
        print(f"[ws_token] Redis persist failed: {e}");
    }

    return ws_token;
}

# GitHub OAuth state is now stored on UserProfile nodes (survives restarts + multi-pod)

node Router {
}

node UserProfile {
    has user_id: str;
    has display_name: str = "";
    has created_at: str = "";
    has github_access_token: str = "";
    has github_username: str = "";
    has github_connected: bool = False;
    has github_refresh_token: str = "";
    has github_token_expires_at: float = 0.0;
    has github_app_installed: bool = False;
    has github_oauth_state: str = "";
    has github_oauth_state_ts: float = 0.0;
}

node Project {
    has id: str;
    has name: str;
    has template_id: str = "preview-template";
    has project_type: str = "fullstack";
    has repo_path: str = "";
    has created_at: str = "";
    has updated_at: str = "";
    has active_branch: str = "main";
    has last_commit: str = "";
    has deployment_namespace: str = "";
    has deployment_app_name: str = "";
    has deployment_url: str = "";
    has deployment_status: str = "";
    has sandbox_namespace: str = "";
    has sandbox_app_name: str = "";
    has sandbox_url: str = "";
    has sandbox_status: str = "";
    has preview_sandbox_id: str = "";
    has ai_processing: bool = False;
}


"""Unified sandbox state — replaces SandboxSession + all in-memory dicts.

Lives on global root so every pod can query [-->(?:SandboxInstance)].
Auto-persists to MongoDB via Jac.commit() at end of walker execution.
The `purpose` field unifies preview sandboxes (30min TTL) and deploy
sandboxes (1-week TTL) into a single lifecycle model.

Desired/observed state machine:
  desired_state:  "running" | "stopped" | "destroyed"
  observed_state: "pending" | "creating" | "starting" | "running" | "error" | "stopped"

The reconciler background loop drives observed_state transitions based
on desired_state + actual K8s pod status."""
node SandboxInstance {
    has sandbox_id: str;
    has user_id: str;
    has project_id: str;
    has purpose: str = "preview";

    # K8s resource identifiers
    has pod_name: str = "";
    has namespace: str = "";
    has configmap_name: str = "";
    has service_name: str = "";

    # Lifecycle state machine
    has desired_state: str = "running";
    has observed_state: str = "pending";
    has error_message: str = "";
    has warm_start: bool = False;

    # Addressing
    has url: str = "";
    has port: int = 8000;

    # Directory state
    has staging_dir: str = "";
    has source_dir: str = "";
    has is_worktree: bool = False;
    has worktree_path: str = "";

    # Lifecycle metadata
    has created_at: float = 0.0;
    has last_heartbeat: float = 0.0;
    has owner_pod: str = "";
    has ttl_seconds: int = 1800;
    has version: int = 0;
}

"""Create a SandboxInstance node, attach it to `root_node`, and grant
public write access so any root (other pods, reconciler, WS walkers)
can read and update it."""
def _create_sandbox_node(root_node: Any, params: dict) -> None {
    si = SandboxInstance(**params);
    root_node ++> si;
    Jac.perm_grant(si, "WRITE");
}

"""Leader lease for sandbox reconciler — only one pod runs expensive
drift detection and TTL enforcement phases."""
node ReconcilerLease {
    has holder: str = "";
    has expires_at: float = 0.0;
}

node ProjectVersion {
    has id: str;
    has project_id: str;
    has commit_sha: str = "";
    has jacpack_path: str = "";
    has created_at: str = "";
    has trigger: str = "autosave";
}

node ClaudeThread {
    has id: str;
    has title: str = "New Chat";
    has session_id: str = "";
    has status: str = "idle";
    has model: str = "";
    has branch: str = "";
    has worktree_path: str = "";
    has turn_count: int = 0;
    has created_at: str = "";
    has updated_at: str = "";
}

node ClaudeMessage {
    has id: str;
    has role: str = "user";
    has content: str = "";
    has turn_number: int = 0;
    has created_at: str = "";
}

node ClaudeActivity {
    has id: str;
    has activity_type: str = "tool";
    has tool_name: str = "";
    has message: str = "";
    has tool_input: str = "";
    has tool_output: str = "";
    has status: str = "";
    has turn_number: int = 0;
    has created_at: str = "";
}

node JacCoderMessage {
    has id: str;
    has role: str = "user";
    has content: str = "";
    has updated_files: list = [];
    has checkpoint_ref: str = "";
    has version_id: str = "";
    has images: list = [];
    has activities_log: list = [];
    has created_at: str = "";
}

"""Current UTC timestamp in ISO format."""
def _utc_now() -> str {
    return datetime.utcnow().isoformat() + "Z";
}

"""Check if a relative path matches any excluded directory/file pattern."""
def _zip_is_excluded(rel: str) -> bool {
    import fnmatch;
    exclude_patterns = [
        ".git", ".jac", ".jac-ide", "node_modules",
        "__pycache__", "__jac_gen__", "dist", "build", ".jacpack"
    ];
    parts = rel.replace(os.sep, "/").split("/");
    for part in parts {
        for pat in exclude_patterns {
            if fnmatch.fnmatch(part, pat) {
                return True;
            }
        }
    }
    return False;
}

"""Create a zip of the project directory, excluding build artifacts."""
def _create_project_zip(repo_path: str, output_path: str, project_name: str = "") -> dict {
    import zipfile;

    try {
        with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf {
            for entry in os.walk(repo_path) {
                dirpath = entry[0];
                dirnames = entry[1];
                filenames = entry[2];
                # Prune excluded directories in-place
                dirnames[:] = [
                    d for d in dirnames
                    if not _zip_is_excluded(os.path.relpath(os.path.join(dirpath, d), repo_path))
                ];
                for fname in filenames {
                    full = os.path.join(dirpath, fname);
                    rel = os.path.relpath(full, repo_path);
                    if not _zip_is_excluded(rel) {
                        zf.write(full, rel);
                    }
                }
            }
        }
    } except Exception as e {
        return {"success": False, "error": "zip failed: " + str(e)};
    }

    with open(output_path, "rb") as f {
        raw = f.read();
    }
    encoded = base64.b64encode(raw).decode("ascii");
    proj_name = project_name.replace(" ", "_") if project_name else "project";
    return {
        "success": True,
        "file_name": proj_name + ".zip",
        "content_base64": encoded,
        "mime_type": "application/zip"
    };
}

"""Convert project node to plain dict."""
def _project_to_dict(project: Any) -> dict {
    project_node = project;
    if isinstance(project_node, list) {
        if len(project_node) > 0 {
            project_node = project_node[0];
        } else {
            return {};
        }
    }
    return {
        "id": project_node.id,
        "name": project_node.name,
        "template_id": project_node.template_id,
        "project_type": project_node.project_type if hasattr(project_node, "project_type") else "fullstack",
        "repo_path": project_node.repo_path,
        "created_at": project_node.created_at,
        "updated_at": project_node.updated_at,
        "active_branch": project_node.active_branch,
        "last_commit": project_node.last_commit,
        "deployment_namespace": project_node.deployment_namespace,
        "deployment_app_name": project_node.deployment_app_name,
        "deployment_url": project_node.deployment_url,
        "deployment_status": project_node.deployment_status,
        "sandbox_namespace": project_node.sandbox_namespace,
        "sandbox_app_name": project_node.sandbox_app_name,
        "sandbox_url": project_node.sandbox_url,
        "sandbox_status": project_node.sandbox_status,
        "has_thumbnail": has_project_thumbnail(project_node.repo_path)
    };
}

"""Convert version node to plain dict."""
def _version_to_dict(version: Any) -> dict {
    return {
        "id": version.id,
        "project_id": version.project_id,
        "commit_sha": version.commit_sha,
        "jacpack_path": version.jacpack_path,
        "created_at": version.created_at,
        "trigger": version.trigger
    };
}

"""Convert UserProfile node to plain dict."""
def _userprofile_to_dict(profile: Any) -> dict {
    return {
        "user_id": profile.user_id,
        "display_name": profile.display_name,
        "created_at": profile.created_at,
        "github_connected": _github_is_connected(profile.user_id, profile),
        "github_username": _github_get_username(profile.user_id, profile)
    };
}

"""Convert ClaudeThread node to plain dict.
Note: session_id is intentionally excluded — it's an internal implementation
detail used for --resume and exposing it would be a security concern."""
def _thread_to_dict(thread: Any) -> dict {
    return {
        "id": thread.id,
        "title": thread.title,
        "status": thread.status,
        "model": thread.model,
        "branch": thread.branch,
        "worktree_path": thread.worktree_path,
        "turn_count": thread.turn_count,
        "created_at": thread.created_at,
        "updated_at": thread.updated_at
    };
}

"""Convert ClaudeMessage node to plain dict."""
def _message_to_dict(msg: Any) -> dict {
    return {
        "id": msg.id,
        "role": msg.role,
        "content": msg.content,
        "turn_number": msg.turn_number,
        "created_at": msg.created_at
    };
}

"""Convert ClaudeActivity node to plain dict."""
def _activity_to_dict(act: Any) -> dict {
    return {
        "id": act.id,
        "activity_type": act.activity_type,
        "tool_name": act.tool_name,
        "message": act.message,
        "tool_input": getattr(act, "tool_input", ""),
        "tool_output": getattr(act, "tool_output", ""),
        "status": act.status,
        "turn_number": act.turn_number,
        "created_at": act.created_at
    };
}

walker template_ops {
    has action: str = "list";
    has template_id: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list";
        if action == "list" {
            builtin = list_templates();
            user_tmpls: list = [];
            profiles = [-->(?:UserProfile)];
            if profiles and len(profiles) > 0 {
                user_tmpls = list_user_templates(profiles[0].user_id);
            }
            report {"success": True, "templates": builtin + user_tmpls};
        } elif action == "get" {
            if not self.template_id {
                report {"success": False, "error": "template_id is required"};
            } else {
                result = get_template(self.template_id);
                if result.get("success", False) {
                    report {"success": True, "template": result.get("template", {})};
                } else {
                    report result;
                }
            }
        } else {
            report {"success": False, "error": f"Unknown action: {action}"};
        }
    }
}

walker me {
    has display_name_hint: str = "";

    obj __specs__ {
        static has methods: list = ["post"];
    }

    can handle_action with Root entry {
        profiles = [-->(?:UserProfile)];
        if profiles and len(profiles) > 0 {
            profile = profiles[0];
            if not profile.display_name and self.display_name_hint {
                profile.display_name = self.display_name_hint;
            }
            # Generate WS auth token with TTL for this session.
            # Multiple tokens per user allow concurrent browser tabs.
            ws_token = _register_ws_token(profile.user_id);
            report {"success": True, "user": _userprofile_to_dict(profile), "ws_token": ws_token};
        } else {
            hint = self.display_name_hint or "";
            new_profile = here ++> UserProfile(
                user_id=str(uuid4()),
                display_name=hint,
                created_at=_utc_now()
            );
            profile_node = new_profile if not isinstance(new_profile, list) else (new_profile[0] if new_profile else None);
            if profile_node {
                ws_token = _register_ws_token(profile_node.user_id);
                report {"success": True, "user": _userprofile_to_dict(profile_node), "ws_token": ws_token};
            } else {
                # Fallback: re-query graph in case ++> returned a list
                fallback_profiles = [-->(?:UserProfile)];
                if fallback_profiles and len(fallback_profiles) > 0 {
                    uid = fallback_profiles[0].user_id;
                    ws_token = _register_ws_token(uid);
                    report {"success": True, "user": _userprofile_to_dict(fallback_profiles[0]), "ws_token": ws_token};
                } else {
                    report {"success": False, "error": "Failed to create user profile"};
                }
            }
        }
    }
}

"""Background cleanup for project deletion — subprocess kills + filesystem removal.
Runs in a daemon thread so the walker can return immediately and avoid 504 timeouts."""
def _bg_delete_cleanup(uid: str, pid: str, repo_path: str, worktree_paths: list) -> None {
    try { stop_claude_session(uid, pid); } except Exception { ; }
    try { clear_session(uid, pid); } except Exception { ; }
    try { stop_lsp(uid, pid); } except Exception { ; }
    try { cleanup_preview(uid, pid); } except Exception { ; }
    for wp in worktree_paths {
        if os.path.exists(wp) {
            try { git_remove_worktree(repo_path, wp, force=True); } except Exception { ; }
        }
    }
    tmp_preview = "/tmp/jac-preview-" + uid + "-" + pid;
    if os.path.exists(tmp_preview) {
        try { shutil.rmtree(tmp_preview, ignore_errors=True); } except Exception { ; }
    }
    if repo_path {
        try { delete_project_workspace(repo_path); } except Exception { ; }
    }
    try { remove_session(uid, pid); } except Exception { ; }
}

walker project_ops {
    has action: str = "list";
    has project_id: str = "";
    has name: str = "";
    has template_id: str = "preview-template";
    has jacpack_url: str = "";
    has jacpack_content_base64: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list";
        now = _utc_now();

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found. Call /walker/me first."};
        } else {
            profile = profiles[0];

            if action == "create" {
                project_name = self.name.strip() if self.name else "";
                if not project_name {
                    report {"success": False, "error": "Project name is required"};
                } elif _get_project_count(profile.user_id) >= MAX_PROJECTS_PER_USER {
                    report {"success": False, "error": "Project limit reached (3 per user). Delete an existing project to create a new one."};
                } else {
                    tmpl_id = self.template_id or "preview-template";
                    if tmpl_id.startswith("user_") {
                        user_tmpl = get_user_template(profile.user_id, tmpl_id);
                        if not user_tmpl.get("success", False) {
                            report user_tmpl;
                        }
                        result = create_project_from_jacpack(profile.user_id, project_name, user_tmpl.get("abs_path", ""), profile.display_name);
                    } else {
                        result = create_project_workspace(profile.user_id, project_name, tmpl_id, profile.display_name);
                    }
                    if not result.get("success", False) {
                        report result;
                    } else {
                        created = result.get("project", {});
                        # Derive project_type from template_id
                        p_type = "fullstack";
                        if tmpl_id == "backend-api" {
                            p_type = "backend";
                        } elif tmpl_id == "script" {
                            p_type = "script";
                        }
                        created_node = profile ++> Project(
                            id=created.get("id", ""),
                            name=created.get("name", project_name),
                            template_id=created.get("template_id", self.template_id or "preview-template"),
                            project_type=p_type,
                            repo_path=created.get("repo_path", ""),
                            created_at=created.get("created_at", now),
                            updated_at=created.get("updated_at", now),
                            active_branch=created.get("active_branch", "main"),
                            last_commit=created.get("last_commit", "")
                        );

                        versions = list_project_versions(created.get("repo_path", ""));
                        for version in versions {
                            created_node ++> ProjectVersion(
                                id=version.get("id", ""),
                                project_id=created.get("id", ""),
                                commit_sha=version.get("commit_sha", ""),
                                jacpack_path=version.get("jacpack_path", ""),
                                created_at=version.get("created_at", now),
                                trigger=version.get("trigger", "init")
                            );
                        }

                        project_payload = _project_to_dict(created_node) if created_node else {};
                        if not project_payload.get("id", "") {
                            project_payload = {
                                "id": created.get("id", ""),
                                "name": created.get("name", project_name),
                                "template_id": created.get("template_id", self.template_id or "preview-template"),
                                "project_type": p_type,
                                "repo_path": created.get("repo_path", ""),
                                "created_at": created.get("created_at", now),
                                "updated_at": created.get("updated_at", now),
                                "active_branch": created.get("active_branch", "main"),
                                "last_commit": created.get("last_commit", "")
                            };
                        }

                        if project_payload.get("id", "") {
                            _project_counts[profile.user_id] = _get_project_count(profile.user_id) + 1;
                            report {"success": True, "project": project_payload, "versions": versions};
                        } else {
                            report {"success": False, "error": "Failed to create graph node for project"};
                        }
                    }
                }
            } elif action == "list" {
                projects: list = [];
                all_projects = [profile -->(?:Project)];
                for project in all_projects {
                    projects.append(_project_to_dict(project));
                }
                projects.sort(key=lambda item: item.get("updated_at", ""), reverse=True);
                report {"success": True, "projects": projects};
            } elif action == "open" or action == "status" {
                if not self.project_id {
                    report {"success": False, "error": "project_id is required"};
                } else {
                    all_projects = [profile -->(?:Project)];
                    target = None;
                    for project in all_projects {
                        if project.id == self.project_id {
                            target = project;
                            break;
                        }
                    }
                    if not target {
                        report {"success": False, "error": "Project not found"};
                    } else {
                        status = get_project_status(target.repo_path);
                        if status.get("success", False) {
                            target.updated_at = now;
                            target.active_branch = status.get("active_branch", target.active_branch);
                            target.last_commit = status.get("last_commit", target.last_commit);
                        }
                        report {"success": True, "project": _project_to_dict(target), "status": status};
                    }
                }
            } elif action == "rename" {
                if not self.project_id or not self.name {
                    report {"success": False, "error": "project_id and name are required"};
                } else {
                    all_projects = [profile -->(?:Project)];
                    target = None;
                    for project in all_projects {
                        if project.id == self.project_id {
                            target = project;
                            break;
                        }
                    }
                    if not target {
                        report {"success": False, "error": "Project not found"};
                    } else {
                        target.name = self.name;
                        target.updated_at = now;
                        report {"success": True, "project": _project_to_dict(target)};
                    }
                }
            } elif action == "delete" {
                if not self.project_id {
                    report {"success": False, "error": "project_id is required"};
                } else {
                    all_projects = [profile -->(?:Project)];
                    target = None;
                    for project in all_projects {
                        if project.id == self.project_id {
                            target = project;
                            break;
                        }
                    }
                    if not target {
                        report {"success": False, "error": "Project not found"};
                    } else {
                        uid = profile.user_id;
                        pid = self.project_id;
                        repo_path = target.repo_path or "";

                        # Collect worktree paths before deleting graph nodes
                        worktree_paths: list = [];
                        all_threads = [target -->(?:ClaudeThread)];
                        for thread in all_threads {
                            if thread.worktree_path {
                                worktree_paths.append(thread.worktree_path);
                            }
                            for msg in [thread -->(?:ClaudeMessage)] {
                                del msg;
                            }
                            for act in [thread -->(?:ClaudeActivity)] {
                                del act;
                            }
                            del thread;
                        }

                        # Delete JacCoderMessage nodes
                        for jmsg in [target -->(?:JacCoderMessage)] {
                            del jmsg;
                        }

                        # Delete ProjectVersion nodes
                        for version in [target -->(?:ProjectVersion)] {
                            del version;
                        }

                        # Delete the Project node
                        del target;

                        _project_counts[profile.user_id] = max(0, _get_project_count(profile.user_id) - 1);

                        # Report success immediately — heavy I/O cleanup runs in background
                        # to avoid 504 gateway timeout on production K8s deployments
                        report {"success": True};
                        threading.Thread(
                            target=_bg_delete_cleanup,
                            args=(uid, pid, repo_path, worktree_paths),
                            daemon=True
                        ).start();
                    }
                }
            } elif action == "import" {
                project_name = self.name.strip() if self.name else "";
                if not project_name {
                    report {"success": False, "error": "Project name is required"};
                } elif _get_project_count(profile.user_id) >= MAX_PROJECTS_PER_USER {
                    report {"success": False, "error": "Project limit reached (3 per user). Delete an existing project to create a new one."};
                } elif not self.jacpack_url and not self.jacpack_content_base64 {
                    report {"success": False, "error": "jacpack_url or jacpack_content_base64 is required"};
                } else {
                    tmp_path = None;
                    url_error = "";
                    if self.jacpack_content_base64 and len(self.jacpack_content_base64) > 14_000_000 {
                        url_error = "Upload too large (max 10MB)";
                    }
                    if not self.jacpack_content_base64 and self.jacpack_url {
                        import from urllib.parse {urlparse}
                        import ipaddress;
                        import socket;
                        parsed = urlparse(self.jacpack_url);
                        if parsed.scheme not in ("http", "https") {
                            url_error = "Only http/https URLs are allowed";
                        } elif not (parsed.hostname or "") {
                            url_error = "Invalid URL";
                        } else {
                            try {
                                resolved = socket.getaddrinfo(parsed.hostname, None);
                                for info in resolved {
                                    addr = ipaddress.ip_address(info[4][0]);
                                    if addr.is_private or addr.is_loopback or addr.is_link_local or addr.is_reserved {
                                        url_error = "URL resolves to a private/internal address";
                                    }
                                }
                            } except Exception as dns_err {
                                url_error = "Cannot resolve URL hostname: " + str(dns_err);
                            }
                        }
                    }
                    if url_error {
                        report {"success": False, "error": url_error};
                    } else {
                    try {
                        tmp_path = os.path.join(tempfile.gettempdir(), "jac_upload_" + str(int(time.time() * 1000)) + ".jacpack");
                        if self.jacpack_content_base64 {
                            content_bytes = base64.b64decode(self.jacpack_content_base64);
                            with open(tmp_path, "wb") as f {
                                f.write(content_bytes);
                            }
                        } else {
                            import httpx;
                            with httpx.Client(follow_redirects=False, timeout=30.0) as client {
                                resp = client.get(self.jacpack_url);
                                if resp.status_code in (301, 302, 303, 307, 308) {
                                    raise Exception("URL redirects are not allowed for security");
                                }
                                resp.raise_for_status();
                                if len(resp.content) > 10_000_000 {
                                    raise Exception("Downloaded file too large (max 10MB)");
                                }
                                with open(tmp_path, "wb") as f {
                                    f.write(resp.content);
                                }
                            }
                        }
                        import from zipfile {is_zipfile as _is_zip}
                        if _is_zip(tmp_path) {
                            result = create_project_from_zip(profile.user_id, project_name, tmp_path, profile.display_name);
                        } else {
                            result = create_project_from_jacpack(profile.user_id, project_name, tmp_path, profile.display_name);
                        }
                        if not result.get("success", False) {
                            report result;
                        } else {
                            created = result.get("project", {});
                            created_node = profile ++> Project(
                                id=created.get("id", ""),
                                name=created.get("name", project_name),
                                template_id="uploaded",
                                repo_path=created.get("repo_path", ""),
                                created_at=created.get("created_at", now),
                                updated_at=created.get("updated_at", now),
                                active_branch=created.get("active_branch", "main"),
                                last_commit=created.get("last_commit", "")
                            );
                            versions = list_project_versions(created.get("repo_path", ""));
                            for version in versions {
                                created_node ++> ProjectVersion(
                                    id=version.get("id", ""),
                                    project_id=created.get("id", ""),
                                    commit_sha=version.get("commit_sha", ""),
                                    jacpack_path=version.get("jacpack_path", ""),
                                    created_at=version.get("created_at", now),
                                    trigger=version.get("trigger", "import")
                                );
                            }
                            project_payload = _project_to_dict(created_node) if created_node else {};
                            if not project_payload.get("id", "") {
                                project_payload = {
                                    "id": created.get("id", ""),
                                    "name": created.get("name", project_name),
                                    "template_id": "uploaded",
                                    "repo_path": created.get("repo_path", ""),
                                    "created_at": created.get("created_at", now),
                                    "updated_at": created.get("updated_at", now),
                                    "active_branch": created.get("active_branch", "main"),
                                    "last_commit": created.get("last_commit", "")
                                };
                            }
                            if project_payload.get("id", "") {
                                _project_counts[profile.user_id] = _get_project_count(profile.user_id) + 1;
                                if not _is_zip(tmp_path) {
                                    save_user_template(profile.user_id, project_name, tmp_path);
                                }
                                report {"success": True, "project": project_payload, "versions": versions};
                            } else {
                                report {"success": False, "error": "Failed to create graph node for project"};
                            }
                        }
                    } except Exception as e {
                        report {"success": False, "error": str(e)};
                    } finally {
                        if tmp_path and os.path.exists(tmp_path) {
                            os.unlink(tmp_path);
                        }
                    }
                    }
                }
            } elif action == "get_thumbnail" {
                if not self.project_id {
                    report {"success": False, "error": "project_id is required"};
                } else {
                    all_projects = [profile -->(?:Project)];
                    target = None;
                    for project in all_projects {
                        if project.id == self.project_id {
                            target = project;
                            break;
                        }
                    }
                    if not target {
                        report {"success": False, "error": "Project not found"};
                    } else {
                        report get_project_thumbnail(target.repo_path);
                    }
                }
            } else {
                report {"success": False, "error": f"Unknown action: {action}"};
            }
        }
    }
}

walker version_ops {
    has project_id: str;
    has action: str = "list";
    has version_id: str = "";
    has commit_sha: str = "";
    has output_path: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list";
        now = _utc_now();

        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
        } else {
            profiles = [-->(?:UserProfile)];
            if not profiles or len(profiles) == 0 {
                report {"success": False, "error": "User profile not found"};
            } else {
                profile = profiles[0];
                user_id = profile.user_id;
                all_projects = [profile -->(?:Project)];
                target = None;
                for project in all_projects {
                    if project.id == self.project_id {
                        target = project;
                        break;
                    }
                }
                if not target {
                    report {"success": False, "error": "Project not found"};
                } else {
                    if action == "list" {
                        disk_versions = list_project_versions(target.repo_path);
                        all_nodes = [target -->(?:ProjectVersion)];
                        seen_ids: list = [];
                        for node in all_nodes {
                            seen_ids.append(node.id);
                        }
                        for entry in disk_versions {
                            entry_id = entry.get("id", "");
                            if entry_id and not (entry_id in seen_ids) {
                                target ++> ProjectVersion(
                                    id=entry_id,
                                    project_id=self.project_id,
                                    commit_sha=entry.get("commit_sha", ""),
                                    jacpack_path=entry.get("jacpack_path", ""),
                                    created_at=entry.get("created_at", now),
                                    trigger=entry.get("trigger", "autosave")
                                );
                            }
                        }
                        report {"success": True, "versions": disk_versions};
                    } elif action == "capture" {
                        capture = autosave_version(
                            target.repo_path,
                            "capture",
                            f"chore: version capture {now}"
                        );
                        if not capture.get("success", False) {
                            report capture;
                        } else {
                            target.updated_at = now;
                            if capture.get("commit_sha", "") {
                                target.last_commit = capture.get("commit_sha", target.last_commit);
                            }
                            version = capture.get("version", None);
                            if version {
                                target ++> ProjectVersion(
                                    id=version.get("id", ""),
                                    project_id=self.project_id,
                                    commit_sha=version.get("commit_sha", ""),
                                    jacpack_path=version.get("jacpack_path", ""),
                                    created_at=version.get("created_at", now),
                                    trigger=version.get("trigger", "autosave")
                                );
                            }
                            removed = capture.get("removed_versions", []);
                            if removed and len(removed) > 0 {
                                all_nodes = [target -->(?:ProjectVersion)];
                                for node in all_nodes {
                                    for old in removed {
                                        if node.id == old.get("id", "") {
                                            del node;
                                            break;
                                        }
                                    }
                                }
                            }
                            report capture;
                        }
                    } elif action == "checkout" {
                        target_commit = self.commit_sha;
                        if not target_commit and self.version_id {
                            versions = list_project_versions(target.repo_path);
                            for entry in versions {
                                if entry.get("id", "") == self.version_id {
                                    target_commit = entry.get("commit_sha", "");
                                    break;
                                }
                            }
                        }
                        if not target_commit {
                            report {"success": False, "error": "commit_sha or version_id is required"};
                        } else {
                            result = checkout_project_commit(target.repo_path, target_commit);
                            if result.get("success", False) {
                                target.last_commit = result.get("commit_sha", target.last_commit);
                                target.active_branch = result.get("active_branch", target.active_branch);
                                target.updated_at = now;
                                print(f"[version_ops] checkout success: cleanup+setup preview project={self.project_id} repo_path={target.repo_path}");
                                cleanup_preview(user_id, self.project_id);
                                setup_preview(user_id, self.project_id, target.repo_path);
                            }
                            report result;
                        }
                    } elif action == "export_jacpack" {
                        result = export_project_jacpack(
                            target.repo_path,
                            self.version_id
                        );
                        report result;
                    } elif action == "export_jacpack_download" {
                        tmp_path = os.path.join(tempfile.gettempdir(), "jac-ide-export-" + str(int(time.time() * 1000)) + ".jacpack");
                        result = export_project_jacpack(
                            target.repo_path,
                            self.version_id,
                            tmp_path
                        );
                        if not result.get("success", False) {
                            report result;
                        } else {
                            out_path = result.get("output_path", tmp_path);
                            try {
                                with open(out_path, "rb") as f {
                                    raw = f.read();
                                }
                                encoded = base64.b64encode(raw).decode("ascii");
                                report {
                                    "success": True,
                                    "file_name": os.path.basename(out_path) or "export.jacpack",
                                    "content_base64": encoded,
                                    "mime_type": "application/octet-stream"
                                };
                            } except Exception as e {
                                report {"success": False, "error": str(e)};
                            } finally {
                                if out_path and os.path.exists(out_path) {
                                    try {
                                        os.remove(out_path);
                                    } except Exception {
                                    }
                                }
                            }
                        }
                    } elif action == "export_zip_download" {
                        tmp_path = os.path.join(tempfile.gettempdir(), "jac-ide-zip-" + str(int(time.time() * 1000)) + ".zip");
                        try {
                            result = _create_project_zip(target.repo_path, tmp_path, target.name);
                            report result;
                        } except Exception as e {
                            report {"success": False, "error": str(e)};
                        } finally {
                            if os.path.exists(tmp_path) {
                                try {
                                    os.remove(tmp_path);
                                } except Exception {
                                }
                            }
                        }
                    } else {
                        report {"success": False, "error": f"Unknown action: {action}"};
                    }
                }
            }
        }
    }
}

walker preview_control {
    has action: str;
    has project_id: str = "";
    has worktree_path: str = "";
    has project_type: str = "fullstack";

    can handle_action with Root entry {
        import from services.sandbox_store {
            ensure_sandbox as ss_ensure,
            stop_sandbox as ss_stop,
            destroy_sandbox as ss_destroy,
            get_status_for_project as ss_status,
            find_sandbox_for_project as ss_find,
            sandbox_id_for as ss_id_for
        }

        action = self.action.lower().strip() if self.action else "";
        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
        } else {
            user_id = profiles[0].user_id;

            # Find project repo_path from graph
            all_projects = [profiles[0] -->(?:Project)];
            source_dir = "";
            for project in all_projects {
                if project.id == self.project_id {
                    source_dir = project.repo_path;
                    break;
                }
            }

            # Get all SandboxInstance nodes for queries
            all_si = [-->(?:SandboxInstance)];

            if action == "start" {
                print(f"[preview_control] start: user={user_id} project={self.project_id} worktree={self.worktree_path}");

                # Handle worktree switching: destroy existing sandbox first
                existing_si = ss_find(all_si, user_id, self.project_id, "preview");
                if self.worktree_path and existing_si is not None {
                    ss_destroy(all_si, str(existing_si.sandbox_id));
                    cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
                } elif not self.worktree_path and existing_si is not None and existing_si.is_worktree {
                    # Switching worktree → local: destroy worktree sandbox
                    ss_destroy(all_si, str(existing_si.sandbox_id));
                    cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
                }

                # Setup preview workspace (file watcher, jac install)
                setup_result = setup_preview(user_id, self.project_id, source_dir, self.worktree_path);
                if not setup_result.get("success") {
                    report setup_result;
                    return;
                }

                # Re-fetch after potential destroy above
                all_si = [-->(?:SandboxInstance)];

                # Create or get existing sandbox via sandbox_store
                result = ss_ensure(
                    all_si, user_id, self.project_id,
                    purpose="preview",
                    source_dir=source_dir,
                    worktree_path=self.worktree_path
                );

                # If new sandbox was created, persist the graph node
                if result.get("_create_params") {
                    _create_sandbox_node(here, result["_create_params"]);
                    print(f"[preview_control] Created SandboxInstance node sid={result.get('sandbox_id', '')}");
                }

                # Store sandbox_id on Project node so file-op walkers can find it
                # Register watch dir → sandbox mapping for file watcher sync
                if result.get("success") {
                    new_sid = result.get("sandbox_id", "");
                    for proj in all_projects {
                        if proj.id == self.project_id {
                            proj.preview_sandbox_id = new_sid;
                            break;
                        }
                    }
                    if new_sid and source_dir {
                        try {
                            import from services.file_watcher { register_sandbox_for_dir }
                            register_sandbox_for_dir(source_dir, new_sid);
                        } except Exception {
                            x = 0;
                        }
                    }
                }

                report {
                    "success": result.get("success", False),
                    "url": result.get("url", ""),
                    "port": result.get("port", 0),
                    "api_port": 0,
                    "status": result.get("status", "error")
                };
            } elif action == "stop" {
                existing_si = ss_find(all_si, user_id, self.project_id, "preview");
                if existing_si is not None {
                    result = ss_stop(all_si, str(existing_si.sandbox_id));
                    report result;
                } else {
                    # Fallback: try legacy stop
                    result = stop_preview(user_id, self.project_id, sandbox_id="");
                    report result;
                }
            } elif action == "status" {
                existing_si = ss_find(all_si, user_id, self.project_id, "preview");
                if existing_si is not None {
                    result = ss_status(all_si, user_id, self.project_id);
                    report result;
                } else {
                    # Fallback: try legacy status
                    result = get_preview_status(user_id, self.project_id);
                    report result;
                }
            } elif action == "cleanup" {
                existing_si = ss_find(all_si, user_id, self.project_id, "preview");
                if existing_si is not None {
                    ss_destroy(all_si, str(existing_si.sandbox_id));
                }
                result = cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
                report result;
            } else {
                report {"success": False, "error": f"Unknown action: {action}"};
            }
        }
    }
}

walker preview_screenshot {
    has project_id: str = "";
    has viewport: str = "desktop";
    has format: str = "jpeg";
    has full_page: bool = False;
    has delay: int = 1000;
    has url: str = "";

    can handle with Root entry {
        print(f"[screenshot-walker] Called: project_id={self.project_id}, url={self.url}, delay={self.delay}");
        if self.url {
            result = take_screenshot(
                url=self.url,
                viewport=self.viewport,
                format=self.format,
                full_page=self.full_page,
                delay=self.delay
            );
            report result;
        } elif self.project_id {
            profiles = [-->(?:UserProfile)];
            if not profiles or len(profiles) == 0 {
                print("[screenshot-walker] No user profile found");
                report {"success": False, "error": "User profile not found"};
            } else {
                user_id = profiles[0].user_id;
                status = get_preview_status(user_id, self.project_id);
                print(f"[screenshot-walker] Preview status: {status}");
                if status.get("status") != "running" {
                    print(f"[screenshot-walker] Preview not running, status={status.get('status')}");
                    report {"success": False, "error": "Preview is not running for this project"};
                } else {
                    preview_url = status.get("url", "");
                    print(f"[screenshot-walker] Preview URL: {preview_url}");
                    if not preview_url {
                        report {"success": False, "error": "No preview URL available"};
                    } elif "localhost" in preview_url and "localhost" not in MCP_SERVER_URL {
                        print(f"[screenshot-walker] Skipped: localhost URL with remote MCP");
                        report {"success": False, "error": "Cannot screenshot localhost URL from remote MCP server. Set JAC_IDE_PREVIEW_PUBLIC_URL_TEMPLATE for public preview URLs."};
                    } else {
                        print(f"[screenshot-walker] Calling take_screenshot({preview_url})...");
                        result = take_screenshot(
                            url=preview_url,
                            viewport=self.viewport,
                            format=self.format,
                            full_page=self.full_page,
                            delay=self.delay
                        );
                        print(f"[screenshot-walker] take_screenshot result: success={result.get('success')}, error={result.get('error', 'none')}");
                        if result.get("success") and result.get("image") {
                            all_projects = [profiles[0] -->(?:Project)];
                            for proj in all_projects {
                                if proj.id == self.project_id {
                                    save_result = save_project_thumbnail(proj.repo_path, result["image"]);
                                    print(f"[screenshot-walker] Thumbnail saved: {save_result}");
                                    break;
                                }
                            }
                        }
                        report result;
                    }
                }
            }
        } else {
            report {"success": False, "error": "Either project_id or url is required"};
        }
    }
}

walker ide_file_ops {
    has action: str;
    has project_id: str = "";
    has path: str = "";
    has content: str = "";
    has encoding: str = "";
    has new_path: str = "";
    has log_offset: int = 0;
    has files: list = [];
    has query: str = "";
    has case_sensitive: bool = False;
    has replace_text: str = "";
    has file_filter: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "";
        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
        } else {
            profiles = [-->(?:UserProfile)];
            if not profiles or len(profiles) == 0 {
                report {"success": False, "error": "User profile not found"};
            } else {
                profile = profiles[0];
                user_id = profile.user_id;
                all_projects = [profile -->(?:Project)];
                target = None;
                for project in all_projects {
                    if project.id == self.project_id {
                        target = project;
                        break;
                    }
                }
                if not target {
                    report {"success": False, "error": "Project not found"};
                } else {
                    # Get sandbox_id from Project node for file operations
                    sid = target.preview_sandbox_id or "";
                    if action == "setup" {
                        print(f"[ide_file_ops] setup: user={user_id} project={self.project_id} repo_path={target.repo_path}");
                        result = setup_preview(user_id, self.project_id, target.repo_path);
                        report result;
                    } elif action == "list" {
                        result = list_preview_files(user_id, self.project_id, self.path or ".", sandbox_id=sid);
                        report result;
                    } elif action == "read" {
                        result = read_preview_file(user_id, self.project_id, self.path, sandbox_id=sid);
                        report result;
                    } elif action == "write" {
                        if self.encoding == "base64" {
                            file_bytes = base64.b64decode(self.content);
                            result = write_preview_file_binary(user_id, self.project_id, self.path, file_bytes, sandbox_id=sid);
                        } else {
                            result = write_preview_file(user_id, self.project_id, self.path, self.content, sandbox_id=sid);
                        }
                        if result.get("success", False) and not result.get("skipped", False) {
                            # Single-dir: write_preview_file already wrote to the repo dir.
                            # No duplicate write needed.
                            if os.path.basename(self.path) == "jac.toml" {
                                mark_needs_install(user_id, self.project_id, sandbox_id=sid);
                            }
                            version_res = autosave_version(
                                target.repo_path,
                                "autosave",
                                f"chore: autosave file {self.path}"
                            );
                            if version_res.get("success", False) {
                                target.updated_at = _utc_now();
                                if version_res.get("commit_sha", "") {
                                    target.last_commit = version_res.get("commit_sha", target.last_commit);
                                }
                                version = version_res.get("version", None);
                                if version {
                                    target ++> ProjectVersion(
                                        id=version.get("id", ""),
                                        project_id=self.project_id,
                                        commit_sha=version.get("commit_sha", ""),
                                        jacpack_path=version.get("jacpack_path", ""),
                                        created_at=version.get("created_at", _utc_now()),
                                        trigger=version.get("trigger", "autosave")
                                    );
                                }
                            }
                            result["version"] = version_res if version_res else {};
                        }
                        report result;
                    } elif action == "batch_write" {
                        if not self.files or len(self.files) == 0 {
                            report {"success": False, "error": "files list is required for batch_write"};
                        } else {
                            written: list = [];
                            errors: list = [];
                            needs_install = False;
                            preview_ready = bool(get_preview_dir(user_id, self.project_id, sandbox_id=sid));
                            for file_entry in self.files {
                                fpath = file_entry.get("path", "");
                                fcontent = file_entry.get("content", "");
                                fencoding = file_entry.get("encoding", "");
                                if not fpath {
                                    errors.append({"path": fpath, "error": "empty path"});
                                } else {
                                    if fencoding == "base64" {
                                        # Binary file: decode and write directly
                                        try {
                                            file_bytes = base64.b64decode(fcontent);
                                            if preview_ready {
                                                res = write_preview_file_binary(user_id, self.project_id, fpath, file_bytes, sandbox_id=sid);
                                                ok = res.get("success", False) and not res.get("skipped", False);
                                            } else {
                                                full_path = os.path.normpath(os.path.join(target.repo_path, fpath));
                                                if not full_path.startswith(target.repo_path) {
                                                    errors.append({"path": fpath, "error": "invalid path"});
                                                    continue;
                                                }
                                                parent = os.path.dirname(full_path);
                                                if parent and not os.path.exists(parent) {
                                                    os.makedirs(parent, exist_ok=True);
                                                }
                                                with open(full_path, "wb") as f {
                                                    f.write(file_bytes);
                                                }
                                                ok = True;
                                            }
                                        } except Exception as e {
                                            errors.append({"path": fpath, "error": str(e)});
                                            ok = False;
                                        }
                                    } else {
                                        # Text file: use existing write path
                                        if preview_ready {
                                            res = write_preview_file(user_id, self.project_id, fpath, fcontent, sandbox_id=sid);
                                            ok = res.get("success", False) and not res.get("skipped", False);
                                        } else {
                                            try {
                                                full_path = os.path.normpath(os.path.join(target.repo_path, fpath));
                                                if not full_path.startswith(target.repo_path) {
                                                    errors.append({"path": fpath, "error": "invalid path"});
                                                    continue;
                                                }
                                                parent = os.path.dirname(full_path);
                                                if parent and not os.path.exists(parent) {
                                                    os.makedirs(parent, exist_ok=True);
                                                }
                                                with open(full_path, "w", encoding="utf-8") as f {
                                                    f.write(fcontent);
                                                }
                                                ok = True;
                                            } except Exception as e {
                                                errors.append({"path": fpath, "error": str(e)});
                                                ok = False;
                                            }
                                        }
                                    }
                                    if ok {
                                        written.append(fpath);
                                        if os.path.basename(fpath) == "jac.toml" {
                                            needs_install = True;
                                        }
                                    } elif not ok and fpath not in [e.get("path", "") for e in errors] {
                                        err_msg = "write failed";
                                        if preview_ready and not fencoding {
                                            err_msg = res.get("error", "write failed");
                                        }
                                        errors.append({"path": fpath, "error": err_msg});
                                    }
                                }
                            }
                            if needs_install {
                                mark_needs_install(user_id, self.project_id, sandbox_id=sid);
                            }
                            version_res = {};
                            if len(written) > 0 {
                                version_res = autosave_version(
                                    target.repo_path,
                                    "folder_upload",
                                    "chore: upload " + str(len(written)) + " files"
                                );
                                if version_res.get("success", False) {
                                    target.updated_at = _utc_now();
                                    if version_res.get("commit_sha", "") {
                                        target.last_commit = version_res.get("commit_sha", target.last_commit);
                                    }
                                    version = version_res.get("version", None);
                                    if version {
                                        target ++> ProjectVersion(
                                            id=version.get("id", ""),
                                            project_id=self.project_id,
                                            commit_sha=version.get("commit_sha", ""),
                                            jacpack_path=version.get("jacpack_path", ""),
                                            created_at=version.get("created_at", _utc_now()),
                                            trigger=version.get("trigger", "folder_upload")
                                        );
                                    }
                                }
                            }
                            report {
                                "success": True,
                                "written": written,
                                "errors": errors,
                                "written_count": len(written),
                                "error_count": len(errors),
                                "version": version_res
                            };
                        }
                    } elif action == "delete" {
                        result = delete_preview_file(user_id, self.project_id, self.path, sandbox_id=sid);
                        if result.get("success", False) {
                            # Single-dir: delete_preview_file already deleted from the repo dir.
                            ver_res = autosave_version(target.repo_path, "autosave", f"chore: delete {self.path}");
                            if ver_res.get("success", False) {
                                target.updated_at = _utc_now();
                                if ver_res.get("commit_sha", "") {
                                    target.last_commit = ver_res.get("commit_sha", target.last_commit);
                                }
                                ver_entry = ver_res.get("version", None);
                                if ver_entry {
                                    target ++> ProjectVersion(
                                        id=ver_entry.get("id", ""),
                                        project_id=self.project_id,
                                        commit_sha=ver_entry.get("commit_sha", ""),
                                        jacpack_path=ver_entry.get("jacpack_path", ""),
                                        created_at=ver_entry.get("created_at", _utc_now()),
                                        trigger=ver_entry.get("trigger", "autosave")
                                    );
                                }
                            }
                        }
                        report result;
                    } elif action == "rename" {
                        if not self.path or not self.new_path {
                            report {"success": False, "error": "Both path and new_path are required for rename"};
                        } else {
                            result = rename_preview_item(user_id, self.project_id, self.path, self.new_path, sandbox_id=sid);
                            if result.get("success", False) {
                                # Single-dir: rename_preview_item already renamed in the repo dir.
                                ver_res = autosave_version(target.repo_path, "autosave", f"chore: rename {self.path} -> {self.new_path}");
                                if ver_res.get("success", False) {
                                    target.updated_at = _utc_now();
                                    if ver_res.get("commit_sha", "") {
                                        target.last_commit = ver_res.get("commit_sha", target.last_commit);
                                    }
                                    ver_entry = ver_res.get("version", None);
                                    if ver_entry {
                                        target ++> ProjectVersion(
                                            id=ver_entry.get("id", ""),
                                            project_id=self.project_id,
                                            commit_sha=ver_entry.get("commit_sha", ""),
                                            jacpack_path=ver_entry.get("jacpack_path", ""),
                                            created_at=ver_entry.get("created_at", _utc_now()),
                                            trigger=ver_entry.get("trigger", "autosave")
                                        );
                                    }
                                }
                            }
                            report result;
                        }
                    } elif action == "mkdir" {
                        result = preview_mkdir(user_id, self.project_id, self.path, sandbox_id=sid);
                        if result.get("success", False) {
                            # Single-dir: preview_mkdir already created in the repo dir.
                            ver_res = autosave_version(target.repo_path, "autosave", f"chore: mkdir {self.path}");
                            if ver_res.get("success", False) {
                                target.updated_at = _utc_now();
                                if ver_res.get("commit_sha", "") {
                                    target.last_commit = ver_res.get("commit_sha", target.last_commit);
                                }
                                ver_entry = ver_res.get("version", None);
                                if ver_entry {
                                    target ++> ProjectVersion(
                                        id=ver_entry.get("id", ""),
                                        project_id=self.project_id,
                                        commit_sha=ver_entry.get("commit_sha", ""),
                                        jacpack_path=ver_entry.get("jacpack_path", ""),
                                        created_at=ver_entry.get("created_at", _utc_now()),
                                        trigger=ver_entry.get("trigger", "autosave")
                                    );
                                }
                            }
                        }
                        report result;
                    } elif action == "copy" {
                        if not self.path or not self.new_path {
                            report {"success": False, "error": "Both path and new_path are required for copy"};
                        } else {
                            read_res = read_preview_file(user_id, self.project_id, self.path, sandbox_id=sid);
                            if not read_res.get("success", False) {
                                report {"success": False, "error": "Failed to read source: " + read_res.get("error", "")};
                            } elif read_res.get("is_binary", False) {
                                report {"success": False, "error": "Cannot copy binary files"};
                            } else {
                                src_content = read_res.get("content", "");
                                write_res = write_preview_file(user_id, self.project_id, self.new_path, src_content, sandbox_id=sid);
                                if write_res.get("success", False) and not write_res.get("skipped", False) {
                                    ver_res = autosave_version(target.repo_path, "autosave", f"chore: copy {self.path} -> {self.new_path}");
                                    if ver_res.get("success", False) {
                                        target.updated_at = _utc_now();
                                        if ver_res.get("commit_sha", "") {
                                            target.last_commit = ver_res.get("commit_sha", target.last_commit);
                                        }
                                        ver_entry = ver_res.get("version", None);
                                        if ver_entry {
                                            target ++> ProjectVersion(
                                                id=ver_entry.get("id", ""),
                                                project_id=self.project_id,
                                                commit_sha=ver_entry.get("commit_sha", ""),
                                                jacpack_path=ver_entry.get("jacpack_path", ""),
                                                created_at=ver_entry.get("created_at", _utc_now()),
                                                trigger=ver_entry.get("trigger", "autosave")
                                            );
                                        }
                                    }
                                }
                                report write_res;
                            }
                        }
                    } elif action == "search" {
                        result = search_preview_files(user_id, self.project_id, self.query, self.case_sensitive, sandbox_id=sid);
                        report result;
                    } elif action == "replace" {
                        if not self.query {
                            report {"success": False, "error": "query is required"};
                        } else {
                            result = replace_in_preview_files(
                                user_id, self.project_id, self.query, self.replace_text,
                                self.case_sensitive, self.file_filter, sandbox_id=sid
                            );
                            if result.get("success") and result.get("replaced_files") {
                                # Sync replaced files from preview to repo
                                preview_dir = get_preview_dir(user_id, self.project_id, sandbox_id=sid) or "";
                                repo_path = target.repo_path;
                                for rf in result.get("replaced_files", []) {
                                    src = os.path.join(preview_dir, rf["file"]);
                                    dst = os.path.join(repo_path, rf["file"]);
                                    dst_dir = os.path.dirname(dst);
                                    if dst_dir and not os.path.exists(dst_dir) {
                                        os.makedirs(dst_dir, exist_ok=True);
                                    }
                                    if os.path.isfile(src) {
                                        shutil.copy2(src, dst);
                                    }
                                }
                                ver_res = autosave_version(target.repo_path, "replace", "chore: find-and-replace");
                                if ver_res.get("success", False) {
                                    target.updated_at = _utc_now();
                                    if ver_res.get("commit_sha", "") {
                                        target.last_commit = ver_res.get("commit_sha", target.last_commit);
                                    }
                                    ver_entry = ver_res.get("version", None);
                                    if ver_entry {
                                        target ++> ProjectVersion(
                                            id=ver_entry.get("id", ""),
                                            project_id=self.project_id,
                                            commit_sha=ver_entry.get("commit_sha", ""),
                                            jacpack_path=ver_entry.get("jacpack_path", ""),
                                            created_at=ver_entry.get("created_at", _utc_now()),
                                            trigger=ver_entry.get("trigger", "replace")
                                        );
                                    }
                                }
                            }
                            report result;
                        }
                    } elif action == "log" {
                        result = get_preview_log(user_id, self.project_id, self.log_offset, sandbox_id=sid);
                        report result;
                    } else {
                        report {"success": False, "error": f"Unknown action: {action}"};
                    }
                }
            }
        }
    }
}


walker ai_chat {
    has project_id: str = "";
    has message: str = "";
    has current_file_path: str = "";
    has action: str = "start";
    has response_text: str = "";
    has promoted_files: list = [];
    has is_error: bool = False;
    has checkpoint_ref: str = "";
    has images: list = [];
    has activities_log: list = [];

    can handle_action with Root entry {
        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
            return;
        }

        # Stop action is lightweight — sets abort flag, agent summarizes and stops
        if self.action and self.action.lower().strip() == "stop" {
            result = stop_jaccoder("", self.project_id);
            report result;
            return;
        }

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
            return;
        }

        profile = profiles[0];
        user_id = profile.user_id;
        all_projects = [profile -->(?:Project)];
        target = None;
        for project in all_projects {
            if project.id == self.project_id {
                target = project;
                break;
            }
        }

        if not target {
            report {"success": False, "error": "Project not found"};
            return;
        }

        action = self.action.lower().strip() if self.action else "start";

        # Get preview workspace directory (required for start/poll, not for history actions)
        preview_dir = get_preview_dir(user_id, self.project_id) or "";
        print(f"[ai_chat] action={action} user={user_id} project={self.project_id} preview_dir={preview_dir}");
        if not preview_dir and action not in ["load_history", "clear_history"] {
            print(f"[ai_chat] BLOCKED: no preview_dir for action={action}");
            report {"success": False, "error": "Preview not set up. Start preview first."};
            return;
        }

        if action == "start" {
            # On first ai_chat start per project, reset any stale ai_processing
            # flags left from a prior server crash (graph flag persists, in-memory
            # state does not). This is cheap and idempotent.
            if target.ai_processing and not is_ai_processing(user_id, self.project_id) {
                target.ai_processing = False;
                print(f"[ai_chat] Reset stale ai_processing flag on project {self.project_id}");
            }

            # --- Non-blocking mode: launch agent in background, return immediately ---
            session_id = get_or_create_session(user_id, self.project_id, preview_dir);
            if not session_id {
                report {"success": False, "error": "Failed to create JacCoder session"};
                return;
            }

            # Build agent context as a system-level instruction (separate from user message)
            agent_ctx = f"Working directory: {preview_dir}\n";
            if self.current_file_path {
                agent_ctx += f"Currently open file: {os.path.join(preview_dir, self.current_file_path)}\n";
            }
            agent_ctx += "\n[LIVE PREVIEW MODE]\n";
            agent_ctx += "The user is watching a LIVE preview of the app as you build it (Vite dev server with HMR).\n";
            agent_ctx += "BUILD INCREMENTALLY — one component at a time so each piece appears live:\n";
            agent_ctx += "1. Start with jac.toml and main.jac (entry point with basic layout/routing)\n";
            agent_ctx += "2. Write ONE component file, make it complete and renderable on its own\n";
            agent_ctx += "3. Import/wire it into the parent page or main.jac so it shows in the preview\n";
            agent_ctx += "4. Move to the next component — repeat until done\n";
            agent_ctx += "DO NOT use scaffold_project. Write each file individually with write_file.\n";
            agent_ctx += "DO NOT write placeholder/stub files — each file should render real UI immediately.\n";
            agent_ctx += "The user sees each component appear in real-time as you write it.\n";

            # Ensure preview is running so jac-coder has a sandbox for browser testing
            import logging;
            _log = logging.getLogger("jac.ai_chat");
            preview_url = "";
            sandbox_sid = target.preview_sandbox_id or "";
            import from services.sandbox_store {
                get_status as _ss_get_status,
                is_k8s_sandbox as _ai_is_k8s,
                find_sandbox_for_project as _ss_find_proj
            }

            _k8s_mode = _ai_is_k8s();
            _log.warning(f"[ai_chat] k8s={_k8s_mode} sandbox_sid={sandbox_sid} user={user_id} project={self.project_id}");
            if _k8s_mode {
                # Fast path: graph node lookup
                all_si = [-->(?:SandboxInstance)];
                _log.warning(f"[ai_chat] SandboxInstance nodes found: {len(all_si)}");
                if not sandbox_sid {
                    existing_si = _ss_find_proj(all_si, user_id, self.project_id, "preview");
                    if existing_si is not None {
                        sandbox_sid = str(existing_si.sandbox_id);
                        target.preview_sandbox_id = sandbox_sid;
                        _log.warning(f"[ai_chat] recovered sandbox_sid={sandbox_sid} from graph");
                    }
                }
                if sandbox_sid {
                    sb_status = _ss_get_status(all_si, sandbox_sid);
                    preview_url = sb_status.get("url", "");
                    _log.warning(f"[ai_chat] sandbox status: sid={sandbox_sid} status={sb_status.get('status', 'none')} url={preview_url}");
                }
                # Fallback: graph cache may be stale — query MongoDB directly
                if not preview_url {
                    import from services.sandbox_store { find_sandbox_id_from_db as _ss_find_db, build_sandbox_url as _build_url }
                    _log.warning(f"[ai_chat] graph cache stale, querying MongoDB directly");
                    db_result = _ss_find_db(user_id, self.project_id, "preview");
                    if db_result.get("sandbox_id") {
                        sandbox_sid = db_result["sandbox_id"];
                        preview_url = db_result.get("url", "");
                        target.preview_sandbox_id = sandbox_sid;
                        if not preview_url {
                            preview_url = _build_url(sandbox_sid);
                        }
                        _log.warning(f"[ai_chat] MongoDB fallback: sid={sandbox_sid} url={preview_url}");
                    } else {
                        _log.warning(f"[ai_chat] no sandbox in MongoDB either");
                    }
                }
            } else {
                preview_status = get_preview_status(user_id, self.project_id, sandbox_id=sandbox_sid);
                if preview_status.get("url") {
                    preview_url = preview_status["url"];
                }
                _log.warning(f"[ai_chat] LOCAL mode: url={preview_status.get('url', '')}");
            }
            if preview_url {
                agent_ctx += "\n[PREVIEW SERVER — ALREADY RUNNING]\n";
                agent_ctx += "A live preview server is ALREADY running and managed externally. Do NOT start your own server with run_command('jac start ...') — it will fail.\n";
                agent_ctx += "To browser-test the app, call browser_open() directly (no URL needed — the preview URL is pre-configured).\n";
                agent_ctx += "Browser tools: browser_open() → browser_do('click @e1') → browser_state() → browser_close().\n";
            }

            # Create checkpoint before AI turn for rollback support
            checkpoint = git_create_checkpoint(target.repo_path);
            checkpoint_ref = checkpoint.get("checkpoint_ref", "") if checkpoint.get("success") else "";

            # Start async processing — returns immediately
            result = start_jaccoder_async(
                session_id,
                self.message,
                user_id,
                self.project_id,
                preview_dir,
                repo_path=target.repo_path,
                project_node=target,
                agent_context=agent_ctx,
                preview_url=preview_url,
                images=self.images,
                sandbox_id=sandbox_sid
            );

            # Persist user message to graph (Lovable-style: single chat per project)
            if result.get("success", False) {
                _msg = JacCoderMessage(
                    id=str(uuid4()),
                    role="user",
                    content=self.message,
                    images=self.images,
                    created_at=_utc_now()
                );
                target ++> _msg;
                Jac.perm_grant(_msg, "WRITE");
            }

            report {
                "success": result.get("success", False),
                "status": result.get("status", "error"),
                "error": result.get("error", ""),
                "checkpoint_ref": checkpoint_ref
            };

        } elif action == "poll" {
            # --- Poll for events and check completion ---
            # Note: persistence is handled by the "persist_done" action (called
            # by frontend after WS polling completes). This action is drain-only.
            events = drain_events(user_id, self.project_id, project_node=target);
            processing = is_ai_processing(user_id, self.project_id, project_node=target);

            done_event = None;
            for evt in events {
                if evt.get("type") == "agent_done" {
                    done_event = evt;
                    break;
                }
            }

            report {
                "success": True,
                "events": events,
                "processing": processing,
                "done": done_event is not None
            };

        } elif action == "load_history" {
            # Return all persisted messages for this project, ordered by created_at
            all_msgs = [target -->(?:JacCoderMessage)];
            all_msgs.sort(key=lambda m: m.created_at);
            history: list = [];
            for m in all_msgs {
                entry = {
                    "role": m.role,
                    "content": m.content,
                    "timestamp": m.created_at
                };
                if m.updated_files {
                    entry["updatedFiles"] = m.updated_files;
                }
                if m.checkpoint_ref {
                    entry["checkpoint_ref"] = m.checkpoint_ref;
                }
                if m.version_id {
                    entry["version_id"] = m.version_id;
                }
                if m.images and len(m.images) > 0 {
                    entry["images"] = m.images;
                }
                if m.activities_log and len(m.activities_log) > 0 {
                    entry["activities_log"] = m.activities_log;
                }
                history.append(entry);
            }
            report {"success": True, "messages": history};

        } elif action == "clear_history" {
            # If AI is actively processing, drain remaining events and stop it
            # before clearing — prevents orphaned assistant messages.
            if is_ai_processing(user_id, self.project_id, project_node=target) {
                drain_events(user_id, self.project_id, project_node=target);
            }
            # Delete all JacCoderMessage nodes for this project
            all_msgs = [target -->(?:JacCoderMessage)];
            count = len(all_msgs);
            for m in all_msgs {
                target del--> m;
                del m;
            }
            # Also clear jac-coder session so chat_history resets
            clear_session(user_id, self.project_id, project_node=target);
            report {"success": True, "deleted": count};

        } elif action == "persist_done" {
            # Persist assistant/error response after WS polling completes.
            # The WS ai_events path is lightweight (drain only); this HTTP
            # action handles durable persistence + git versioning.

            # Create git version FIRST to get commit_sha for the message
            commit_sha = "";
            if self.promoted_files and not self.is_error {
                commit_label = "";
                ci = 0;
                for wf in self.promoted_files {
                    if ci >= 3 { break; }
                    if ci > 0 { commit_label += ", "; }
                    commit_label += wf;
                    ci += 1;
                }
                version_res = autosave_version(
                    target.repo_path,
                    "ai_chat",
                    "chore: AI chat update - " + commit_label
                );
                if version_res.get("success", False) {
                    commit_sha = version_res.get("commit_sha", "");
                    target.updated_at = _utc_now();
                    if commit_sha {
                        target.last_commit = commit_sha;
                    }
                    version = version_res.get("version", None);
                    if version {
                        target ++> ProjectVersion(
                            id=version.get("id", ""),
                            project_id=self.project_id,
                            commit_sha=version.get("commit_sha", ""),
                            jacpack_path=version.get("jacpack_path", ""),
                            created_at=version.get("created_at", _utc_now()),
                            trigger=version.get("trigger", "ai_chat")
                        );
                    }
                }
            }

            # Now persist message with checkpoint_ref, version_id, and activities_log
            if self.response_text {
                msg_role = "error" if self.is_error else "assistant";
                _msg = JacCoderMessage(
                    id=str(uuid4()),
                    role=msg_role,
                    content=self.response_text,
                    updated_files=self.promoted_files if not self.is_error else [],
                    checkpoint_ref=self.checkpoint_ref if not self.is_error else "",
                    version_id=commit_sha if not self.is_error else "",
                    activities_log=self.activities_log if not self.is_error else [],
                    created_at=_utc_now()
                );
                target ++> _msg;
                Jac.perm_grant(_msg, "WRITE");
            }
            report {"success": True, "version_commit_sha": commit_sha};

        } elif action == "revert_to_message" {
            # Non-destructive revert to a previous AI turn's checkpoint
            if not self.checkpoint_ref {
                report {"success": False, "error": "checkpoint_ref is required"};
                return;
            }
            # Only check in-memory state (authoritative for active threads).
            # The graph flag target.ai_processing can be stale after server
            # restarts, so we intentionally skip it here and reset it below.
            if is_ai_processing(user_id, self.project_id) {
                report {"success": False, "error": "Cannot revert while AI is processing"};
                return;
            }
            target.ai_processing = False;
            revert_res = git_revert_to_commit(target.repo_path, self.checkpoint_ref);
            if revert_res.get("success") {
                # Re-sync preview: cleanup old dir, setup fresh copy from reverted repo
                # Frontend will call startPreview to spawn the subprocess
                print(f"[ai_chat] revert success: cleanup+setup preview project={self.project_id} repo_path={target.repo_path}");
                cleanup_preview(user_id, self.project_id);
                setup_preview(user_id, self.project_id, target.repo_path);
                # Update project metadata
                if revert_res.get("commit_sha") {
                    target.last_commit = revert_res.get("commit_sha", target.last_commit);
                }
                target.updated_at = _utc_now();
            }
            report revert_res;

        } else {
            report {"success": False, "error": f"Unknown ai_chat action: {action}"};
        }
    }
}

walker:pub community_ops {
    has action: str = "list";
    has search: str = "";
    has tag: str = "";
    has comm_id: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list";
        if action == "list" {
            items = list_community_templates(self.search, self.tag);
            report {"success": True, "items": items};
        } elif action == "get" {
            if not self.comm_id {
                report {"success": False, "error": "comm_id is required"};
            } else {
                result = get_community_template(self.comm_id);
                report result;
            }
        } else {
            report {"success": False, "error": f"Unknown action: {action}"};
        }
    }
}

walker community_submit {
    has action: str = "submit";
    has name: str = "";
    has description: str = "";
    has tags: list = [];
    has jacpack_content_base64: str = "";
    has comm_id: str = "";
    has project_name: str = "";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "submit";

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "Not authenticated"};
        } else {
            profile = profiles[0];

            if action == "submit" {
                if not self.name or not self.name.strip() {
                    report {"success": False, "error": "name is required"};
                } elif not self.jacpack_content_base64 {
                    report {"success": False, "error": "jacpack_content_base64 is required"};
                } elif len(self.jacpack_content_base64) > 14_000_000 {
                    report {"success": False, "error": "Upload too large (max 10MB)"};
                } else {
                    tmp_path = None;
                    try {
                        tmp_path = os.path.join(tempfile.gettempdir(), "comm_upload_" + str(int(time.time() * 1000)) + ".jacpack");
                        content_bytes = base64.b64decode(self.jacpack_content_base64);
                        with open(tmp_path, "wb") as f {
                            f.write(content_bytes);
                        }
                        item_tags = self.tags if isinstance(self.tags, list) else [];
                        result = submit_community_template(
                            profile.user_id,
                            profile.display_name or profile.user_id,
                            self.name.strip(),
                            self.description or "",
                            item_tags,
                            tmp_path
                        );
                        report result;
                    } except Exception as e {
                        report {"success": False, "error": str(e)};
                    } finally {
                        if tmp_path and os.path.exists(tmp_path) {
                            try { os.unlink(tmp_path); } except Exception { }
                        }
                    }
                }
            } elif action == "clone" {
                if not self.comm_id {
                    report {"success": False, "error": "comm_id is required"};
                } elif _get_project_count(profile.user_id) >= MAX_PROJECTS_PER_USER {
                    report {"success": False, "error": "Project limit reached (3 per user). Delete an existing project to clone."};
                } else {
                    jacpack_path = get_community_jacpack_path(self.comm_id);
                    if not jacpack_path {
                        report {"success": False, "error": "Community item not found or file missing"};
                    } else {
                        now = datetime.utcnow().isoformat() + "Z";
                        clone_name = (self.project_name.strip() if self.project_name else "cloned-project");
                        result = create_project_from_jacpack(profile.user_id, clone_name, jacpack_path, profile.display_name);
                        if not result.get("success", False) {
                            report result;
                        } else {
                            increment_clone_count(self.comm_id);
                            created = result.get("project", {});
                            created_node = profile ++> Project(
                                id=created.get("id", ""),
                                name=created.get("name", clone_name),
                                template_id="community",
                                repo_path=created.get("repo_path", ""),
                                created_at=created.get("created_at", now),
                                updated_at=created.get("updated_at", now),
                                active_branch=created.get("active_branch", "main"),
                                last_commit=created.get("last_commit", "")
                            );
                            versions = list_project_versions(created.get("repo_path", ""));
                            for version in versions {
                                created_node ++> ProjectVersion(
                                    id=version.get("id", ""),
                                    project_id=created.get("id", ""),
                                    commit_sha=version.get("commit_sha", ""),
                                    jacpack_path=version.get("jacpack_path", ""),
                                    created_at=version.get("created_at", now),
                                    trigger=version.get("trigger", "clone")
                                );
                            }
                            project_payload = _project_to_dict(created_node) if created_node else {};
                            if not project_payload.get("id", "") {
                                project_payload = {
                                    "id": created.get("id", ""),
                                    "name": created.get("name", clone_name),
                                    "template_id": "community",
                                    "repo_path": created.get("repo_path", ""),
                                    "created_at": created.get("created_at", now),
                                    "updated_at": created.get("updated_at", now),
                                    "active_branch": created.get("active_branch", "main"),
                                    "last_commit": created.get("last_commit", "")
                                };
                            }
                            _project_counts[profile.user_id] = _get_project_count(profile.user_id) + 1;
                            report {"success": True, "project": project_payload};
                        }
                    }
                }
            } elif action == "remove" {
                if not self.comm_id {
                    report {"success": False, "error": "comm_id is required"};
                } else {
                    removed = remove_community_template(self.comm_id, profile.user_id);
                    if removed {
                        report {"success": True};
                    } else {
                        report {"success": False, "error": "Not found or not your submission"};
                    }
                }
            } else {
                report {"success": False, "error": f"Unknown action: {action}"};
            }
        }
    }
}

walker env_ops {
    has project_id: str = "";
    has action: str = "list_project";
    has env_list: list = [];

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list_project";
        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
        } else {
            profile = profiles[0];
            if action == "list_global" or action == "save_global" {
                global_env_path = os.path.join(
                    os.path.expanduser("~"), ".jac-ide", "users",
                    profile.user_id, "global.env"
                );
                if action == "list_global" {
                    items = read_project_env(global_env_path);
                    report {"success": True, "env_list": items};
                } else {
                    result = write_project_env(global_env_path, self.env_list);
                    report result;
                }
            } elif not self.project_id {
                report {"success": False, "error": "project_id is required"};
            } else {
                all_projects = [profile -->(?:Project)];
                target = None;
                for project in all_projects {
                    if project.id == self.project_id {
                        target = project;
                        break;
                    }
                }
                if not target {
                    report {"success": False, "error": "Project not found"};
                } else {
                    repo_path = target.repo_path;
                    if action == "list_project" {
                        env_path = os.path.join(repo_path, ".env");
                        items = read_project_env(env_path);
                        report {"success": True, "env_list": items};
                    } elif action == "save_project" {
                        env_path = os.path.join(repo_path, ".env");
                        result = write_project_env(env_path, self.env_list);
                        report result;
                    } else {
                        report {"success": False, "error": f"Unknown action: {action}"};
                    }
                }
            }
        }
    }
}

walker deploy_ops {
    has action: str = "deploy";
    has project_id: str = "";
    has deploy_mode: str = "permanent";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "deploy";
        mode = self.deploy_mode.lower().strip() if self.deploy_mode else "permanent";
        is_sandbox = mode == "sandbox";

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
        } else {
            profile = profiles[0];
            user_id = profile.user_id;

            if not self.project_id {
                report {"success": False, "error": "project_id is required"};
            } else {
                all_projects = [profile -->(?:Project)];
                target = None;
                for project in all_projects {
                    if project.id == self.project_id {
                        target = project;
                        break;
                    }
                }
                if not target {
                    report {"success": False, "error": "Project not found"};
                } elif is_sandbox {
                    # --- Sandbox deploy: via sandbox_store (purpose="deploy") ---
                    import from services.sandbox_store {
                        ensure_sandbox as ss_ensure,
                        destroy_sandbox as ss_destroy,
                        get_status_for_project as ss_status,
                        find_sandbox_for_project as ss_find
                    }
                    all_si = [-->(?:SandboxInstance)];

                    if action == "deploy" {
                        result = ss_ensure(
                            all_si, user_id, target.id,
                            purpose="deploy",
                            source_dir=target.repo_path,
                            ttl_seconds=604800
                        );
                        if result.get("success", False) {
                            target.sandbox_status = "running";
                            target.sandbox_url = result.get("url", "");
                            target.sandbox_app_name = result.get("sandbox_id", "");
                            target.sandbox_namespace = "jac-sandboxes";
                            if result.get("_create_params") {
                                _create_sandbox_node(here, result["_create_params"]);
                            }
                        } else {
                            target.sandbox_status = "failed";
                        }
                        report {
                            "success": result.get("success", False),
                            "message": result.get("message", "Sandbox deployment started"),
                            "project": _project_to_dict(target),
                            "deployment": {
                                "status": target.sandbox_status,
                                "url": target.sandbox_url,
                                "namespace": target.sandbox_namespace,
                                "app_name": target.sandbox_app_name
                            }
                        };
                    } elif action == "status" {
                        existing_si = ss_find(all_si, user_id, target.id, "deploy");
                        if existing_si is not None {
                            sb_status = ss_status(all_si, user_id, target.id, "deploy");
                            state = sb_status.get("status", "unknown");
                            url = sb_status.get("url", "");
                            if state == "running" {
                                target.sandbox_status = "running";
                            }
                            if url {
                                target.sandbox_url = url;
                            }
                        }
                        report {
                            "success": True,
                            "project": _project_to_dict(target),
                            "deployment": {
                                "status": target.sandbox_status,
                                "url": target.sandbox_url,
                                "namespace": target.sandbox_namespace,
                                "app_name": target.sandbox_app_name
                            }
                        };
                    } elif action == "destroy" {
                        existing_si = ss_find(all_si, user_id, target.id, "deploy");
                        if existing_si is None {
                            report {"success": False, "error": "No sandbox deploy to destroy"};
                        } else {
                            target.sandbox_status = "destroying";
                            result = ss_destroy(all_si, str(existing_si.sandbox_id));
                            here del--> existing_si;
                            if result.get("success", False) {
                                target.sandbox_status = "";
                                target.sandbox_url = "";
                                target.sandbox_app_name = "";
                                target.sandbox_namespace = "";
                            } else {
                                target.sandbox_status = "failed";
                            }
                            report {
                                "success": result.get("success", False),
                                "message": result.get("message", result.get("error", "")),
                                "project": _project_to_dict(target)
                            };
                        }
                    } else {
                        report {"success": False, "error": f"Unknown action: {action}"};
                    }
                } else {
                    # --- Permanent deploy: full K8s namespace via deploy_manager ---
                    if action == "deploy" {
                        if target.deployment_status == "deploying" {
                            report {"success": False, "error": "Deployment already in progress"};
                        } else {
                            (app_name, namespace) = generate_deploy_identifiers(user_id, target.name);
                            target.deployment_status = "deploying";
                            target.deployment_app_name = app_name;
                            target.deployment_namespace = namespace;
                            target.deployment_url = "";

                            deploy_async(user_id, target.name, target.repo_path, None);
                            report {
                                "success": True,
                                "message": "Deployment started",
                                "project": _project_to_dict(target)
                            };
                        }
                    } elif action == "status" {
                        if target.deployment_app_name and target.deployment_namespace {
                            if target.deployment_status == "deploying" {
                                deploy_result = get_deploy_result(user_id, target.name);
                                if deploy_result {
                                    if deploy_result.get("success", False) {
                                        target.deployment_status = "running";
                                        target.deployment_url = deploy_result.get("url", "");
                                    } else {
                                        target.deployment_status = "failed";
                                    }
                                }
                            } else {
                                status = get_deployment_status(target.deployment_app_name, target.deployment_namespace);
                                if status.get("success", False) {
                                    new_status = status.get("status", "unknown");
                                    if new_status == "running" {
                                        target.deployment_status = "running";
                                    }
                                    url = status.get("url", "");
                                    if url {
                                        target.deployment_url = url;
                                    }
                                }
                            }
                        }
                        report {
                            "success": True,
                            "project": _project_to_dict(target),
                            "deployment": {
                                "status": target.deployment_status,
                                "url": target.deployment_url,
                                "namespace": target.deployment_namespace,
                                "app_name": target.deployment_app_name
                            }
                        };
                    } elif action == "destroy" {
                        if not target.deployment_namespace or not target.deployment_app_name {
                            report {"success": False, "error": "No active deployment to destroy"};
                        } else {
                            target.deployment_status = "destroying";
                            result = destroy_deployment(target.deployment_app_name, target.deployment_namespace);
                            if result.get("success", False) {
                                target.deployment_status = "";
                                target.deployment_url = "";
                                target.deployment_app_name = "";
                                target.deployment_namespace = "";
                            } else {
                                target.deployment_status = "failed";
                            }
                            report {
                                "success": result.get("success", False),
                                "message": result.get("message", ""),
                                "project": _project_to_dict(target)
                            };
                        }
                    } else {
                        report {"success": False, "error": f"Unknown action: {action}"};
                    }
                }
            }
        }
    }
}

@restspec(protocol=APIProtocol.WEBSOCKET)
async walker ide_preview_stream {
    has action: str = "";
    has project_id: str = "";
    has log_offset: int = 0;
    has worktree_path: str = "";
    has connection_id: str = "";
    has request_id: str = "";

    has user_id: str = "";

    async can handle with Root entry {
        # JWT-authenticated walker — runs on user root.
        # user_id passed by client as fallback; validated via JWT context.
        user_id = self.user_id;
        if not user_id {
            profiles = [-->(?:UserProfile)];
            if profiles and len(profiles) > 0 {
                user_id = profiles[0].user_id;
            }
        }
        if not user_id {
            report {"type": "error", "request_id": self.request_id, "data": {"success": False, "error": "User not identified"}};
            return;
        }

        # Keep session alive while user is polling
        if self.project_id {
            touch_session(user_id, self.project_id);
        }

        action = self.action.lower().strip() if self.action else "";
        rid = self.request_id;
        cid = self.connection_id;

        # Multi-pod discovery: SandboxInstance nodes on global root (MongoDB-backed).
        # Every pod sees the same nodes — no populate_from_shared() needed.
        import from services.sandbox_store {
            ensure_sandbox as ss_ensure,
            stop_sandbox as ss_stop,
            destroy_sandbox as ss_destroy,
            get_status_for_project as ss_status,
            find_sandbox_for_project as ss_find,
            sandbox_id_for as ss_id_for
        }
        all_si = [-->(?:SandboxInstance)];

        # Update heartbeat if sandbox exists (keeps TTL alive while user is polling)
        if user_id and self.project_id {
            existing_si = ss_find(all_si, user_id, self.project_id, "preview");
            if existing_si is not None {
                existing_si.last_heartbeat = time.time();
            }
        }

        if action == "start" {
            import from services.preview_manager { _staging_dirs }
            # Resolve source_dir: SandboxInstance → _preview_registry → _staging_dirs
            existing_si = ss_find(all_si, user_id, self.project_id, "preview");
            prev_source = "";
            if existing_si is not None {
                prev_source = existing_si.source_dir or "";
            }
            if not prev_source {
                existing_reg = _preview_registry.get(_preview_key(user_id, self.project_id));
                if existing_reg {
                    prev_source = existing_reg.get("source_dir", "") or existing_reg.get("dir", "");
                }
            }
            if not prev_source {
                prev_source = _staging_dirs.get(_preview_key(user_id, self.project_id), "");
            }
            print(f"[ide_preview_stream] WS start: user={user_id} project={self.project_id} worktree={self.worktree_path} source={prev_source}");

            # Reuse existing running sandbox — don't create a new one if preview
            # is still alive (e.g. user navigated away and came back)
            if existing_si is not None and str(existing_si.desired_state) == "running" and not self.worktree_path {
                existing_si.last_heartbeat = time.time();
                setup_preview(user_id, self.project_id, prev_source, self.worktree_path);
                report {
                    "type": "status", "request_id": rid,
                    "data": {
                        "success": True,
                        "url": existing_si.url,
                        "port": int(existing_si.port),
                        "api_port": 0,
                        "status": "running"
                    }
                };
                print(f"[ide_preview_stream] Reusing existing sandbox sid={existing_si.sandbox_id}");
            } else {

            # Destroy stale stopped/error sandbox before creating a new one
            if existing_si is not None and str(existing_si.desired_state) in ("stopped", "error") {
                ss_destroy(all_si, str(existing_si.sandbox_id));
                cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id));
                all_si = [-->(?:SandboxInstance)];
            }

            # Handle worktree switching
            if self.worktree_path and existing_si is not None and str(existing_si.desired_state) not in ("stopped", "error", "destroyed") {
                ss_destroy(all_si, str(existing_si.sandbox_id));
                cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
            } elif not self.worktree_path and existing_si is not None and existing_si.is_worktree and str(existing_si.desired_state) not in ("stopped", "error", "destroyed") {
                ss_destroy(all_si, str(existing_si.sandbox_id));
                cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
            }

            # Setup preview workspace (file watcher, jac install)
            setup_preview(user_id, self.project_id, prev_source, self.worktree_path);

            # After setup, staging_dirs has the actual dir — use it as source
            effective_source = _staging_dirs.get(_preview_key(user_id, self.project_id), prev_source);

            # Re-fetch after potential destroy
            all_si = [-->(?:SandboxInstance)];

            # Create or get sandbox via sandbox_store (synchronous K8s create)
            result = ss_ensure(
                all_si, user_id, self.project_id,
                purpose="preview",
                source_dir=effective_source,
                worktree_path=self.worktree_path
            );

            # Persist graph node if new sandbox was created
            if result.get("_create_params") {
                _create_sandbox_node(here, result["_create_params"]);
                print(f"[ide_preview_stream] Created SandboxInstance sid={result.get('sandbox_id', '')}");
            }

            } # end else (new sandbox creation)

            # Store sandbox_id on Project node + register file watcher
            new_sid = result.get("sandbox_id", "");
            if result.get("success") and new_sid {
                # Set preview_sandbox_id on the Project node so ai_chat can find it
                profiles = [-->(?:UserProfile)];
                if profiles and len(profiles) > 0 {
                    all_projects = [profiles[0] -->(?:Project)];
                    for proj in all_projects {
                        if proj.id == self.project_id {
                            proj.preview_sandbox_id = new_sid;
                            break;
                        }
                    }
                }
                if prev_source {
                    try {
                        import from services.file_watcher { register_sandbox_for_dir }
                        register_sandbox_for_dir(prev_source, new_sid);
                    } except Exception {
                        x = 0;
                    }
                }
            }

            report {"type": "status", "request_id": rid, "data": {
                "success": result.get("success", False),
                "url": result.get("url", ""),
                "port": result.get("port", 0),
                "api_port": 0,
                "status": result.get("status", "error")
            }};
        } elif action == "stop" {
            existing_si = ss_find(all_si, user_id, self.project_id, "preview");
            if existing_si is not None {
                result = ss_stop(all_si, str(existing_si.sandbox_id));
            } else {
                result = stop_preview(user_id, self.project_id, sandbox_id="");
            }
            report {"type": "status", "request_id": rid, "data": result};
        } elif action == "status" {
            existing_si = ss_find(all_si, user_id, self.project_id, "preview");
            if existing_si is not None {
                result = ss_status(all_si, user_id, self.project_id);
            } else {
                result = get_preview_status(user_id, self.project_id, sandbox_id="");
            }
            report {"type": "status", "request_id": rid, "data": result};
        } elif action == "log" {
            log_si = ss_find(all_si, user_id, self.project_id, "preview");
            log_sid = str(log_si.sandbox_id) if log_si is not None else "";
            result = get_preview_log(user_id, self.project_id, self.log_offset, sandbox_id=log_sid);
            report {"type": "log", "request_id": rid, "data": result};
        } elif action == "cleanup" {
            existing_si = ss_find(all_si, user_id, self.project_id, "preview");
            if existing_si is not None {
                ss_destroy(all_si, str(existing_si.sandbox_id));
                # Remove node from graph
                here del--> existing_si;
                print(f"[ide_preview_stream] Removed SandboxInstance");
            }
            result = cleanup_preview(user_id, self.project_id, sandbox_id=str(existing_si.sandbox_id) if existing_si is not None else "");
            report {"type": "status", "request_id": rid, "data": result};
        } elif action == "ai_events" {
            events = drain_events(user_id, self.project_id, connection_id=cid);
            processing = is_ai_processing(user_id, self.project_id);
            report {"type": "ai_events", "request_id": rid, "data": {"success": True, "events": events, "processing": processing}};
        } elif action == "claude_events" {
            events = drain_claude_events(user_id, self.project_id, connection_id=cid);
            processing = is_claude_processing(user_id, self.project_id);
            report {"type": "claude_events", "request_id": rid, "data": {"success": True, "events": events, "processing": processing}};
        } elif action == "file_events" {
            events = drain_file_events(user_id, self.project_id, connection_id=cid);
            report {"type": "file_events", "request_id": rid, "data": {"success": True, "events": events}};
        } else {
            report {"type": "error", "request_id": rid, "data": {"success": False, "error": f"Unknown action: {action}"}};
        }
    }
}

@restspec(protocol=APIProtocol.WEBSOCKET)
async walker :pub lsp_stream {
    has user_id: str = "";
    has project_id: str = "";
    has action: str = "";
    has data: dict = {};
    has ws_token: str = "";

    async can handle with Root entry {
        # Validate WS auth token with TTL check
        if not _validate_ws_token(self.user_id, self.ws_token) {
            report {"type": "error", "data": {"success": False, "error": "Invalid or missing ws_token"}};
            return;
        }

        action = self.action.lower().strip() if self.action else "";
        if action == "init" {
            workspace_dir = self.data.get("workspace_dir", "") if self.data else "";
            result = start_lsp(self.user_id, self.project_id, workspace_dir);
            report {"type": "lsp_init", "data": result};
        } elif action == "message" {
            msg = self.data if self.data else {};
            send_result = send_lsp_message(self.user_id, self.project_id, msg);
            if not send_result.get("success") {
                report {"type": "lsp_response", "data": send_result};
            } else {
                response = None;
                if "id" in msg {
                    response = wait_lsp_response(self.user_id, self.project_id, msg["id"], 5.0);
                }
                notifications = drain_lsp_notifications(self.user_id, self.project_id);
                report {
                    "type": "lsp_response",
                    "data": {
                        "success": True,
                        "response": response,
                        "notifications": notifications
                    }
                };
            }
        } elif action == "poll" {
            notifications = drain_lsp_notifications(self.user_id, self.project_id);
            report {"type": "lsp_notifications", "data": {"success": True, "notifications": notifications}};
        } elif action == "close" {
            result = stop_lsp(self.user_id, self.project_id);
            report {"type": "lsp_close", "data": result};
        } elif action == "status" {
            result = get_lsp_status(self.user_id, self.project_id);
            report {"type": "lsp_status", "data": result};
        } else {
            report {"type": "error", "data": {"success": False, "error": "Unknown LSP action: " + str(action)}};
        }
    }
}


# ===========================================================================
# Claude Thread Helpers
# ===========================================================================

"""Find a ClaudeThread by ID under a Project node."""
def _find_thread(project: Any, thread_id: str) -> Any {
    if not thread_id {
        return None;
    }
    all_threads = [project -->(?:ClaudeThread)];
    for t in all_threads {
        if t.id == thread_id {
            return t;
        }
    }
    return None;
}

"""Find or create a ClaudeThread under a Project node.

When env_mode is 'local', reuse the single local thread for this project
(a thread with no worktree_path). This enforces one-local-thread-per-project
since local threads share the same filesystem — multiple local threads would
give a false sense of isolation."""
def _find_or_create_thread(
    project: Any, thread_id: str, message: str, model: str,
    env_mode: str = "local"
) -> Any {
    if thread_id {
        existing = _find_thread(project, thread_id);
        if existing {
            return existing;
        }
    }
    # For local mode, reuse existing local thread if one exists
    if env_mode == "local" {
        all_threads = [project -->(?:ClaudeThread)];
        for t in all_threads {
            if not t.worktree_path {
                return t;
            }
        }
    }
    now = _utc_now();
    title = message[:80] if len(message) > 80 else message;
    thread_node = ClaudeThread(
        id=str(uuid4()),
        title=title,
        model=model,
        created_at=now,
        updated_at=now
    );
    project ++> thread_node;
    return thread_node;
}

"""Add a ClaudeMessage to a thread."""
def _add_message_to_thread(
    thread: Any, role: str, content: str, turn_number: int
) -> Any {
    msg = ClaudeMessage(
        id=str(uuid4()),
        role=role,
        content=content,
        turn_number=turn_number,
        created_at=_utc_now()
    );
    thread ++> msg;
    return msg;
}

"""Add a ClaudeActivity to a thread."""
def _add_activity_to_thread(
    thread: Any, activity_type: str, tool_name: str,
    message: str, status: str, turn_number: int,
    tool_input: str = "", tool_output: str = ""
) -> Any {
    act = ClaudeActivity(
        id=str(uuid4()),
        activity_type=activity_type,
        tool_name=tool_name,
        message=message,
        tool_input=tool_input,
        tool_output=tool_output,
        status=status,
        turn_number=turn_number,
        created_at=_utc_now()
    );
    thread ++> act;
    return act;
}

"""Update thread status by ID."""
def _update_thread_status(project: Any, thread_id: str, status: str) -> None {
    if not thread_id {
        return;
    }
    thread = _find_thread(project, thread_id);
    if thread {
        thread.status = status;
        thread.updated_at = _utc_now();
    }
}


# ===========================================================================
# Claude Code Chat Walker
# ===========================================================================

walker claude_chat {
    has project_id: str;
    has thread_id: str = "";
    has message: str = "";
    has action: str = "start";
    has model: str = "";
    has allowed_tools: str = "Read,Edit,Bash,Glob,Grep,Write";
    has env_mode: str = "local";
    has branch: str = "";
    has images: list = [];
    has activities: list = [];

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "start";

        # Check doesn't need a project — just detect Claude CLI
        if action == "check" {
            result = check_claude_availability();
            report result;
            return;
        }

        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
            return;
        }

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
            return;
        }

        profile = profiles[0];
        user_id = profile.user_id;
        all_projects = [profile -->(?:Project)];
        target = None;
        for project in all_projects {
            if project.id == self.project_id {
                target = project;
                break;
            }
        }

        if not target {
            report {"success": False, "error": "Project not found"};
            return;
        }

        if action == "start" {
            # Send a turn to Claude Code CLI
            if not self.message {
                report {"success": False, "error": "Message is required"};
                return;
            }

            # Validate env_mode
            env_mode = self.env_mode.lower().strip() if self.env_mode else "local";
            if env_mode not in ("local", "worktree") {
                report {"success": False, "error": "env_mode must be 'local' or 'worktree'"};
                return;
            }

            # Validate branch name (prevent shell injection via branch names)
            if self.branch and not re.match(r"^[a-zA-Z0-9._/\-]+$", self.branch) {
                report {"success": False, "error": "Invalid branch name"};
                return;
            }

            # Find or create thread FIRST (before preview check)
            thread_node = _find_or_create_thread(
                target, self.thread_id, self.message, self.model,
                env_mode=env_mode
            );

            # Worktree mode: create worktree on first turn if env_mode=worktree
            if env_mode == "worktree" and not thread_node.worktree_path {
                base_branch = self.branch if self.branch else "main";
                wt_branch = "jac-ide/" + str(uuid4())[:8];
                wt_result = git_create_worktree(
                    target.repo_path, base_branch, wt_branch
                );
                if wt_result.get("success") {
                    thread_node.worktree_path = wt_result.get("worktree_path", "");
                    thread_node.branch = wt_result.get("branch", "");
                } else {
                    report {
                        "success": False,
                        "error": "Failed to create worktree: " + wt_result.get("error", "")
                    };
                    return;
                }
            } elif env_mode == "local" and self.branch and self.branch != thread_node.branch {
                thread_node.branch = self.branch;
            }

            # Resolve CWD based on worktree or preview registry
            cwd = "";
            repo_for_sync = target.repo_path;
            if thread_node.worktree_path {
                # Worktree mode: use worktree dir directly as CWD
                cwd = thread_node.worktree_path;
                repo_for_sync = thread_node.worktree_path;
                # Auto-setup preview registry for worktree (re-setup if pointing elsewhere)
                preview_key = _preview_key(user_id, self.project_id);
                existing_entry = _preview_registry.get(preview_key);
                print(f"[claude_chat] worktree CWD: wt={thread_node.worktree_path} existing_registry={existing_entry}");
                if not existing_entry or existing_entry.get("dir", "") != thread_node.worktree_path {
                    print(f"[claude_chat] re-setup preview: registry dir={existing_entry.get('dir', '<none>') if existing_entry else '<none>'} != worktree={thread_node.worktree_path}");
                    cleanup_preview(user_id, self.project_id);
                    setup_preview(user_id, self.project_id, target.repo_path, thread_node.worktree_path);
                }
            } else {
                # Local mode: require preview to be set up
                cwd = get_preview_dir(user_id, self.project_id) or "";
                print(f"[claude_chat] local CWD: get_preview_dir={cwd}");
                if not cwd {
                    report {"success": False, "error": "Preview not set up. Start preview first."};
                    return;
                }
            }

            # Increment turn count and persist user message
            thread_node.turn_count = thread_node.turn_count + 1;
            thread_node.status = "running";
            thread_node.updated_at = _utc_now();
            if self.model {
                thread_node.model = self.model;
            }

            _add_message_to_thread(
                thread_node, "user", self.message, thread_node.turn_count
            );

            # Resume from persisted session_id if available.
            # For worktree threads with no session yet, force a new session to
            # prevent resuming a different thread's session (sessions are scoped
            # by working directory — cross-thread resume causes errors).
            session_id_for_resume = thread_node.session_id;
            force_new = bool(thread_node.worktree_path and not thread_node.session_id);

            # Create git checkpoint before Claude turn
            checkpoint_repo = thread_node.worktree_path if thread_node.worktree_path else target.repo_path;
            checkpoint = git_create_checkpoint(checkpoint_repo);

            result = send_claude_turn(
                user_id,
                self.project_id,
                self.message,
                cwd,
                model=self.model,
                allowed_tools=self.allowed_tools,
                repo_path=repo_for_sync,
                persisted_session_id=session_id_for_resume,
                force_new_session=force_new,
                images=self.images
            );

            result["checkpoint_ref"] = checkpoint.get("checkpoint_ref", "");
            result["thread_id"] = thread_node.id;
            result["turn_number"] = thread_node.turn_count;
            result["worktree_path"] = thread_node.worktree_path;
            result["branch"] = thread_node.branch;
            result["env_mode"] = "worktree" if thread_node.worktree_path else "local";
            report result;

        } elif action == "poll" {
            # Poll for Claude events — lightweight drain only.
            # Message persistence is handled by the "persist" action (called by
            # frontend _handleDone) to avoid duplicate persistence.
            events = drain_claude_events(user_id, self.project_id);
            processing = is_claude_processing(user_id, self.project_id);

            # Find active thread to update status metadata only
            thread_node = _find_thread(target, self.thread_id) if self.thread_id else None;

            done_event = None;
            for evt in events {
                evt_type = evt.get("type", "");

                if evt_type == "claude_done" {
                    done_event = evt;
                    if thread_node {
                        sid = evt.get("session_id", "");
                        if sid {
                            thread_node.session_id = sid;
                        }
                        thread_node.status = "idle";
                        thread_node.updated_at = _utc_now();
                    }

                } elif evt_type == "claude_version_saved" {
                    target.updated_at = _utc_now();
                    commit_sha = evt.get("commit_sha", "");
                    if commit_sha {
                        target.last_commit = commit_sha;
                    }
                    # Create graph node for Claude-created version
                    disk_versions = list_project_versions(target.repo_path);
                    for dv in disk_versions {
                        if dv.get("commit_sha", "") == commit_sha {
                            existing = [target -->(?:ProjectVersion)];
                            already_exists = False;
                            for ev in existing {
                                if ev.id == dv.get("id", "") {
                                    already_exists = True;
                                    break;
                                }
                            }
                            if not already_exists {
                                target ++> ProjectVersion(
                                    id=dv.get("id", ""),
                                    project_id=self.project_id,
                                    commit_sha=dv.get("commit_sha", ""),
                                    jacpack_path=dv.get("jacpack_path", ""),
                                    created_at=dv.get("created_at", _utc_now()),
                                    trigger=dv.get("trigger", "claude_chat")
                                );
                            }
                            break;
                        }
                    }

                } elif evt_type == "claude_error" {
                    if thread_node {
                        thread_node.status = "error";
                        thread_node.updated_at = _utc_now();
                    }

                } elif evt_type == "claude_session_started" {
                    if thread_node {
                        sid = evt.get("session_id", "");
                        if sid {
                            thread_node.session_id = sid;
                        }
                    }
                }
            }

            thread_id_out = "";
            if thread_node {
                thread_id_out = thread_node.id;
            }

            report {
                "success": True,
                "events": events,
                "processing": processing,
                "done": done_event is not None,
                "thread_id": thread_id_out
            };

        } elif action == "persist" {
            # Persist assistant message + activities after a turn finishes
            # Called by frontend _handleDone when using WS-based event polling
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }

            # Persist assistant message
            content = self.message or "";
            if content.strip() {
                _add_message_to_thread(thread_node, "assistant", content, thread_node.turn_count);
            }

            # Persist activities (thinking logs, tool calls, etc.)
            if self.activities {
                for act in self.activities {
                    act_type = act.get("type", "tool");
                    act_tool = act.get("tool", "");
                    act_message = act.get("message", "");
                    act_status = act.get("status", "");
                    _add_activity_to_thread(
                        thread_node,
                        act_type,
                        act_tool,
                        act_message,
                        act_status,
                        thread_node.turn_count
                    );
                }
            }

            # Update thread status
            thread_node.status = "idle";
            thread_node.updated_at = _utc_now();

            # Persist session_id from Claude adapter if available
            session_info = get_claude_session_info(user_id, self.project_id);
            if session_info and session_info.get("session_id") {
                thread_node.session_id = session_info["session_id"];
            }

            report {"success": True, "thread_id": thread_node.id};

        } elif action == "interrupt" {
            result = interrupt_claude(user_id, self.project_id);
            report result;

        } elif action == "stop" {
            result = stop_claude_session(user_id, self.project_id);
            # Mark thread idle
            _update_thread_status(target, self.thread_id, "idle");
            report result;

        } elif action == "info" {
            result = get_claude_session_info(user_id, self.project_id);
            # Include thread info
            thread_node = _find_thread(target, self.thread_id) if self.thread_id else None;
            if thread_node {
                result["thread"] = _thread_to_dict(thread_node);
            }
            report result;

        } else {
            report {"success": False, "error": f"Unknown claude_chat action: {action}"};
        }
    }
}


# ===========================================================================
# Claude History Walker — list threads, load messages, manage threads
# ===========================================================================

walker claude_history {
    has project_id: str;
    has thread_id: str = "";
    has message: str = "";
    has action: str = "list_threads";

    can handle_action with Root entry {
        action = self.action.lower().strip() if self.action else "list_threads";

        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
            return;
        }

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
            return;
        }

        profile = profiles[0];
        all_projects = [profile -->(?:Project)];
        target = None;
        for project in all_projects {
            if project.id == self.project_id {
                target = project;
                break;
            }
        }

        if not target {
            report {"success": False, "error": "Project not found"};
            return;
        }

        if action == "list_threads" {
            all_threads = [target -->(?:ClaudeThread)];
            threads_list: list = [];
            for t in all_threads {
                threads_list.append(_thread_to_dict(t));
            }
            # Sort by updated_at descending (most recent first)
            threads_list.sort(key=lambda x: x.get("updated_at", ""), reverse=True);
            report {"success": True, "threads": threads_list};

        } elif action == "get_thread" {
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }

            # Get all messages and activities for this thread
            msgs = [thread_node -->(?:ClaudeMessage)];
            acts = [thread_node -->(?:ClaudeActivity)];

            messages_list: list = [];
            for m in msgs {
                messages_list.append(_message_to_dict(m));
            }
            # Sort by created_at ascending
            messages_list.sort(key=lambda x: x.get("created_at", ""));

            activities_list: list = [];
            for a in acts {
                activities_list.append(_activity_to_dict(a));
            }
            activities_list.sort(key=lambda x: x.get("created_at", ""));

            report {
                "success": True,
                "thread": _thread_to_dict(thread_node),
                "messages": messages_list,
                "activities": activities_list
            };

        } elif action == "delete_thread" {
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }

            # Clean up worktree if this thread owns one
            wt_path = thread_node.worktree_path;
            if wt_path {
                # Stop preview if it's running from this worktree
                user_id = profile.user_id;
                existing_preview = _preview_registry.get(_preview_key(user_id, self.project_id));
                print(f"[claude_history] delete_thread: wt_path={wt_path} existing_preview={existing_preview}");
                if existing_preview and existing_preview.get("dir", "") == wt_path {
                    print(f"[claude_history] preview running from worktree being deleted, re-setup from repo={target.repo_path}");
                    stop_preview(user_id, self.project_id);
                    cleanup_preview(user_id, self.project_id);
                    # Re-setup preview from main repo so file ops still work
                    setup_preview(user_id, self.project_id, target.repo_path);
                }
                git_remove_worktree(target.repo_path, wt_path, force=True);
            }

            # Delete all messages and activities first
            msgs = [thread_node -->(?:ClaudeMessage)];
            for m in msgs {
                del m;
            }
            acts = [thread_node -->(?:ClaudeActivity)];
            for a in acts {
                del a;
            }
            del thread_node;
            report {"success": True};

        } elif action == "rename_thread" {
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }
            # Use the message field as new title
            if self.message {
                thread_node.title = self.message;
                thread_node.updated_at = _utc_now();
            }
            report {"success": True, "thread": _thread_to_dict(thread_node)};

        } elif action == "clear_thread" {
            # Clear all messages and activities from a thread without deleting it.
            # Used by the local thread (one-per-project) to reset conversation history.
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }
            msgs = [thread_node -->(?:ClaudeMessage)];
            for m in msgs {
                del m;
            }
            acts = [thread_node -->(?:ClaudeActivity)];
            for a in acts {
                del a;
            }
            thread_node.turn_count = 0;
            thread_node.session_id = "";
            thread_node.status = "idle";
            thread_node.updated_at = _utc_now();
            report {"success": True, "thread": _thread_to_dict(thread_node)};

        } elif action == "merge_thread" {
            # Merge a worktree thread's branch into the project's active branch.
            # Steps: commit pending changes in worktree → remove worktree →
            #        checkout target branch in main repo → merge → clean up thread.
            if not self.thread_id {
                report {"success": False, "error": "thread_id is required"};
                return;
            }
            thread_node = _find_thread(target, self.thread_id);
            if not thread_node {
                report {"success": False, "error": "Thread not found"};
                return;
            }
            if not thread_node.worktree_path or not thread_node.branch {
                report {"success": False, "error": "Thread is not a worktree thread"};
                return;
            }

            wt_path = thread_node.worktree_path;
            wt_branch = thread_node.branch;
            repo_path = target.repo_path;
            merge_into = target.active_branch if target.active_branch else "main";
            user_id = profile.user_id;

            # 1. Commit any uncommitted changes in the worktree
            wt_status = git_status(wt_path);
            if wt_status.get("dirty", False) {
                git_commit(wt_path, "Auto-commit before merge");
            }

            # 2. Checkout target branch in main repo BEFORE removing worktree.
            #    This is safe because merge_into (e.g. "main") is not the branch
            #    checked out in the worktree (jac-ide/xxx), so git allows it.
            checkout_res = git_checkout(repo_path, merge_into);
            if not checkout_res.get("success") {
                report {
                    "success": False,
                    "error": "Failed to checkout " + merge_into + ": " + checkout_res.get("error", "")
                };
                return;
            }

            # 3. Merge worktree branch (git_merge auto-aborts on conflict).
            #    Worktree is still intact here — if merge fails, the user can
            #    fix conflicts in the worktree and retry.
            merge_res = git_merge(repo_path, wt_branch);
            if not merge_res.get("success") {
                report merge_res;
                return;
            }

            # 4. Remove worktree AFTER successful merge (safe to delete now)
            git_remove_worktree(repo_path, wt_path, force=True);

            # 5. Stop preview (after successful merge, before cleanup)
            existing_preview = _preview_registry.get(_preview_key(user_id, self.project_id));
            print(f"[claude_history] merge_thread: existing_preview={existing_preview}");
            if existing_preview and existing_preview.get("is_worktree", False) {
                print(f"[claude_history] stopping worktree preview before merge cleanup");
                stop_preview(user_id, self.project_id);
            }

            # 6. Delete the merged branch
            git_delete_branch(repo_path, wt_branch);

            # 7. Update thread: mark as merged, clear worktree info
            thread_node.status = "merged";
            thread_node.worktree_path = "";
            thread_node.updated_at = _utc_now();

            # 8. Update project metadata
            new_sha = git_head_sha(repo_path);
            if new_sha {
                target.last_commit = new_sha;
            }
            target.updated_at = _utc_now();

            # 9. Re-setup preview from main repo
            if existing_preview {
                print(f"[claude_history] re-setup preview after merge: repo_path={repo_path}");
                cleanup_preview(user_id, self.project_id);
                setup_preview(user_id, self.project_id, repo_path);
            }

            report {
                "success": True,
                "message": "Merged " + wt_branch + " into " + merge_into,
                "thread": _thread_to_dict(thread_node)
            };

        } elif action == "cleanup_worktrees" {
            # Find all worktree paths owned by threads
            all_threads = [target -->(?:ClaudeThread)];
            thread_wt_paths: set = set();
            for t in all_threads {
                if t.worktree_path {
                    thread_wt_paths.add(t.worktree_path);
                }
            }

            # List actual git worktrees
            wt_result = git_list_worktrees(target.repo_path);
            removed: list = [];
            if wt_result.get("success") {
                for wt in wt_result.get("worktrees", []) {
                    wt_path = wt.get("path", "");
                    wt_branch = wt.get("branch", "");
                    # Only clean up jac-ide/* branches (our worktrees)
                    if wt_branch.startswith("jac-ide/") and wt_path not in thread_wt_paths {
                        rm_result = git_remove_worktree(target.repo_path, wt_path, force=True);
                        if rm_result.get("success") {
                            removed.append(wt_path);
                        }
                    }
                }
            }
            report {"success": True, "removed": removed, "count": len(removed)};

        } else {
            report {"success": False, "error": f"Unknown claude_history action: {action}"};
        }
    }
}


# ===========================================================================
# Git Operations Walker
# ===========================================================================

walker git_ops {
    has project_id: str;
    has action: str;
    has branch: str = "";
    has new_branch: str = "";
    has message: str = "";
    has remote_url: str = "";
    has remote_name: str = "origin";
    has from_ref: str = "";
    has to_ref: str = "";
    has worktree_path: str = "";
    has file_path: str = "";
    has limit: int = 20;

    can handle_action with Root entry {
        if not self.project_id {
            report {"success": False, "error": "project_id is required"};
            return;
        }

        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
            return;
        }

        profile = profiles[0];
        all_projects = [profile -->(?:Project)];
        target = None;
        for project in all_projects {
            if project.id == self.project_id {
                target = project;
                break;
            }
        }

        if not target {
            report {"success": False, "error": "Project not found"};
            return;
        }

        repo_path = target.repo_path;
        if not repo_path or not os.path.isdir(repo_path) {
            report {"success": False, "error": "Project workspace not found"};
            return;
        }

        # Use worktree path if provided, otherwise use main repo path
        # SECURITY: validate that the worktree_path is a registered worktree of this project's repo
        effective_path = repo_path;
        if self.worktree_path and os.path.isdir(self.worktree_path) {
            wt_list = git_list_worktrees(repo_path);
            valid_wt_paths = [w["path"] for w in wt_list.get("worktrees", [])];
            if self.worktree_path in valid_wt_paths {
                effective_path = self.worktree_path;
            } else {
                report {"success": False, "error": "Invalid worktree path — not a worktree of this project"};
                return;
            }
        }

        action = self.action.lower().strip() if self.action else "";

        if action == "status" {
            report git_status(effective_path);

        } elif action == "branches" {
            report git_branches(effective_path);

        } elif action == "checkout" {
            if not self.branch {
                report {"success": False, "error": "branch is required"};
                return;
            }
            result = git_checkout(effective_path, self.branch);
            if result.get("success") {
                target.active_branch = self.branch;
            }
            report result;

        } elif action == "create_branch" {
            if not self.branch {
                report {"success": False, "error": "branch name is required"};
                return;
            }
            result = git_create_branch(effective_path, self.branch);
            if result.get("success") {
                target.active_branch = self.branch;
            }
            report result;

        } elif action == "diff" {
            report git_diff(effective_path, self.from_ref, self.to_ref);

        } elif action == "diff_working" {
            report git_diff_working(effective_path);

        } elif action == "diff_staged" {
            report git_diff_staged(effective_path);

        } elif action == "diff_last_commit" {
            report git_diff_last_commit(effective_path);

        } elif action == "show_file" {
            if not self.from_ref or not self.file_path {
                report {"success": False, "error": "from_ref and file_path are required"};
                return;
            }
            report git_show_file(effective_path, self.from_ref, self.file_path);

        } elif action == "read_working_file" {
            if not self.file_path {
                report {"success": False, "error": "file_path is required"};
                return;
            }
            report git_read_working_file(effective_path, self.file_path);

        } elif action == "commit" {
            if not self.message {
                report {"success": False, "error": "commit message is required"};
                return;
            }
            result = git_commit(effective_path, self.message);
            if result.get("success") {
                target.last_commit = result.get("sha", target.last_commit);
                target.updated_at = _utc_now();
                # Create version snapshot on manual commit
                commit_sha = result.get("sha", "");
                if commit_sha {
                    snap = create_project_snapshot(target.repo_path, commit_sha);
                    if snap.get("success") {
                        recorded = record_project_version(target.repo_path, commit_sha, snap.get("jacpack_path", ""), "commit");
                        if recorded.get("success") {
                            version = recorded.get("entry");
                            if version {
                                target ++> ProjectVersion(
                                    id=version.get("id", ""),
                                    project_id=self.project_id,
                                    commit_sha=commit_sha,
                                    jacpack_path=version.get("jacpack_path", ""),
                                    created_at=version.get("created_at", _utc_now()),
                                    trigger="commit"
                                );
                            }
                        }
                    }
                }
            }
            report result;

        } elif action == "push" {
            report git_push(effective_path);

        } elif action == "pull" {
            report git_pull(effective_path);

        } elif action == "log" {
            report git_log(effective_path, self.limit);

        } elif action == "remote_add" {
            if not self.remote_url {
                report {"success": False, "error": "remote_url is required"};
                return;
            }
            report git_remote_add(effective_path, self.remote_url);

        } elif action == "remotes" {
            report git_remotes(effective_path);

        } elif action == "remote_remove" {
            if not self.remote_name {
                report {"success": False, "error": "remote_name is required"};
                return;
            }
            report git_remote_remove(effective_path, self.remote_name);

        } elif action == "checkpoint_create" {
            report git_create_checkpoint(effective_path);

        } elif action == "checkpoint_restore" {
            if not self.from_ref {
                report {"success": False, "error": "from_ref (checkpoint ref) is required"};
                return;
            }
            cp_res = git_restore_checkpoint(effective_path, self.from_ref);
            if cp_res.get("success") {
                # Re-sync preview dir with restored files
                # Frontend will call startPreview to spawn the subprocess
                print(f"[git_ops] checkpoint_restore success: cleanup+setup preview project={self.project_id} repo_path={repo_path}");
                cleanup_preview(profile.user_id, self.project_id);
                setup_preview(profile.user_id, self.project_id, repo_path);
            }
            report cp_res;

        } elif action == "checkpoint_diff" {
            report git_checkpoint_diff(effective_path, self.from_ref);

        } elif action == "stage_file" {
            if not self.file_path {
                report {"success": False, "error": "file_path is required"};
                return;
            }
            report git_stage_file(effective_path, self.file_path);

        } elif action == "unstage_file" {
            if not self.file_path {
                report {"success": False, "error": "file_path is required"};
                return;
            }
            report git_unstage_file(effective_path, self.file_path);

        } elif action == "commit_staged" {
            if not self.message {
                report {"success": False, "error": "commit message is required"};
                return;
            }
            result = git_commit_staged(effective_path, self.message);
            if result.get("success") {
                target.last_commit = result.get("sha", target.last_commit);
                target.updated_at = _utc_now();
                commit_sha = result.get("sha", "");
                if commit_sha {
                    snap = create_project_snapshot(target.repo_path, commit_sha);
                    if snap.get("success") {
                        recorded = record_project_version(target.repo_path, commit_sha, snap.get("jacpack_path", ""), "commit");
                        if recorded.get("success") {
                            version = recorded.get("entry");
                            if version {
                                target ++> ProjectVersion(
                                    id=version.get("id", ""),
                                    project_id=self.project_id,
                                    commit_sha=commit_sha,
                                    jacpack_path=version.get("jacpack_path", ""),
                                    created_at=version.get("created_at", _utc_now()),
                                    trigger="commit"
                                );
                            }
                        }
                    }
                }
            }
            report result;

        } elif action == "delete_branch" {
            if not self.branch {
                report {"success": False, "error": "branch name is required"};
                return;
            }
            # Safety: cannot delete the current branch
            current_branch_res = git_branches(effective_path);
            current_br = current_branch_res.get("current", "");
            if self.branch == current_br {
                report {"success": False, "error": "Cannot delete the currently checked-out branch"};
                return;
            }
            report git_delete_branch(effective_path, self.branch);

        } elif action == "merge" {
            if not self.branch {
                report {"success": False, "error": "branch name is required for merge"};
                return;
            }
            report git_merge(effective_path, self.branch);

        } elif action == "worktree_create" {
            if not self.branch {
                report {"success": False, "error": "Base branch is required"};
                return;
            }
            new_branch = self.new_branch;
            if not new_branch {
                new_branch = "jac-ide/" + str(uuid4())[:8];
            }
            report git_create_worktree(repo_path, self.branch, new_branch);

        } elif action == "worktree_remove" {
            if not self.worktree_path {
                report {"success": False, "error": "worktree_path is required"};
                return;
            }
            report git_remove_worktree(repo_path, self.worktree_path, force=True);

        } elif action == "worktree_list" {
            report git_list_worktrees(repo_path);

        } else {
            report {"success": False, "error": f"Unknown git_ops action: {action}"};
        }
    }
}


# ===========================================================================
# GitHub Integration Walker
# ===========================================================================

"""Get a valid user OAuth token, refreshing if expired.

Returns {"success": True, "token": "..."} or {"success": False, "error": "..."}.
Updates the profile fields if a refresh occurs.
"""
def _get_valid_user_token(profile: Any) -> dict {
    # Try in-memory store first (local dev), fall back to graph node (prod)
    token = _github_get_token(profile.user_id, profile);
    if not token {
        return {"success": False, "error": "No GitHub token stored"};
    }

    # Check if token is expired (with 5-minute buffer)
    mem_expires = _github_mem_get(profile.user_id, "token_expires_at", 0.0);
    expires_at = mem_expires if mem_expires else (profile.github_token_expires_at or 0.0);
    if expires_at > 0 and time.time() > (expires_at - 300) {
        # Token expired or about to expire — try refresh
        refresh_tok = decrypt_token(profile.github_refresh_token);
        if not refresh_tok {
            return {"success": False, "error": "GitHub token expired. Please disconnect and reconnect GitHub."};
        }

        refresh_result = github_refresh_user_token(refresh_tok);
        if not refresh_result.get("success") {
            return {"success": False, "error": "Token refresh failed: " + refresh_result.get("error", "unknown") + ". Please reconnect GitHub."};
        }

        # Update profile with new tokens (graph + in-memory)
        new_token = refresh_result["access_token"];
        profile.github_access_token = encrypt_token(new_token);
        if refresh_result.get("refresh_token") {
            profile.github_refresh_token = encrypt_token(refresh_result["refresh_token"]);
        }
        if refresh_result.get("expires_at") {
            profile.github_token_expires_at = refresh_result["expires_at"];
        }
        _github_mem_set(profile.user_id, {
            "access_token": new_token,
            "refresh_token": refresh_result.get("refresh_token", ""),
            "token_expires_at": refresh_result.get("expires_at", 0.0)
        });
        return {"success": True, "token": new_token};
    }

    return {"success": True, "token": token};
}

"""Clone a public GitHub repository without authentication."""
def _unauthenticated_clone(clone_url: str, dest_path: str) -> dict {
    parent_dir = os.path.dirname(dest_path);
    if not os.path.exists(parent_dir) {
        os.makedirs(parent_dir, exist_ok=True);
    }
    try {
        result = subprocess.run(
            ["git", "clone", clone_url, dest_path],
            cwd=parent_dir,
            capture_output=True,
            text=True,
            timeout=120
        );
        if result.returncode != 0 {
            err_msg = result.stderr.strip();
            if "Authentication" in err_msg or "could not read Username" in err_msg or "Repository not found" in err_msg {
                return {"success": False, "error": "This repository is private. Connect GitHub to clone private repos."};
            }
            return {"success": False, "error": err_msg or "Clone failed"};
        }
        return {"success": True};
    } except subprocess.TimeoutExpired {
        return {"success": False, "error": "Clone timed out — repository may be too large"};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}


# In-memory fast path for local dev; graph node is source of truth in prod (multi-pod).
# Local dev (Anchor.persistent=False): graph mutations don't persist between requests,
# so this dict is the primary store. Prod (jac-scale + MongoDB): graph persists across
# pods, and this dict acts as a warm cache for the current pod.
glob _github_oauth_states: dict = {};

def _github_mem_get(user_id: str, field: str, fallback: Any = "") -> Any {
    entry = _github_oauth_states.get(user_id, {});
    return entry.get(field, fallback);
}

def _github_mem_set(user_id: str, fields: dict) -> None {
    existing = _github_oauth_states.get(user_id, {});
    existing.update(fields);
    _github_oauth_states[user_id] = existing;
}

def _github_clear(user_id: str) -> None {
    _github_oauth_states.pop(user_id, None);
}

def _github_is_connected(user_id: str, profile: Any) -> bool {
    mem_val = _github_mem_get(user_id, "connected", None);
    if mem_val is not None { return mem_val; }
    return profile.github_connected;
}

def _github_get_token(user_id: str, profile: Any) -> str {
    mem_tok = _github_mem_get(user_id, "access_token", "");
    if mem_tok { return mem_tok; }
    if profile.github_access_token { return decrypt_token(profile.github_access_token); }
    return "";
}

def _github_get_username(user_id: str, profile: Any) -> str {
    mem_name = _github_mem_get(user_id, "username", "");
    if mem_name { return mem_name; }
    return profile.github_username;
}

walker github_ops {
    has action: str;
    has project_id: str = "";
    has code: str = "";
    has state: str = "";
    has installation_id: str = "";
    has repo_name: str = "";
    has repo_private: bool = True;
    has repo_description: str = "";
    has clone_url: str = "";
    has pr_title: str = "";
    has pr_head: str = "";
    has pr_base: str = "main";
    has pr_body: str = "";
    has page: int = 1;
    has per_page: int = 30;

    can start with Root entry {
        profiles = [-->(?:UserProfile)];
        if not profiles or len(profiles) == 0 {
            report {"success": False, "error": "User profile not found"};
            return;
        }
        profile = profiles[0];
        action = self.action;

        if action == "connect" {
            state_token = str(uuid4());
            now_ts = time.time();
            # Store in both in-memory (local dev) and graph node (prod multi-pod)
            _github_oauth_states[profile.user_id] = {"state": state_token, "ts": now_ts};
            profile.github_oauth_state = state_token;
            profile.github_oauth_state_ts = now_ts;

            host = os.environ.get("HOST", "http://localhost:8000");
            redirect_uri = host + "/auth/github-connect";
            repo_client_id = os.environ.get("GITHUB_REPO_CLIENT_ID", "");

            authorize_url = (
                "https://github.com/login/oauth/authorize"
                + "?client_id=" + repo_client_id
                + "&redirect_uri=" + redirect_uri
                + "&scope=repo,read:user,user:email"
                + "&state=" + state_token
            );
            report {"success": True, "authorize_url": authorize_url, "state": state_token};

        } elif action == "exchange_code" {
            if not self.code {
                report {"success": False, "error": "Missing authorization code"};
                return;
            }

            # Mandatory CSRF state validation — always required
            if not self.state {
                report {"success": False, "error": "Missing state parameter (CSRF protection)"};
                return;
            }
            # Try in-memory first (local dev), fall back to graph node (prod multi-pod)
            stored = _github_oauth_states.get(profile.user_id, {});
            stored_state = stored.get("state", "");
            stored_ts = stored.get("ts", 0.0);
            if not stored_state {
                stored_state = profile.github_oauth_state;
                stored_ts = profile.github_oauth_state_ts;
            }
            if self.state != stored_state {
                report {"success": False, "error": "Invalid state token"};
                return;
            }
            # Check state is not expired (10 minute TTL)
            if time.time() - stored_ts > 600 {
                _github_oauth_states.pop(profile.user_id, None);
                profile.github_oauth_state = "";
                profile.github_oauth_state_ts = 0.0;
                report {"success": False, "error": "State token expired, please try again"};
                return;
            }
            # Clear state after validation (single use)
            _github_oauth_states.pop(profile.user_id, None);
            profile.github_oauth_state = "";
            profile.github_oauth_state_ts = 0.0;

            token_result = github_exchange_code(self.code);
            if not token_result.get("success") {
                report {"success": False, "error": token_result.get("error", "Token exchange failed")};
                return;
            }

            access_token = token_result["access_token"];
            user_result = github_get_user(access_token);
            if not user_result.get("success") {
                report {"success": False, "error": "Failed to fetch GitHub profile"};
                return;
            }

            github_username = user_result.get("login", "");
            # Store on graph node (persists in prod with jac-scale)
            profile.github_access_token = encrypt_token(access_token);
            profile.github_username = github_username;
            profile.github_connected = True;
            if token_result.get("refresh_token") {
                profile.github_refresh_token = encrypt_token(token_result["refresh_token"]);
            }
            if token_result.get("expires_at") {
                profile.github_token_expires_at = token_result["expires_at"];
            }
            # Also store in-memory (survives between requests in local dev)
            _github_mem_set(profile.user_id, {
                "access_token": access_token,
                "username": github_username,
                "connected": True,
                "refresh_token": token_result.get("refresh_token", ""),
                "token_expires_at": token_result.get("expires_at", 0.0)
            });

            report {
                "success": True,
                "github_username": github_username,
                "github_connected": True
            };

        } elif action == "status" {
            report {
                "success": True,
                "github_connected": _github_is_connected(profile.user_id, profile),
                "github_username": _github_get_username(profile.user_id, profile)
            };

        } elif action == "disconnect" {
            # Revoke token on GitHub before clearing locally
            token_to_revoke = _github_get_token(profile.user_id, profile);
            if token_to_revoke {
                github_revoke_token(token_to_revoke);
            }
            profile.github_access_token = "";
            profile.github_username = "";
            profile.github_connected = False;
            profile.github_refresh_token = "";
            profile.github_token_expires_at = 0.0;
            _github_clear(profile.user_id);
            report {"success": True};

        } elif action == "list_repos" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }
            result = github_list_repos(user_token_result["token"], self.page, self.per_page);
            report result;

        } elif action == "create_repo" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            if not self.repo_name {
                report {"success": False, "error": "Repository name is required"};
                return;
            }
            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }
            result = github_create_repo(
                user_token_result["token"],
                self.repo_name,
                self.repo_private,
                self.repo_description
            );
            report result;

        } elif action == "push" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            if not self.project_id {
                report {"success": False, "error": "Project ID is required"};
                return;
            }

            all_projects = [profile -->(?:Project)];
            target = None;
            for project in all_projects {
                if project.id == self.project_id {
                    target = project;
                    break;
                }
            }
            if not target or not target.repo_path {
                report {"success": False, "error": "Project not found"};
                return;
            }

            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }

            result = github_push(target.repo_path, user_token_result["token"]);
            if result.get("success") {
                target.updated_at = _utc_now();
            }
            report result;

        } elif action == "pull" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            if not self.project_id {
                report {"success": False, "error": "Project ID is required"};
                return;
            }

            all_projects = [profile -->(?:Project)];
            target = None;
            for project in all_projects {
                if project.id == self.project_id {
                    target = project;
                    break;
                }
            }
            if not target or not target.repo_path {
                report {"success": False, "error": "Project not found"};
                return;
            }

            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }

            result = github_pull(target.repo_path, user_token_result["token"]);
            if result.get("success") {
                target.updated_at = _utc_now();
            }
            report result;

        } elif action == "push_new" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            if not self.project_id {
                report {"success": False, "error": "Project ID is required"};
                return;
            }

            all_projects = [profile -->(?:Project)];
            target = None;
            for project in all_projects {
                if project.id == self.project_id {
                    target = project;
                    break;
                }
            }
            if not target or not target.repo_path {
                report {"success": False, "error": "Project not found"};
                return;
            }

            name = self.repo_name or target.name;
            name = re.sub("[^a-zA-Z0-9._-]", "-", name);

            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }
            _user_token = user_token_result["token"];

            create_result = github_create_repo(
                _user_token,
                name,
                self.repo_private,
                self.repo_description
            );

            repo = None;
            repo_clone_url = "";
            if create_result.get("success") {
                repo = create_result["repo"];
                repo_clone_url = repo["clone_url"];
            } else {
                # Repo may already exist — verify ownership before pushing
                err_msg = create_result.get("error", "");
                if "already exists" in err_msg or "name already exists" in err_msg or "creation failed" in err_msg.lower() {
                    check_result = github_check_repo_exists(_user_token, _github_get_username(profile.user_id, profile), name);
                    if not check_result.get("success") or not check_result.get("exists") {
                        report {"success": False, "error": "Repository '" + name + "' already exists but could not be verified"};
                        return;
                    }
                    _gh_user = _github_get_username(profile.user_id, profile);
                    perms = check_result.get("permissions", {});
                    if not perms.get("push", False) {
                        report {"success": False, "error": "You do not have push access to '" + _gh_user + "/" + name + "'"};
                        return;
                    }
                    repo_clone_url = check_result.get("clone_url", "https://github.com/" + _gh_user + "/" + name + ".git");
                    repo = {
                        "name": name,
                        "full_name": _gh_user + "/" + name,
                        "html_url": "https://github.com/" + _gh_user + "/" + name,
                        "clone_url": repo_clone_url
                    };
                } else {
                    report create_result;
                    return;
                }
            }

            existing = git_remotes(target.repo_path);
            has_origin = False;
            if existing.get("success") {
                for r in existing.get("remotes", []) {
                    if r.get("name") == "origin" {
                        has_origin = True;
                        break;
                    }
                }
            }
            if has_origin {
                git_remote_remove(target.repo_path, "origin");
            }
            git_remote_add(target.repo_path, repo_clone_url, "origin");

            # Retry push — GitHub may need a moment after repo creation
            push_result: dict = {};
            max_retries = 3;
            retry_i = 0;
            while retry_i < max_retries {
                push_result = github_push(target.repo_path, _user_token);
                if push_result.get("success") {
                    target.updated_at = _utc_now();
                    break;
                }
                push_err = push_result.get("error", "");
                if "not found" in push_err.lower() or "Repository not found" in push_err {
                    retry_i += 1;
                    if retry_i < max_retries {
                        time.sleep(2);
                    }
                } else {
                    break;
                }
            }

            report {
                "success": push_result.get("success", False),
                "repo": repo,
                "push_result": push_result,
                "error": push_result.get("error", "")
            };

        } elif action == "import_repo" {
            if not self.clone_url or not self.repo_name {
                report {"success": False, "error": "Clone URL and project name are required"};
                return;
            }
            # Validate clone URL — must be a GitHub HTTPS URL
            if not re.match("^https://github\\.com/[\\w.-]+/[\\w.-]+(\\.git)?$", self.clone_url) {
                report {"success": False, "error": "Invalid clone URL — must be a GitHub HTTPS URL"};
                return;
            }

            projects_root = os.environ.get("JAC_IDE_PROJECTS_ROOT", os.path.expanduser("~/.jac-ide/projects"));
            user_dir = os.path.join(projects_root, profile.user_id);
            os.makedirs(user_dir, exist_ok=True);

            project_id = str(uuid4());
            safe_name = re.sub("[^a-zA-Z0-9._-]", "-", self.repo_name);
            repo_path = os.path.join(user_dir, safe_name);

            if os.path.exists(repo_path) {
                repo_path = repo_path + "-" + project_id[:8];
            }

            # Use authenticated clone if GitHub is connected (supports private repos),
            # otherwise fall back to unauthenticated clone (public repos only)
            if _github_is_connected(profile.user_id, profile) and _github_get_token(profile.user_id, profile) {
                user_token_result = _get_valid_user_token(profile);
                if user_token_result.get("success") {
                    clone_result = github_clone(self.clone_url, repo_path, user_token_result["token"]);
                } else {
                    # Token refresh failed — inform user
                    report {"success": False, "error": "GitHub token expired. Please reconnect GitHub in Settings."};
                    return;
                }
            } else {
                clone_result = _unauthenticated_clone(self.clone_url, repo_path);
            }
            if not clone_result.get("success") {
                report clone_result;
                return;
            }

            now = _utc_now();
            active_branch = "main";
            last_commit = "";
            try {
                branch_res = subprocess.run(
                    ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                    cwd=repo_path,
                    capture_output=True,
                    text=True,
                    timeout=5
                );
                active_branch = branch_res.stdout.strip() or "main";
            } except Exception {
                active_branch = "main";
            }
            try {
                sha_res = subprocess.run(
                    ["git", "rev-parse", "HEAD"],
                    cwd=repo_path,
                    capture_output=True,
                    text=True,
                    timeout=5
                );
                last_commit = sha_res.stdout.strip();
            } except Exception {
                last_commit = "";
            }

            profile ++> Project(
                id=project_id,
                name=self.repo_name,
                template_id="github-import",
                repo_path=repo_path,
                created_at=now,
                updated_at=now,
                active_branch=active_branch,
                last_commit=last_commit
            );

            report {
                "success": True,
                "project": {
                    "id": project_id,
                    "name": self.repo_name,
                    "repo_path": repo_path,
                    "active_branch": active_branch,
                    "created_at": now
                }
            };

        } elif action == "create_pr" {
            if not _github_is_connected(profile.user_id, profile) or not _github_get_token(profile.user_id, profile) {
                report {"success": False, "error": "GitHub not connected"};
                return;
            }
            if not self.project_id {
                report {"success": False, "error": "Project ID is required"};
                return;
            }
            if not self.pr_title or not self.pr_head {
                report {"success": False, "error": "PR title and head branch are required"};
                return;
            }

            all_projects = [profile -->(?:Project)];
            target = None;
            for project in all_projects {
                if project.id == self.project_id {
                    target = project;
                    break;
                }
            }
            if not target or not target.repo_path {
                report {"success": False, "error": "Project not found"};
                return;
            }

            remotes_result = git_remotes(target.repo_path);
            origin_url = "";
            if remotes_result.get("success") {
                for r in remotes_result.get("remotes", []) {
                    if r.get("name") == "origin" {
                        origin_url = r.get("url", "") or r.get("fetch_url", "") or r.get("push_url", "");
                        break;
                    }
                }
            }

            if not origin_url {
                report {"success": False, "error": "No remote origin found"};
                return;
            }

            owner = "";
            repo = "";
            clean_url = origin_url.replace(".git", "").strip();
            if "github.com:" in clean_url {
                # SSH format: git@github.com:owner/repo
                after_colon = clean_url.split("github.com:", 1)[-1];
                segments = after_colon.split("/");
                if len(segments) >= 2 {
                    owner = segments[0];
                    repo = segments[1];
                }
            } elif "github.com/" in clean_url {
                # HTTPS format: https://github.com/owner/repo
                after_slash = clean_url.split("github.com/", 1)[-1];
                segments = after_slash.split("/");
                if len(segments) >= 2 {
                    owner = segments[0];
                    repo = segments[1];
                }
            }

            if not owner or not repo {
                report {"success": False, "error": "Cannot parse GitHub owner/repo from remote URL"};
                return;
            }

            user_token_result = _get_valid_user_token(profile);
            if not user_token_result.get("success") {
                report user_token_result;
                return;
            }

            result = github_create_pr(
                user_token_result["token"],
                owner, repo,
                self.pr_title,
                self.pr_head,
                self.pr_base,
                self.pr_body
            );
            report result;

        } else {
            report {"success": False, "error": "Unknown action: " + self.action};
        }
    }
}

# ---------------------------------------------------------------------------
# Reconciler Walker — spawned periodically by background thread
# ---------------------------------------------------------------------------

"""Walker that reconciles K8s sandbox state. Runs K8s-only operations
(drift detection, warm pool replenishment). SandboxInstance nodes live
on user roots (not global root), so this walker can't see them.

Spawned by the reconciler background thread every 15 seconds."""
walker :pub reconcile_sandboxes {
    can handle with Root entry {
        import from services.sandbox_reconciler {
            reconcile_drift_k8s_only,
            reconcile_warm_pool
        }
        import from services.sandbox_store { get_backend }

        backend = get_backend();
        if backend is None {
            return;
        }

        # K8s-only operations — no graph node access needed
        reconcile_drift_k8s_only(backend);
        reconcile_warm_pool(backend);

        report {"reconciled": True};
    }
}
