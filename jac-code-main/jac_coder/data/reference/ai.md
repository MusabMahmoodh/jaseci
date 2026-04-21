
# AI Integration (by llm)

## 9. AI Integration (by llm)

```jac
# Simple — LLM infers from function name and types
def classify_sentiment(text: str) -> str by llm();

# ReAct agent with tools (passing tools auto-triggers ReAct)
def respond(message: str, chat_history: list[dict]) -> str by llm(
    messages=chat_history,
    tools=[read_file, search, bash_exec],
    incl_info={"reference": knowledge_base},
    max_react_iterations=10,
    temperature=0.2
);

# Chain-of-thought reasoning
def classify(message: str) -> str by llm(method="Reason", temperature=0.1);

# Semantic annotations — system prompt for by llm()
sem BuildHandler.respond = """You are an expert coding agent.
Use tools to read, write, and test code.""";

sem ReviewResult.is_approved = "True if content meets quality standards";  # Field-level
```

## 10. Library Mode (Interface/Implementation Split)

```jac
# module.jac — Declaration
node Router {
    def classify(message: str) -> str by llm(method="Reason");
}

def ensure_router() -> Router;

walker :pub interact {
    has message: str;
    can route with Router entry;
}
```

```jac
# impl/module.impl.jac — Implementation
sem Router.classify = """Return exactly one label: BUILD, PLAN, or EXPLORE.""";

impl ensure_router() -> Router {
    routers = [root-->][?:Router];
    if routers { return routers[0]; }
    router = Router();
    root ++> router;
    return router;
}

impl interact.route with Router entry {
    label = here.classify(message=self.message);
    if "BUILD" in label { visit [-->][?:BuildHandler]; }
    else { disengage; }
}
```
