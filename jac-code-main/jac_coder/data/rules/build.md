# Jac Coding Rules — Quick Reference

> RULE: Call `jac_docs(query)` before EACH file. Don't guess syntax — look it up.

---

## 0. BEFORE WRITING ANY CODE

**Read `jac.toml` FIRST before writing ANY code.** Only use npm packages listed in `[dependencies.npm]`. Do NOT import libraries that aren't in jac.toml — they won't be installed and the build will crash.
- ALWAYS read jac.toml to check `[dependencies.npm]` before importing any npm package
- If the package is NOT listed → do NOT use it. Use plain HTML/CSS instead
- Do NOT add packages to jac.toml yourself — ask the user first
- NEVER assume @shadcn/ui, @radix-ui, @headlessui, @hugeicons, or any UI library is available
- NEVER import icon libraries (lucide-react, @hugeicons, react-icons, heroicons, etc.) — use plain text, emoji, or inline SVG instead
- Use plain Tailwind CSS classes for styling instead of UI component libraries

---

## 1. WHEN WRITING .cl.jac (Frontend Components)

### Syntax — Jac, NOT JavaScript
```
WRONG (JS)                          →  CORRECT (Jac)
──────────────────────────────────────────────────────
const x = 5;                        →  x = 5;
let items = [];                     →  has items: list = [];
x ? a : b                           →  a if x else b
() => { ... }                       →  def handle_click() -> None { ... }
`hello ${name}`                     →  f"hello {name}"
x === y                             →  x == y
console.log(x)                      →  print(x)
x.length                            →  len(x)
parseInt(x)                         →  int(x)
x.toString()                        →  str(x)
new Date()                          →  Reflect.construct(Date, [])
items.map(lambda ...)               →  {[<Item /> for item in items]}
items.filter(...)                   →  [i for i in items if condition]
items.push(x) / items.concat([x])   →  items = items + [x];
useEffect(() => {}, [])             →  can with entry { ... }
useState(0)                         →  has count: int = 0;
throw new Error()                   →  raise Exception()
catch (e) { }                       →  except Exception as e { }
for i, k in dict.items()            →  for (i, k) in dict.items()
for p: Type in items                 →  for p in items  (NO type annotation on loop var)
x, y = func()                       →  (x, y) = func()
return a, b                         →  return (a, b)
d.get("key", default) (in .cl.jac)  →  d["key"] if "key" in d else default
type(x) == dict (in .cl.jac)       →  "key" in x  (just guard access directly)
!condition (in .cl.jac)            →  not condition  (Jac uses 'not', not '!')
window.open(url) (in .cl.jac)      →  globalThis.open(url, "_blank")
pass;                               →  NOT valid — use _unused = 0; or just {}
```

### Functions MUST be defined BEFORE `return`
```jac
# WRONG — helper defined after return (unreachable)
return <div>{render_item(data)}</div>;
def render_item(d: dict) -> JsxElement { ... }

# CORRECT — define helpers ABOVE the return
def render_item(d: dict) -> JsxElement { ... }
return <div>{render_item(data)}</div>;
```

### Event Handlers — NEVER inline functions in JSX
```jac
# WRONG — lambda
<button onClick={lambda -> None { count = count + 1; }}>

# WRONG — inline def (this is NOT valid Jac)
<button onClick={def(e: any) -> None { count = count + 1; }}>

# CORRECT — named function ABOVE the return, passed by name
def handle_click() -> None {
    count = count + 1;
}
return <button onClick={handle_click}>Click</button>;

# For handlers that need arguments, define a wrapper:
def handle_delete_item(id: str) -> None {
    items = [i for i in items if i["id"] != id];
}
return <button onClick={handle_delete_item}>Delete</button>;
```
RULE: ALL event handlers must be named `def` functions defined BEFORE the return statement. NEVER put `lambda` or `def(...)` inside JSX attributes.

### Comments — ABOVE logic, NEVER inside JSX
```jac
# CORRECT — comments above logic blocks
def:pub TodoList() -> JsxElement {
    data = useTodos();
    items = data["items"] or [];

    # Filter active items
    active = [i for i in items if not i["done"]];

    # Handle submission
    has input_value: str = "";
    def handle_add() -> None {
        if input_value { add_todo(input_value); input_value = ""; }
    }

    # Render list
    return <div class="space-y-4">...</div>;
}

# WRONG — comments inside JSX break rendering
return (
    <div>
        {# comment}          ← CRASH
        <!-- HTML comment --> ← CRASH
        {/* JS comment */}   ← CRASH
    </div>
);
```
RULE: Add `#` comments ABOVE each logical section (state, handlers, effects, render). NEVER put comments inside JSX return blocks.

### State — `has` auto-generates useState
```jac
has count: int = 0;        # auto-creates count + setCount
has name: str = "";        # auto-creates name + setName
has items: list = [];      # auto-creates items + setItems

# NEVER define setX yourself — it already exists from has
count = count + 1;         # this calls setCount internally
items = items + [newItem]; # this calls setItems (new reference = re-render)
```

### Effects — `can with entry/exit`
```jac
can with entry { ... }                  # mount (replaces useEffect(fn, []))
async can with entry { ... }           # async mount
can with [dep1, dep2] entry { ... }    # dependency (replaces useEffect(fn, [dep]))
can with exit { ... }                   # cleanup/unmount
```

### List Rendering — comprehension
```jac
{[<TodoItem key={item["id"]} data={item} /> for item in items]}
{[<Tag key={t} label={t} /> for t in tags if t != "hidden"]}
```

### sv import Calls — POSITIONAL ARGS ONLY (CRITICAL)
```jac
# In .cl.jac, kwargs compile to a SINGLE dict arg — server gets wrong data
# WRONG — kwargs: calc(a=2, b=4, op="add") → server receives {"a": {"a":2, "b":4, "op":"add"}}
resp = await calc(a=a_val, b=b_val, op=op);

# CORRECT — positional: calc(2, 4, "add") → server receives {"a":2, "b":4, "op":"add"}
resp = await calc(a_val, b_val, op);
```
This applies to ALL sv import function calls in .cl.jac. ALWAYS use positional arguments.
The parameter ORDER must match the def:pub signature in main.jac exactly.

### JS Built-ins — Reflect.construct (CRITICAL)
```jac
# .cl.jac ONLY — server .jac files use Python calls directly
year = Reflect.construct(Date, []).getFullYear();
ws = Reflect.construct(WebSocket, ["ws://localhost:8000/ws"]);
# Safe statics (no Reflect needed): Date.now(), JSON.parse(), Math.random()
```

### Imports in .cl.jac — DOT LEVEL CHEAT SHEET
```
.   = same directory          import from ".Header" { Header }
..  = 1 level up (parent)     import from "..hooks.useTodos" { useTodos }
... = 2 levels up             import from "...lib.utils" { cn }

Example project:
  components/Layout.cl.jac    → imports ".Header" (same dir)
  components/TodoList.cl.jac  → imports "..hooks.useTodos" (up to root, into hooks/)
  pages/index.jac             → imports "..components.TodoList" (up to root, into components/)
```

```jac
# Client-to-client (other .cl.jac files) — WITH quotes, DOTS not slashes
import from ".Header" { Header }
import from "..hooks.useTodos" { useTodos }
import from "...lib.utils" { cn }

# Server calls — sv import, NO quotes, DOTS only
sv import from ..main { get_todos, add_todo }

# npm packages — WITH quotes
import from "clsx" { cn }

# Runtime — cl import, WITH quotes
cl import from "@jac/runtime" { jacLogin, Outlet }

# NEVER: cl sv import, "..main" with quotes, slashes in paths
```

### Defensive Coding — ALWAYS guard everything (CRITICAL)

Jac compiles to JS on the client. Undefined access CRASHES the whole app.
ALWAYS code defensively — assume any value can be undefined/None/empty.

```jac
# 1. ALWAYS init state with correct types — NEVER None or any
has items: list = [];          # NOT: has items: any = None
has user: dict = {};           # NOT: has user = None
has loading: bool = True;      # NOT: has loading = None
has error: str = "";           # NOT: has error = None

# 2. ALWAYS guard sv import responses — backend can return anything
async def handle_add(name: str) -> None {
    try {
        result = await add_item(name);    # positional args only
        if result and "error" not in result {
            items = items + [result];
        }
    } except Exception as e {
        error = str(e);
    }
}

# 3. ALWAYS guard dict access — use "key" in dict, not .get()
name = item["name"] if "name" in item else "";
tags = item["tags"] if "tags" in item else [];

# 4. ALWAYS guard list rendering — check length first
{len(items) > 0 and ([<Item key={item["id"]} data={item} /> for item in items])}

# 5. ALWAYS wrap async calls in try/except
async can with entry {
    try {
        result = await get_items();
        items = result or [];
    } except Exception as e {
        error = str(e);
    }
    loading = False;
}

# 6. ALWAYS display non-string values with str()
<span>{str(count)}</span>
<p>{str(item["price"])}</p>

# 7. ALWAYS guard props — assume they can be missing
items = props.items or [];
title = props.title or "";
on_click = props.on_click or (def noop() -> None {});
```

**RULE: If in doubt, guard it. An extra `or []` or `try/except` is cheap. A crash is not.**

### Component Return Types
```jac
def Layout() -> JsxElement { ... }     # component
def useTodos() -> dict { ... }         # hook
def handle_click() -> None { ... }     # handler
```

### Browser Global Names — NEVER shadow these
`open`, `close`, `fetch`, `focus`, `blur`, `scroll`, `alert`, `confirm`, `prompt`, `print`, `stop`, `find`
→ Use `handleOpen`, `handleClose`, `handleFetch`, etc.

---

## CRITICAL Jac Syntax Rules (applies to ALL .jac files)

### `self` is implicit — NEVER include as parameter
```jac
# WRONG
obj Foo {
    def get_x(self) -> int { return self.x; }
}

# CORRECT — self available in body, not in params
obj Foo {
    has x: int = 0;
    def get_x() -> int { return self.x; }
}
```

### `can` vs `def` — `can` ONLY with `with` clause
```jac
# WRONG — can without with clause
obj Foo {
    can do_stuff() -> None { ... }
}

# CORRECT — def for regular methods
obj Foo {
    def do_stuff() -> None { ... }
}

# CORRECT — can ONLY for walker/node event-driven abilities
walker MyWalker {
    can process with MyNode entry {
        visit [-->];
    }
}
```

### `glob` for module-level variables
```jac
glob MAX_SIZE: int = 100;
glob config: dict = {};
```

### `def init` not `__init__`, and call `super.init()`
```jac
obj Foo {
    has x: int;
    def init(x: int) {
        super.init();
        self.x = x;
    }
}
```

### Backtick escaping for keywords as identifiers
```jac
has `type: str;      # "type" is a keyword — backtick escapes it
`edge = 5;           # "edge" is a keyword

# These do NOT need backtick: self, super, root, here, visitor, init, postinit
```

### `import:py` is DEPRECATED — never use it
```jac
# WRONG
import:py from os { path }

# CORRECT
import from os { path }
```

### match/case uses colon, not braces
```jac
match op {
    case "add":
        result = a + b;
    case "sub":
        result = a - b;
    case _:
        result = 0;
}
```

---

## 2. WHEN WRITING .jac (Backend)

### Project Structure
```
project-root/
├── jac.toml            # config + deps
├── main.jac            # ALL backend code here
├── components/         # .cl.jac UI components — each in its own file
│   ├── Layout.cl.jac   # Root layout — imports Header + child components
│   ├── Header.cl.jac   # Nav/header bar
│   ├── ItemList.cl.jac # List + add form (calls hook, renders ItemCard)
│   └── ItemCard.cl.jac # Single item display
├── hooks/              # .cl.jac data hooks (sv import + state)
│   └── useItems.cl.jac # sv import from ..main, state management
├── pages/              # .jac file-based routing
├── lib/                # .cl.jac shared utilities
│   └── utils.cl.jac    # cn() utility
└── styles/             # CSS files
```

**RULE: Layout.cl.jac is the root layout.** It imports Header + child components and renders them in a shell. All data logic lives in hooks/, called by child components — NOT by Layout.cl.jac.

### All Backend in main.jac
```jac
# Nodes — data models
node Todo {
    has title: str;
    has done: bool = False;
}

# Public endpoints — shared root
def:pub get_todos() -> list {
    return [{"id": str(t.id), "title": t.title, "done": t.done}
            for t in [root-->][?:Todo]];
}

# Private endpoints — per-user root (requires auth)
def:priv get_my_todos() -> list { ... }

# Walker endpoints — for complex graph operations
walker:pub search_todos {
    has query: str;
    can search with Root entry { report {"results": [...]}; }
}

# App entry — serves the frontend (Layout.cl.jac is the root layout)
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement { return <Layout />; }
}

# Layout.cl.jac imports Header + child components (e.g. TodoList)
# TodoList calls useTodos() hook which does sv import from ..main
# Each component is in its own file — NO monolithic Layout.cl.jac
```

### Node Persistence
```jac
root ++> Todo(title="Buy milk");              # create + connect to root
todos = [root-->][?:Todo];                   # query all Todos from root
todo = [root-->][?:Todo](?title == "Buy milk")[0]; # query with filter
del todo;                                      # delete
```

### Import Prefixes — NEVER combine
```jac
# In .jac files — client imports use cl import (no quotes)
cl import from .components.Layout { Layout }

# In .cl.jac files — backend calls use sv import (no quotes)
sv import from ..main { get_todos }

# WRONG: cl sv import, "..main" with quotes
```

---

## 3. SAFETY-FIRST PRINCIPLE

Jac is a young language. Many things can break unexpectedly. ALWAYS take the safer path:
- Use simple patterns over clever ones
- Guard every external value (backend responses, props, user input)
- Wrap every async call in try/except
- Initialize every state variable with the correct type (never None)
- Use positional args for sv import calls (kwargs are broken)
- Test one file at a time — don't write 5 files and hope they all work
- When unsure about syntax, call `jac_docs()` — don't guess
- Prefer simple flat components over deeply nested ones
- If something seems fragile, it IS fragile — add a guard

---

## 4. WORKFLOW

### Build Order
1. Call `jac_docs(query)` — look up syntax for what you're building
2. If existing project: `analyze_project(directory)` — understand structure
3. Write `main.jac` backend first (nodes + endpoints)
4. Write hooks (sv import from backend) — e.g. hooks/useItems.cl.jac
5. Write leaf components first (ItemCard, Header) — no data logic
6. Write container components that call hooks (ItemList calls useItems)
7. Write Layout.cl.jac LAST — root layout, imports Header + child components
8. Write `main.jac` app entry (`cl { def:pub app() }`)
9. After ALL files: `validate_project(directory)` once

**Component separation rule:** Layout.cl.jac is the root layout. Each component gets its own file. Data hooks are called by the components that need the data, NOT by Layout.cl.jac.

### Validation — 3-Step Process (MUST follow all 3)

**Step 1: Cross-file check** — after writing all files, verify imports are consistent:
- Read each file and check: does every `import from "..."` / `sv import from ...` reference a file that exists?
- Check for duplicate component names, duplicate endpoint names, duplicate node definitions across files
- Check that sv import function names match actual def:pub names in main.jac
- Check that component imports use correct dot-levels (`.` same dir, `..` one up, `...` two up)

**Step 2: Validate** — call `validate_project(directory)` ONCE after all files written:
- Do NOT run `jac_check` or `jac check` manually
- Do NOT use `run_command` for jac check
- `write_code`/`edit_code` already catch syntax errors per-file — `validate_project` does the full type check

**Step 3: Preview log check** — read `.jac-preview.log` to catch runtime errors:
- Read the LAST 50 lines of `.jac-preview.log` (not the whole file)
- Look for: `[Client]`, `ERROR`, `Exception`, `undefined`, `module not found`, `failed to resolve`
- Fix any runtime errors found — these are errors that passed type check but fail at runtime
- Common runtime errors:
  - "module not found" → file doesn't exist OR stale HMR cache
  - "undefined" → missing prop, uninitialized state, or wrong import
  - "Function X failed" → sv import function name doesn't match backend def:pub
  - "422" → request body schema mismatch (check endpoint param types)

### When Stuck
1. Call `jac_docs(query)` — look up the correct syntax
2. Call `analyze_project` or `find_symbol` — check existing patterns
3. If same error 2-3 times → `ask_question` to ask the user
4. If editing same file 3+ times → step back, check assumptions

### HMR "module not found" Fix
1. File exists but compiled JS is stale
2. Do trivial edit on the TARGET file (not the importing file) — add a blank line
3. HMR recompiles, import resolves
4. Do NOT rewrite the importing file
