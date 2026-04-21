# Jac Syntax Reference

## 1. Syntax Basics

Jac uses curly braces `{}` for code blocks and semicolons `;` to terminate statements.

```jac
# Single-line comment
#* Multi-line comment *#
"""Docstring for modules, classes, functions"""

with entry {
    x = 5;
    print(f"Hello {x}");
}
```

**File extensions:**
- `.jac` — Universal Jac code (backend)
- `.cl.jac` — Client-side only (React/JSX frontend)
- `.impl.jac` — Implementation file (separates interface from logic)

## 2. Types & Variables

**Builtin types:** int, float, str, bool, bytes, list, tuple, set, dict, any, type, None

**Generic types:** `list[str]`, `dict[str, int]`, `set[int]`, `tuple[str, int]`, `Type | None`

```jac
obj Example {
    has name: str;                    # Required field
    has count: int = 0;              # With default
    has items: list[str] = [];       # Generic type with default
}

glob config: dict = {};              # Global variable
x: int = 42;                        # Local with annotation
name = "hello";                      # Type inferred
```

Type annotations are **required** on `has` fields and function signatures.

## 3. Control Flow

```jac
if x > 0 { print("positive"); } elif x == 0 { print("zero"); } else { print("negative"); }
for item in items { print(item); }
while count < 10 { count += 1; }
match value { case "a": print("alpha"); case _: print("other"); }
try { result = risky(); } except ValueError as e { print(f"Error: {e}"); } finally { cleanup(); }
```

## 4. Functions & Objects

```jac
def greet(name: str, greeting: str = "Hello") -> str {
    return f"{greeting}, {name}!";
}

obj Person {
    has name: str;
    has age: int = 0;

    def postinit { print(f"Created {self.name}"); }
    def greet() -> str { return f"Hi, I'm {self.name}"; }
}

obj Student(Person) { has grade: str = "A"; }    # Inheritance

enum Color { RED, GREEN, BLUE }

walker :pub my_walker { ... }   # Public access modifier
```

### Access Modifiers (`:pub`, `:priv`, `:protect`)

| Modifier | Meaning | Use Case |
|----------|---------|----------|
| `:pub` | Public | REST API endpoints, importable components/hooks/services |
| `:priv` | Private (authenticated) | Per-user endpoints — requires login, user data isolation |
| `:protect` | Protected | Module-internal helpers, not exposed via HTTP |
| *(none)* | Default | Module-scoped, not an HTTP endpoint, not importable |

```jac
# Backend — walkers as REST endpoints
walker :pub get_tasks { ... }        # Public API — anyone can call
walker :priv add_task { ... }        # Authenticated — per-user data
def :protect validate(x: str) -> bool { ... }  # Internal helper

# Frontend (.cl.jac) — components must be :pub to be importable
def:pub Header(props: dict) -> JsxElement { ... }     # Importable by other files
def:pub useChat() -> dict { ... }                      # Importable hook
def:pub generateSessionId() -> str { ... }             # Importable utility
def helperFn() -> None { ... }                         # Only usable within this file

# Fields
obj Account {
    has :pub name: str;              # Public field
    has :priv balance: float;        # Private field
}
```

**Rules:**
- Walkers/functions need `:pub` to be exposed as HTTP endpoints
- `.cl.jac` components, hooks, and services need `def:pub` to be importable by other `.cl.jac` files
- The `app()` entry function in `main.jac` MUST be `def:pub`
- Use `:priv` for endpoints that require authentication

## 5. Imports

```jac
# Backend imports (.jac files)
import from jac_coder.nodes {Session, Router}    # Jac modules
import os;                                         # Python module
import from datetime {datetime}                    # Python library
import from pathlib {Path}
cl import from .components.Layout { Layout }       # Client component (no quotes)

# Frontend imports (.cl.jac files)
import from ".contact_card" { ContactCard }        # Client-to-client (WITH quotes)
import from "..hooks.useData" { useData }          # Parent directory (WITH quotes)
sv import from ..main { get_todos, add_todo }      # Backend function (NO quotes)
cl import from "@jac/runtime" { jacLogin, Outlet } # Runtime (cl import, no quotes)
import from "clsx" { cn }                            # NPM package (WITH quotes)
import "..styles.global.css";                      # CSS import
```

**Import prefix rules — NEVER combine `cl` and `sv`:**
- `cl import` — in `.jac` files to import client components, NO quotes
- `sv import` — in `.cl.jac` files to call backend functions, NO quotes
- `import` — in `.cl.jac` for client-to-client or npm imports, WITH quotes
- `cl import from "@jac/runtime"` — runtime imports (auth, routing), WITH quotes

**Backend:** All backend code (nodes, endpoints, walkers) goes directly in `main.jac`. No separate backend files needed.

**Frontend imports (in .cl.jac files):** Use dots for relative paths (`.` = same dir, `..` = parent).
To call backend functions from frontend: `sv import from ..main { get_todos }` (dots count from file to main.jac, NO quotes).

**NEVER include file extensions in imports.** NEVER use `.cl`, `.jac`, or `.cl.jac` in import paths.
