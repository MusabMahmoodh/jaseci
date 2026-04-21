"""JacCoder public API."""

import os;
import sys;

import from datetime { datetime }
import from jac_coder.config { get_config }
import from jac_coder.util.tool_output { tool_end }
import from jac_coder.permission { permission_engine }
import from jac_coder.util.sandbox { set_sandbox_root }
import from jac_coder.context { build_context, ContextConfig }
import from jac_coder.walkers { new_session, ensure_main_agent, _consume_llm_stream }
import from jac_coder.memory {
    find_or_create_memory,
    _init_memory,
    update_memory_from_session
}
import from jac_coder.nodes { Session, MainAgent }
import from jac_coder.events {
    register_event_callback,
    clear_event_callbacks,
    reset_steps,
    start_turn,
    emit_turn_summary,
    emit_event
}


# Thread-safe session registry — graph root is per-request in jac-cloud,
# so background threads can't find sessions via [root-->]. This dict
# is module-level and accessible from any thread.
glob _session_registry: dict = {};

"""Initialize jac-coder."""
def initialize(mode: str = "web") -> None;

"""Create a new session."""
def create_session(directory: str, title: str = "", agent: str = "main") -> dict;

"""Send a message and get a response."""
def chat(
    session_id: str,
    message: str,
    directory: str = "",
    on_event: Any = None,
    mode: str = "full",
    agent_context: str = ""
) -> dict;

def list_sessions() -> list;

def get_session(session_id: str) -> dict;

def close_session(session_id: str) -> dict;
