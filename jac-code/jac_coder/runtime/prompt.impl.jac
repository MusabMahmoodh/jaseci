"""Implementation of mode-aware dynamic prompt assembly."""


# ---------------------------------------------------------------------------
# infer_mode_hint — classify what the agent did from ground truth
# ---------------------------------------------------------------------------
impl infer_mode_hint(tools_used: list[str], files_modified: list[str]) -> str {
    if files_modified {
        return MODE_BUILDING;
    }
    tool_set = set(tools_used);
    if _BUILD_TOOLS & tool_set {
        return MODE_BUILDING;
    }
    if _DEBUG_TOOLS & tool_set {
        return MODE_DEBUGGING;
    }
    if _GIT_TOOLS & tool_set {
        return MODE_GIT_OPS;
    }
    if _READ_TOOLS & tool_set {
        return MODE_EXPLORING;
    }
    return MODE_ANSWERING;
}


# ---------------------------------------------------------------------------
# select_prompt_modules — assemble the right workflow modules for this turn
# ---------------------------------------------------------------------------
impl select_prompt_modules(
    last_mode_hint: str,
    message: str,
    directory: str,
    chat_history: list[dict]
) -> str {
    # ── FIRST TURN: no previous hint ──
    if not last_mode_hint {
        return _first_turn_prompt(message, directory);
    }

    # ── SUBSEQUENT TURNS ──
    effective_mode = last_mode_hint;

    # Override: user shifting from non-build → build
    if effective_mode in [MODE_ANSWERING, MODE_EXPLORING, MODE_GIT_OPS] {
        if _smells_like_build(message) {
            effective_mode = MODE_BUILDING;
        }
    }

    # Assemble modules for the effective mode
    parts: list = [];
    modules = _MODULE_MAP.get(effective_mode, []);
    parts.extend(modules);

    # Browser testing rules: only if browser was used in this session
    if effective_mode in [MODE_BUILDING, MODE_DEBUGGING] {
        if _has_browser_history(chat_history) {
            if SEM_BROWSER_TESTING not in parts {
                parts.append(SEM_BROWSER_TESTING);
            }
        }
    }

    # Progress template: only if file doesn't exist yet
    if effective_mode == MODE_BUILDING and not _progress_exists(directory) {
        parts.append(SEM_PROGRESS_TEMPLATE);
    }

    if not parts {
        return "";
    }
    return "\n\n".join(parts);
}


# ---------------------------------------------------------------------------
# First turn prompt — uses filesystem state + keyword match
# ---------------------------------------------------------------------------
def _first_turn_prompt(message: str, directory: str) -> str {
    has_progress = _progress_exists(directory);
    has_project = directory and (
        os.path.isfile(os.path.join(directory, "jac.toml"))
        or os.path.isfile(os.path.join(directory, "main.jac"))
    );

    if has_progress or has_project or _smells_like_build(message) {
        parts: list = [SEM_BUILD_WORKFLOW, SEM_STYLING];
        if not has_progress {
            parts.append(SEM_PROGRESS_TEMPLATE);
        }
        return "\n\n".join(parts);
    }

    # No project, no build intent → no workflow modules (core sem is always present)
    return "";
}


# ---------------------------------------------------------------------------
# Helpers — all zero-cost (string checks + stat syscalls)
# ---------------------------------------------------------------------------

def _smells_like_build(message: str) -> bool {
    msg = message.lower();
    for phrase in _BUILD_PHRASES {
        if phrase in msg {
            return True;
        }
    }
    return False;
}

def _progress_exists(directory: str) -> bool {
    if not directory {
        return False;
    }
    return os.path.isfile(os.path.join(directory, ".jaccoder", "progress.md"));
}

def _has_browser_history(chat_history: list[dict]) -> bool {
    for msg in chat_history {
        used = msg.get("tools_used", []);
        if _BROWSER_TOOLS & set(used) {
            return True;
        }
    }
    return False;
}
