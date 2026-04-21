# Frontend Components — .cl.jac

## Component Definition

Components are public functions returning `JsxElement`.

```jac
# In a .cl.jac file:
def:pub Header(props: dict) -> JsxElement {
    title = props["title"] or "";
    return (
        <header className="border-b px-6 py-4">
            <h1 className="text-xl font-bold">{title}</h1>
        </header>
    );
}
```

Components need `def:pub` to be importable by other files.

## Inline client component in main.jac (cl def:pub)

For simple apps, you can define client components directly in `main.jac` using the `cl` prefix — no separate `.cl.jac` file needed:

```jac
# main.jac — backend + frontend in one file
node Todo {
    has title: str = "", done: bool = False;
}

def:pub get_todos -> list[Todo] { return [root()-->][?:Todo]; }
def:pub add_todo(title: str) -> Todo { return (root() ++> Todo(title=title))[0]; }

cl def:pub app -> JsxElement {
    has todos: list = [];
    has text: str = "";

    async can with entry { todos = await get_todos(); }

    async def add -> None {
        if text.strip() {
            todo = await add_todo(text.strip());
            todos = todos + [todo];
            text = "";
        }
    }

    def handle_input(e: any) -> None {
        text = e.target.value;
    }

    return <div>
        <input value={text} onChange={handle_input} />
        <button onClick={add}>Add</button>
        {[<p key={jid(t)}>{t.title}</p> for t in todos]}
    </div>;
}
```

Note: `cl def:pub` replaces the `cl { def:pub app() -> JsxElement { ... } }` block syntax. Both work, but `cl def:pub` is cleaner for single-file apps.

## State Management

`has` inside a component function auto-generates `useState`.

```jac
def:pub Counter() -> JsxElement {
    has count: int = 0;
    has name: str = "";
    has items: list = [];

    # Assignment triggers re-render (calls setter internally)
    count = count + 1;
    items = items + [newItem];    # new reference = re-render
}
```

- NEVER define `setX` yourself — it already exists from `has`
- NEVER use `.append()` — it mutates in place (no re-render)
- Always init with correct type, NEVER `None` or `any`
- **`has` declarations MUST come first in the function**, before any other statements (including prop extraction, variable assignments, or hook calls). Placing them later breaks state registration and causes silent render failures.

```jac
# WRONG — has after prop extraction breaks state
def:pub Form(props: dict) -> JsxElement {
    initial = props["initial"] or {};
    has title: str = "";     # ← TOO LATE, state won't work
}

# RIGHT — all has declarations first
def:pub Form(props: dict) -> JsxElement {
    has title: str = "";     # ← at the top
    has submitting: bool = False;

    initial = props["initial"] or {};
}
```

### Initializing state from props

When a component needs to seed its state from a prop (e.g. pre-filling an edit form from a fetched record), initialize inline at render time with an `initialized` flag — NOT via `can with (prop) entry`. Object-typed props (dicts) get new references every parent render, causing reactive effects to misfire or trigger infinite re-renders.

```jac
def:pub Form(props: dict) -> JsxElement {
    has title: str = "";
    has initialized: bool = False;

    initial = props["initial"] or {};

    # Inline one-shot init — runs on first render, skipped after
    if initial and not initialized {
        title = initial["title"] if "title" in initial else "";
        initialized = True;
    }

    # ... rest of component
}
```

## Effects (Lifecycle)

```jac
can with entry { ... }                  # Mount (runs once on load)
async can with entry { ... }            # Async mount (for data fetching)
can with [dep1, dep2] entry { ... }     # Re-run when dependencies change
can with exit { ... }                   # Cleanup/unmount
```

NEVER use `useEffect` — use `can with entry` instead. NEVER import from react.

## Event Handlers

ALL handlers MUST be named `def` functions defined BEFORE `return`. NEVER use `lambda` or inline `def` in JSX.

```jac
def:pub TodoList() -> JsxElement {
    has inputValue: str = "";

    # Define handler above return
    def handle_input(e: any) -> None {
        inputValue = e.target.value;
    }

    def handle_submit() -> None {
        if inputValue { add_item(inputValue); inputValue = ""; }
    }

    # Pass by name
    return <div>
        <input value={inputValue} onChange={handle_input} />
        <button onClick={handle_submit}>Add</button>
    </div>;
}
```

## jid() — get graph identity of a node

Use `jid(node)` to get the unique graph ID of a node object. Essential for React `key` props when rendering lists of typed nodes.

```jac
# With typed returns — use jid() for keys, dot access for fields
{[<p key={jid(t)}>{t.title}</p> for t in todos]}

# jid() gives clear errors:
# - If node is null: "jid() called on null — server may have returned an error"
# - If wrong type: "jid() expected a node or edge, but received ..."
```

`jid()` is available automatically in `.cl.jac` — no import needed.

## Typed objects vs props — where dot access works

**Dot access** works on typed objects returned from API calls (via `sv import`).
**Props are always `dict`** — use bracket access (`props["title"]`). NEVER use dot access (`props.title`).

```jac
# In hook — typed objects from API, dot access works
todos = await get_todos();     # list[Todo] typed objects
todos[0].title                 # dot access on typed object

# When passing to child — extract fields from typed object
{[<TodoItem key={jid(t)} todoId={jid(t)} title={t.title} completed={t.completed} /> for t in todos]}

# Inside child component — props is a dict, NOT a typed object
def:pub TodoItem(props: dict) -> JsxElement {
    title = props["title"] or "";          # props access (dict)
    completed = props["completed"] or False;
    todoId = props["todoId"] or "";
}
```

## List Rendering

Use list comprehension, NEVER `.map()`.

```jac
# Render list of typed objects — use jid() for key, dot access for fields
{[<TodoItem key={jid(item)} data={item} /> for item in items]}

# Render list of dicts — use dict access for key
{[<TodoItem key={item["id"]} data={item} /> for item in items]}

# With filter
{[<Tag key={t} label={t} /> for t in tags if t != "hidden"]}

# Add to list (new reference)
items = items + [newItem];

# Remove from list
items = [item for item in items if item["id"] != targetId];
```

**WARNING:** Dynamic dict values as JSX text children render BLANK.
```jac
# WRONG — renders blank buttons
{[<Button>{k["label"]}</Button> for k in keys]}

# RIGHT — explicit elements with literal text for small fixed sets
<Button><span>7</span></Button>
<Button><span>8</span></Button>

# RIGHT — child component that renders via str(props["label"])
{[<KeyBtn key={k["label"]} label={k["label"]} /> for k in keys]}
```

## Conditional Rendering

```jac
{showSidebar and (<Sidebar items={items} />)}
{isActive and (<ActiveView />) or (<InactiveView />)}
{(not loading) and (<Content />)}
```

## Custom Hooks

```jac
def:pub useCounter(initial: int = 0) -> dict {
    has count: int = initial;
    def increment() -> None { count = count + 1; }
    def decrement() -> None { count = count - 1; }
    return {"count": count, "increment": increment, "decrement": decrement};
}
```

## Data Hook Pattern (sv import + state)

```jac
# hooks/useTodos.cl.jac — point to the .sv.jac file, NOT main.jac
sv import from ..services.todoService { get_todos, add_todo, delete_todo }

def:pub useTodos() -> dict {
    has todos: list = [];
    has loading: bool = True;
    has error: str = "";

    async can with entry {
        try {
            result = await get_todos();
            todos = result or [];
        } except Exception as e {
            error = str(e);
        }
        loading = False;
    }

    async def handleAdd(title: str) -> None {
        if not title { return; }
        result = await add_todo(title);  # positional args only
        if result and not result.error {
            todos = todos + [result];
        }
    }

    async def handleDelete(id: str) -> None {
        result = await delete_todo(id);  # positional args only
        if result and not result.error {
            todos = [t for t in todos if t["id"] != id];
        }
    }

    return {
        "todos": todos, "loading": loading, "error": error,
        "handleAdd": handleAdd, "handleDelete": handleDelete
    };
}
```

## Frontend Import Rules

```jac
# Same directory (.cl.jac to .cl.jac) — NO quotes, dots not slashes
import from .Header { Header }

# Parent directory — NO quotes
import from ..hooks.useTodos { useTodos }

# Two levels up — NO quotes
import from ...lib.utils { cn }

# Server calls — sv import, NO quotes, point to .sv.jac file
sv import from ..services.todoService { get_todos, add_todo }

# NPM packages — WITH quotes
import from "clsx" { cn }

# Runtime — WITH quotes (no cl prefix needed in .cl.jac files)
import from "@jac/runtime" { jacLogin, Outlet }

# CSS — WITH quotes
import "..styles.global.css";
```

**Dot levels:** `.` = same dir, `..` = parent, `...` = 2 up

## Calling Backend Walkers

```jac
sv import from ..services.postService { get_post_details }

async def loadDetails() -> None {
    result = root spawn get_post_details(post_id=postId);
    if result and result.reports and len(result.reports) > 0 {
        data = result.reports[0];
    }
}
```

## Primitive Idioms (Jac, NOT JavaScript)

| JS (WRONG) | Jac (RIGHT) |
|---|---|
| `console.log(x)` | `print(x)` |
| `String(x)` / `.toString()` | `str(x)` |
| `parseInt(x)` | `int(x)` |
| `x.length` | `len(x)` |
| `.toLowerCase()` | `.lower()` |
| `.toUpperCase()` | `.upper()` |
| `.trim()` | `.strip()` |
| `.indexOf(sub)` | `.find(sub)` |

## Inline Styles

```jac
<div style={{"display": "flex", "gap": "8px", "backgroundColor": "#f0f0f0"}} />
```

## Service Layer Pattern (for walker calls)

```jac
# services/apiService.cl.jac
sv import from .itemService { create_item, list_items }

async def:pub createItem(title: str) -> any {
    try {
        response = root spawn create_item(title=title);
        result = response.reports[len(response.reports) - 1]
            if response.reports and len(response.reports) > 0 else {};
        return {"success": True, "item": result};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}
```

## @jac/runtime — Complete symbol list

ONLY these symbols exist in `@jac/runtime`. Do NOT import anything else — any other name is hallucinated and will crash.

In `.cl.jac` files: `import from "@jac/runtime"` (WITH quotes, NO `cl` prefix).
In `.jac` files (main.jac): `cl import from "@jac/runtime"` (WITH `cl` prefix).
ALWAYS quotes + slash: `"@jac/runtime"`. NEVER dots: `@jac.runtime` ← WRONG.

**Auth:**
- `jacLogin(username, password)` — async, returns bool. POSITIONAL args only.
- `jacSignup(username, password)` — async, returns `{"success": bool, "error"?: str}`. Auto-logs in on success.
- `jacLogout()` — sync, clears token + cache.
- `jacIsLoggedIn()` — sync, returns bool.

**Routing:**
- `Router` — BrowserRouter container
- `Routes` — Route group
- `Route` — Individual route
- `Link` — `<Link to="/path">text</Link>`
- `Navigate` — redirect component: `<Navigate to="/login" />`
- `Outlet` — renders child routes in layouts: `<Outlet />`
- `useNavigate` — `navigate = useNavigate(); navigate("/path");`
- `useLocation` — `location = useLocation(); location.pathname`
- `useParams` — `params = useParams(); params.id`
- `useRouter` — returns `{navigate, location, params, pathname, search, hash}`
- `AuthGuard` — **KNOWN BROKEN**: silently renders nothing due to a jac-client plugin bug. Do NOT use. Guard routes with a manual check instead (see "Manual route protection" below).

**Forms (Zod validation):**
- `JacForm` — auto-rendering form component from schema
- `JacSchema` — Zod schema wrapper for validation
- `useJacForm` — hook to initialize form with validation

**Error handling:**
- `ErrorFallback` — error boundary fallback component
- `JacClientErrorBoundary` — React error boundary wrapper

**DO NOT USE directly (internal only):**
- `useState`, `useEffect` — these exist in the runtime but are INTERNAL. Use `has` for state and `can with entry` for effects instead. NEVER import or call them directly.

## @jac/runtime — Auth example

```jac
import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

# ASYNC — always await. POSITIONAL args only (kwargs broken in .cl.jac)
success = await jacLogin(username, password);
result = await jacSignup(username, password);
if result["success"] { navigate("/dashboard"); }
else { error = result["error"] or "Signup failed"; }

jacLogout();                  # sync
is_auth = jacIsLoggedIn();    # sync
```

## @jac/runtime — Routing example

```jac
import from "@jac/runtime" {
    Link, Navigate, useNavigate, useLocation, useParams, Outlet
}

<Link to="/dashboard">Go to Dashboard</Link>

if not jacIsLoggedIn() { return <Navigate to="/login" />; }

navigate = useNavigate();
navigate("/path");                     # push
navigate("/path", {"replace": True});  # replace
navigate(-1);                          # back

location = useLocation();    # location.pathname, location.search
params = useParams();        # params.id

return <div><Outlet /></div>;
```

### Manual route protection (use instead of AuthGuard)

`AuthGuard` is currently broken. Protect routes with a manual check at the top of each page:

```jac
cl {
    def:pub page() -> JsxElement {
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }
        # ... rest of the page
    }
}
```

Backend `def:priv` endpoints still enforce auth server-side, so even without a client-side guard, unauthenticated users cannot create, read, or modify data.
