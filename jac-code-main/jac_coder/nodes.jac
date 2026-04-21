import os;

import from uuid { uuid4 }
import from datetime { datetime }
import from jac_coder.config { llm, get_config, get_data_dir }

# MainAgent tools — full orchestrator set
import from jac_coder.tool.think { think }
import from jac_coder.tool.delegation { spawn_agent }
import from jac_coder.tool.todo { update_todos }
import from jac_coder.tool.jac_docs { jac_docs }
import from jac_coder.tool.question { ask_question }
import from jac_coder.tool.scaffold { scaffold_project }
import from jac_coder.tool.web { web_fetch, web_search }
import from jac_coder.tool.guarded { run_command }
import from jac_coder.tool.jac_tools { jac_check, jac_run }
import from jac_coder.tool.search { grep_search, find_files }
import from jac_coder.tool.filesystem { read_file, list_files }
import from jac_coder.tool.git { git_status, git_diff, git_commit, git_log }
import from jac_coder.tool.checked { write_code, edit_code }
import from jac_coder.tool.jac_analyzer { analyze_project, find_symbol }
import from jac_coder.tool.validate { validate_project }


def load_subagent_rules() -> dict {
    data_dir = get_data_dir();
    rules: dict = {};
    rules_dir = os.path.join(data_dir, "rules");
    for (key, filename) in [
        ("build_rules", "build.md"),
        ("client_rules", "client.md"),
        ("server_rules", "server.md")
    ] {
        filepath = os.path.join(rules_dir, filename);
        try {
            with open(filepath, "r") as f {
                rules[key] = f.read();
            }
        } except (FileNotFoundError, OSError) {
            rules[key] = "";
        }
    }
    toc_lines: list = ["Call jac_docs(query) to look up Jac syntax. Available topics:"];
    for subdir in ["reference", "examples"] {
        search_dir = os.path.join(data_dir, subdir);
        if not os.path.isdir(search_dir) {
            continue;
        }
        for fname in sorted(os.listdir(search_dir)) {
            if not fname.endswith(".md") {
                continue;
            }
            filepath = os.path.join(search_dir, fname);
            try {
                with open(filepath, "r") as f {
                    content = f.read();
                }
                headings = [
                    line.replace("## ", "").strip()
                    for line in content.split("\n")
                    if line.startswith("## ")
                ];
                label = subdir + "/" + fname.replace(".md", "");
                toc_lines.append(f"  {label}: {', '.join(headings)}");
            } except (FileNotFoundError, OSError) { }
        }
    }
    rules["available_docs"] = "\n".join(toc_lines);
    return rules;
}

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
        project_summary: str = "";

    def postinit;
}


# ---------------------------------------------------------------------------
# MainAgent — the orchestrator node
# ---------------------------------------------------------------------------
node MainAgent {
    def respond(message: str, chat_history: list[dict]) -> str by llm(
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
            validate_project,
            scaffold_project,
            # Git — first-class version control
            git_status,
            git_diff,
            git_log,
            git_commit,
            # Web — search and fetch external resources
            web_fetch,
            web_search,
            # Delegate — spawn SubAgent walkers for complex tasks
            spawn_agent,
            # Interact — ask user questions, track todos
            ask_question,
            update_todos
        ],
        incl_info=_subagent_rules,
        max_react_iterations=40,
        temperature=0.2,
        stream=True,
        logging=True
    );
}


# ---------------------------------------------------------------------------
# SubAgent runners — in-process, pre-defined tool sets
# ---------------------------------------------------------------------------
glob _subagent_rules: dict = load_subagent_rules();

obj WorkerRunner {
    def run(task_str: str) -> str by llm(
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
            validate_project,
            scaffold_project,
            git_status,
            git_diff,
            git_commit,
            git_log,
            web_fetch,
            web_search
        ],
        incl_info=_subagent_rules,
        max_react_iterations=30,
        temperature=0.2,
        stream=True,
        logging=True
    );
}

obj ExplorerRunner {
    def run(task_str: str) -> str by llm(
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
        incl_info=_subagent_rules,
        max_react_iterations=30,
        temperature=0.2,
        stream=True,
        logging=True
    );
}
