# Frontend Components (.cl.jac)

## 16. Client-Side Components (.cl.jac)

Components are **public functions** returning `JsxElement`. State uses `has`. Effects use `can with entry/exit`. Lists use comprehensions, NOT `.map()`.

**CRITICAL — Read Section 15 (Runtime Gotchas) for rules that pass compilation but crash at runtime:**
- JS constructors (`Date`, `WebSocket`, `URL`, etc.) MUST use `Reflect.construct(ClassName, [args])` — never bare `ClassName()` and never `new ClassName()`
- Function names must not shadow browser globals (`open`, `close`, `print`, `fetch`, etc.)
- Numbers/booleans in JSX need `str()` conversion

### Complete Multi-File Example (demonstrates component separation)

Each component gets its own file. Layout.cl.jac is the root layout. Data logic lives in hooks. Child components handle their own rendering.

**components/Layout.cl.jac — Layout wrapper (minimal logic)**

```jac
import "..styles.global.css";
import from ".Header" { Header }
import from ".TodoList" { TodoList }

def:pub Layout() -> JsxElement {
    # State
    has theme: str = "light";

    # Effects
    can with (theme) entry {
        if theme == "dark" {
            document.documentElement.classList.add("dark");
        } else {
            document.documentElement.classList.remove("dark");
        }
    }

    # Handlers
    def handle_toggle_theme() -> None {
        theme = (theme == "dark") and "light" or "dark";
    }

    # Render
    return (
        <div className="min-h-screen bg-background text-text-primary">
            <Header title="My App" theme={theme} on_toggle_theme={handle_toggle_theme} />
            <main className="max-w-2xl mx-auto px-4 py-8">
                <TodoList />
            </main>
        </div>
    );
}
```

**components/Header.cl.jac — Nav/header bar**

```jac
def:pub Header(title: str, theme: str, on_toggle_theme: any) -> JsxElement {
    return (
        <header className="border-b border-border px-6 py-4 flex items-center justify-between">
            <h1 className="text-xl font-bold">{title}</h1>
            <button onClick={on_toggle_theme}
                className="px-3 py-1 bg-secondary text-secondary-foreground rounded-lg text-sm">
                {(theme == "dark") and "Light" or "Dark"}
            </button>
        </header>
    );
}
```

**hooks/useTodos.cl.jac — Data hook (sv import + state)**

```jac
sv import from ..main { get_todos, add_todo, delete_todo }

def:pub useTodos() -> dict {
    # State
    has items: list = [];
    has loading: bool = True;
    has error: str = "";

    # Fetch data on mount
    async can with entry {
        try {
            result = await get_todos();
            items = result or [];
        } except Exception as e {
            error = str(e);
        }
        loading = False;
    }

    # Handlers
    async def handleAdd(text: str) -> None {
        if not text { return; }
        result = await add_todo(text);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            items = items + [result];
        }
    }

    async def handleDelete(id: str) -> None {
        result = await delete_todo(id);  # positional args only — kwargs broken in .cl.jac
        if result and not result.error {
            items = [i for i in items if i["id"] != id];
        }
    }

    return {
        "items": items, "loading": loading, "error": error,
        "handleAdd": handleAdd, "handleDelete": handleDelete
    };
}
```

**components/TodoList.cl.jac — List + add form (calls hook)**

```jac
import from "..lib.utils" { cn }
import from "..hooks.useTodos" { useTodos }
import from ".TodoItem" { TodoItem }

def:pub TodoList() -> JsxElement {
    # Fetch data
    data = useTodos();
    items = data["items"] or [];

    # State
    has inputValue: str = "";

    # Handlers
    def handle_input_change(e: any) -> None {
        inputValue = e.target.value;
    }

    def handleAdd() -> None {
        if inputValue {
            data["handleAdd"](inputValue);
            inputValue = "";
        }
    }

    # Guard
    if data["loading"] {
        return <p className="text-text-secondary text-center py-8">Loading...</p>;
    }

    # Render
    return (
        <div className="p-4 bg-surface rounded-lg">
            {data["error"] and (
                <p className="text-error mb-4">{data["error"]}</p>
            )}
            <div className="flex gap-2 mb-4">
                <input
                    value={inputValue}
                    onChange={handle_input_change}
                    className="flex-1 px-3 py-2 border border-border rounded"
                />
                <button onClick={handleAdd} className="px-3 py-2 bg-primary text-primary-foreground rounded">
                    +
                </button>
            </div>
            {len(items) == 0 and (
                <p className="text-text-secondary">No items yet</p>
            )}
            {[
                <TodoItem key={item["id"]} item={item} on_delete={data["handleDelete"]} />
                for item in items
            ]}
        </div>
    );
}
```

**components/TodoItem.cl.jac — Single item display**

```jac
def:pub TodoItem(item: dict, on_delete: any) -> JsxElement {
    # Guard props
    itemId = item["id"] or "";
    text = item["title"] or "";

    # Handlers
    def handle_delete() -> None {
        on_delete(itemId);
    }

    # Render
    return (
        <div className="flex items-center justify-between p-2 border-b border-border">
            <span>{text}</span>
            <button onClick={handle_delete}>
                ×
            </button>
        </div>
    );
}
```

### Entry Point (main.jac)

```jac
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement {
        return <Layout />;
    }
}
```

### Import Rules

| Pattern | Example |
|---------|---------|
| Backend code location | All backend code goes in `main.jac` — no separate backend files |
| Sibling component (.cl.jac) | `import from .ComponentName { ComponentName }` |
| Nested component (.cl.jac) | `import from .ui.Button { Button }` |
| Parent directory (.cl.jac) | `import from "..hooks.useData" { useData }` |
| Two levels up (.cl.jac) | `import from "...lib.utils" { cn }` |
| Server import (.cl.jac) | `sv import from ..main { get_todos }` — dots count from file to main.jac |
| NPM package | `import from "clsx" { cn }` |
| CSS file | `import "..styles.global.css";` |
| NEVER extensions | `.cl`, `.jac`, `.cl.jac` are NEVER in import paths |

### Effects Reference

| Jac Pattern | React Equivalent |
|-------------|-----------------|
| `can with entry { ... }` | `useEffect(() => { ... }, [])` |
| `async can with entry { ... }` | `useEffect(() => { (async () => { ... })(); }, [])` |
| `can with [dep] entry { ... }` | `useEffect(() => { ... }, [dep])` |
| `can with (a, b) entry { ... }` | `useEffect(() => { ... }, [a, b])` |
| `can with exit { ... }` | `useEffect(() => { return () => { ... }; }, [])` |

**DO NOT use `useEffect(lambda...)`** — that is OLD syntax. Always use `can with entry/exit`.

### List Rendering & Operations

```jac
# Render lists — use list comprehension, NOT .map()
{[<ListItem key={item["id"]} data={item} /> for item in items]}

# With filter
{[<ListItem key={item["id"]} data={item} /> for item in items if item["active"]]}

# Add to list — use +, NOT .concat() or .append()
items = items + [newItem];

# Remove from list — use list comprehension, NOT .filter()
items = [item for item in items if item["id"] != targetId];

# Transform list
items = [{"id": item["id"], "done": True} for item in items];
```

**NEVER use `.map()`, `.concat()`, `.filter()`, `.append()` for state updates** — they either don't exist or mutate in place (no re-render).

### Primitive Idioms (Jac ≠ JavaScript)

In `.cl.jac` files, use **Jac/Python idioms**, not JavaScript equivalents. The compiler translates them automatically.

**Primitive functions (use these, NOT the JS equivalent):**

| JS Idiom (WRONG in Jac) | Jac Idiom (CORRECT) | Compiles To |
|---|---|---|
| `console.log(x)` | `print(x)` | `console.log(x)` |
| `String(x)` / `.toString()` | `str(x)` | `String(x)` |
| `parseInt(x)` | `int(x)` | `Math.trunc(Number(x))` |
| `parseFloat(x)` | `float(x)` | `parseFloat(x)` |
| `x.length` | `len(x)` | `.length` |

**String methods (fully supported in .cl.jac):**

| Jac Method | JS Equivalent |
|---|---|
| `.lower()` | `.toLowerCase()` |
| `.upper()` | `.toUpperCase()` |
| `.strip()` | `.trim()` |
| `.split(sep)` | `.split(sep)` |
| `.replace(old, new)` | `.replaceAll(old, new)` |
| `.startswith(prefix)` | `.startsWith(prefix)` |
| `.endswith(suffix)` | `.endsWith(suffix)` |
| `.find(sub)` | `.indexOf(sub)` |
| `.join(list)` | `.join(list)` |

```jac
# All of these work in .cl.jac
print("hello");
name = str(value);
count = len(items);
n = int("42");
lower_name = name.lower();
parts = text.split(",");
trimmed = raw_input.strip();
```

**State list updates — use `+` and comprehension, NOT `.append()`:**

`.append()` mutates in place — no re-render. Use `items = items + [x]` instead.

### Custom Hook

```jac
def:pub useCounter(props: dict) -> dict {
    has count: int = props.initial or 0;
    def increment() -> None { count = count + 1; }
    def decrement() -> None { count = count - 1; }
    return {"count": count, "increment": increment, "decrement": decrement};
}
```

### Calling Backend Walkers

```jac
async def handleFetch() -> None {
    result = my_walker(param=value) spawn root;
    if result and result.reports and len(result.reports) > 0 {
        data = result.reports[0];
    }
}
```

### Conditional Rendering

```jac
{showSidebar and (<Sidebar items={items} />)}
{isActive and (<ActiveView />) or (<InactiveView />)}
{(not loading) and (<Content />)}
{[<ListItem key={item["id"]} data={item} /> for item in items]}
```

### Inline Styles

```jac
<div style={{"display": "flex", "gap": "8px", "backgroundColor": "#f0f0f0"}} />
```

## 17. Common Patterns

### Graph CRUD — nodes as data models

```jac
# Create and connect to root (auto-persists)
node Product {
    has id: str;
    has name: str;
    has price: float;
    has category: str = "";
}

def:pub add_product(name: str, price: float, category: str = "") -> dict {
    import from uuid {uuid4}
    product = root ++> Product(id=str(uuid4()), name=name, price=price, category=category);
    return {"id": product.id, "name": product.name, "price": product.price};
}

# Query with filter
def:pub get_products(category: str = "") -> list {
    all_products = [root-->][?:Product];
    if category {
        return [{"id": p.id, "name": p.name, "price": p.price}
                for p in all_products if p.category == category];
    }
    return [{"id": p.id, "name": p.name, "price": p.price} for p in all_products];
}

# Delete by ID
def:pub delete_product(product_id: str) -> dict {
    for p in [root-->][?:Product] {
        if p.id == product_id {
            root del--> p;
            return {"success": True};
        }
    }
    return {"success": False, "error": "Not found"};
}
```

### Related nodes — parent-child relationships

```jac
node Category { has name: str; }
node Item { has title: str; has done: bool = False; }

# Create hierarchy: root -> Category -> Item
def:pub add_category(name: str) -> dict {
    cat = root ++> Category(name=name);
    return {"name": cat.name};
}

def:pub add_item_to_category(category_name: str, title: str) -> dict {
    for cat in [root-->][?:Category] {
        if cat.name == category_name {
            item = cat ++> Item(title=title);
            return {"title": item.title, "category": cat.name};
        }
    }
    return {"error": "Category not found"};
}

def:pub get_items_by_category(category_name: str) -> list {
    for cat in [root-->][?:Category] {
        if cat.name == category_name {
            return [{"title": i.title, "done": i.done} for i in [cat-->][?:Item]];
        }
    }
    return [];
}
```

### Lazy graph creation

```jac
visit [-->][?:Router] else {
    router = (here ++> Router())[0];
    visit router;
}
```

### Walker with multi-node traversal

```jac
walker :pub get_order_details {
    has order_id: str;
    obj __specs__ { static has methods: list = ["post"]; }

    can find_order with Root entry {
        for order in [-->][?:Order] {
            if order.id == self.order_id {
                visit order;
                return;
            }
        }
        report {"error": "Order not found"};
    }

    can collect_items with Order entry {
        items = [{"name": i.name, "qty": i.qty, "price": i.price}
                 for i in [-->][?:OrderItem]];
        report {
            "order_id": here.id,
            "status": here.status,
            "items": items,
            "total": here.total
        };
    }
}
```

### Advanced: LLM-driven graph traversal (for AI agents)

```jac
# LLM picks which child node to visit based on context
can route with Router entry {
    visit [-->] by llm(
        incl_info={"message": self.message, "context": self.context}
    );
}

# Supervisor loop (multi-agent routing)
impl interact.route with Router entry {
    label = here.classify(message=self.message, context=self.context);
    if "DONE" in label { disengage; }
    else { visit [-->][?:Handler]; }
}
```
