sem summarize_turns = """Summarize conversation history for a coding agent. Capture: user requests, files created/modified, errors and fixes, key decisions, current project state.
Format: 3-8 bullet points, one sentence each. No code snippets, no tool names. Focus on what happened and why. Under 300 words.""";

sem summarize_turns.older_messages = "Older conversation messages to summarize";
sem summarize_turns.session_goal = "The original user request that started this session";


def _build_prefix(
    active_files: list[str], pending_errors: list[str], project_summary: str = ""
) -> list[dict] {
    parts = [];
    if project_summary {
        # project_summary comes from .jaccoder/progress.md (preferred) or ProjectMemory
        # This is the agent's persistent knowledge of the project state.
        is_progress_file = project_summary.lstrip().startswith("#");
        label = "Project progress (.jaccoder/progress.md)" if is_progress_file else "Project context";
        parts.append(f"[INTERNAL — do NOT present this to the user unless they ask about the project. This is your background knowledge for making informed decisions.]\n{label}:\n{project_summary}");
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


"""Format older messages into a text block for the summarization LLM."""
def _format_for_summary(messages: list[dict]) -> str {
    lines: list = [];
    for msg in messages {
        role = msg.get("role", "");
        content = msg.get("content", "")[:200];
        if role == "user" {
            lines.append(f"User: {content}");
        } elif role == "assistant" {
            files = msg.get("files_modified", []);
            files_str = f" [files: {', '.join(files[:5])}]" if files else "";
            lines.append(f"Assistant: {content}{files_str}");
        } elif role == "tool" {
            name = msg.get("name", "tool");
            lines.append(f"Tool({name}): {content}");
        }
    }
    return "\n".join(lines);
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

    # Layer 1: Extract the session goal (first user message — always preserved)
    session_goal = "";
    for msg in older {
        if msg.get("role") == "user" {
            session_goal = msg.get("content", "");
            break;
        }
    }

    # Layer 2: LLM-based summarization of older turns
    summary_text = "";
    older_text = _format_for_summary(older);
    if older_text {
        try {
            import from jac_coder.runtime.events { emit_event }
            ;
            emit_event("context_compaction", {
                "status": "started",
                "turns_to_summarize": len([m for m in older if m.get("role") == "user"])
            });
            summary_text = summarize_turns(
                older_messages=older,
                session_goal=session_goal
            );
            emit_event("context_compaction", {
                "status": "done",
                "summary_length": len(summary_text)
            });
        } except Exception as e {
            # Fallback: extract key info without LLM
            sys.stderr.write(f"[context] Summarization failed, using fallback: {e}\n");
            files: list = [];
            user_requests: list = [];
            for msg in older {
                if msg.get("role") == "user" {
                    req = msg.get("content", "")[:80];
                    if req {
                        user_requests.append(req);
                    }
                }
                for f in msg.get("files_modified", []) {
                    if f not in files {
                        files.append(f);
                    }
                }
            }
            parts: list = [];
            parts.append(f"{len(user_requests)} earlier turns.");
            if user_requests {
                parts.append("User asked: " + " → ".join(user_requests[:5]));
            }
            if files {
                parts.append(f"Files modified: {', '.join(files[:8])}.");
            }
            summary_text = " ".join(parts);
        }
    }

    # Build the compacted context
    result = list(prefix);

    # Session background — context only, NOT a standing instruction.
    # The agent should always prioritize the current user message.
    if session_goal or summary_text {
        bg_parts: list = [];
        if session_goal {
            bg_parts.append(f"Session started with: {session_goal}");
        }
        if summary_text {
            bg_parts.append(f"Previous work:\n{summary_text}");
        }
        result.append({
            "role": "system",
            "content": "Background (for context only — respond to the user's CURRENT message, not this):\n" + "\n".join(bg_parts)
        });
    }

    # Layer 3: Recent exchanges verbatim
    result.extend(recent);
    return result;
}
