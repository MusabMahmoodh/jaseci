# OSP: Object-Spatial Programming

## 6. OSP: Nodes, Edges, Walkers

Object-Spatial Programming: nodes = data, walkers = computation, edges = relationships.

```jac
node Session {
    has id: str = "";
    has chat_history: list[dict] = [];

    def postinit { if not self.id { self.id = str(uuid4()); } }

    can process with interact entry {
        visitor.chat_history = self.chat_history;   # visitor = the walker
        visit [-->][?:Router];
    }
}

edge Knows { has since: int; has strength: float = 1.0; }

walker Collector {
    has items: list = [];
    can start with Root entry { visit [-->]; }
    can collect with DataNode entry {
        self.items.append(here.value);              # here = current node
        visit [-->];
    }
}

with entry { root spawn Collector(); }
```

**Context keywords:** `here` = current node (walker abilities), `visitor` = the walker (node abilities), `self` = archetype itself, `root` = graph root.

## 7. Graph Operations

```jac
a ++> b;                                           # Connect (directed)
alice +>: Knows(since=2020) :+> bob;              # Typed edge
new_node = here ++> Session(id="abc");            # Returns list — use [0]
root ++> Router() ++> BuildHandler();              # Chain

sessions = [-->][?:Session];                       # Query by type
active = [-->][?:Session](?status == "active");   # Query with condition
friends = [->:Knows:->];                          # Query by edge type
routers = [root-->][?:Session]-->[?:Router];       # Chained query

a del--> b;                                        # Delete edge
```

## 8. Walker Mechanics

```jac
visit [-->];                                       # Visit all outgoing
visit [-->][?:BuildHandler];                       # Visit by type
visit [<--][?:Router];                             # Back-traverse
visit [-->][?:Router] else {                       # Fallback
    router = here ++> Router();
    visit router;
}

result = root spawn my_walker(param=value);        # Spawn and get result
response = result.reports[0];                      # Access reported data

report {"response": response, "agent": "build"};  # Emit data
disengage;                                         # Stop walker entirely
```

**`disengage`** stops all traversal. **`return`** only exits current ability — walker continues to next node.
