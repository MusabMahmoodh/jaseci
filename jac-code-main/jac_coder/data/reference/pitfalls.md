# Common Pitfalls & Runtime Gotchas

## 18. Pitfalls

| # | Pitfall | Fix |
|---|---------|-----|
| 1 | Missing semicolons | Every statement ends with `;` |
| 2 | `here` vs `self` | `here` = current node (walker abilities), `self` = the archetype |
| 3 | `++>` returns list | Use `(here ++> Node())[0]` to get the node |
| 4 | `visit` queues | Walker moves AFTER current ability finishes |
| 5 | `disengage` vs `return` | `disengage` stops walker entirely; `return` only exits ability |
| 6 | Abilities need type clauses | `can handle with BuildHandler entry` — without type clause, only triggers at spawn |
| 7 | Graph queries return lists | `[-->][?:Session]` returns list — check before `[0]` |
| 8 | `impl` must match declaration | Signature must exactly match `can` declaration |
| 9 | No file extensions in imports | `import from .components { X }` — NEVER `.cl` or `.jac` in path |
| 10 | sv import kwargs broken in .cl.jac | `calc(a=1, b=2)` compiles to single dict arg → use positional: `calc(1, 2)` |
| 10 | No `component` keyword | Use `def:pub Name(props: dict) -> JsxElement { ... }` |
| 11 | No JS arrow functions | Use named `def handler(x: T) -> R { ... }` — NEVER `=>` or inline lambda in JSX |
| 12 | **JS constructors need `Reflect.construct`** | NEVER `new X(args)` (no `new` in Jac). NEVER `Date()`, `WebSocket()`, `URL()` etc. bare — returns wrong type or throws. ALWAYS `Reflect.construct(Date, [])` for instances. Safe statics: `Date.now()`, `JSON.parse()`, `Math.random()` |
| 13 | No `#` comments in JSX | `#` comments inside JSX elements render as literal text — put comments OUTSIDE JSX |
| 14 | Use correct return types | Components → `JsxElement`, hooks → `dict`, handlers → `None`, data functions → proper type. Never use `any` as a lazy default. |
| 15 | No `const`/`let`/`var` | Just assign: `x = 5;` — no declaration keywords |
| 16 | No `===` or `!==` | Use `==` and `!=` |
| 17 | No ternary `? :` | Use `(a if cond else b)` |
| 18 | Default all props | `items = props.items or [];` — accessing undefined props crashes: "Cannot read properties of undefined" |
| 19 | Guard before access | Check `if result and result.reports` before `result.reports[0]` — never chain on potentially undefined |
| 20 | Missing `:pub` on exports | Components, hooks, services in `.cl.jac` need `def:pub` to be importable. Walkers need `walker :pub` for REST API. `app()` in main.jac MUST be `def:pub`. |
| 21 | Use `can with entry`, not `useEffect` | `useEffect(lambda...)` is OLD syntax — NEVER use it. Always use `can with entry { ... }` / `can with exit { ... }`. |
| 22 | Use list comprehension, not `.map()` | `{[<Item /> for item in items]}` — NOT `items.map(lambda...)`. Use `+` to add, comprehension to filter. |
| 23 | Never import before building | Writing `import from .Foo { Foo }` when `Foo.cl.jac` doesn't exist yet causes HMR "module not found" error in preview. Build dependencies bottom-up: leaf components first, parent components last. |
| 24 | Don't use `.append()` for state lists | `.append()` mutates in place — no re-render. Use `items = items + [x]` to create a new reference. |
| 25 | All backend in main.jac | Put all nodes, endpoints, and walkers directly in `main.jac`. Do NOT create separate backend files. Frontend calls backend via `sv import from ..main { func_name }`. |

## 19. Runtime Gotchas (.cl.jac)

These issues **pass compilation** but **crash at runtime** in the browser.

### JS Constructors Need `Reflect.construct`

In JavaScript, `ClassName()` without `new` does NOT return an object — it returns a primitive or throws. Jac has no `new` keyword, so you must use `Reflect.construct`.

```jac
# WRONG — Date() returns a string, not a Date object
year = Date().getFullYear();          # CRASH: "string has no method getFullYear"
ws = WebSocket("ws://localhost");     # CRASH: "must be called with new"

# RIGHT — Reflect.construct creates the actual object
year = Reflect.construct(Date, []).getFullYear();      # 2026
ws = Reflect.construct(WebSocket, ["ws://localhost"]);  # WebSocket object
```

**Safe patterns that work without Reflect.construct:**
- `Date.now()` → epoch milliseconds (static method, no object needed)
- `Date()` → date string for display only (no methods available)
- `JSON.parse()`, `JSON.stringify()` → static methods, always fine
- `Math.random()`, `Math.floor()` → static methods, always fine

**Classes that ALWAYS need Reflect.construct when you want an instance:**
Date, WebSocket, TextDecoder, TextEncoder, URL, URLSearchParams, FormData,
Map, Set, Error, TypeError, RegExp, Blob, File, FileReader, AbortController,
MutationObserver, ResizeObserver, IntersectionObserver, Headers, Request, Response,
Uint8Array, Int8Array, Float32Array, ArrayBuffer, Worker, BroadcastChannel

### Browser Global Name Conflicts

Do NOT define functions with names that shadow browser globals:

```jac
# WRONG — shadows window.open, causes unexpected behavior
def open(url: str) -> None { window.open(url, "_blank"); }

# RIGHT — use descriptive handler names
def handleOpen(url: str) -> None { window.open(url, "_blank"); }
```

**Avoid as function names:** open, close, print, focus, blur, scroll, fetch, stop, find, alert, confirm, prompt

### Callback-in-Lambda Bug

Jac compiles `callback(arg)` inside a lambda as `new callback(arg)` when `callback` is a function parameter. This silently crashes at runtime.

```jac
# WRONG — compiles to `new onMessage(msg)` → crash
ws.onmessage = lambda(e: any) -> None { onMessage(e.data); };

# RIGHT — assign to local variable, use .call()
msgHandler = onMessage;
ws.onmessage = lambda(e: any) -> None { msgHandler.call(None, e.data); };
```

### "Cannot read properties of undefined" Prevention

This is the #2 most common runtime crash. It happens when you access a property on `undefined` — usually from missing prop defaults or unloaded async data.

```jac
# WRONG — crashes if parent doesn't pass "items" prop
def MyList(props: dict) -> JsxElement {
    items = props.items;              # undefined if not passed!
    return <div>{items.map(...)}</div>;  # CRASH
}

# RIGHT — always default props
def MyList(props: dict) -> JsxElement {
    items = props.items or [];        # safe default
    title = props.title or "";        # safe default
    onAction = props.onAction or None;

    return <div>
        {len(items) > 0 and ([
            <span key={item["id"]}>{item["name"]}</span>
            for item in items
        ])}
    </div>;
}

# WRONG — accessing nested property without guard
data = result.reports[0].items;    # CRASH if reports is empty

# RIGHT — guard each level
if result and result.reports and len(result.reports) > 0 {
    data = result.reports[0].items or [];
}
```

**Rules:**
- Default ALL props: `x = props.x or defaultValue;`
- Initialize state with correct shape: `has items: list = [];` never `has data: any = None;`
- Guard before list comprehension, `len()`, `[0]`: check the value exists first
- Guard async results: always check `if result and result.reports` before accessing

### Number/Boolean Display in JSX

Jac does not auto-convert numbers/booleans to strings in JSX:

```jac
# WRONG — may render nothing or [object Object]
<span>{count}</span>

# RIGHT — explicit str() conversion (Jac idiom, compiles to toString())
<span>{str(count)}</span>
```
