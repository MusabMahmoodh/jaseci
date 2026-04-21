"""Mode-aware dynamic prompt assembly for JacCoder.

The MainAgent's system prompt is split into a core (always injected via sem
annotation) and workflow modules (conditionally injected as system messages
based on what the agent was doing last turn).

Signal chain per turn:
  1. Filesystem state     (100% reliable — is there a project?)
  2. Previous mode_hint   (100% reliable — what was the agent doing?)
  3. Current message scan  (override only — is the user shifting intent?)
"""

import os;


# ---------------------------------------------------------------------------
# Mode hint constants — stored as strings for graph persistence safety
# ---------------------------------------------------------------------------
glob MODE_BUILDING: str = "building";
glob MODE_DEBUGGING: str = "debugging";
glob MODE_ANSWERING: str = "answering";
glob MODE_EXPLORING: str = "exploring";
glob MODE_GIT_OPS: str = "git_ops";


# ---------------------------------------------------------------------------
# Prompt modules — injected conditionally as system messages
# ---------------------------------------------------------------------------

glob SEM_BUILD_WORKFLOW: str = """## New Projects
`jac create name` (backend) or `jac create name --use client` (fullstack). Use absolute paths.

## Iteration Budget
You have limited iterations. Prioritize a WORKING app over a perfect one:
- Build breadth-first: get ALL files written and the app running before polishing any single file.
- If a component has errors after 2 fix attempts, write a minimal working version and move on.
- Target: app starts and renders by iteration ~50. Remaining iterations for testing and fixes.
- Never spend 10+ iterations debugging one file while the rest of the app is unbuilt.

## Build Workflow
1. jac_docs('fullstack setup') — look up syntax AND jac.toml Tailwind wiring.
2. Create .jaccoder/progress.md with plan.
3. Backend services (.sv.jac) + main.jac.
4. Verify jac.toml has `[plugins.client.vite]` with tailwindcss. Run `jac install` after toml changes.
5. styles/global.css (see Styling). In main.jac: `cl import ".styles.global.css";` (dot-path).
6. Frontend hooks + components (.cl.jac) with Tailwind.
7. `run_command("jac start --dev main.jac", background=True)`.
8. browser_validate(url) → PASS/FAIL. Follow FAIL action instructions.
9. If PASS → one interactive test (browser_do + browser_state), then browser_close.
10. Update progress.md Status: DONE.

## Starting Apps
- Fullstack: `run_command("jac start --dev main.jac", background=True)`
- Backend: `run_command("jac start main.jac", background=True)`
- Script: `jac_run(file_path)`
- jac start is long-running — ALWAYS background=True. Check readiness with curl retry loop.
- Frontend at root `/` (e.g. http://localhost:8001). Logs in .jac-server.log.
- Never read /proc/PID/fd/ (blocks forever). Never use `jac serve`.""";


glob SEM_STYLING: str = """## Styling (mandatory)
Write `styles/global.css` BEFORE components:
- `@import "tailwindcss";` first, then `@theme {}` (colors, fonts, shadows), `.dark {}` overrides, base styles (min-height 100vh).
- Components: Tailwind utility classes in className. Proper spacing, typography, hover/focus states, responsive layout.
- Unstyled app = bug. Call `jac_docs('frontend styling tailwind')` if unsure.""";


glob SEM_BROWSER_TESTING: str = """## Browser Testing
Fix problems yourself — never stop to report them. Follow browser_validate's escalating ACTION instructions exactly:
- 1st FAIL: read source, fix. 2nd: warning. 3rd+: mandatory bisect (skeleton → add components back).
- Auth-gated blank page: tool auto-detects, follow its instructions.

## After PASS
PASS = page renders, NOT that it works. You must:
1. Screenshot to confirm UI looks correct.
2. Test the primary feature (one action + verify state changed via screenshot).
3. If action fails → code bug. Fix, restart, retest. Never retry same action twice.
4. After 2 failed interactive tests → close browser, report status, move on.

SKELETON/PLACEHOLDER PASS is not done — restore all components.""";


glob SEM_PROGRESS_TEMPLATE: str = """## Progress Tracking
Create `.jaccoder/progress.md` at the START of any multi-file task. Update after each major step.
If it already exists, READ IT FIRST — it has context from previous sessions.

Structure (keep under 3000 chars):
```markdown
# Project: <name>
## Status: IN PROGRESS | DONE
## Plan
1. [x] Done step
2. [ ] Next step
## Files
- path/file.jac — description
## Issues
- Errors and fixes
## Learnings
- Syntax/import/runtime discoveries
## Last Action
What was done, what's next.
```
Record errors in Issues and pattern discoveries in Learnings — prevents repeating mistakes.""";


# ---------------------------------------------------------------------------
# Module map — which modules each mode needs
# ---------------------------------------------------------------------------
glob _MODULE_MAP: dict = {
    "building":  [SEM_BUILD_WORKFLOW, SEM_STYLING],
    "debugging": [SEM_BUILD_WORKFLOW, SEM_BROWSER_TESTING],
    "answering": [],
    "exploring": [],
    "git_ops":   []
};

# Tools that indicate each mode (ground truth from previous turn)
glob _BUILD_TOOLS: set = {"write_code", "edit_code", "scaffold_project", "spawn_agent"};
glob _DEBUG_TOOLS: set = {"jac_check", "jac_run", "browser_validate", "browser_open"};
glob _GIT_TOOLS: set = {"git_status", "git_diff", "git_log", "git_commit"};
glob _READ_TOOLS: set = {"read_file", "grep_search", "find_files", "analyze_project", "find_symbol"};
glob _BROWSER_TOOLS: set = {"browser_open", "browser_validate", "browser_do", "browser_state"};

# Keywords that signal a build intent (used only at intent-shift boundaries)
glob _BUILD_PHRASES: list = [
    "build", "create", "implement", "make me", "scaffold",
    "write a", "add a", "set up", "let's build", "now build",
    "go ahead", "start building", "make a"
];


# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

"""Infer mode hint from what the agent actually did (ground truth)."""
def infer_mode_hint(tools_used: list[str], files_modified: list[str]) -> str;

"""Assemble workflow prompt modules for the current turn."""
def select_prompt_modules(
    last_mode_hint: str,
    message: str,
    directory: str,
    chat_history: list[dict]
) -> str;
