# Key Patterns Summary

### Backend Patterns

| Pattern | Syntax |
|---------|--------|
| Node (data model) | `node Todo { has id: str; has title: str; }` |
| Public endpoint | `def:pub get_todos -> list { ... }` |
| Private endpoint (per-user) | `def:priv get_my_tasks -> list { ... }` |
| Walker endpoint | `walker :pub get_details { obj __specs__ { static has methods: list = ["post"]; } }` |
| Graph connect | `root ++> Todo(title="Buy milk");` |
| Graph query | `[root-->][?:Todo]` |
| Parent-child | `post ++> Comment(text="Nice!");` then `[post-->][?:Comment]` |
| Graph delete | `here del--> node;` |
| Report result | `report {"id": item.id, "status": "created"};` |
| Persistence | Nodes connected to `root` auto-persist (SQLite) |

### Frontend Patterns

| Pattern | Syntax |
|---------|--------|
| Component | `def:pub Name(props: dict) -> JsxElement { ... }` |
| State | `has count: int = 0;` (inside function = useState) |
| Effect (mount) | `can with entry { ... }` |
| Effect (async) | `async can with entry { ... }` |
| Effect (deps) | `can with [dep] entry { ... }` |
| Effect (cleanup) | `can with exit { ... }` |
| Ref | `myRef = useRef(None);` |
| Event handler | `def handle_change(e: any) -> None { value = e.target.value; }` then `onChange={handle_change}` |
| List rendering | `{[<Item key={item["id"]} data={item} /> for item in items]}` |
| Add to list | `items = items + [newItem];` |
| Update item | `items = [{"id": m["id"], "done": True} for m in items];` |
| Filter list | `items = [item for item in items if item["id"] != targetId];` |
| Conditional JSX | `{showIt and (<Component />)}` |
| Inline style | `style={{"display": "flex", "gap": "8px"}}` |

### Full-Stack Data Flow

| Pattern | Syntax |
|---------|--------|
| Import server func | `sv import from ..main { get_todos, add_todo }` |
| Call def:pub | `result = await get_todos();` |
| Call walker | `result = root spawn walker_name(param=value);` |
| Access reports | `result.reports[len(result.reports) - 1]` (always guard first) |
| Service layer | Wrap `root spawn` / `sv import` calls in async functions with try/except |
| Auth header | `"Authorization": ("Bearer " + localStorage.getItem("jac_token") if token else "")` |
| SSE fetch (advanced) | `response = await fetch("/walker/name", {...}); reader = response.body.getReader();` |

### Auth & Routing

| Pattern | Syntax |
|---------|--------|
| Auth import | `cl import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }` |
| Login | `success = await jacLogin(username, password);` |
| Signup | `result = await jacSignup(username, password);` |
| Logout | `jacLogout();` |
| Check auth | `jacIsLoggedIn()` → bool |
| AuthGuard | `<AuthGuard redirect="/login"><Outlet /></AuthGuard>` |
| Routing imports | `cl import from "@jac/runtime" { Outlet, Link, useNavigate, useParams }` |
| Layout | `pages/layout.jac` with `<Outlet />` for child routes |
| Dynamic route | `pages/posts/[id].jac` → `params = useParams(); params.id` |
| Protected group | `pages/(auth)/layout.jac` with AuthGuard |
| Public group | `pages/(public)/login.jac` |
| Navigate | `navigate = useNavigate(); navigate("/path");` |
| Link | `<Link to="/about">About</Link>` |
| Manual routing | `import from "@jac/runtime" { Router, Routes, Route }` |
| ProtectedRoute | Custom component wrapping `jacIsLoggedIn()` check |

### Import Patterns

| Pattern | Example |
|---------|---------|
| Sibling component | `import from .ComponentName { ComponentName }` |
| Nested component | `import from .ui.Button { Button }` |
| Parent directory | `import from "..hooks.useData" { useData }` |
| Two levels up | `import from "...lib.utils" { cn }` |
| NPM package | `import from "clsx" { cn }` |
| CSS file | `import "..styles.global.css";` |
| Server import | `sv import from ..main { get_todos }` — dots count from file to main.jac |
| Runtime import | `cl import from "@jac/runtime" { jacLogin, Outlet }` |
| NEVER extensions | `.cl`, `.jac`, `.cl.jac` are NEVER in import paths |

### Construction Rules

| Pattern | Syntax |
|---------|--------|
| JS constructor | `Reflect.construct(ClassName, [arg1, arg2])` — NEVER use `new` |
| Date (static) | `Date.now()` → epoch ms; `Date()` → string only |
| Date (object) | `Reflect.construct(Date, []).getFullYear()` |
| No `#` in JSX | Put comments OUTSIDE JSX elements |
| Return types | Components → `JsxElement`, hooks → `dict`, handlers → `None` |
| Handler naming | NEVER `open`, `close`, `print`, `fetch` — use `handleOpen`, etc. |
| Console output | `print(x)` NOT `console.log(x)` |
| String convert | `str(x)` NOT `String(x)` |
| Length | `len(items)` NOT `items.length` |
