# Client Rules — .cl.jac Quick Card

> Full reference: see build_rules.md Section 1

## Critical Reminders
- NEVER use `lambda` — define named `def handle_something()` ABOVE the return, pass by name
- NEVER put `def(...)` inline in JSX — `onClick={def(...)}` is WRONG. Extract to named function
- NEVER use `new` — use `Reflect.construct(ClassName, [args])`
- NEVER use `.map()` — use `{[<Item /> for item in items]}`
- NEVER use `useEffect` — use `can with entry { ... }`
- NEVER use `useState` — use `has x: type = default;`
- NEVER use JS syntax (`const`, `let`, `===`, `=>`, `` ` ` ``)
- NEVER use slashes in imports — use DOTS: `import from "..components.button" { Button }`
- NEVER combine import prefixes — `cl sv import` is WRONG

## Import Cheat Sheet — Dot Levels
```
.   = same directory          import from ".Header" { Header }
..  = 1 level up (parent)     import from "..hooks.useTodos" { useTodos }
... = 2 levels up             import from "...lib.utils" { cn }
```
```jac
import from ".TodoItem" { TodoItem }            # same dir .cl.jac (WITH quotes)
import from "..hooks.useTodos" { useTodos }     # parent dir (WITH quotes)
import from "...lib.utils" { cn }               # 2 levels up (WITH quotes)
sv import from ..main { get_todos }             # backend call (NO quotes)
import from "clsx" { cn }                      # npm package (WITH quotes)
cl import from "@jac/runtime" { Outlet }        # runtime (cl import, WITH quotes)
```

## Component Template
```jac
import from "..components.ui.button" { Button }
sv import from ..main { get_items, add_item }

def:pub ItemList() -> JsxElement {
    has items: list = [];
    has input_value: str = "";

    async can with entry {
        result = await get_items();
        items = result;
    }

    def handle_add() -> None {
        if input_value {
            await add_item(input_value);  # positional args only — kwargs broken in .cl.jac
            input_value = "";
            result = await get_items();
            items = result;
        }
    }

    def handle_input_change(e: any) -> None {
        input_value = e.target.value;
    }

    return <div>
        <input value={input_value}
            onChange={handle_input_change} />
        <Button onClick={handle_add}>Add</Button>
        {[<div key={item["id"]}>{item["title"]}</div> for item in items]}
    </div>;
}
```
