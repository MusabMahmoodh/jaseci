def _build_prefix(
    active_files: list[str], pending_errors: list[str], project_summary: str = ""
) -> list[dict] {
    parts = [];
    if project_summary {
        parts.append("Project context:\n" + project_summary);
    }
    if active_files {
        parts.append("Active files: " + ", ".join(active_files));
    }
    if pending_errors {
        parts.append("Pending errors:\n" + "\n".join(pending_errors));
    }
    if parts {
        return [{"role": "system", "content": "\n\n".join(parts)}];
    }
    return [];
}


def _extract_key_actions(messages: list[dict]) -> str {
    files = [];
    for msg in messages {
        if msg.get("role") == "assistant" {
            for f in msg.get("files_modified", []) {
                if f not in files {
                    files.append(f);
                }
            }
        }
    }
    if files {
        return ", ".join(files[:5]);
    }
    return "exploration and planning";
}


def _select_important(older: list[dict]) -> list[dict] {
    important = [];
    i = 0;
    while i < len(older) {
        msg = older[i];
        if msg.get("role") == "assistant" {
            content = msg.get("content", "");
            files = msg.get("files_modified", []);
            is_important = (
                len(files) > 0
                or "ACTION REQUIRED" in content
                or "VALIDATION ERRORS" in content
                or "RUNTIME ERRORS" in content
            );
            if is_important {
                if i > 0 and older[i - 1] not in important {
                    important.append(older[i - 1]);
                }
                important.append(msg);
            }
        }
        i += 1;
    }
    return important;
}


impl estimate_tokens(messages: list[dict]) -> int {
    total = 0;
    for msg in messages {
        total += len(msg.get("content", ""));
    }
    return total // 4;
}


impl needs_compaction(messages: list[dict], budget: int = 20000) -> bool {
    return estimate_tokens(messages) > int(budget * 0.8);
}


impl build_context(
    chat_history: list[dict],
    active_files: list[str] = [],
    pending_errors: list[str] = [],
    config: ContextConfig | None = None,
    project_summary: str = ""
) -> list[dict] {
    cfg = config if config else ContextConfig();
    prefix = _build_prefix(active_files, pending_errors, project_summary);

    if not needs_compaction(chat_history, cfg.token_budget) {
        return prefix + list(chat_history);
    }

    recent_msg_count = cfg.recent_window * 2;
    if len(chat_history) <= recent_msg_count {
        return prefix + list(chat_history);
    }

    recent = chat_history[-recent_msg_count:];
    older = chat_history[:-recent_msg_count];

    important = _select_important(older);

    non_important_count = (len(older) - len(important)) // 2;
    result = list(prefix);
    if non_important_count > 0 {
        actions = _extract_key_actions(older);
        summary = (
            f"[Context compacted: {non_important_count} earlier exchanges condensed. "
            f"Key actions: {actions}]"
        );
        result.append({"role": "system", "content": summary});
    }
    result.extend(important);
    result.extend(recent);
    return result;
}
