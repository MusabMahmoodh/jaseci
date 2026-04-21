glob TOOL_LABELS: dict = {
         "read": "Read",
         "write": "Write",
         "edit": "Edit",
         "list": "List files",
         "grep": "Search",
         "glob": "Find files",
         "bash": "Run command",
         "web_fetch": "Fetch URL",
         "web_search": "Web search",
         "jac_docs": "Jac docs",
         "jac_check": "Check",
         "jac_run": "Run",
         "scaffold": "Scaffold",
         "spawn_task": "Spawn task",
         "spawn_agent": "SubAgent",
         "update_todos": "Update plan"
     };


def _auto_close_tool(prev: dict) -> None {
    duration_ms = int((time.time() - prev["start_time"]) * 1000);
    if duration_ms >= 1000 {
        timing = f"{round(duration_ms / 1000, 1)}s";
    } else {
        timing = f"{duration_ms}ms";
    }
    sys.stderr.write(f" {DIM}({timing}){RESET}\n");
    sys.stderr.flush();
    emit_event(
        "tool_end",
        {
            "tool": prev["tool"],
            "step": prev["step"],
            "status": "done",
            "duration_ms": duration_ms,
            "result_preview": "",
            "message": f"{prev['message']} ({timing})"
        }
    );
    set_active_tool({});
}


impl smart_path(path: str) -> str {
    if not path {
        return path;
    }
    sroot = get_sandbox_root();
    if sroot and path.startswith(sroot) {
        rel = os.path.relpath(path, sroot);
        return rel;
    }
    stripped = re.sub(r'/tmp/jac-preview-[a-f0-9\-]+-prj_\d+/', '', path);
    if stripped != path {
        return stripped;
    }
    parts = path.replace("\\", "/").split("/");
    if len(parts) > 2 {
        return os.path.join(parts[-2], parts[-1]);
    }
    return path;
}


def _clean_paths(text: str) -> str {
    if not text {
        return text;
    }
    sroot = get_sandbox_root();
    if sroot and sroot in text {
        text = text.replace(sroot + "/", "").replace(sroot, "");
    }
    text = re.sub(r'/tmp/jac-preview-[a-f0-9\-]+-prj_\d+/', '', text);
    text = re.sub(r'/tmp/[^\s]+/([^/\s]+/[^/\s]+)', r'\1', text);
    return text;
}


impl tool_status(tool_name: str, detail: str = "") -> None {
    prev = get_active_tool();
    if prev {
        _auto_close_tool(prev);
    }

    step = next_step();
    label = TOOL_LABELS.get(tool_name, tool_name);
    prefix = get_agent_prefix();
    prefix_display = f"{prefix}:" if prefix else "";
    detail_display = _clean_paths(detail) if detail else "";
    detail_short = detail_display[:80] + "..."
        if len(detail_display) > 80
        else detail_display;

    if detail_short {
        sys.stderr.write(
            f"  {DIM}{CYAN}[{prefix_display}{step}] {label}:{RESET}{DIM} {detail_short}{RESET}"
        );
    } else {
        sys.stderr.write(f"  {DIM}{CYAN}[{prefix_display}{step}] {label}{RESET}");
    }
    sys.stderr.flush();

    if detail_short {
        message = f"{label} {detail_short}";
    } else {
        message = label;
    }

    # Track file modifications for turn summary
    if tool_name in ["write", "edit"] and detail {
        track_file(detail_display);
    }

    note_tool(tool_name);

    set_active_tool(
        {
            "tool": tool_name,
            "detail": detail_short or tool_name,
            "step": step,
            "message": message,
            "start_time": time.time()
        }
    );

    emit_event(
        "tool_start",
        {
            "tool": tool_name,
            "detail": detail_short or tool_name,
            "step": step,
            "message": message
        }
    );
}


impl tool_end(result_preview: str = "", error: bool = False) -> None {
    active = get_active_tool();
    if not active {
        return;
    }
    duration_ms = int((time.time() - active["start_time"]) * 1000);
    status = "error" if error else "done";
    preview = result_preview[:80] + "..."
        if len(result_preview) > 80
        else result_preview;

    if error {
        track_error();
    }

    # Format timing
    if duration_ms >= 1000 {
        timing = f"{round(duration_ms / 1000, 1)}s";
    } else {
        timing = f"{duration_ms}ms";
    }

    if preview {
        sys.stderr.write(f" {DIM}{preview}{RESET} {DIM}({timing}){RESET}\n");
    } else {
        sys.stderr.write(f" {DIM}({timing}){RESET}\n");
    }
    sys.stderr.flush();

    emit_event(
        "tool_end",
        {
            "tool": active["tool"],
            "step": active["step"],
            "status": status,
            "duration_ms": duration_ms,
            "result_preview": preview,
            "message": f"{active['message']} ({timing})"
        }
    );
    set_active_tool({});
}


impl note_tool(name: str) -> None {
    _tl_tool.name = name;
}


impl persist_result(tool_name: str, text: str) -> str {
    sroot = get_sandbox_root();
    if not sroot {
        sroot = os.getcwd();
    }
    store_dir = os.path.join(sroot, ".jaccoder", "tool-results");
    try {
        os.makedirs(store_dir, exist_ok=True);
    } except Exception {
        return text[:MAX_CHARS] + "\n\n(output truncated — could not persist)";
    }

    timestamp = int(time.time() * 1000);
    clean_name = tool_name if tool_name else "tool";
    filename = f"{clean_name}-{timestamp}.txt";
    filepath = os.path.join(store_dir, filename);
    try {
        with open(filepath, "w", encoding="utf-8") as f {
            f.write(text);
        }
    } except Exception {
        return text[:MAX_CHARS] + "\n\n(output truncated — could not write file)";
    }

    sizes = PREVIEW_SIZES.get(tool_name, (25, 25));
    head_n: int = int(sizes[0]);
    tail_n: int = int(sizes[1]);
    lines = text.split("\n");
    total: int = len(lines);
    rel_path = os.path.join(".jaccoder", "tool-results", filename);

    if tail_n > 0 and total > (head_n + tail_n) {
        head: list = lines[:head_n];
        tail: list = lines[-tail_n:];
        omitted: int = total - head_n - tail_n;
        preview_lines: list = head + [f"\n... ({omitted} lines omitted) ...\n"] + tail;
        preview = "\n".join(preview_lines);
    } else {
        take: int = head_n + tail_n;
        preview = "\n".join(lines[:take]);
    }

    return preview + f"\n\n[Full output ({total} lines) saved to {rel_path}]";
}


impl truncate_output(
    text: str, max_lines: int = MAX_LINES, max_chars: int = MAX_CHARS
) -> tuple {
    tool = getattr(_tl_tool, "name", "");

    # Tier 1 — fits within limit: apply line cap if needed, send as-is
    if len(text) <= max_chars {
        lines = text.split("\n");
        if len(lines) <= max_lines {
            return (text, False);
        }
        half = max_lines // 2;
        kept = lines[:half] + [
            "",
            f"... ({len(lines) - max_lines} lines omitted) ...",
            ""
        ] + lines[-half:];
        return ("\n".join(kept) + "\n\n(output truncated)", True);
    }

    # Tier 2 — file tools: source is on disk, cap by chars and hint agent to use offset
    if tool in FILE_TOOLS {
        preview = text[:max_chars];
        last_nl = preview.rfind("\n");
        if last_nl > 0 {
            preview = preview[:last_nl];
        }
        return (preview + "\n\n(truncated — use offset parameter to read more)", True);
    }

    # Tier 3 — large ephemeral output: persist to disk + smart head+tail preview
    result = persist_result(tool, text);
    return (result, True);
}
