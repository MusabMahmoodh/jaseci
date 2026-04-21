# Runtime Gotchas — Passes Compilation, Crashes at Runtime

## JS Constructors Need Reflect.construct

In .cl.jac, `ClassName()` without `new` returns wrong type or throws. Jac has no `new` keyword.

```jac
# WRONG — Date() returns string, not Date object
year = Date().getFullYear();          # CRASH

# RIGHT
year = Reflect.construct(Date, []).getFullYear();
ws = Reflect.construct(WebSocket, ["ws://localhost"]);
```

**Safe statics (no Reflect needed):** `Date.now()`, `JSON.parse()`, `JSON.stringify()`, `Math.random()`, `Math.floor()`

**Always need Reflect.construct:** Date, WebSocket, TextDecoder, TextEncoder, URL, URLSearchParams, FormData, AbortController, RegExp, Error, Worker, Headers, Request, Response, Uint8Array, ArrayBuffer, Blob, File, FileReader, MutationObserver, ResizeObserver, IntersectionObserver

## Browser Global Name Conflicts

Do NOT define functions with names that shadow browser globals:

```jac
# WRONG — shadows window.open
def open(url: str) -> None { ... }

# RIGHT
def handleOpen(url: str) -> None { ... }
```

**Avoid as function names:** open, close, print, focus, blur, scroll, fetch, stop, find, alert, confirm, prompt

## Callback-in-Lambda Bug

Jac compiles `callback(arg)` inside a lambda as `new callback(arg)`. Crashes silently.

```jac
# WRONG — lambda compiles to new onMessage(msg), crashes
ws.onmessage = lambda(e: any) -> None { onMessage(e.data); };

# RIGHT — named handler with .call()
msgHandler = onMessage;
def handle_ws_message(e: any) -> None {
    msgHandler.call(None, e.data);
}
ws.onmessage = handle_ws_message;
```

## Undefined Property Access Crashes

The #1 runtime crash in .cl.jac. Happens when accessing property on `undefined`.

```jac
# WRONG — crashes if parent doesn't pass "items" prop
items = props["items"];           # undefined!
return <div>{[... for item in items]}</div>;  # CRASH

# RIGHT — always default props
items = props["items"] or [];
title = props["title"] or "";

# WRONG — chaining on undefined
data = result.reports[0].items;   # CRASH if reports empty

# RIGHT — guard each level
if result and result.reports and len(result.reports) > 0 {
    data = result.reports[0].items or [];
}
```

## "Cannot use 'in' operator" Crash — Guard Items Before Dict Access

When iterating over a list from an async API call, items may be `undefined` on the first render (before data loads). Using `"key" in item` when `item` is `undefined` crashes with: `TypeError: Cannot use 'in' operator to search for 'key' in undefined`.

```jac
# WRONG — crashes if p is undefined (async data not loaded yet)
for p in projects {
    title = p["title"] if "title" in p else "";
}

# WRONG — crashes when rendering a list comprehension with undefined items
{[<Card title={p["title"]} /> for p in projects]}

# RIGHT — guard the item itself before accessing properties
for p in projects {
    if not p { continue; }
    title = p["title"] if "title" in p else "";
}

# RIGHT — filter out undefined items in list comprehension
{[<Card title={p["title"] if p and "title" in p else ""} /> for p in projects if p]}

# RIGHT — safest pattern: use a render helper with full guard
def render_item(p: any) -> JsxElement {
    if not p { return <span />; }
    title = p["title"] if "title" in p else "";
    return <div>{title}</div>;
}
return <div>{[render_item(p) for p in projects]}</div>;
```

**Why this happens:** In .cl.jac, `has items: list = []` creates React state. On first render, the list is `[]`. When the async `can with entry` fires and calls `await get_items()`, the state updates and triggers a re-render. But during the FIRST render, if the list comes from a hook that returns a dict, the items inside may be `undefined` — NOT an empty list. Always guard with `if not item { continue; }` or `if p` before any dict access.

**Key rule:** NEVER use `"key" in x` without first checking `if x`. Always: `x and "key" in x`.

## Dynamic Dict Values as JSX Children Render Blank

Accessing dict/object properties dynamically and using them as JSX text children renders blank. This includes loop variables from list comprehension over dicts.

```jac
# WRONG — k["label"] renders blank inside the element
keys = [{"label": "7", "onClick": h7}, {"label": "8", "onClick": h8}];
{[<Button key={k["label"]} onClick={k["onClick"]}>{k["label"]}</Button> for k in keys]}

# WRONG — same problem with dot access
{[<Button>{k.label}</Button> for k in keys]}

# RIGHT — use explicit literal JSX for each element
<Button onClick={h7}><span>7</span></Button>
<Button onClick={h8}><span>8</span></Button>

# RIGHT — if you must loop, pass data as a prop to a child component
{[<KeyButton key={k["label"]} label={k["label"]} onClick={k["onClick"]} /> for k in keys]}
# Where KeyButton renders: <button onClick={props["onClick"]}><span>{str(props["label"])}</span></button>
```

**Rule:** When rendering a list of elements with text content, either:
1. Write each element explicitly with literal text (best for small fixed sets like calculator keys)
2. Create a child component that receives data as props and renders the text via `str()`

## Number and Boolean Display in JSX

Jac doesn't auto-convert to strings in JSX.

```jac
# WRONG — may render nothing
<span>{count}</span>

# RIGHT
<span>{str(count)}</span>
<p>{str(item["price"])}</p>
```

## sv import kwargs Are Broken

In .cl.jac, kwargs compile to a single dict argument. Server gets wrong data.

```jac
# WRONG — server receives {"a": {"a":2, "b":4, "op":"add"}}
resp = await calc(a=2, b=4, op="add");

# RIGHT — positional, order matches def:pub signature
resp = await calc(2, 4, "add");
```

## No Type Annotations in For Loops

Jac does NOT support type annotations on for-loop variables. The filter `[?:Type]` already handles typing.

```jac
# WRONG — type annotation in for loop causes syntax error
for p: Product in [root()-->][?:Product] {
    ...
}

# RIGHT — no annotation, the [?:Product] filter ensures type
for p in [root()-->][?:Product] {
    ...
}
```

## State List Mutation Doesn't Re-render

`.append()` mutates in place — React won't detect the change.

```jac
# WRONG — no re-render
items.append(newItem);

# RIGHT — new reference triggers re-render
items = items + [newItem];
```

## Comments Inside JSX Break Rendering

```jac
# WRONG — all of these crash
return <div>
    {# comment}
    <!-- comment -->
    {/* comment */}
</div>;

# RIGHT — comments above JSX only
# Render the list
return <div>...</div>;
```

## Interface/Implementation File Rules

Jac supports splitting declarations (`.jac`) from implementations (`.impl.jac`):

```jac
# mymod.jac — declaration (signature ends with ;)
obj Calculator {
    has result: float = 0.0;
    def add(x: float) -> float;    # ← no body, just ;
}

# impl/mymod.impl.jac — implementation (MUST exist if declaration has ;)
impl Calculator.add(x: float) -> float {
    self.result += x;
    return self.result;
}
```

**CRITICAL RULES:**
1. If a `.jac` file declares a function/method ending with `;` (no body), the implementation MUST exist in the corresponding `impl/*.impl.jac` file. Otherwise the function silently does nothing.
2. The impl file MUST be in an `impl/` subdirectory and named `<module>.impl.jac` (e.g., `mymod.jac` → `impl/mymod.impl.jac`).
3. A single syntax error in an `.impl.jac` file breaks ALL implementations in that file — they all silently become empty with 0 body items. The compiler won't report which one failed.
4. If you DON'T need separation, put the body directly in the `.jac` file — no impl file needed:
```jac
# mymod.jac — inline implementation (no impl file needed)
obj Calculator {
    has result: float = 0.0;
    def add(x: float) -> float {
        self.result += x;
        return self.result;
    }
}
```
5. For simple apps (todo, portfolio, calculator), use inline implementations — don't create impl files unnecessarily.

## @-scoped npm Imports Use / Not Dots

Jac uses dots for local file imports, but npm-scoped packages starting with `@` MUST keep the `/` separator with quotes.

```jac
# WRONG — dots break npm resolution
import from @jac.runtime { Link }
import from @mantine.core { Button }

# RIGHT — quoted path with / separator
# In .cl.jac files (no cl prefix needed):
import from "@jac/runtime" { Link }
import from "@mantine/core" { Button }

# In .jac files (need cl prefix for client context):
cl import from "@jac/runtime" { Link }
```

**Rule:** Any import path starting with `@` is an npm package — use quotes and `/` separators. Dots are ONLY for local Jac file paths (e.g. `import from ..components.Header`).

## Missing :pub on Exports

- Components in `.cl.jac` need `def:pub` to be importable
- Walkers need `walker :pub` for REST API
- `app()` in main.jac MUST be `def:pub`
- Hooks need `def:pub` to be importable

```jac
# WRONG — not importable
def Header() -> JsxElement { ... }

# RIGHT
def:pub Header() -> JsxElement { ... }
```

## Blank Screen Pitfalls

Three silent-failure patterns that render nothing and produce no error.

### 1. `app()` without `children` discards routed pages

If your project uses file-based routing (a `pages/` directory), `main.jac`'s `app()` MUST accept `children: Any = None` and render them. Otherwise the routed tree is thrown away and the screen stays blank.

```jac
# WRONG — routed pages silently discarded
cl { def:pub app() -> JsxElement { return <div />; } }

# RIGHT
cl { def:pub app(children: Any = None) -> JsxElement { return <>{children}</>; } }
```

### 2. `has` declarations placed after other statements

`has` must come at the very top of the function. If any prop extraction, variable assignment, or hook call precedes them, state registration breaks silently and the component stops rendering.

```jac
# WRONG — state broken
def:pub Form(props: dict) -> JsxElement {
    initial = props["initial"] or {};
    has title: str = "";
}

# RIGHT
def:pub Form(props: dict) -> JsxElement {
    has title: str = "";
    initial = props["initial"] or {};
}
```

### 3. Initializing state via `can with (prop) entry`

Object-typed props get a new reference on every parent render, so `can with (initial) entry` fires incorrectly and the child can fail to render. Use an inline `initialized` flag instead.

```jac
# WRONG — blank render when initial is a dict
can with (initial) entry {
    if initial and not initialized {
        title = initial["title"];
        initialized = True;
    }
}

# RIGHT — inline init at render time
if initial and not initialized {
    title = initial["title"] if "title" in initial else "";
    initialized = True;
}
```

## Routing Pitfalls

### Layout collision between root and route-group layouts

`pages/layout.jac` and `pages/(group)/layout.jac` cannot coexist — Jac's router throws `Layout collision: '/' has layouts from both ...`. Only ONE layout may claim each URL prefix.

Route groups like `(auth)` do not add a URL segment, so a `layout.jac` inside them tries to claim the same prefix as the root. Pick one pattern per prefix.

### AuthGuard is currently broken

`<AuthGuard redirect="/login">` silently renders nothing (jac-client plugin config loader bug). Do NOT rely on it. Protect routes with a manual check:

```jac
cl {
    def:pub page() -> JsxElement {
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }
        # ... protected content
    }
}
```

Backend `def:priv` endpoints still enforce auth server-side, so data access is safe regardless.
