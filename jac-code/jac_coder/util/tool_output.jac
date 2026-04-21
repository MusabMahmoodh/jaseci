import os;
import re;
import sys;
import time;
import threading;

import from jac_coder.util.colors { DIM, CYAN, RESET }
import from jac_coder.util.sandbox { get_sandbox_root }
import from jac_coder.runtime.events {
    emit_event,
    next_step,
    get_active_tool,
    set_active_tool,
    track_file,
    track_error,
    get_agent_prefix
}

glob MAX_LINES: int = 2000;
glob MAX_CHARS: int = 25000;      # send limit — above this, persist to disk + smart preview

# Thread-local storage — one tool name per session thread (safe for concurrent sessions)
glob _tl_tool = threading.local();

# File-based tools: source already on disk, never persist to tool-results
glob FILE_TOOLS: list = ["read"];

# Per-tool smart preview sizes: (head_lines, tail_lines)
# Only applies to ephemeral tools (Tier 3)
glob PREVIEW_SIZES: dict = {
    "grep": (100, 0),
    "web_fetch": (50, 10),
    "web_search": (50, 10),
    "jac_docs": (50, 10),
    "bash": (25, 25),
    "jac_run": (25, 25),
    "jac_check": (25, 25)
};

def tool_status(tool_name: str, detail: str = "") -> None;
def tool_end(result_preview: str = "", error: bool = False) -> None;
def smart_path(path: str) -> str;
def note_tool(name: str) -> None;
def persist_result(tool_name: str, text: str) -> str;

def truncate_output(
    text: str, max_lines: int = MAX_LINES, max_chars: int = MAX_CHARS
) -> tuple;
