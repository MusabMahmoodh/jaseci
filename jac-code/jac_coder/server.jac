"""JacCoder stdio server.

This is the bridge between the VS Code extension (TypeScript) and the
JacCoder AI agent (Jac). The extension spawns this file as a subprocess
and they talk to each other through stdin/stdout using JSON messages.

How it works:
  Extension  -->  sends a JSON request  -->  stdin  -->  this server
  This server --> does the work         -->  stdout -->  extension

Message format (JSON-RPC 2.0):
  Request  (extension → server, has an "id", server replies):
    health            → check if server is alive
    session.create    → start a new chat session
    session.list      → get all sessions
    session.get       → get one session by id
    session.close     → close a session
    chat              → send a message to the AI agent
    mcp.add           → register an MCP tool server
    mcp.disconnect    → disconnect an MCP server (keeps config, reconnectable)
    mcp.reconnect     → reconnect a previously disconnected MCP server
    mcp.delete        → remove an MCP server entirely
    mcp.list          → list all MCP tool servers
    api.validate      → validate the configured API key
    model.get         → get the currently active model
    model.set         → switch the active model

  Inbound notification (extension → server, no "id", no reply):
    chat.cancel         → abort the running agent turn
    permission.response → user's Allow/Always/Deny decision for a guarded tool

  Outbound notification (server → extension, no "id"):
    server.ready      → server is up (sent once on startup, includes {service, version})
    chat.event        → live updates while agent runs:
                        llm_thought, llm_tool_call, llm_chunk,
                        tool_start, tool_end, file_written, file_edited,
                        file_snapshot, permission_request,
                        context_compaction, turn_summary
"""

import sys;
import os;
import json;
import asyncio;
import logging;
import threading;
import from typing { Any, IO }
import from importlib.metadata { version as _pkg_version, PackageNotFoundError }

import from jac_coder.tool.run.guarded { _permission_events, _permission_decisions }

import from jac_coder.api {
    initialize,
    chat as _api_chat,
    create_session as _api_create_session,
    list_sessions as _api_list_sessions,
    get_session as _api_get_session,
    close_session as _api_close_session,
    abort_session as _api_abort_session,
    api_mcp_add as _api_mcp_add,
    api_mcp_disconnect as _api_mcp_disconnect,
    api_mcp_reconnect as _api_mcp_reconnect,
    api_mcp_delete as _api_mcp_delete,
    api_mcp_list as _api_mcp_list,
    api_set_model as _api_set_model,
    api_get_model as _api_get_model
}
import from jac_coder.runtime.events { request_abort_thread }
import from jac_coder.runtime.cost_tracker { get_summary as _get_usage_summary, is_cost_tracking_enabled, reset as _reset_usage }
import from jac_coder.infra.config { llm }
import from byllm.exceptions { AuthenticationError as ByllmAuthError, RateLimitError as ByllmRateLimitError, ModelNotFoundError as ByllmModelNotFoundError }


# Debug logs — goes to stderr, not stdout, so JSON messages stay clean.
glob logger = logging.getLogger("jaccoder.stdio");

# Save a private copy of stdout before we redirect it to stderr.
# All JSON writes use this — so accidental print() calls never reach the extension.
glob _real_stdout: IO[str] = os.fdopen(os.dup(1), 'w', 1);

# Prevents two threads writing JSON at the same time and mixing the output.
glob _stdout_lock: threading.Lock = threading.Lock();

# Tracks cancelled sessions — set to True when user hits cancel.
glob _stop_flags: dict = {};

# Holds the running thread per session — used to force-stop it on cancel.
glob _chat_threads: dict = {};

# Guards against double-reply: set to True once the final frame is sent for a turn.
glob _reply_flags: dict = {};
glob _reply_lock: threading.Lock = threading.Lock();


"""Return installed jac-coder version, or 'unknown' if not installed as a package."""
def _get_server_version() -> str {
    try {
        return _pkg_version("jac-coder");
    } except PackageNotFoundError {
        return "unknown";
    }
}


"""Claim the single reply slot for a chat turn. Returns True only on the first call."""
def _try_reply(session_id: str) -> bool {
    global _reply_lock, _reply_flags;
    with _reply_lock {
        if _reply_flags.get(session_id) {
            return False;
        }
        _reply_flags[session_id] = True;
        return True;
    }
}


# ---------------------------------------------------------------------------
# JSON-RPC 2.0 message builders
# These just build the correct dict shape — nothing else.
# ---------------------------------------------------------------------------

"""Build a success response for a request."""
def _ok(req_id: Any, result: Any) -> dict {
    return {"jsonrpc": "2.0", "id": req_id, "result": result};
}

"""Build an error response for a request."""
def _err(req_id: Any, code: int, message: str) -> dict {
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}};
}

"""Build a server-push notification (no id — no reply expected)."""
def _notify(method: str, params: dict) -> dict {
    return {"jsonrpc": "2.0", "method": method, "params": params};
}

"""Build a cancelled response — sent when the user aborts a chat turn."""
def _cancelled(req_id: Any, extra: dict | None = None) -> dict {
    payload: dict = {"response": "", "agent": "cancelled", "cancelled": True};
    if extra {
        payload.update(extra);
    }
    return _ok(req_id, payload);
}


# ---------------------------------------------------------------------------
# Writes one JSON message to the extension — one at a time, thread-safe.
# ---------------------------------------------------------------------------

"""Write one JSON message to stdout (thread-safe)."""
def _write(msg: dict) -> None {
    global _stdout_lock, _real_stdout;
    line = json.dumps(msg, ensure_ascii=False);
    with _stdout_lock {
        _real_stdout.write(line + "\n");
        _real_stdout.flush();
    }
}


# ---------------------------------------------------------------------------
# Chat handler
#
# Each chat turn runs in its own thread because the LLM call is blocking
# (can take seconds or minutes). We can't block the main asyncio loop or
# we'd never be able to receive a chat.cancel notification while waiting.
#
# Flow:
#   1. Thread starts, calls the AI agent (_api_chat)
#   2. Agent fires on_event() for every tool it runs → we stream those back
#   3. When agent finishes → we send the final response
#   4. If user cancelled → we send a cancelled frame instead
# ---------------------------------------------------------------------------

"""Run one chat turn in a background thread and stream results back."""
def _handle_chat(req_id: Any, params: dict) -> None {
    session_id: str = params.get("session_id", "");
    message: str = params.get("message", "");
    agent_context: str = params.get("agent_context", "") or "";
    edit_mode: str = params.get("edit_mode", "auto");
    _raw_images = params.get("images");
    images: list = _raw_images if isinstance(_raw_images, list) else [];

    _stop_flags[session_id] = False;
    # Reset per-turn cost accumulator so get_summary() returns this turn's tokens only
    if is_cost_tracking_enabled() {
        _reset_usage();
    }

    # Called by the agent each time it does something (reads a file, calls a tool, etc.)
    # We forward these as chat.event notifications so the UI can show live progress.
    def on_event(event_type: str, data: dict) -> None {
        if _stop_flags.get(session_id) {
            raise KeyboardInterrupt("cancelled");  # unwinds the agent immediately
        }
        _write(_notify("chat.event", {"type": event_type, **data}));
    }

    try {
        result = _api_chat(
            session_id=session_id,
            message=message,
            on_event=on_event,
            agent_context=agent_context,
            images=images,
            edit_mode=edit_mode
        );
        if _stop_flags.get(session_id) {
            partial: dict = {"usage": _get_usage_summary()} if is_cost_tracking_enabled() else {};
            if _try_reply(session_id) {
                _write(_cancelled(req_id, partial));
            }
        } else {
            if is_cost_tracking_enabled() {
                result["usage"] = _get_usage_summary();
            }
            if _try_reply(session_id) {
                _write(_ok(req_id, result));
            }
        }
    } except (KeyboardInterrupt, InterruptedError) {
        partial: dict = {"usage": _get_usage_summary()} if is_cost_tracking_enabled() else {};
        if _try_reply(session_id) {
            _write(_cancelled(req_id, partial));
        }
    } except Exception as e {
        logger.error("chat error: %s", e);
        if _try_reply(session_id) {
            _write(_err(req_id, -32000, str(e)));
        }
    } finally {
        _stop_flags.pop(session_id, None);
        _chat_threads.pop(session_id, None);
        _reply_flags.pop(session_id, None);
    }
}


# ---------------------------------------------------------------------------
# Request dispatcher
#
# Routes each incoming request to the right API call and sends back the result.
# Runs inside the asyncio event loop so Jac graph operations (root, spawn, -->)
# are always available.
# ---------------------------------------------------------------------------

"""Route one JSON-RPC request to the correct API function."""
async def _dispatch(req_id: Any, method: str, params: dict) -> None {
    try {
        if method == "health" {
            _write(_ok(req_id, {"status": "ok", "service": "jac-coder"}));

        } elif method == "session.create" {
            _write(_ok(req_id, _api_create_session(
                directory=params.get("directory", ""),
                title=params.get("title", "New Session")
            )));

        } elif method == "session.list" {
            _write(_ok(req_id, {"sessions": _api_list_sessions()}));

        } elif method == "session.get" {
            _write(_ok(req_id, _api_get_session(session_id=params["session_id"])));

        } elif method == "session.close" {
            _write(_ok(req_id, _api_close_session(session_id=params["session_id"])));

        } elif method == "chat" {
            # Chat runs in a thread — LLM calls are blocking and can take a long time.
            # The thread writes events and the final response directly via _write().
            sid: str = params.get("session_id", "");
            chat_thread = threading.Thread(
                target=_handle_chat,
                args=(req_id, params),
                daemon=True,
                name=f"chat-{sid[:8]}"
            );
            _chat_threads[sid] = chat_thread;
            chat_thread.start();

        } elif method == "mcp.add" {
            _write(_ok(req_id, _api_mcp_add(
                name=params["name"],
                config=params["config"]
            )));

        } elif method == "mcp.disconnect" {
            _write(_ok(req_id, _api_mcp_disconnect(name=params["name"])));

        } elif method == "mcp.reconnect" {
            _write(_ok(req_id, _api_mcp_reconnect(name=params["name"])));

        } elif method == "mcp.delete" {
            _write(_ok(req_id, _api_mcp_delete(name=params["name"])));

        } elif method == "mcp.list" {
            _write(_ok(req_id, {"servers": _api_mcp_list()}));

        } elif method == "api.validate" {
            # Run in a thread — model_call_no_stream is blocking and would freeze
            # the event loop (and all other requests) if called directly here.
            def _do_validate() -> None {
                try {
                    llm.model_call_no_stream({
                        "model": llm.model_name,
                        "messages": [{"role": "user", "content": "hi"}],
                        # Use a small but non-trivial output budget. Some providers/models
                        # can reject ultra-tiny limits during internal reasoning.
                        "max_tokens": 16
                    });
                    _write(_ok(req_id, {"valid": True}));
                } except ByllmAuthError as e {
                        _write(_ok(req_id, {"valid": False, "error": str(e)}));
                } except ByllmRateLimitError {
                    # Rate limit means key is valid — just being throttled
                    _write(_ok(req_id, {"valid": True}));
                } except ByllmModelNotFoundError as e {
                        # Model resolution failure does not prove the API key is invalid.
                        # Treat as a validation warning so key onboarding is not blocked.
                        _write(_ok(req_id, {"valid": True, "warning": str(e)}));
                } except Exception as e {
                        # byllm currently wraps auth/rate/notfound, but many non-auth
                        # provider errors (e.g. BadRequest on max_tokens/model limits)
                        # bubble up as generic Exception. For key validation, only
                        # explicit auth failures should be treated as invalid keys.
                        _write(_ok(req_id, {"valid": True, "warning": str(e)}));
                }
            }
            threading.Thread(target=_do_validate, daemon=True, name="api-validate").start();

        } elif method == "model.get" {
            _write(_ok(req_id, _api_get_model()));

        } elif method == "model.set" {
            _write(_ok(req_id, _api_set_model(model=params["model"])));

        } else {
            _write(_err(req_id, -32601, f"Method not found: {method}"));
        }

    } except KeyError as exc {
        _write(_err(req_id, -32602, f"Missing required param: {exc}"));
    } except BaseException as exc {
        logger.error("dispatch [%s]: %s", method, exc);
        _write(_err(req_id, -32000, str(exc)));
    }
}


# ---------------------------------------------------------------------------
# Main loop
#
# Reads one JSON message per line from stdin.
# - If the message has an "id" → it's a request, dispatch it.
# - If no "id" → it's a notification (currently only chat.cancel).
# - Empty line → EOF → extension closed, exit cleanly.
# ---------------------------------------------------------------------------

"""Read stdin forever and dispatch each incoming message."""
async def _main() -> None {
    loop: asyncio.AbstractEventLoop = asyncio.get_event_loop();

    # Tell the extension we are ready to receive requests.
    _write(_notify("server.ready", {"service": "jac-coder", "version": _get_server_version()}));

    while True {
        try {
            # run_in_executor keeps stdin reading off the async loop
            # so the loop stays free to handle other tasks while waiting.
            line = await loop.run_in_executor(None, sys.stdin.readline);
        } except Exception as e {
            logger.error("stdin read error: %s", e);
            break;
        }

        if not line {
            # Empty string = EOF = extension disconnected. Exit cleanly.
            break;
        }

        line = line.strip();
        if not line {
            continue;  # blank line, skip
        }

        try {
            msg: dict = json.loads(line);
        } except Exception {
            _write(_err(None, -32700, "Invalid JSON"));
            continue;
        }

        method: str = msg.get("method", "");
        params: dict = msg.get("params") or {};
        req_id: Any = msg.get("id");

        if "id" not in msg {
            # Inbound notification (no reply) — chat.cancel and permission.response.
            if method == "chat.cancel" {
                sid: str = params.get("session_id", "");
                if sid {
                    _stop_flags[sid] = True;
                    # If the thread is blocked waiting for a permission decision, unblock it
                    # with a deny so the turn can abort cleanly.
                    perm_gate = _permission_events.get(sid);
                    if perm_gate {
                        _permission_decisions[sid] = "deny";
                        perm_gate.set();
                    }
                    running_thread = _chat_threads.get(sid);
                    if running_thread and running_thread.is_alive() {
                        # Signal the iteration hook for graceful per-step abort.
                        request_abort_thread(running_thread.ident);
                        # Persist an INTERRUPTED note so the LLM knows to actually
                        # execute (not just describe) when the user resumes.
                        _api_abort_session(sid);
                        # Force-stop as a fallback for threads stuck in blocking LLM calls.
                        import ctypes;
                        ctypes.pythonapi.PyThreadState_SetAsyncExc(
                            ctypes.c_ulong(running_thread.ident),
                            ctypes.py_object(KeyboardInterrupt)
                        );
                    }
                }
            }

            if method == "permission.response" {
                sid: str = params.get("session_id", "");
                decision: str = params.get("decision", "deny");
                if sid {
                    _permission_decisions[sid] = decision;
                    perm_gate = _permission_events.get(sid);
                    if perm_gate {
                        perm_gate.set();
                    }
                }
            }
            continue;
        }

        # It's a request — schedule it on the event loop and keep reading.
        asyncio.ensure_future(_dispatch(req_id, method, params));
    }
}


# ---------------------------------------------------------------------------
# Entry point — runs when: jac run server.jac
# ---------------------------------------------------------------------------

with entry {
    # Log warnings and above to stderr (safe — won't touch the JSON channel).
    logging.basicConfig(
        level=logging.WARNING,
        format="[jaccoder] %(levelname)s %(name)s: %(message)s",
        stream=sys.stderr
    );

    # Redirect stdout → stderr so accidental print() calls never corrupt the JSON pipe.
    os.dup2(2, 1);
    sys.stdout = sys.stderr;

    # Boot the Jac agent (loads config, connects LLM, sets up the graph).
    initialize("ide");

    # Start the async event loop — runs forever until stdin closes.
    asyncio.run(_main());
}
