# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
impl initialize(mode: str = "web") -> None {
    if mode == "web" {
        os.environ["JACCODER_WEB_MODE"] = "1";
        permission_engine.init_defaults();
        permission_engine.enable_web_mode();
    } else {
        permission_engine.init_defaults();
    }
}


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------
impl create_session(directory: str, title: str = "", agent: str = "main") -> dict {
    session_title = title if title else f"Session-{datetime.now().strftime('%H%M%S')}";
    before_ids = set([s.id for s in [root-->][?:Session]]);

    root spawn new_session(title=session_title, directory=directory);

    session_id = "";
    session_obj = None;
    for s in [root-->][?:Session] {
        if s.id not in before_ids {
            session_id = s.id;
            session_obj = s;
            break;
        }
    }
    if not session_id {
        return {"error": "Failed to create session"};
    }

    # Store in registry so background threads can find it
    _session_registry[session_id] = session_obj;

    return {"session_id": session_id, "title": session_title, "status": "created"};
}


impl list_sessions() -> list {
    result: list = [];
    for s in [root-->][?:Session][?status=="active"] {
        user_msgs = len(
            [
                m
                for m in s.chat_history
                if m.get("role") == "user"
            ]
        );
        result.append(
            {
                "id": s.id,
                "title": s.title,
                "message_count": user_msgs,
                "updated_at": s.updated_at
            }
        );
    }
    result.sort(key=lambda x : x["updated_at"], reverse=True);
    return result;
}


impl get_session(session_id: str) -> dict {
    matches = [root-->][?:Session][?id==session_id];
    if not matches {
        return {"error": "Session not found"};
    }
    s = matches[0];
    return {
        "id": s.id,
        "title": s.title,
        "status": s.status,
        "directory": s.directory,
        "chat_history": s.chat_history,
        "created_at": s.created_at,
        "updated_at": s.updated_at
    };
}


impl close_session(session_id: str) -> dict {
    matches = [root-->][?:Session][?id==session_id];
    if not matches {
        return {"error": "Session not found"};
    }
    matches[0].status = "closed";
    matches[0].updated_at = datetime.now().isoformat();
    _session_registry.pop(session_id, None);
    return {"status": "closed", "id": matches[0].id};
}


# ---------------------------------------------------------------------------
# chat — the main entry point
# ---------------------------------------------------------------------------
impl chat(
    session_id: str,
    message: str,
    directory: str = "",
    on_event: Any = None,
    mode: str = "full",
    agent_context: str = ""
) -> dict {
    # Find session — try registry first (works across threads), then graph
    session = _session_registry.get(session_id);
    if not session {
        matches = [root-->][?:Session][?id==session_id];
        if matches {
            session = matches[0];
            _session_registry[session_id] = session;
        }
    }
    if not session {
        return {"error": "Session not found", "agent": "error"};
    }

    # Override directory if provided
    if directory {
        session.directory = directory;
    }
    work_dir = session.directory;

    # Setup
    reset_steps();
    start_turn();
    if work_dir {
        set_sandbox_root(work_dir);
    }
    if on_event {
        register_event_callback(on_event);
    }

    try {
        # Memory initialization
        _ensure_memory(session, work_dir);

        # Add user message
        session.chat_history.append({"role": "user", "content": message});
        session.updated_at = datetime.now().isoformat();

        # Get MainAgent — always resolve fresh (cached refs go stale in jac serve)
        main_agent = ensure_main_agent();

        # Initialize shared budget for SubAgents
        config = get_config();
        _init_spawn_budget(config.max_react_iterations * 3);

        # Build context
        ctx_history = build_context(
            session.chat_history,
            session.active_files,
            session.pending_errors,
            project_summary=session.project_summary or ""
        );

        # Inject agent_context if provided (e.g. from JacBuilder)
        if agent_context {
            ctx_history.insert(0, {"role": "system", "content": agent_context});
        }

        # Call MainAgent — returns StreamEvent generator with logging enabled
        event_stream = main_agent.respond(message=message, chat_history=ctx_history);
        stream_result = _consume_llm_stream(event_stream);

        response_text = stream_result["content"];
        tools_used = stream_result["tools_used"];

        # Finalize turn — get accumulated file/error data from tool internals
        tool_end();
        summary = emit_turn_summary();

        files_modified = summary.get("files_modified", []);
        has_errors = summary.get("errors", 0) > 0;

        # Update session state
        if files_modified {
            for f in files_modified {
                if f not in session.active_files {
                    session.active_files.append(f);
                }
            }
            if len(session.active_files) > 10 {
                session.active_files = session.active_files[-10:];
            }
        }
        if has_errors {
            files_str = ", ".join(files_modified) if files_modified else "unknown";
            session.pending_errors = [f"Errors in previous turn (files: {files_str})"];
        } else {
            session.pending_errors = [];
        }
        if files_modified and session.directory {
            memory = find_or_create_memory(session.directory);
            if memory {
                update_memory_from_session(
                    memory, files_modified, response_text[:500]
                );
                session.project_summary = memory.summarize();
            }
        }

        # Persist response
        record: dict = {"role": "assistant", "content": response_text, "agent": "main"};
        if tools_used {
            record["tools_used"] = tools_used;
        }
        if files_modified {
            record["files_modified"] = files_modified;
        }
        session.chat_history.append(record);
        session.last_agent = "main";
        session.updated_at = datetime.now().isoformat();

        return {
            "response": response_text,
            "agent": "main",
            "tools_used": tools_used,
            "files_modified": files_modified,
            "has_errors": has_errors,
            "next_steps": [],
            "turn_summary": summary
        };
    } except Exception as e {
        sys.stderr.write(f"[api] chat error: {e}\n");
        return {"error": str(e), "agent": "error"};
    } finally {
        if on_event {
            clear_event_callbacks();
        }
    }
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
def _ensure_memory(session: Session, work_dir: str) -> None {
    if not work_dir or session.project_summary {
        return;
    }
    memory = find_or_create_memory(work_dir);
    if not memory {
        return;
    }
    has_project = (
        os.path.exists(os.path.join(work_dir, "jac.toml"))
        or os.path.exists(os.path.join(work_dir, "main.jac"))
    );
    if not memory.architecture and not memory.scan_attempted and has_project {
        _init_memory(memory, work_dir);
    }
    summary = memory.summarize();
    if summary {
        session.project_summary = summary;
    }
}


def _post_process(session: Session, response_obj: Any) -> None {
    # Track files
    if response_obj.files_modified {
        for f in response_obj.files_modified {
            if f not in session.active_files {
                session.active_files.append(f);
            }
        }
        if len(session.active_files) > 10 {
            session.active_files = session.active_files[-10:];
        }
    }

    # Track errors
    if response_obj.has_errors {
        files_str = ", ".join(response_obj.files_modified)
            if response_obj.files_modified
            else "unknown";
        session.pending_errors = [f"Errors in previous turn (files: {files_str})"];
    } else {
        session.pending_errors = [];
    }

    # Update memory
    if response_obj.files_modified and session.directory {
        memory = find_or_create_memory(session.directory);
        if memory {
            update_memory_from_session(
                memory, response_obj.files_modified, response_obj.content[:500]
            );
            session.project_summary = memory.summarize();
        }
    }

    # Persist response
    record: dict = {
        "role": "assistant",
        "content": response_obj.content,
        "agent": "main"
    };
    if response_obj.tools_used {
        record["tools_used"] = response_obj.tools_used;
    }
    if response_obj.files_modified {
        record["files_modified"] = response_obj.files_modified;
    }
    session.chat_history.append(record);
    session.last_agent = "main";
    session.updated_at = datetime.now().isoformat();
}


def _init_spawn_budget(total: int) -> None {
    try {
        import from jac_coder.tool.delegation { init_budget }
        ;
        init_budget(total);
    } except Exception { }
}
