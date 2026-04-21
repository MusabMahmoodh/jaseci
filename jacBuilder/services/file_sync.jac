"""File Sync — Debounced, batched file sync from repo dir to K8s sandbox pods.

Solves the dual-write race condition where both editor saves (write_preview_file)
and file watcher (_sync_file_to_sandbox) independently write to the sandbox.

Both paths now call notify_change() which adds to a pending set. After 500ms
of no new changes, a single batched flush sends all changed files to the
sandbox in one operation.
"""

import os;
import time;
import from threading { Lock, Timer }
import from typing { Any }

glob _pending: dict = {};
glob _timers: dict = {};
glob _sync_lock: Any = Lock();
glob DEBOUNCE_MS: int = 500;

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

"""Notify that a file has changed and needs syncing to the sandbox.
Debounces: waits 500ms after the last change before flushing."""
def notify_change(sandbox_id: str, rel_path: str, abs_path: str) -> None {
    if not sandbox_id or not rel_path {
        return;
    }
    _sync_lock.acquire();
    try {
        if sandbox_id not in _pending {
            _pending[sandbox_id] = set();
        }
        _pending[sandbox_id].add((rel_path, abs_path));

        existing_timer = _timers.get(sandbox_id);
        if existing_timer is not None {
            existing_timer.cancel();
        }
        delay = DEBOUNCE_MS / 1000.0;
        t = Timer(delay, _flush, args=[sandbox_id]);
        t.daemon = True;
        t.start();
        _timers[sandbox_id] = t;
    } finally {
        _sync_lock.release();
    }
}

"""Notify a change with content already available (from editor save).
Writes content to a temp buffer and syncs via the same debounced path."""
def notify_change_with_content(sandbox_id: str, rel_path: str, content: str) -> None {
    if not sandbox_id or not rel_path {
        return;
    }
    _sync_lock.acquire();
    try {
        if sandbox_id not in _pending {
            _pending[sandbox_id] = set();
        }
        _pending[sandbox_id].add((rel_path, f"__content__:{content}"));

        existing_timer = _timers.get(sandbox_id);
        if existing_timer is not None {
            existing_timer.cancel();
        }
        delay = DEBOUNCE_MS / 1000.0;
        t = Timer(delay, _flush, args=[sandbox_id]);
        t.daemon = True;
        t.start();
        _timers[sandbox_id] = t;
    } finally {
        _sync_lock.release();
    }
}

"""Force immediate flush for a sandbox (used on explicit save)."""
def flush_now(sandbox_id: str) -> None {
    _sync_lock.acquire();
    try {
        existing_timer = _timers.pop(sandbox_id, None);
        if existing_timer is not None {
            existing_timer.cancel();
        }
    } finally {
        _sync_lock.release();
    }
    _flush(sandbox_id);
}

"""Cancel all pending syncs for a sandbox (used on cleanup)."""
def cancel_pending(sandbox_id: str) -> None {
    _sync_lock.acquire();
    try {
        _pending.pop(sandbox_id, None);
        existing_timer = _timers.pop(sandbox_id, None);
        if existing_timer is not None {
            existing_timer.cancel();
        }
    } finally {
        _sync_lock.release();
    }
}

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

def _flush(sandbox_id: str) -> None {
    _sync_lock.acquire();
    try {
        files = _pending.pop(sandbox_id, set());
        _timers.pop(sandbox_id, None);
    } finally {
        _sync_lock.release();
    }
    if not files {
        return;
    }

    try {
        import from services.sandbox_store { get_backend }
        backend = get_backend();
        if backend is None {
            return;
        }

        cnt: int = 0;
        for item in files {
            try {
                (rel_path, source) = item;
                if str(source).startswith("__content__:") {
                    content = str(source)[len("__content__:"):];
                    backend.write_file(sandbox_id, str(rel_path), content);
                    cnt = int(cnt) + 1;
                } elif os.path.isfile(str(source)) {
                    with open(str(source), "r", encoding="utf-8") as f {
                        content = f.read();
                    }
                    backend.write_file(sandbox_id, str(rel_path), content);
                    cnt = int(cnt) + 1;
                }
            } except Exception as e {
                print(f"[file_sync] Failed to sync to {sandbox_id}: {e}");
            }
        }
        if cnt > 0 {
            print(f"[file_sync] Flushed {cnt} files to sandbox {sandbox_id}");
        }
    } except Exception as e {
        print(f"[file_sync] Flush error for {sandbox_id}: {e}");
    }
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

"""Cancel all pending syncs (called on shutdown)."""
def cleanup_all() -> None {
    _sync_lock.acquire();
    try {
        for sid in list(_timers.keys()) {
            timer = _timers.get(sid);
            if timer is not None {
                timer.cancel();
            }
        }
        _timers.clear();
        _pending.clear();
    } finally {
        _sync_lock.release();
    }
}
