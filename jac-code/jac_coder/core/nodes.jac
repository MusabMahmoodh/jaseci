import os;
import sys;

import from uuid { uuid4 }
import from datetime { datetime }
import from byllm.types { IterationAction, IterationContext }
import from jac_coder.infra.config { llm, get_config }
import from jac_coder.runtime.events { is_abort_requested }

# MainAgent tools — full orchestrator set
import from jac_coder.tool.meta.think { think }
import from jac_coder.tool.meta.delegation { spawn_agent }
import from jac_coder.tool.meta.todo { update_todos }
import from jac_coder.tool.read.jac_docs { jac_docs }
import from jac_coder.tool.meta.question { ask_question }
import from jac_coder.tool.write.scaffold { scaffold_project }
import from jac_coder.tool.net.web { web_fetch, web_search }
import from jac_coder.tool.run.guarded { run_command }
import from jac_coder.tool.run.jac_tools { jac_check, jac_run }
import from jac_coder.tool.read.search { grep_search, find_files }
import from jac_coder.tool.read.filesystem { read_file, list_files }
import from jac_coder.tool.git { git_status, git_diff, git_commit, git_log }
import from jac_coder.tool.write.checked { write_code, edit_code }
import from jac_coder.tool.read.jac_analyzer { analyze_project, find_symbol }
import from jac_coder.tool.net.preview { browser_open, browser_do, browser_state, browser_close, browser_validate }
import from jac_coder.tool.mcp { mcp_call }
import from byllm.lib { Image }



# ---------------------------------------------------------------------------
# Response objects
# ---------------------------------------------------------------------------
obj AgentResponse {
    has content: str;
    has agent_mode: str;
    has tools_used: list[str];
    has files_modified: list[str];
    has has_errors: bool;
    has next_steps: list[str];
}

sem AgentResponse.content = "Main response text to display to user";
sem AgentResponse.agent_mode = "Always 'main' for MainAgent responses";
sem AgentResponse.tools_used = "List of tool names that were called during execution";
sem AgentResponse.files_modified = "List of file paths that were written or edited";
sem AgentResponse.has_errors = "TRUE if any tool execution failed, FALSE otherwise";
sem AgentResponse.next_steps = "Suggested follow-up actions for the user (empty list if none)";


obj SubAgentResult {
    has content: str;
    has files_modified: list[str];
    has errors: list[str];
    has tools_used: list[str];
    has iterations_used: int;
}

sem SubAgentResult.content = "The SubAgent's response to the task";
sem SubAgentResult.files_modified = "Files written or edited during execution";
sem SubAgentResult.errors = "Errors encountered (jac_check failures, tool errors)";
sem SubAgentResult.tools_used = "Tools called during execution";
sem SubAgentResult.iterations_used = "Number of ReAct iterations consumed";


obj ProjectScan {
    has architecture: str;
    has file_map: dict[str, str];
    has conventions: list[str];
}


obj SessionLearnings {
    has new_files: dict[str, str];
    has new_conventions: list[str];
    has new_decisions: list[str];
    has known_issues: list[str];
}


# ---------------------------------------------------------------------------
# McpRegistry — persists MCP server configs in the graph
# ---------------------------------------------------------------------------
node McpRegistry {
    has servers: dict[str, dict] = {};
}


# ---------------------------------------------------------------------------
# ProjectMemory — persists codebase knowledge across sessions
# ---------------------------------------------------------------------------
node ProjectMemory {
    has project_dir: str = "",
        architecture: str = "",
        file_map: dict[str, str] = {},
        conventions: list[str] = [],
        past_decisions: list[str] = [],
        known_issues: list[str] = [],
        graph_topology: str = "",
        node_details: str = "",
        walker_details: str = "",
        import_map: str = "",
        scan_attempted: bool = False,
        last_updated: str = "";

    def profile_project(file_tree: str, key_files: str) -> ProjectScan by llm(
        temperature=0.1
    );

    def collect_learnings(
        files_modified: list[str], session_summary: str
    ) -> SessionLearnings by llm(temperature=0.1);

    def summarize() -> str;
}


# ---------------------------------------------------------------------------
# Session — persistent chat state
# ---------------------------------------------------------------------------
node Session {
    has id: str = "",
        title: str = "New Session",
        directory: str = "",
        agent: str = "main",
        status: str = "active",
        created_at: str = "",
        updated_at: str = "",
        chat_history: list[dict] = [],
        last_agent: str = "",
        active_files: list[str] = [],
        pending_errors: list[str] = [],
        project_summary: str = "",
        last_mode_hint: str = "";

    def postinit;
}


# ---------------------------------------------------------------------------
# MainAgent — the orchestrator node
# ---------------------------------------------------------------------------
node MainAgent {
    def respond(message: str, chat_history: list[dict], user_image: Image | None = None) -> str by llm(
        tools=[
            # Think — explicit reasoning before acting or delegating
            think,
            # Understand — read, search, analyze the codebase
            read_file,
            grep_search,
            find_files,
            list_files,
            analyze_project,
            find_symbol,
            jac_docs,
            # Act — handle simple tasks directly
            edit_code,
            write_code,
            run_command,
            jac_run,
            scaffold_project,
            # Git — first-class version control
            git_status,
            git_diff,
            git_log,
            git_commit,
            # Web — search and fetch external resources
            web_fetch,
            web_search,
            # Browser — interactive testing via agent-browser
            browser_validate,
            browser_open,
            browser_do,
            browser_state,
            browser_close,
            # Delegate — spawn SubAgent walkers for complex tasks
            spawn_agent,
            # Interact — ask user questions, track todos
            ask_question,
            update_todos,
            # MCP — call tools from connected MCP servers
            mcp_call
        ],
        on_iteration=_iteration_hook,
        max_react_iterations=80,
        temperature=0.2,
        max_tokens=8192,
        stream=True,
        logging=True
    );
}


# ---------------------------------------------------------------------------
# SubAgent walkers — spawned on MainAgent node for task delegation
# ---------------------------------------------------------------------------

"""on_iteration callback — checks abort flag between ReAct iterations."""
def _iteration_hook(ctx: IterationContext) -> IterationAction {
    if is_abort_requested() {
        return IterationAction.ABORT;
    }
    return IterationAction.CONTINUE;
}


walker WorkerAgent {
    has task: str;
    has result_content: str = "";
    has result_tools: list[str] = [];
    has result_files: list[str] = [];

    def do_work(task_str: str) -> str by llm(
        tools=[
            jac_docs,
            analyze_project,
            find_symbol,
            read_file,
            list_files,
            grep_search,
            find_files,
            write_code,
            edit_code,
            run_command,
            jac_run,
            scaffold_project,
            git_status,
            git_diff,
            git_commit,
            git_log,
            web_fetch,
            web_search,
            browser_open,
            browser_do,
            browser_state,
            browser_close,
            browser_validate,
            mcp_call
        ],
        on_iteration=_iteration_hook,
        max_react_iterations=60,
        temperature=0.2,
        max_tokens=8192,
        stream=True,
        logging=True
    );
    can execute with MainAgent entry;
}

walker ExplorerAgent {
    has task: str;
    has result_content: str = "";
    has result_tools: list[str] = [];
    has result_files: list[str] = [];

    def do_work(task_str: str) -> str by llm(
        tools=[
            jac_docs,
            analyze_project,
            find_symbol,
            read_file,
            list_files,
            grep_search,
            find_files,
            git_log,
            web_search,
            web_fetch
        ],
        on_iteration=_iteration_hook,
        max_react_iterations=30,
        temperature=0.2,
        max_tokens=8192,
        stream=True,
        logging=True
    );
    can execute with MainAgent entry;
}
