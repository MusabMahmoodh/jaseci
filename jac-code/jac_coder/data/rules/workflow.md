# Coding Workflow & Validation Discipline

> Follow this workflow EVERY TIME you write Jac code. No shortcuts.
> For fullstack apps: Steps 1-5 are ALL MANDATORY. You are NOT done until browser testing passes.

---

## Creating a New Project

Use the `jac create` CLI command to scaffold new projects — do NOT create `jac.toml` and project files manually:

```bash
# Backend-only project (no frontend)
jac create project_name

# Fullstack project (backend + frontend with Vite/Tailwind)
jac create project_name --use client
```

`--use client` adds the frontend toolchain: Vite dev server, Tailwind CSS, `.cl.jac` component support, and the correct `jac.toml` configuration.

After creating, `cd` into the project directory before writing code.

---

## Before Writing Code

1. **Read `jac.toml`** — check npm deps, project config, entry point.
2. **Call `jac_docs(query)`** — look up syntax for what you're building. Do NOT guess.
3. **If existing project**: call `analyze_project(directory)` to understand structure.
4. **Call `jac_docs` again** before EACH new file type (`.jac` vs `.cl.jac` have different syntax).

---

## Build Order (fullstack apps)

1. Backend services — `services/*.sv.jac` files (nodes + endpoints)
2. Entry point — `main.jac` imports from services/ + `cl { def:pub app() }`
3. **Styles — `styles/global.css`** (MANDATORY — write BEFORE components)
   - `@import "tailwindcss";` as the first line
   - `@theme { }` block with design tokens: `--color-*`, `--font-*`, `--shadow-*`
   - Optional: Google Fonts `@import url(...)` for custom typography
   - Dark mode: `.dark { }` block overriding color tokens
   - Base: `html, body, #root { min-height: 100vh; }`, body bg, font smoothing
4. Hooks — `hooks/useX.cl.jac` (sv import from services/)
5. Leaf components — `Header.cl.jac`, `ItemCard.cl.jac` (no data logic)
   - Use Tailwind utility classes: spacing, colors, typography, shadows, rounded corners
   - Add hover/focus states for interactive elements
6. Container components — `ItemList.cl.jac` (calls hooks, renders leaf components)
7. Layout — `Layout.cl.jac` LAST (imports child components)

**Endpoints must be imported in TWO places:**
- `main.jac` - `import from services.products { get_products }` (registers with server)
- `hooks/*.cl.jac` — `sv import from ..services.products { get_products }` (calls from frontend)

**Build dependencies bottom-up.** Never import a file that doesn't exist yet.
**An unstyled app is not done.** Always write `global.css` and use Tailwind classes in components.

---

## While Writing Code

- Use `write_code` / `edit_code` — they auto-run `jac_check` per file for syntax errors.
- Do NOT call `jac_check` or `jac check` manually.
- Do NOT use `run_command` for jac check.
- If `write_code`/`edit_code` report errors → call `jac_docs(query)` to look up correct syntax → fix → retry.
- Call `jac_docs` at least once every 3-4 tool calls. If unsure about ANY syntax, look it up immediately.
- Use ABSOLUTE file paths for all operations.

---

## Cross-file import check

Before starting the server, manually verify:
- Every `import from "..."` / `sv import from ...` references a file that exists
- sv import function names match actual `def:pub` names in `main.jac`
- Component imports use correct dot-levels (`.` same dir, `..` one up, `...` two up)
- No duplicate component names or endpoint names across files

## Starting the app server

Start the application server using `run_command` with `background=True`:
- **Fullstack:** `run_command("jac start --dev main.jac", background=True)`
- **Backend only:** `run_command("jac start main.jac", background=True)`
- **Single script:** `jac run main.jac` — one-off execution (no server)

CRITICAL: `jac start` is a LONG-RUNNING server process — ALWAYS use `background=True`.
It will block forever if run in foreground. ALWAYS use `jac start`, NEVER `jac serve`.

## Checking server readiness

After starting:
1. Check readiness with retry: `run_command("for i in 1 2 3 4 5; do curl -s http://localhost:<port>/ > /dev/null && echo UP && break || sleep 2; done")`
2. If DOWN, read `.jac-server.log` in the project dir for startup errors.
3. Then proceed with browser validation.

The port depends on project config — check `jac.toml` for the actual port.
The frontend is served at the ROOT `/` (e.g. `http://localhost:8001`). Do NOT append `/app` — just use the port directly.
NEVER read `/proc/PID/fd/` — it blocks forever. Use `.jac-server.log` or curl instead.

## Browser validation — primary validation method

Use `browser_validate(url)` as the primary validation for fullstack apps:

1. `browser_validate(url)` — opens the app, checks console errors, verifies page rendered (not blank), returns PASS/FAIL + snapshot.
2. If FAIL → read the errors, fix code, restart server, `browser_validate()` again.
3. If PASS → interactive testing with `browser_do()` to click, fill forms, verify behavior.
4. `browser_close()` — close when done.

Do NOT use `validate_project()` as a gate. `jac check` type errors often don't affect runtime — the browser is the source of truth.

## Auth-gated apps — validate /login first, not /

If the app uses `AuthGuard` or `def:priv` endpoints, the root `/` will be BLANK for unauthenticated users. This is EXPECTED behavior, not a bug.

For auth apps:
1. `browser_validate(url + "/login")` first — verify the login page renders
2. If `/login` renders → the app works. The blank `/` is just the auth redirect.
3. To test protected pages: `browser_do('fill ...')` to login first, then navigate to `/home`
4. NEVER spend iterations "fixing" a blank `/` on an auth app — check `/login` or `/signup` instead.

## Fixing browser validation failures

If browser validation reveals problems — FIX THEM.
Do NOT stop and report to the user. Investigate, fix the code, restart the server, and re-validate.
Only stop after 3+ failed fix attempts on the same issue.

**IMPORTANT:** If `/` is blank but `/login` renders → this is auth working correctly, NOT a bug. Do not enter a fix loop.

Common runtime issues and how to fix them:
  - Blank page at `/` with auth app → check `/login` first. If login renders, auth is working.
  - Blank page at `/` without auth → check console errors, fix entry point or imports
  - Buttons that don't respond → event handler or sv import mismatch, fix the handler
  - Missing content → data not loading, wrong endpoint name, fix the API call
  - Broken layout → CSS/component rendering issues, fix the styles
  - Form submission failures → request body schema mismatch (422), fix the request format

---

## When Stuck — Systematic Debugging (Bisect Strategy)

If you hit a vague error with no clear source file, OR the same error persists after 2 fix attempts:

### Quick checks first
1. `jac_docs(query)` — look up the correct syntax for the pattern you're using
2. `analyze_project` or `find_symbol` — check existing patterns in the codebase
3. Read `.jac-server.log` — check for server-side errors not visible in browser

### If quick checks don't solve it → BISECT

**Step 1: Strip Layout to skeleton**
- Edit `Layout.cl.jac` — replace ALL child components with plain `<div>` placeholders
  (e.g. `<div>Header placeholder</div>` instead of `<Header />`)
- Keep only the outer layout shell
- `browser_validate` → this MUST pass. If not, bug is in Layout itself or `main.jac`

**Step 2: Add components back one-by-one**
- Restore ONE component at a time, `browser_validate` after each:
  1. Add `<Header />` → validate → PASS? next. FAIL? Header is broken.
  2. Add next component → validate → PASS? next. FAIL? This one is broken.
- This finds the broken component in at most N validate calls.

**Step 3: Fix the broken component in isolation**
- Read the broken component's source file
- `jac_docs` for the specific pattern it uses
- Rewrite it as MINIMAL (static text only) → validate it works
- Add features back one at a time (data fetch → rendering → interactivity)
- Validate after EACH addition

### Rules
- Do NOT guess which component is broken — PROVE it with the bisect
- Do NOT rewrite multiple files at once hoping it fixes things
- Do NOT retry the same fix more than twice — if it failed twice, BISECT
- After 3 failed bisect iterations on the same component → `ask_question` to ask the user

---

## HMR "module not found" Fix

1. File exists but compiled JS is stale
2. Do trivial edit on the TARGET file (not the importing file) — add a blank line
3. HMR recompiles, import resolves
