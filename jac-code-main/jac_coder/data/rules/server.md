# Server Rules — .jac Quick Card

> Full reference: see build_rules.md Section 2

## Critical Reminders
- ALL backend code goes in `main.jac` — do NOT split into separate files
- Use `def:pub` (public) or `def:priv` (per-user auth) for endpoints
- Return `dict` or `list` from endpoints — NOT nodes directly
- Nodes on `root` auto-persist (SQLite) — no DB setup needed
- Use `walker:pub` for complex graph traversal endpoints
- Client imports use `cl import` (no quotes) inside `cl {}` block
- NEVER use Reflect.construct in .jac — that's client-only

## Project Structure
```
project-root/
├── jac.toml            # config + deps
├── main.jac            # ALL backend: nodes + endpoints + app entry
├── components/         # .cl.jac components
├── hooks/              # .cl.jac hooks (sv import from ..main)
├── pages/              # .jac file-based routing
├── lib/                # .cl.jac utilities
└── styles/             # CSS
```

## Backend Template (main.jac)
```jac
import from datetime { datetime }

node Item {
    has title: str;
    has done: bool = False;
    has created_at: str = "";
}

def:pub get_items() -> list {
    return [{"id": str(i.id), "title": i.title, "done": i.done}
            for i in [root-->][?:Item]];
}

def:pub add_item(title: str) -> dict {
    item = (root ++> Item(title=title, created_at=str(datetime.now())))[0];
    return {"id": str(item.id), "title": item.title};
}

def:pub delete_item(item_id: str) -> dict {
    for i in [root-->][?:Item] {
        if str(i.id) == item_id {
            del i;
            return {"deleted": True};
        }
    }
    return {"deleted": False};
}

# App entry — serves frontend
cl import from .components.Layout { Layout }
cl {
    def:pub app() -> JsxElement { return <Layout />; }
}
```

## Node Operations
```jac
root ++> MyNode(field=value);                    # create + connect
nodes = [root-->][?:MyNode];                    # query all
node = [root-->][?:MyNode](?title == "x")[0];   # query with filter
del node;                                         # delete
```
