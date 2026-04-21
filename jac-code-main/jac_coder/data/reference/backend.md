# Backend Development

## 11. REST API & Backend Endpoints

### Two Backend Approaches

**Option 1: Walker endpoints (for graph traversal & multi-step operations)**

```jac
walker :pub create_user {
    has name: str;
    has email: str;
    obj __specs__ { static has methods: list = ["post"]; }

    can create with Root entry {
        user = (here ++> User(name=self.name, email=self.email))[0];
        report {"id": user.id, "status": "created"};
    }
}

walker :pub list_users {
    obj __specs__ { static has methods: list = ["get"]; }
    can list with Root entry {
        report {"users": [{"name": u.name} for u in [-->][?:User]]};
    }
}

walker :pub search {
    has query: str;
    obj __specs__ { static has methods: list = ["get"]; static has as_query: list = ["query"]; }
}
```

**Option 2: `def:pub` functions (simpler, for CRUD)**

```jac
import from uuid { uuid4 }

node Todo {
    has id: str;
    has title: str;
    has completed: bool = False;
}

def:pub get_todos -> list {
    return [{"id": t.id, "title": t.title, "completed": t.completed}
            for t in [root-->][?:Todo]];
}

def:pub add_todo(title: str) -> dict {
    todo = root ++> Todo(id=str(uuid4()), title=title);
    return {"id": todo[0].id, "title": todo[0].title, "completed": False};
}

def:pub toggle_todo(id: str) -> dict {
    for todo in [root-->][?:Todo] {
        if todo.id == id {
            todo.completed = not todo.completed;
            return {"id": todo.id, "completed": todo.completed};
        }
    }
    return {"error": "not found"};
}

def:pub delete_todo(id: str) -> dict {
    for todo in [root-->][?:Todo] {
        if todo.id == id {
            del todo;
            return {"deleted": id};
        }
    }
    return {"error": "not found"};
}
```

### Data Persistence

- **Nodes connected to `root` automatically persist** across requests (SQLite by default)
- No database setup needed — the language handles persistence
- Each user gets their own isolated `root` node when using `:priv` endpoints

### Per-User Data Isolation with `:priv`

```jac
# Public — shared root, anyone can call
def:pub get_shared_data -> list {
    return [root-->][?:DataNode];
}

# Private — per-user root, requires authentication
def:priv get_my_tasks -> list {
    # 'root' here is THIS user's isolated root
    return [{"id": t.id, "title": t.title} for t in [root-->][?:Task]];
}

walker :priv add_task {
    has title: str;
    obj __specs__ { static has methods: list = ["post"]; }
    can create with Root entry {
        task = (here ++> Task(id=str(uuid4()), title=self.title))[0];
        report {"id": task.id, "title": task.title};
    }
}
```

## 12. Authentication

Built-in auth functions for full-stack apps:

```jac
cl import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }

cl {
    def:pub LoginPage() -> JsxElement {
        has username: str = "";
        has password: str = "";
        has error: str = "";

        navigate = useNavigate();

        async def handleLogin() -> None {
            success = await jacLogin(username, password);
            if success {
                navigate("/dashboard");
            } else {
                error = "Invalid credentials";
            }
        }

        async def handleSignup() -> None {
            result = await jacSignup(username, password);
            if result.success {
                navigate("/dashboard");
            } else {
                error = "Signup failed";
            }
        }

        def handle_submit(e: any) -> None {
            e.preventDefault();
            handleLogin();
        }
        def handle_username_change(e: any) -> None {
            username = e.target.value;
        }
        def handle_password_change(e: any) -> None {
            password = e.target.value;
        }

        return <form onSubmit={handle_submit}>
            {error and <div className="text-error">{error}</div>}
            <input value={username}
                onChange={handle_username_change}
                placeholder="Username" />
            <input type="password" value={password}
                onChange={handle_password_change}
                placeholder="Password" />
            <button type="submit">Login</button>
        </form>;
    }
}
```

**Auth function signatures:**

| Function | Returns | Purpose |
|----------|---------|---------|
| `jacLogin(username, password)` | `bool` | Log in, stores token in localStorage |
| `jacSignup(username, password)` | `dict` (has `.success`) | Register new user |
| `jacLogout()` | `void` | Clear auth token |
| `jacIsLoggedIn()` | `bool` | Check if user has valid token |

## 13. File-Based Routing

Convention-based routing using the `pages/` directory:

```
pages/
├── layout.jac              # Root layout (wraps all pages)
├── index.jac               # Route: /
├── about.jac               # Route: /about
├── users/
│   ├── index.jac           # Route: /users
│   └── [id].jac            # Route: /users/:id (dynamic)
├── (public)/               # Route group — no URL segment
│   ├── login.jac           # Route: /login
│   └── signup.jac          # Route: /signup
├── (auth)/                 # Protected group — requires login
│   ├── layout.jac          # Auth layout with AuthGuard
│   └── dashboard.jac       # Route: /dashboard
└── [...notFound].jac       # Catch-all: * (404 page)
```

### Layout with Outlet

```jac
# pages/layout.jac
cl import from "@jac/runtime" { Outlet, Link }

cl {
    def:pub layout() -> JsxElement {
        return <>
            <nav>
                <Link to="/">Home</Link>
                <Link to="/about">About</Link>
            </nav>
            <main>
                <Outlet />
            </main>
        </>;
    }
}
```

### Dynamic Routes

```jac
# pages/users/[id].jac
cl import from "@jac/runtime" { useParams }

cl {
    def:pub page() -> JsxElement {
        params = useParams();
        userId = params.id;
        return <div>User: {userId}</div>;
    }
}
```

### Protected Routes with AuthGuard

```jac
# pages/(auth)/layout.jac
cl import from "@jac/runtime" { AuthGuard, Outlet }

cl {
    def:pub layout() -> JsxElement {
        return <AuthGuard redirect="/login">
            <Outlet />
        </AuthGuard>;
    }
}
```

### Navigation

```jac
cl import from "@jac/runtime" { useNavigate, Link }

cl {
    navigate = useNavigate();
    navigate("/path");            # Push
    navigate("/path", {"replace": True});  # Replace
    navigate(-1);                 # Back

    <Link to="/about">About</Link>
}
```

### Manual Routing (alternative to file-based)

```jac
import from "@jac/runtime" { Router, Routes, Route, useNavigate }

def:pub app() -> JsxElement {
    return <Router>
        <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/login" element={<LoginPage />} />
            <Route path="/admin" element={<ProtectedRoute><AdminPage /></ProtectedRoute>} />
        </Routes>
    </Router>;
}
```

**ProtectedRoute component:**
```jac
import from "@jac/runtime" { jacIsLoggedIn, useNavigate }

def:pub ProtectedRoute(props: dict) -> JsxElement {
    navigate = useNavigate();
    isAuth = jacIsLoggedIn();

    can with entry {
        if not isAuth {
            navigate("/login");
        }
    }

    if not isAuth {
        return <div>Redirecting...</div>;
    }
    return <>{props.children}</>;
}
```

## 14. Frontend Calling Backend

### Calling `def:pub` functions (recommended for simple CRUD)

Use a hook file for sv import + state, then call the hook from a component:

```jac
# hooks/useTodos.cl.jac — data hook
sv import from ..main { get_todos, add_todo, delete_todo }

def:pub useTodos() -> dict {
    has todos: list = [];
    has loading: bool = True;

    async can with entry {
        result = await get_todos();
        todos = result or [];
        loading = False;
    }

    async def handleAdd(title: str) -> None {
        if not title { return; }
        result = await add_todo(title);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            todos = todos + [result];
        }
    }

    async def handleDelete(id: str) -> None {
        result = await delete_todo(id);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            todos = [t for t in todos if t["id"] != id];
        }
    }

    return {"todos": todos, "loading": loading,
            "handleAdd": handleAdd, "handleDelete": handleDelete};
}
```

```jac
# components/TodoList.cl.jac — uses the hook
import from "..hooks.useTodos" { useTodos }

def:pub TodoList() -> JsxElement {
    data = useTodos();
    todos = data["todos"] or [];

    has newTitle: str = "";

    def handle_title_change(e: any) -> None {
        newTitle = e.target.value;
    }

    def handleAdd() -> None {
        if newTitle {
            data["handleAdd"](newTitle);
            newTitle = "";
        }
    }

    if data["loading"] {
        return <p>Loading...</p>;
    }

    return <div>
        <input value={newTitle} onChange={handle_title_change} />
        <button onClick={handleAdd}>Add</button>
        {[<div key={todo["id"]}>{todo["title"]}</div> for todo in todos]}
    </div>;
}
```

### Calling walkers with `root spawn`

```jac
sv import from ..main { get_tasks, add_task }

cl {
    async def loadTasks() -> None {
        result = root spawn get_tasks();
        if result and result.reports and len(result.reports) > 0 {
            tasks = result.reports[0];
        }
    }

    async def handleAdd() -> None {
        result = root spawn add_task(title=newTitle);
        if result and result.reports and len(result.reports) > 0 {
            newItem = result.reports[0];
            tasks = tasks + [newItem];
        }
    }
}
```

### Service Layer Pattern (recommended for walker calls)

Wrap `root spawn` calls in a service file with error handling:

```jac
# services/apiService.cl.jac
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

async def:pub fetchItems() -> any {
    try {
        response = root spawn list_items();
        result = response.reports[len(response.reports) - 1]
            if response.reports and len(response.reports) > 0 else {};
        return {"success": True, "items": result.items or []};
    } except Exception as e {
        return {"success": False, "error": str(e), "items": []};
    }
}
```

### Advanced: SSE Streaming (optional — for real-time apps)

Most apps do NOT need streaming. Use this only for real-time features like live updates or AI chat:

```jac
# services/streamService.cl.jac
async def:pub streamData(query: str, onChunk: any = None, abortSignal: any = None) -> any {
    try {
        token = localStorage.getItem("jac_token");
        response = await fetch("/walker/stream_endpoint", {
            "method": "POST",
            "headers": {
                "Content-Type": "application/json",
                "Authorization": ("Bearer " + token if token else "")
            },
            "body": JSON.stringify({"query": query}),
            "signal": abortSignal
        });
        reader = response.body.getReader();
        decoder = Reflect.construct(TextDecoder, ["utf-8"]);
        buffer = "";
        while True {
            read_result = await reader.read();
            if read_result.done { break; }
            buffer += decoder.decode(read_result.value, {"stream": True});
            doubleNewline = String.fromCharCode(10) + String.fromCharCode(10);
            events = buffer.split(doubleNewline);
            buffer = events.pop() or "";
            for event in events {
                if not event.startsWith("data:") { continue; }
                data = event.replace("data:", "").trim();
                try {
                    parsed = JSON.parse(data);
                    if parsed.type == "chunk" and onChunk { onChunk(parsed.content); }
                } except Exception as parseError {}
            }
        }
        return {"success": True};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}
```

### Advanced: Request Cancellation with AbortController

```jac
import from react { useRef }

abortControllerRef = useRef(None);

# Start cancellable request
abortControllerRef.current = Reflect.construct(AbortController, []);
result = await streamData(query, onChunk, abortControllerRef.current.signal);

# Cancel request
def handleStop() -> None {
    if abortControllerRef.current {
        abortControllerRef.current.abort();
        abortControllerRef.current = None;
    }
}
```

## 15. Full-Stack Project Structure

```
myapp/
├── jac.toml                # Project config (python + npm deps)
├── main.jac                # ALL backend code (nodes, endpoints) + cl { app() }
├── components/             # Frontend: .cl.jac component files
│   ├── Layout.cl.jac       # Root layout — imports Header + child components
│   ├── Header.cl.jac       # Nav/header bar
│   ├── ItemList.cl.jac     # List + add form (calls hook, renders ItemCard)
│   └── ItemCard.cl.jac     # Single item display
├── hooks/                  # Frontend: custom hooks (sv import from ..main)
│   ├── useAuth.cl.jac
│   └── useItems.cl.jac     # sv import + state management
├── pages/                  # File-based routing (optional)
│   ├── layout.jac
│   ├── index.jac
│   ├── (public)/login.jac
│   └── (auth)/dashboard.jac
├── utils/
│   └── ProtectedRoute.cl.jac  # Auth guard component
├── lib/
│   └── utils.cl.jac        # cn() utility
├── styles/
│   └── global.css          # Tailwind CSS
└── .env                    # API keys (git-ignored)
```

**Key rule: Layout.cl.jac is the root layout.** It imports Header and child components (e.g., ItemList), renders them in a layout shell. All data fetching and business logic lives in hooks, called by the child components — NOT in Layout.cl.jac.

**Running:**
```bash
jac start --dev    # Dev mode: Vite on :8000, API on :8001
jac start          # Production: single server on :8000
```

Visit `http://localhost:8000/docs` for Swagger UI to test endpoints.
