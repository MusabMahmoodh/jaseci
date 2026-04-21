import sys;
import threading;

import from jac_coder.config { get_config }
import from jac_coder.util.tool_output { tool_status, tool_end }
import from jac_coder.events { track_file, track_error, set_agent_prefix, reset_steps, emit_event }


glob _budget_lock: Any = threading.Lock();
glob _shared_budget: int = 0;
glob _budget_initialized: bool = False;
glob _recent_results: list = [];


def init_budget(total: int = 90) -> None;
def get_remaining_budget() -> int;
def consume_budget(used: int) -> None;
def get_recent_results_summary() -> str;
def get_project_summary_for_subagent() -> str;


"""Spawn a SubAgent for a task."""
def spawn_agent(task: str, mode: str = "worker") -> str;

sem spawn_agent = "Delegate a task to a focused SubAgent. mode='worker' for code changes (read+write), 'explorer' for investigation (read-only). Write a detailed instruction string including file paths, patterns to follow, and what success looks like.";
sem spawn_agent.task = "Detailed instruction for the SubAgent — include file paths, context, and success criteria";
sem spawn_agent.mode = "Capability scope: 'worker' (can modify files) or 'explorer' (read-only)";
