# Backend Development — Endpoints, Persistence, Auth

## Function Endpoints (def:pub / def:priv)

Simple CRUD with typed returns — the compiler auto-serializes nodes for the client.

```jac
node Todo {
    has title: str = "",
        done: bool = False;
}

# Typed returns — nodes auto-serialized, client gets dot access
def:pub get_todos -> list[Todo] {
    return [root()-->][?:Todo];
}

def:pub add_todo(title: str) -> Todo {
    return (root() ++> Todo(title=title))[0];
}

def:pub toggle_todo(todo_id: str) -> Todo {
    for t in [root()-->][?:Todo] {
        if jid(t) == todo_id {
            t.done = not t.done;
            return t;
        }
    }
}

def:pub delete_todo(todo_id: str) -> dict {
    for t in [root()-->][?:Todo] {
        if jid(t) == todo_id {
            del t;
            return {"deleted": True};
        }
    }
    return {"error": "not found"};
}
```

Client receives typed objects with **dot access**:
```jac
# In .cl.jac — sv import generates typed stubs
sv import from ..services.todos { get_todos, add_todo }

todos = await get_todos();       # list[Todo] objects
todos[0].title                   # dot access, NOT todos[0]["title"]
todos[0].done                    # direct property access

# Use jid() for React keys
{[<p key={jid(t)}>{t.title}</p> for t in todos]}
```

**When to use typed returns vs dicts:**
- **Typed (`-> list[Todo]`, `-> Todo`)**: preferred — type-safe, dot access on client
- **Dict (`-> dict`, `-> list`)**: use when reshaping data or returning computed fields

## Walker Endpoints

For graph traversal and multi-step operations:

```jac
walker :pub get_post_with_comments {
    has post_id: str = "";

    can find_post with Root entry {
        for p in [-->][?:Post] {
            if p.id == self.post_id { visit p; return; }
        }
        report {"error": "not found"};
    }

    can collect with Post entry {
        comments = [{"id": c.id, "text": c.text}
                    for c in [-->][?:Comment]];
        report {
            "post": {"id": here.id, "title": here.title},
            "comments": comments
        };
    }
}
```

## Data Persistence

- Nodes connected to `root()` **auto-persist** across requests (SQLite)
- No database setup needed — the language handles it
- `del node;` removes from graph and storage
- Use `jid(node)` to get unique graph identity — no need for manual `uuid4()` IDs

```jac
# Create + persist
root() ++> Todo(title="Buy milk");

# Query all
todos = [root()-->][?:Todo];

# Query with filter
found = [root()-->][?:Todo](?title == "Buy milk");

# Delete
root() del--> todo;
# or: del todo;

# Get node ID
todo_id = jid(todo);
```

## Per-User Data Isolation (def:priv)

`:priv` endpoints require authentication. Each user gets their own isolated `root()`.

```jac
# Public — shared root, anyone can call
def:pub get_shared_data -> list[DataNode] {
    return [root()-->][?:DataNode];
}

# Private — per-user root, requires login
def:priv get_my_tasks -> list[Task] {
    return [root()-->][?:Task];
}
```

## Authentication

Built-in — no manual login/signup logic needed. The runtime handles JWT tokens, storage, and session management.

```jac
import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }
```

| Function | Async? | Returns | Behavior |
|----------|--------|---------|----------|
| `jacLogin(username, password)` | yes | `bool` | POSTs `/user/login`, stores JWT in localStorage on success |
| `jacSignup(username, password)` | yes | `dict` `{"success": bool, "error"?: str}` | POSTs `/user/register`, auto-stores token on success (user is logged in) |
| `jacLogout()` | no | `void` | Clears token + all cache |
| `jacIsLoggedIn()` | no | `bool` | Checks if token exists in localStorage |

**Runtime behaviors:**
- Token stored as `jac_token` in localStorage, sent as `Authorization: Bearer {token}` on every `def:priv`/`walker:priv` call
- On 401 response: token auto-cleared, page reloads (user redirected to login)
- `jacSignup` success = user is already logged in (no separate login call needed)

**SSO (Google OAuth)** — configure in `jac.toml`, no code needed:
```toml
[plugins.scale.sso.google]
client_id = "your-google-client-id"
client_secret = "your-google-client-secret"
```

## File-Based Routing

```
pages/
├── layout.jac              # Root layout with <Outlet />
├── index.jac               # Route: /
├── about.jac               # Route: /about
├── users/
│   ├── index.jac           # Route: /users
│   └── [id].jac            # Route: /users/:id (dynamic)
├── (public)/               # Route group (no URL segment)
│   └── login.jac           # Route: /login
├── (auth)/                 # Protected group (no URL segment)
│   └── dashboard.jac       # Route: /dashboard
└── [...notFound].jac       # Catch-all 404
```

**Layout rule:** Only ONE `layout.jac` may claim a given URL prefix. Placing both `pages/layout.jac` and `pages/(group)/layout.jac` at the same level throws "Layout collision". Pick one per prefix. Route groups `(auth)`, `(public)` exist to organize files only — they do not automatically get their own layout without a URL segment beneath them.

### Layout with Outlet

```jac
# pages/layout.jac
import from "@jac/runtime" { Outlet, Link }

cl {
    def:pub layout() -> JsxElement {
        return <>
            <nav>
                <Link to="/">Home</Link>
                <Link to="/about">About</Link>
            </nav>
            <main><Outlet /></main>
        </>;
    }
}
```

### Dynamic Routes

```jac
# pages/users/[id].jac
import from "@jac/runtime" { useParams }

cl {
    def:pub page() -> JsxElement {
        params = useParams();
        return <div>User: {params.id}</div>;
    }
}
```

### Protected Routes

**Note:** `AuthGuard` is currently broken (silently renders nothing due to a jac-client plugin bug). Protect routes with a manual check at the top of each page:

```jac
# pages/(auth)/dashboard.jac
cl import from "@jac/runtime" { Navigate, jacIsLoggedIn }

cl {
    def:pub page() -> JsxElement {
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }
        return <h1>Dashboard</h1>;
    }
}
```

Backend `def:priv` endpoints still enforce auth server-side, so even without a client-side guard, unauthenticated users cannot create, read, or modify data.

### Navigation

```jac
import from "@jac/runtime" { useNavigate, Link }

navigate = useNavigate();
navigate("/path");                    # Push
navigate("/path", {"replace": True}); # Replace
navigate(-1);                          # Back

<Link to="/about">About</Link>
```

## Running a Fullstack App

```bash
jac start --dev main.jac   # Dev: Vite + API server (port from jac.toml config)
jac start main.jac         # Production: single server
```

Visit `http://localhost:<port>/docs` for Swagger UI (check terminal output for actual port).
