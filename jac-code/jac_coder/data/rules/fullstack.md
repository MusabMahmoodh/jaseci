# Fullstack Jac Pitfalls — .cl.jac Frontend + Backend Integration

> These rules apply when building fullstack Jaseci apps with .cl.jac frontend components.
> Everything in core_jac.md ALSO applies. This file covers the additional fullstack gotchas.

---

## File Types

- `.jac` — Backend code (nodes, endpoints, walkers). Uses Python runtime.
- `.cl.jac` — Frontend code (React components). Compiles to JavaScript.

---

## BEFORE WRITING ANY CODE

**Read `jac.toml` FIRST.** Only use npm packages listed in `[dependencies.npm]`. Do NOT import unlisted libraries. NEVER assume any UI library is available. Use plain Tailwind CSS + inline SVG for styling and icons.

When creating a new fullstack project, ensure `jac.toml` has these Tailwind dependencies:

```toml
[dependencies.npm]
tailwind-merge = "^3.4.0"
clsx = "^2.1.1"

[dependencies.npm.dev]
"@jac-client/dev-deps" = "2.0.0"
"@tailwindcss/vite" = "^4.1.17"
tailwindcss = "^4.1.17"

[plugins.client.vite]
plugins = ["tailwindcss()"]
lib_imports = ["import tailwindcss from '@tailwindcss/vite'"]
```

---

## Backend services in .sv.jac files

Define backend logic (nodes, endpoints, walkers) in separate `.sv.jac` files under a `services/` directory. Then import them in TWO places:

```jac
# services/products.sv.jac — define endpoints here
node Product {
    has name: str = "";
    has price: float = 0.0;
}

# Typed returns — nodes auto-serialized, client gets dot access
def:pub get_products -> list[Product] {
    return [root()-->][?:Product];
}

def:pub add_product(name: str, price: float) -> Product {
    return (root() ++> Product(name=name, price=price))[0];
}
```

```jac
# main.jac — import to REGISTER endpoints with the server
import from services.products { get_products, add_product }
```

```jac
# hooks/useProducts.cl.jac — sv import to CALL endpoints from frontend
sv import from ..services.products { get_products, add_product }
```

**Both imports are required:**
- `main.jac` import → registers the endpoint so the server exposes it
- `sv import` in `.cl.jac` → generates HTTP stubs so frontend can call it

For small projects, you can keep everything in `main.jac` directly. For larger apps, split into `.sv.jac` files.

## Endpoint types: def:pub vs def:priv vs walker:pub

```jac
# Public — anyone can call, typed return
def:pub get_items -> list[Item] {
    return [root()-->][?:Item];
}

# Private — requires login, per-user isolated root
def:priv get_my_items -> list[Item] {
    return [root()-->][?:Item];
}

# Walker — for complex graph traversal
walker:pub get_details {
    has item_id: str;
    can find with Root entry {
        for i in [-->][?:Item] {
            if jid(i) == self.item_id { visit i; return; }
        }
        report {"error": "not found"};
    }
}
```

## Returning data from endpoints — typed returns vs dicts

**Preferred: Typed returns** — return nodes directly with type annotation. The compiler auto-serializes.
```jac
# BEST — typed return, auto-serialized, client gets dot access
def:pub get_items -> list[Item] {
    return [root()-->][?:Item];
}
# Client: items[0].title (dot access)
```

**Alternative: Dict returns** — when you need to reshape or join data.
```jac
# OK — manual serialization when you need computed fields
def:pub get_items() -> list {
    return [{"id": str(i.id), "title": i.title, "age_days": compute_age(i)}
            for i in [root()-->][?:Item]];
}
# Client: items[0]["title"] (dict access, needs guards)
```

## Node CRUD pattern

```jac
node Item {
    has title: str = "";
    has done: bool = False;
}

# Create + connect to root (auto-persists in SQLite)
root() ++> Item(title="Buy milk");

# Query
items = [root()-->][?:Item];
found = [root()-->][?:Item][?title == "Buy milk"][0];

# Delete
del found;
# or: root() del--> found;
```

## Frontend entry point in main.jac

When using file-based routing (a `pages/` directory), `app()` MUST accept `children: Any = None` and render them — otherwise routed pages are discarded silently and the screen stays blank.

```jac
# RIGHT — file-based routing: app() receives the routed tree as children
cl {
    def:pub app(children: Any = None) -> JsxElement {
        return <>{children}</>;
    }
}

# Single-file app (no pages/ directory): app() is the entire UI
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement { return <Layout />; }
}
```

---

## Component props — ALWAYS use props: dict

```jac
# WRONG — individual params on JsxElement components
def:pub Header(title: str, theme: str) -> JsxElement { ... }

# RIGHT — always use props: dict, destructure inside
def:pub Header(props: dict) -> JsxElement {
    title = props["title"] or "";
    theme = props["theme"] or "light";
    return <header>{title}</header>;
}

# EXCEPTION: layout(), page() take no props. app() takes `children: Any = None`
# when file-based routing is used (pages/ directory).
def:pub app(children: Any = None) -> JsxElement { return <>{children}</>; }
def:pub layout() -> JsxElement { return <><Nav /><Outlet /></>; }
def:pub page() -> JsxElement { return <h1>Home</h1>; }
```

Components returning `JsxElement` MUST accept `props: dict` as the single parameter (or no params). NEVER use individual typed params like `(title: str, count: int)`.

Also use `className`, NOT `class` for HTML attributes in JSX:
```jac
# WRONG
<div class="container">

# RIGHT
<div className="container">
```

## Jac syntax NOT JavaScript — conversion table

```
WRONG (JS)                          →  RIGHT (Jac)
──────────────────────────────────────────────────
const x = 5;                        →  x = 5;
let items = [];                     →  has items: list = [];
x ? a : b                           →  a if x else b
() => { ... }                       →  def handler() -> None { ... }
`hello ${name}`                     →  f"hello {name}"
x === y                             →  x == y
console.log(x)                      →  print(x)
x.length                            →  len(x)
parseInt(x)                         →  int(x)
x.toString()                        →  str(x)
items.map(fn)                       →  {[<Item /> for item in items]}
items.filter(fn)                    →  [i for i in items if cond]
items.push(x)                       →  items = items + [x];
useEffect(() => {}, [])             →  can with entry { ... }
useState(0)                         →  has count: int = 0;
!condition                          →  not condition
new Date()                          →  Reflect.construct(Date, [])
window.open(url)                    →  globalThis.open(url, "_blank")
```

## State — has auto-generates useState

```jac
has count: int = 0;        # auto-creates count + setCount
has name: str = "";
has items: list = [];

count = count + 1;         # calls setCount internally
items = items + [newItem]; # new reference = re-render
```

**NEVER define `setX` yourself. NEVER use `.append()` for state** — it mutates in place (no re-render). Always `items = items + [x]`.

**`has` declarations MUST come first in the function** — before any prop extraction, variable assignments, or hook calls. Placing them later breaks state registration and causes silent render failures.

```jac
# WRONG — has after other statements breaks state
def:pub Form(props: dict) -> JsxElement {
    initial = props["initial"] or {};
    has title: str = "";       # ← TOO LATE
}

# RIGHT — all has declarations first
def:pub Form(props: dict) -> JsxElement {
    has title: str = "";       # ← at the top
    has submitting: bool = False;

    initial = props["initial"] or {};
}
```

### Initializing state from props

To seed state from a prop (e.g. pre-filling an edit form), initialize inline at render time with an `initialized` flag. NEVER use `can with (prop) entry` for object-typed props — dicts get new references every parent render, causing the effect to misfire.

```jac
def:pub Form(props: dict) -> JsxElement {
    has title: str = "";
    has initialized: bool = False;

    initial = props["initial"] or {};

    if initial and not initialized {
        title = initial["title"] if "title" in initial else "";
        initialized = True;
    }
}
```

## Effects — can with entry/exit

```jac
can with entry { ... }                  # mount (useEffect(fn, []))
async can with entry { ... }            # async mount
can with [dep1, dep2] entry { ... }     # dependency watch
can with exit { ... }                   # cleanup/unmount
```

**NEVER use `useEffect(lambda...)` — that is OLD syntax.**

## Event handlers — ALWAYS use named functions

```jac
# RIGHT — named function ABOVE return, passed by name
def handle_click() -> None {
    count = count + 1;
}
def handle_input(e: any) -> None {
    text = e.target.value;
}
return <div>
    <button onClick={handle_click}>Click</button>
    <input onChange={handle_input} />
</div>;

# WRONG — lambda in JSX
<input onChange={lambda e: any -> None { text = e.target.value; }} />

# WRONG — inline def in JSX
<button onClick={def(e: any) -> None { count = count + 1; }}>
```

NEVER use `lambda` or inline `def` in JSX attributes. ALWAYS define named `def` handlers BEFORE `return` and pass by name.

## Functions MUST be defined BEFORE return

```jac
# WRONG — helper after return (unreachable)
return <div>{render_item(data)}</div>;
def render_item(d: dict) -> JsxElement { ... }

# RIGHT — define above
def render_item(d: dict) -> JsxElement { ... }
return <div>{render_item(data)}</div>;
```

## No comments inside JSX

```jac
# WRONG — all of these crash
return <div>
    {# comment}
    <!-- HTML comment -->
    {/* JS comment */}
</div>;

# RIGHT — comments ABOVE JSX
# Render the list
return <div>...</div>;
```

## sv import — calling server functions from .cl.jac

`sv import` brings server-side functions and walkers into client code. The compiler generates HTTP stubs automatically — no manual fetch calls needed.

```jac
# Import syntax — NO quotes, dots for path, point to the .sv.jac file where endpoints are defined
sv import from ..services.items { get_items, add_item }
```

**Two call patterns — NEVER mix them up:**

```jac
# def:pub / def:priv → await, returns value directly
items = await get_items() or [];

# walker:pub / walker:priv → root spawn, result is in .reports[0]
result = root spawn get_tasks();
if result.reports and len(result.reports) > 0 {
    tasks = result.reports[0] or [];
} else {
    tasks = [];
}
```

## sv import kwargs are broken in .cl.jac

```jac
# def:pub — POSITIONAL ONLY (kwargs compile to a single dict arg — wrong data)
# WRONG
resp = await calc(a=2, b=4, op="add");
# RIGHT
resp = await calc(2, 4, "add");

# root spawn — kwargs ARE fine (matched to walker has fields by name)
result = root spawn add_task(title="Buy milk");
```

## sv import — always wrap in try/except

```jac
async can with entry {
    try {
        items = await get_items() or [];
    } except Exception as e {
        error = str(e);
    }
    loading = False;
}
```

## JS constructors need Reflect.construct

In .cl.jac, `ClassName()` without `new` returns wrong type or throws. Jac has no `new` keyword.

```jac
# WRONG
year = Date().getFullYear();          # CRASH

# RIGHT
year = Reflect.construct(Date, []).getFullYear();
ws = Reflect.construct(WebSocket, ["ws://localhost"]);

# Safe statics (no Reflect needed):
Date.now();  JSON.parse();  Math.random();
```

Classes that ALWAYS need Reflect.construct: Date, WebSocket, TextDecoder, TextEncoder, URL, URLSearchParams, FormData, AbortController, RegExp, Error, Worker, Headers, Request, Response.

## Browser global name conflicts

NEVER define functions named: `open`, `close`, `print`, `fetch`, `focus`, `blur`, `scroll`, `alert`, `confirm`, `prompt`, `stop`, `find`

Use `handleOpen`, `handleClose`, `handleFetch`, etc.

## Display numbers/booleans with str()

```jac
# WRONG — may render nothing
<span>{count}</span>

# RIGHT
<span>{str(count)}</span>
```

## Defensive guards — CRITICAL for .cl.jac

Undefined access CRASHES the whole app in .cl.jac.

```jac
# State — always init with correct types, NEVER None
has items: list = [];
has user: dict = {};
has loading: bool = True;

# ALWAYS guard the object first, then the key
# WRONG — crashes if item is undefined:
name = item["name"] if "name" in item else "";
# RIGHT:
name = item["name"] if item and "name" in item else "";

# List iteration — filter undefined items
# WRONG:
{[<Card title={p["title"]} /> for p in projects]}
# RIGHT:
{[<Card title={p["title"] if p and "title" in p else ""} /> for p in projects if p]}

# Props — always default
items = props["items"] or [];
title = props["title"] or "";
```

**CRITICAL: The `"key" in x` operator crashes if `x` is undefined.** Always write `x and "key" in x`.

---

## Import rules for .jac files (backend)

```jac
import from datetime { datetime }               # Python module
cl import from .components.Layout { Layout }     # Client component (NO quotes, cl prefix)
```

## Import rules for .cl.jac files (frontend)

In `.cl.jac` files, the `cl` prefix is NOT needed — everything is already client-side.

```jac
# Client-to-client — NO quotes, DOTS not slashes (NO cl prefix needed)
import from .Header { Header }                   # same directory
import from ..hooks.useTodos { useTodos }        # parent directory
import from ...lib.utils { cn }                  # 2 levels up

# Server calls — sv import, NO quotes
sv import from ..services.todoService { get_todos, add_todo }

# NPM packages — WITH quotes (NO cl prefix needed in .cl.jac)
import from "clsx" { cn }

# Runtime — WITH quotes
import from "@jac/runtime" { jacLogin, Outlet }

# CSS — WITH quotes
import "..styles.global.css";
```

## Import rules for .sv.jac files (backend services)

In `.sv.jac` files, the `sv` prefix is NOT needed — everything is already server-side.

```jac
# Python modules — no prefix needed
import from uuid { uuid4 }
import from datetime { datetime }
```

## Import dot-level cheat sheet

```
.   = same directory
..  = 1 level up (parent)
... = 2 levels up
```

### NEVER do
- `cl sv import` — never combine prefixes
- `"..main"` with quotes on sv import — sv import has NO quotes
- Slashes in LOCAL import paths — always dots for local files
- File extensions in imports — never `.cl`, `.jac`, `.cl.jac`
- `@jac.runtime` or `@mantine.core` — WRONG! npm `@`-scoped packages keep `/`: `"@jac/runtime"`, `"@mantine/core"`

---

## Fullstack project structure

```
project-root/
├── jac.toml              # config + deps
├── main.jac              # Entry point: imports from services/ + cl { app() }
├── services/             # .sv.jac backend logic (nodes + endpoints)
│   ├── products.sv.jac   # Product node + CRUD endpoints
│   └── cart.sv.jac       # Cart node + cart endpoints
├── components/           # .cl.jac components (one per file)
│   ├── Layout.cl.jac     # Root layout — imports child components
│   ├── Header.cl.jac     # Nav/header
│   └── ItemList.cl.jac   # Data display (calls hook)
├── hooks/                # .cl.jac data hooks (sv import + state)
│   └── useItems.cl.jac   # sv import from ..services.items { get_items }
├── pages/                # .jac file-based routing (optional)
├── lib/                  # .cl.jac shared utilities
└── styles/               # CSS files
```

**Key rule:** Endpoints defined in `.sv.jac` files must be imported in BOTH `main.jac` (to register) AND `.cl.jac` hooks (to call via `sv import`).

Layout.cl.jac is the root layout. Data logic lives in hooks/, called by child components — NOT by Layout.

---

## Styling with Tailwind CSS (MANDATORY)

Every fullstack app must have a styled `styles/global.css`. An app without styling is not done.

### `styles/global.css` template

```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');

@import "tailwindcss";

@theme {
    /* Typography */
    --font-sans: 'Inter', ui-sans-serif, system-ui, sans-serif;

    /* Colors — customize per app */
    --color-background: #f8fafc;
    --color-foreground: #0f172a;
    --color-card: #ffffff;
    --color-card-hover: #f8fafc;
    --color-primary: #3b82f6;
    --color-primary-foreground: #ffffff;
    --color-muted: #f1f5f9;
    --color-muted-foreground: #64748b;
    --color-border: #e2e8f0;
    --color-destructive: #ef4444;
    --color-success: #22c55e;

    /* Shadows */
    --shadow-soft: 0 1px 3px 0 rgba(0, 0, 0, 0.04);
    --shadow-card: 0 4px 16px -2px rgba(0, 0, 0, 0.06);

    /* Radius */
    --radius-sm: 0.375rem;
    --radius-md: 0.5rem;
    --radius-lg: 0.75rem;
    --radius-full: 9999px;
}

/* Dark mode */
.dark {
    --color-background: #0f172a;
    --color-foreground: #f1f5f9;
    --color-card: #1e293b;
    --color-card-hover: #334155;
    --color-primary: #60a5fa;
    --color-muted: #1e293b;
    --color-muted-foreground: #94a3b8;
    --color-border: #334155;
}

/* Base */
html, body, #root {
    min-height: 100vh;
}
body {
    background-color: var(--color-background);
    color: var(--color-foreground);
    font-family: var(--font-sans);
    -webkit-font-smoothing: antialiased;
}
```

### Using Tailwind in .cl.jac components

Use `className` with Tailwind utility classes. Reference `@theme` tokens as Tailwind classes:

```jac
// Colors from @theme tokens
className="bg-background text-foreground"
className="bg-primary text-primary-foreground"
className="bg-card shadow-card rounded-lg"
className="text-muted-foreground"
className="border border-border"

// Layout
className="min-h-screen flex flex-col"
className="max-w-2xl mx-auto px-4 py-8"
className="flex items-center justify-between gap-4"
className="grid grid-cols-1 md:grid-cols-2 gap-6"

// Interactive states
className="hover:bg-card-hover transition-colors"
className="focus:outline-none focus:ring-2 focus:ring-primary"

// Buttons
className="px-4 py-2 bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors"
className="px-3 py-1.5 text-sm text-muted-foreground hover:text-foreground"

// Cards
className="p-4 bg-card rounded-lg shadow-soft border border-border"

// Forms
className="w-full px-3 py-2 bg-background border border-border rounded-md focus:outline-none focus:ring-2 focus:ring-primary"

// Typography
className="text-2xl font-bold"
className="text-sm text-muted-foreground"
```

### Styling checklist (verify before declaring done)
- [ ] `styles/global.css` has `@import "tailwindcss"` + `@theme` block
- [ ] Colors customized for the app (not just scaffold defaults)
- [ ] Dark mode `.dark { }` overrides
- [ ] All components use Tailwind utility classes
- [ ] Interactive elements have hover/focus states
- [ ] Layout uses proper spacing, max-width containers
- [ ] Cards/panels have shadows, borders, rounded corners
- [ ] Typography hierarchy (headings larger/bolder than body text)
