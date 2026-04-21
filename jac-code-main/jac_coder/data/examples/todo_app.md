# Example: Full-Stack Todo App

A complete full-stack app with authentication, per-user data isolation, CRUD operations, and file-based routing.

### Project Structure

```
todo-app/
├── jac.toml
├── main.jac                      # ALL backend (nodes, endpoints) + cl entry
├── components/
│   ├── Layout.cl.jac              # Root layout — imports Header + child components
│   ├── Header.cl.jac             # Nav/header bar
│   ├── TodoList.cl.jac           # Todo list + add form (calls useTodos hook)
│   ├── TodoItem.cl.jac           # Single todo item display
│   └── AddTodoForm.cl.jac        # Input form for adding todos
├── pages/
│   ├── layout.jac                # Root layout with nav
│   ├── index.jac                 # Home page (/)
│   ├── (public)/
│   │   ├── login.jac             # Login page (/login)
│   │   └── signup.jac            # Signup page (/signup)
│   └── (auth)/
│       ├── layout.jac            # Auth guard layout
│       └── dashboard.jac         # Dashboard (/dashboard)
├── hooks/
│   └── useTodos.cl.jac           # Todo data hook (sv import + state)
├── lib/
│   └── utils.cl.jac              # cn() utility
└── styles/
    └── global.css                # Tailwind CSS
```

### jac.toml

```jac
[project]
name = "todo-app"
version = "1.0.0"
description = "Full-stack Todo app with auth"
entry-point = "main.jac"

[dependencies]
python-dotenv = ">=1.0.0"

[dependencies.npm]
jac-client-node = "1.0.5"
clsx = "^2.1.1"
tailwind-merge = "^3.4.0"
tailwindcss = "^4.1.17"

[dependencies.npm.dev]
"@jac-client/dev-deps" = "2.0.0"

[serve]
base_route_app = "app"

[plugins.client]

[plugins.client.vite]
plugins = ["tailwindcss()"]
lib_imports = ["import tailwindcss from '@tailwindcss/vite'"]

[plugins.client.app_meta_data]
title = "Todo App"
```

### main.jac — All backend + frontend entry

```jac
"""Full-stack Todo app — backend nodes, endpoints, and frontend entry.
All backend code goes in main.jac. Nodes connected to root auto-persist in SQLite.
"""

import from uuid { uuid4 }
import from datetime { datetime }


node Todo {
    has id: str = "";
    has title: str;
    has completed: bool = False;
    has created_at: str = "";

    def postinit {
        if not self.id { self.id = str(uuid4()); }
        if not self.created_at {
            self.created_at = datetime.now().isoformat();
        }
    }
}

# Private endpoints — per-user data isolation (requires login)
def:priv get_todos -> list {
    return [{"id": t.id, "title": t.title, "completed": t.completed}
            for t in [root-->][?:Todo]];
}

def:priv add_todo(title: str) -> dict {
    todo = (root ++> Todo(title=title))[0];
    return {"id": todo.id, "title": todo.title, "completed": False};
}

def:priv toggle_todo(id: str) -> dict {
    for todo in [root-->][?:Todo] {
        if todo.id == id {
            todo.completed = not todo.completed;
            return {"id": todo.id, "completed": todo.completed};
        }
    }
    return {"error": "not found"};
}

def:priv delete_todo(id: str) -> dict {
    for todo in [root-->][?:Todo] {
        if todo.id == id {
            here del--> todo;
            return {"deleted": id};
        }
    }
    return {"error": "not found"};
}


# Frontend entry
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement {
        return <Layout />;
    }
}
```

### Hook: hooks/useTodos.cl.jac

```jac
sv import from ..main { get_todos, add_todo, toggle_todo, delete_todo }

def:pub useTodos() -> dict {
    # State
    has todos: list = [];
    has loading: bool = True;
    has error: str = "";

    # Fetch data on mount
    async can with entry {
        try {
            result = await get_todos();
            todos = result or [];
        } except Exception as e {
            error = str(e);
        }
        loading = False;
    }

    # Handlers
    async def handleAdd(title: str) -> None {
        if not title { return; }
        result = await add_todo(title);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            todos = todos + [result];
        }
    }

    async def handleToggle(id: str) -> None {
        result = await toggle_todo(id);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            todos = [
                ({"id": t["id"], "title": t["title"],
                  "completed": result["completed"]}
                 if t["id"] == id else t)
                for t in todos
            ];
        }
    }

    async def handleDelete(id: str) -> None {
        result = await delete_todo(id);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            todos = [t for t in todos if t["id"] != id];
        }
    }

    return {
        "todos": todos,
        "loading": loading,
        "error": error,
        "handleAdd": handleAdd,
        "handleToggle": handleToggle,
        "handleDelete": handleDelete
    };
}
```

### Component: components/Layout.cl.jac — Root Layout

```jac
import "..styles.global.css";
import from ".Header" { Header }
import from ".TodoList" { TodoList }

def:pub Layout() -> JsxElement {
    return (
        <div className="min-h-screen bg-background text-text-primary">
            <Header title="Todo App" />
            <main className="max-w-2xl mx-auto px-4 py-8">
                <TodoList />
            </main>
        </div>
    );
}
```

### Component: components/Header.cl.jac

```jac
def:pub Header(title: str) -> JsxElement {
    return (
        <header className="border-b border-border px-6 py-4">
            <h1 className="text-xl font-bold">{title}</h1>
        </header>
    );
}
```

### Component: components/TodoItem.cl.jac

```jac
def:pub TodoItem(props: dict) -> JsxElement {
    # Guard props
    todo = props.todo or {};
    onToggle = props.onToggle or None;
    onDelete = props.onDelete or None;
    todoId = todo["id"] or "";
    title = todo["title"] or "";
    completed = todo["completed"] or False;

    # Handlers
    def handle_toggle() -> None {
        if onToggle { onToggle(todoId); }
    }

    def handle_delete() -> None {
        if onDelete { onDelete(todoId); }
    }

    # Render
    return (
        <div className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg">
            <button
                onClick={handle_toggle}
                className={completed and "w-5 h-5 rounded border-2 border-success bg-success flex items-center justify-center" or "w-5 h-5 rounded border-2 border-border"}
            >
                {completed and "✓"}
            </button>
            <span className={completed and "flex-1 line-through text-text-secondary" or "flex-1"}>
                {title}
            </span>
            <button
                onClick={handle_delete}
                className="text-error hover:opacity-75"
            >
                ×
            </button>
        </div>
    );
}
```

### Component: components/AddTodoForm.cl.jac

```jac
def:pub AddTodoForm(props: dict) -> JsxElement {
    # Guard props
    onAdd = props.onAdd or None;

    # State
    has inputValue: str = "";

    # Handlers
    def handleSubmit(e: any) -> None {
        e.preventDefault();
        if inputValue and onAdd {
            onAdd(inputValue);
            inputValue = "";
        }
    }

    def handle_input_change(e: any) -> None {
        inputValue = e.target.value;
    }

    # Render
    return (
        <form onSubmit={handleSubmit} className="flex gap-2">
            <input
                value={inputValue}
                onChange={handle_input_change}
                placeholder="What needs to be done?"
                className="flex-1 px-4 py-2 bg-surface border border-border rounded-lg text-text-primary"
            />
            <button type="submit" className="px-4 py-2 bg-primary text-primary-foreground rounded-lg">
                +
            </button>
        </form>
    );
}
```

### Component: components/TodoList.cl.jac

```jac
import from .TodoItem { TodoItem }
import from .AddTodoForm { AddTodoForm }
import from "..hooks.useTodos" { useTodos }

def:pub TodoList() -> JsxElement {
    # Fetch data
    todoData = useTodos();
    todos = todoData["todos"] or [];

    # Guard
    if todoData["loading"] {
        return <p className="text-text-secondary text-center py-8">Loading...</p>;
    }

    # Render
    return (
        <div>
            {todoData["error"] and (
                <p className="text-error mb-4">{todoData["error"]}</p>
            )}
            <div className="mb-6">
                <AddTodoForm onAdd={todoData["handleAdd"]} />
            </div>
            {len(todos) == 0 and (
                <p className="text-text-secondary text-center py-8">No todos yet. Add one above!</p>
            )}
            <div className="space-y-2">
                {[
                    <TodoItem
                        key={todo["id"]}
                        todo={todo}
                        onToggle={todoData["handleToggle"]}
                        onDelete={todoData["handleDelete"]}
                    />
                    for todo in todos
                ]}
            </div>
        </div>
    );
}
```

### Page: pages/layout.jac — Root Layout

```jac
cl import from "@jac/runtime" { Outlet, Link }

cl {
    def:pub layout() -> JsxElement {
        return (
            <div className="min-h-screen bg-background text-text-primary">
                <nav className="border-b border-border px-6 py-4 flex items-center justify-between">
                    <Link to="/" className="text-lg font-bold">Todo App</Link>
                    <div className="flex gap-4">
                        <Link to="/login" className="text-text-secondary hover:text-text-primary">Login</Link>
                        <Link to="/signup" className="text-text-secondary hover:text-text-primary">Sign Up</Link>
                    </div>
                </nav>
                <main className="max-w-2xl mx-auto px-4 py-8">
                    <Outlet />
                </main>
            </div>
        );
    }
}
```

### Page: pages/(public)/login.jac — Login

```jac
cl import from "@jac/runtime" { jacLogin, useNavigate }

cl {
    def:pub page() -> JsxElement {
        # State
        has username: str = "";
        has password: str = "";
        has error: str = "";
        has loading: bool = False;

        navigate = useNavigate();

        # Handlers
        async def handleLogin(e: any) -> None {
            e.preventDefault();
            loading = True;
            error = "";
            success = await jacLogin(username, password);
            if success {
                navigate("/dashboard");
            } else {
                error = "Invalid credentials";
            }
            loading = False;
        }

        def handle_username_change(e: any) -> None {
            username = e.target.value;
        }
        def handle_password_change(e: any) -> None {
            password = e.target.value;
        }

        # Render
        return (
            <div className="max-w-sm mx-auto">
                <h1 className="text-2xl font-bold mb-6">Login</h1>
                {error and <div className="p-3 mb-4 bg-error/10 text-error rounded">{error}</div>}
                <form onSubmit={handleLogin} className="space-y-4">
                    <input value={username}
                        onChange={handle_username_change}
                        placeholder="Username"
                        className="w-full px-4 py-2 border border-border rounded-lg bg-surface" />
                    <input type="password" value={password}
                        onChange={handle_password_change}
                        placeholder="Password"
                        className="w-full px-4 py-2 border border-border rounded-lg bg-surface" />
                    <button type="submit" disabled={loading}
                        className="w-full px-4 py-2 bg-primary text-primary-foreground rounded-lg">
                        {loading and "Logging in..." or "Login"}
                    </button>
                </form>
            </div>
        );
    }
}
```

### Page: pages/(auth)/layout.jac — Auth Guard

```jac
cl import from "@jac/runtime" { AuthGuard, Outlet }

cl {
    def:pub layout() -> JsxElement {
        return <AuthGuard redirect="/login">
            <Outlet />
        </AuthGuard>;
    }
}
```

### Page: pages/(auth)/dashboard.jac — Dashboard

```jac
cl import from "...components.TodoList" { TodoList }
cl import from "@jac/runtime" { jacLogout, useNavigate }

cl {
    def:pub page() -> JsxElement {
        navigate = useNavigate();

        # Handlers
        def handleLogout() -> None {
            jacLogout();
            navigate("/login");
        }

        # Render
        return (
            <div>
                <div className="flex items-center justify-between mb-6">
                    <h1 className="text-2xl font-bold">My Todos</h1>
                    <button onClick={handleLogout}
                        className="text-text-secondary hover:text-text-primary">
                        Logout
                    </button>
                </div>
                <TodoList />
            </div>
        );
    }
}
```

---

## Example 2: Multi-Resource App — Blog with Posts & Comments
