import time;

glob _event_callbacks: list = [];
glob _step_counter: int = 0;
glob _active_tool: dict = {};
glob _turn_start: float = 0.0;
glob _turn_tools: int = 0;
glob _turn_errors: int = 0;
glob _turn_files: list = [];
glob _agent_prefix: str = "";


def set_agent_prefix(prefix: str) -> None {
    global _agent_prefix;
    _agent_prefix = prefix;
}

def get_agent_prefix() -> str {
    return _agent_prefix;
}


def register_event_callback(cb: Any) -> None {
    _event_callbacks.append(cb);
}

def clear_event_callbacks() -> None {
    _event_callbacks.clear();
}

def next_step() -> int {
    global _step_counter,_turn_tools;
    _step_counter += 1;
    _turn_tools += 1;
    return _step_counter;
}

def reset_steps() -> None {
    global _step_counter,_active_tool;
    _step_counter = 0;
    _active_tool = {};
}

def get_active_tool() -> dict {
    return _active_tool;
}

def set_active_tool(info: dict) -> None {
    global _active_tool;
    _active_tool = info;
}

def start_turn() -> None {
    global _turn_start,_turn_tools,_turn_errors,_turn_files;
    _turn_start = time.time();
    _turn_tools = 0;
    _turn_errors = 0;
    _turn_files = [];
}

def track_file(path: str) -> None {
    global _turn_files;
    if path and path not in _turn_files {
        _turn_files.append(path);
    }
}

def track_error() -> None {
    global _turn_errors;
    _turn_errors += 1;
}

def emit_turn_summary() -> dict {
    global _turn_start,_turn_tools,_turn_errors,_turn_files;
    duration_s = round(time.time() - _turn_start, 1) if _turn_start > 0 else 0.0;
    summary = {
        "tools_count": _turn_tools,
        "files_modified": list(_turn_files),
        "errors": _turn_errors,
        "duration_s": duration_s
    };
    emit_event("turn_summary", summary);
    return summary;
}

def emit_event(event_type: str, data: dict) -> None {
    if not _event_callbacks {
        return;
    }
    data["timestamp"] = time.time();
    data["event_type"] = event_type;
    for cb in _event_callbacks {
        try {
            cb(event_type, data);
        } except Exception as e {
            import sys;
            sys.stderr.write(f"[events] callback error: {e}\n");
        }
    }
}
