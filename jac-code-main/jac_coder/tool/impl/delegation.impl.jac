impl init_budget(total: int = 90) -> None {
    global _shared_budget,_budget_initialized;
    with _budget_lock {
        _shared_budget = total;
        _budget_initialized = True;
    }
}


impl get_remaining_budget() -> int {
    with _budget_lock {
        return _shared_budget;
    }
}


impl consume_budget(used: int) -> None {
    global _shared_budget;
    with _budget_lock {
        _shared_budget = max(0, _shared_budget - used);
    }
}


impl get_recent_results_summary() -> str {
    if not _recent_results {
        return "";
    }
    parts: list = [];
    for r in _recent_results[-3:] {
        line = f"- [{r.get('mode', 'worker')}] {r.get('task_preview', '')[:100]}";
        fmod = r.get("files_modified", []);
        if fmod {
            line += f" -> modified: {', '.join(fmod)}";
        }
        errs = r.get("errors", []);
        if errs {
            line += f" -> errors: {', '.join(errs[:2])}";
        }
        parts.append(line);
    }
    return "Previous SubAgent results:\n" + "\n".join(parts);
}


impl get_project_summary_for_subagent() -> str {
    try {
        import jac_coder.nodes as _nodes;
        sessions = [root-->(?:(_nodes.Session))](?status=="active");
        if sessions {
            sessions.sort(key=lambda s : s.updated_at, reverse=True);
            proj_summary = sessions[0].project_summary;
            if proj_summary {
                return proj_summary;
            }
        }
    } except Exception { }
    return "";
}


impl spawn_agent(task: str, mode: str = "worker") -> str {
    tool_status("spawn_agent", f"[{mode}] {task[:80]}...");

    if not task {
        tool_end("-> no task", error=True);
        return "Error: task description is required.";
    }

    if mode not in ["worker", "explorer"] {
        mode = "worker";
    }

    # Check shared budget
    if not _budget_initialized {
        cfg = get_config();
        init_budget(cfg.max_react_iterations * 3);
    }
    remaining = get_remaining_budget();
    if remaining <= 0 {
        tool_end("-> budget exhausted", error=True);
        return "Error: Iteration budget exhausted. Cannot spawn more SubAgents.";
    }

    # Enrich task with session context
    project_ctx = get_project_summary_for_subagent();
    recent_work = get_recent_results_summary();

    enriched_parts: list = [task];
    if project_ctx {
        enriched_parts.append(f"\n\n--- Project Context ---\n{project_ctx}");
    }
    if recent_work {
        enriched_parts.append(f"\n\n--- Recent SubAgent Work ---\n{recent_work}");
    }
    enriched_task = "".join(enriched_parts);

    # Run in-process using pre-defined runner objects
    import from jac_coder.nodes { WorkerRunner, ExplorerRunner }
    ;

    try {
        runner = WorkerRunner() if mode == "worker" else ExplorerRunner();

        # Set prefix so tool events show [sub:worker:N] or [sub:explorer:N]
        set_agent_prefix(f"sub:{mode}");
        sys.stderr.write(f"\n");
        sys.stderr.flush();

        # Consume streaming events from SubAgent runner
        event_stream = runner.run(task_str=enriched_task);
        content = "";
        used_tools: list = [];
        fmod: list = [];

        for event in event_stream {
            if event.event_type == "thought" {
                emit_event("llm_thought", dict(event.data));
            } elif event.event_type == "tool_call" {
                tool_name = event.data.get("tool", "");
                if tool_name and tool_name != "finish_tool" {
                    used_tools.append(tool_name);
                    # Track file-modifying tools for SubAgent file list
                    args = event.data.get("args", {});
                    if tool_name in ["write_code", "edit_code", "write_file", "edit_file"] {
                        fp = args.get("file_path", "");
                        if fp and fp not in fmod {
                            fmod.append(fp);
                        }
                    }
                }
                emit_event("llm_tool_call", dict(event.data));
            } elif event.event_type == "tool_result" {
                emit_event("llm_tool_result", dict(event.data));
            } elif event.event_type == "steps_done" {
                emit_event("llm_steps_done", dict(event.data));
            } elif event.event_type == "chunk" {
                content += event.data.get("content", "");
            } elif event.event_type == "usage" {
                emit_event("llm_usage", dict(event.data));
            }
        }

        # Restore MainAgent prefix
        set_agent_prefix("");

        has_errs = False;
        iters_used = len(used_tools) if used_tools else 5;

        # Track budget and state
        consume_budget(iters_used);
        for fp in fmod {
            track_file(fp);
        }
        if has_errs {
            track_error();
        }

        # Record for future SubAgents
        _recent_results.append(
            {
                "mode": mode,
                "task_preview": task[:200],
                "files_modified": fmod,
                "errors": ["error"] if has_errs else [],
                "content_preview": content[:300] if content else ""
            }
        );

        # Build result string
        result_parts: list = [];
        if content {
            result_parts.append(content);
        }
        if fmod {
            result_parts.append(f"\nFiles modified: {', '.join(fmod)}");
        }
        if has_errs {
            result_parts.append(
                "\nNote: Some errors were encountered during execution."
            );
        }

        tool_end(f"-> {mode} done, {len(fmod)} files");
        return "\n".join(result_parts) if result_parts else "SubAgent completed.";
    } except Exception as e {
        consume_budget(5);
        tool_end(f"-> error: {e}", error=True);
        track_error();
        return f"Error: SubAgent failed - {str(e)}";
    }
}
