"""Session Manager — Unified lifecycle management for all per-user-project state.

Provides:
  - Per-session locks (one Lock per user::project pair)
  - Per-repo git locks (serialize git operations on the same repo)
  - TTL-based idle session cleanup (sweeps every 60s)
  - Graceful shutdown (SIGTERM/SIGINT cleanup all sessions)
  - Cleanup callback registration (each service registers its own cleanup fn)

This is the single coordination layer that replaces the scattered, independent
cleanup strategies across preview_manager, lsp_manager,
claude_adapter, jaccoder_adapter, and file_watcher.
"""

import os;
import time;
import logging;
import signal;
import threading;


glob _logger = logging.getLogger("session_manager");

# --- Configuration ---
glob SESSION_IDLE_TTL: float = float(os.environ.get("JAC_SESSION_IDLE_TTL", "1800"));
glob CLEANUP_INTERVAL: float = 60.0;

# --- Core State ---
glob _session_locks: dict = {};
glob _session_activity: dict = {};
glob _session_user_map: dict = {};
glob _meta_lock = threading.Lock();

glob _cleanup_callbacks: list = [];

glob _repo_locks: dict = {};
glob _repo_meta_lock = threading.Lock();

glob _cleanup_thread: Any = None;
glob _running: bool = True;
glob _initialized: bool = False;


# =====================================================================
# Session Key
# =====================================================================

def session_key(user_id: str, project_id: str) -> str {
    return str(user_id) + "::" + str(project_id);
}

"""Returns [user_id, project_id] from a session key."""
def _parse_key(key: str) -> list {
    parts = key.split("::");
    if len(parts) == 2 {
        return [parts[0], parts[1]];
    }
    return ["", ""];
}


# =====================================================================
# Per-Session Lock
# =====================================================================

"""Get or create a per-session lock. Thread-safe."""
def get_session_lock(user_id: str, project_id: str) -> Any {
    key = session_key(user_id, project_id);
    with _meta_lock {
        if key not in _session_locks {
            _session_locks[key] = threading.Lock();
            _session_user_map[key] = user_id;
        }
        _session_activity[key] = time.time();
        return _session_locks[key];
    }
}

"""Update last-activity timestamp. Call on any user interaction."""
def touch_session(user_id: str, project_id: str) -> None {
    key = session_key(user_id, project_id);
    _session_activity[key] = time.time();
}


# =====================================================================
# Per-Repo Git Lock
# =====================================================================

"""Get or create a per-repo lock for serializing git operations."""
def get_repo_lock(repo_path: str) -> Any {
    with _repo_meta_lock {
        if repo_path not in _repo_locks {
            _repo_locks[repo_path] = threading.Lock();
        }
        return _repo_locks[repo_path];
    }
}

"""Remove a repo lock on project delete."""
def remove_repo_lock(repo_path: str) -> None {
    with _repo_meta_lock {
        _repo_locks.pop(repo_path, None);
    }
}


# =====================================================================
# Cleanup Callback Registration
# =====================================================================

"""Register a cleanup callback: cleanup_fn(user_id, project_id).
Called on idle session expiry and graceful shutdown."""
def register_cleanup(service_name: str, cleanup_fn: Any) -> None {
    _cleanup_callbacks.append((service_name, cleanup_fn));
    _logger.info("Registered cleanup: " + service_name);
}

"""Run all registered cleanup callbacks for a session."""
def _run_cleanup_callbacks(user_id: str, project_id: str) -> None {
    for pair in _cleanup_callbacks {
        svc_name = pair[0];
        fn = pair[1];
        try {
            fn(user_id, project_id);
        } except Exception as e {
            _logger.error(
                "Cleanup '" + svc_name + "' failed for "
                + user_id + "::" + project_id + ": " + str(e)
            );
        }
    }
}


# =====================================================================
# TTL Cleanup Thread
# =====================================================================

"""Background thread: sweep idle sessions every CLEANUP_INTERVAL seconds."""
def _cleanup_loop() -> None {
    while _running {
        try {
            time.sleep(CLEANUP_INTERVAL);
        } except Exception {
            break;
        }
        if not _running {
            break;
        }

        now = time.time();
        stale_keys: list = [];

        with _meta_lock {
            for key in list(_session_activity.keys()) {
                last_active = _session_activity.get(key, now);
                if (now - last_active) > SESSION_IDLE_TTL {
                    stale_keys.append(key);
                }
            }
        }

        for key in stale_keys {
            parts = _parse_key(key);
            uid = parts[0];
            pid = parts[1];
            if uid and pid {
                _logger.info("Cleaning idle session: " + key);
                _run_cleanup_callbacks(uid, pid);
            }
            with _meta_lock {
                _session_locks.pop(key, None);
                _session_activity.pop(key, None);
                _session_user_map.pop(key, None);
            }
        }

        if len(stale_keys) > 0 {
            _logger.info("Cleaned " + str(len(stale_keys)) + " idle sessions");
        }
    }
}


# =====================================================================
# Graceful Shutdown
# =====================================================================

"""Clean up ALL active sessions. Called on SIGTERM or server stop."""
def shutdown_all() -> None {
    with _meta_lock {
        all_keys = list(_session_activity.keys());
    }
    _logger.info("Shutting down " + str(len(all_keys)) + " active sessions");

    for key in all_keys {
        parts = _parse_key(key);
        uid = parts[0];
        pid = parts[1];
        if uid and pid {
            _run_cleanup_callbacks(uid, pid);
        }
    }

    with _meta_lock {
        _session_locks.clear();
        _session_activity.clear();
        _session_user_map.clear();
    }
    _logger.info("Shutdown complete");
}

"""Signal handler for SIGTERM/SIGINT."""
def _shutdown_handler(signum: int, frame: Any) -> None {
    global _running;
    _logger.info("Shutdown signal received (sig=" + str(signum) + ")");
    _running = False;
    shutdown_all();
}


# =====================================================================
# Session Removal (explicit, e.g. project delete)
# =====================================================================

"""Remove a session entry. Does NOT run cleanup callbacks (caller handles that)."""
def remove_session(user_id: str, project_id: str) -> None {
    key = session_key(user_id, project_id);
    with _meta_lock {
        _session_locks.pop(key, None);
        _session_activity.pop(key, None);
        _session_user_map.pop(key, None);
    }
}


# =====================================================================
# Queries
# =====================================================================

"""Return number of active sessions (for health/status endpoints)."""
def get_active_session_count() -> int {
    return len(_session_activity);
}

"""Get all active session keys for a specific user."""
def get_user_sessions(user_id: str) -> list {
    result: list = [];
    with _meta_lock {
        for key in _session_user_map {
            if _session_user_map[key] == user_id {
                result.append(key);
            }
        }
    }
    return result;
}


# =====================================================================
# Initialization
# =====================================================================

"""Start cleanup thread and register signal handlers. Call once at server start."""
def init_session_manager() -> None {
    global _cleanup_thread, _initialized;

    if _initialized {
        return;
    }
    _initialized = True;

    _cleanup_thread = threading.Thread(target=_cleanup_loop, daemon=True);
    _cleanup_thread.start();

    # Register graceful shutdown signals
    try {
        signal.signal(signal.SIGTERM, _shutdown_handler);
    } except Exception as e {
        _logger.warning("Could not register SIGTERM handler: " + str(e));
    }

    _logger.info(
        "Session manager initialized (idle_ttl="
        + str(int(SESSION_IDLE_TTL)) + "s, sweep_interval="
        + str(int(CLEANUP_INTERVAL)) + "s)"
    );
}
