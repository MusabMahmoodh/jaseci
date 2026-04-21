import time;
import threading;

glob _tl = threading.local();


def _callbacks() -> list {
    if not hasattr(_tl, "callbacks") {
        _tl.callbacks = [];
    }
    return _tl.callbacks;
}

def register_event_callback(cb: Any) -> None {
    _callbacks().append(cb);
}

def clear_event_callbacks() -> None {
    _tl.callbacks = [];
}

def next_step() -> int {
    if not hasattr(_tl, "step_counter") {
        _tl.step_counter = 0;
    }
    if not hasattr(_tl, "turn_tools") {
        _tl.turn_tools = 0;
    }
    _tl.step_counter += 1;
    _tl.turn_tools += 1;
    return _tl.step_counter;
}

def reset_steps() -> None {
    _tl.step_counter = 0;
    _tl.active_tool = {};
}

def get_active_tool() -> dict {
    return getattr(_tl, "active_tool", {});
}

def set_active_tool(info: dict) -> None {
    _tl.active_tool = info;
}

def set_agent_prefix(prefix: str) -> None {
    _tl.agent_prefix = prefix;
}

def get_agent_prefix() -> str {
    return getattr(_tl, "agent_prefix", "");
}

def start_turn() -> None {
    _tl.turn_start = time.time();
    _tl.turn_tools = 0;
    _tl.turn_errors = 0;
    _tl.turn_files = [];
    _tl.tool_history = [];
    _tl.jac_docs_called = False;
    _tl.jac_docs_call_count = 0;
    _tl.writes_since_jac_docs = 0;
    # NOTE: validate_fails is NOT reset here — it persists across turns
    # so failure escalation (1st→2nd→3rd FAIL) works across conversation turns.
    # It's initialized lazily in track_validate_result() on first use.
}


# ---------------------------------------------------------------------------
# Doom loop detection — tracks recent tool calls to detect repetition.
# Returns a redirect message if the agent is stuck, or "" if OK.
# ---------------------------------------------------------------------------

def check_tool_loop(tool_name: str, key_arg: str) -> str {
    if not hasattr(_tl, "tool_history") {
        _tl.tool_history = [];
    }
    sig = f"{tool_name}::{key_arg}";
    history = _tl.tool_history;
    history.append(sig);

    # Keep only last 10 calls
    if len(history) > 10 {
        _tl.tool_history = history[-10:];
        history = _tl.tool_history;
    }

    # Check: same tool+arg called 3+ times in last 5 calls
    recent = history[-5:];
    count = recent.count(sig);
    if count >= 3 {
        _tl.tool_history = [h for h in history if h != sig];
        if "edit" in tool_name {
            return (
                f"LOOP DETECTED: {tool_name} called {count} times with the same arguments and keeps failing. "
                f"STOP and try a different approach: call read_file() first to see the actual file content, "
                f"then use the correct old_string from the file."
            );
        }
        if "write" in tool_name {
            return (
                f"LOOP DETECTED: {tool_name} called {count} times on the same file and keeps failing. "
                f"STOP and try a different approach: call jac_docs() to look up the correct syntax, "
                f"then rewrite the file."
            );
        }
        return (
            f"LOOP DETECTED: {tool_name} called {count} times with the same arguments. "
            f"STOP and try a different approach."
        );
    }

    # Check: same tool on same file failed 3+ times (even with different args)
    tool_prefix = tool_name + "::";
    file_part = key_arg.split("/")[-1] if "/" in key_arg else key_arg;
    if file_part {
        same_file_count = 0;
        for h in recent {
            if h.startswith(tool_prefix) and file_part in h {
                same_file_count += 1;
            }
        }
        if same_file_count >= 4 {
            _tl.tool_history = [h for h in history if not (h.startswith(tool_prefix) and file_part in h)];
            return (
                f"LOOP DETECTED: {tool_name} called {same_file_count} times on '{file_part}'. "
                f"STOP guessing. Read the file first, then make ONE correct edit."
            );
        }
    }

    return "";
}

def track_file(path: str) -> None {
    if not hasattr(_tl, "turn_files") {
        _tl.turn_files = [];
    }
    if path and path not in _tl.turn_files {
        _tl.turn_files.append(path);
    }
}

def track_error() -> None {
    if not hasattr(_tl, "turn_errors") {
        _tl.turn_errors = 0;
    }
    _tl.turn_errors += 1;
}

def emit_turn_summary() -> dict {
    turn_start = getattr(_tl, "turn_start", 0.0);
    turn_tools = getattr(_tl, "turn_tools", 0);
    turn_errors = getattr(_tl, "turn_errors", 0);
    turn_files = getattr(_tl, "turn_files", []);
    duration_s = round(time.time() - turn_start, 1) if turn_start > 0 else 0.0;
    summary = {
        "tools_count": turn_tools,
        "files_modified": list(turn_files),
        "errors": turn_errors,
        "duration_s": duration_s
    };
    emit_event("turn_summary", summary);
    return summary;
}


# ---------------------------------------------------------------------------
# Abort signal — dict keyed by thread ID.
# One thread can signal another to stop. GIL protects dict operations.
# ---------------------------------------------------------------------------
glob _abort_flags: dict = {};

"""Mark a specific thread for abort (cross-thread safe)."""
def request_abort_thread(tid: int) -> None {
    _abort_flags[tid] = True;
}

"""Check if the current thread should abort."""
def is_abort_requested() -> bool {
    return _abort_flags.get(threading.current_thread().ident, False);
}

"""Clear abort flag for the current thread (called at turn start)."""
def clear_abort() -> None {
    _abort_flags.pop(threading.current_thread().ident, None);
}

# ---------------------------------------------------------------------------
# jac_docs call tracking — tools check this to enforce "look it up first"
# ---------------------------------------------------------------------------

"""Record that jac_docs was called in this turn."""
def track_jac_docs_call() -> None {
    _tl.jac_docs_called = True;
    _tl.writes_since_jac_docs = 0;
}

"""Record a write/edit on a .jac file."""
def track_write_call() -> None {
    _tl.writes_since_jac_docs = getattr(_tl, "writes_since_jac_docs", 0) + 1;
}

"""Check if jac_docs has been called at least once this turn."""
def was_jac_docs_called() -> bool {
    return getattr(_tl, "jac_docs_called", False);
}

"""How many .jac writes since the last jac_docs call."""
def get_writes_since_jac_docs() -> int {
    return getattr(_tl, "writes_since_jac_docs", 0);
}


# ---------------------------------------------------------------------------
# Validate failure tracking — counts consecutive FAILs per URL
# ---------------------------------------------------------------------------

"""Track browser_validate results. Returns consecutive fail count for this URL."""
def track_validate_result(url: str, passed: bool) -> int {
    if not hasattr(_tl, "validate_fails") {
        _tl.validate_fails = {};
    }
    if passed {
        _tl.validate_fails.pop(url, None);
        return 0;
    }
    # Normalize URL for tracking (strip trailing slash)
    norm = url.rstrip("/");
    _tl.validate_fails[norm] = _tl.validate_fails.get(norm, 0) + 1;
    return _tl.validate_fails[norm];
}

"""Get consecutive fail count for a URL."""
def get_validate_fail_count(url: str) -> int {
    if not hasattr(_tl, "validate_fails") {
        return 0;
    }
    norm = url.rstrip("/");
    return _tl.validate_fails.get(norm, 0);
}


def emit_event(event_type: str, data: dict) -> None {
    cbs = _callbacks();
    if not cbs {
        return;
    }
    data["timestamp"] = time.time();
    data["event_type"] = event_type;
    for cb in list(cbs) {
        try {
            cb(event_type, data);
        } except Exception as e {
            import sys;
            sys.stderr.write(f"[events] callback error: {e}\n");
        }
    }
}
