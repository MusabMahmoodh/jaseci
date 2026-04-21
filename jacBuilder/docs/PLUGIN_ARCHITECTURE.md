# Jac Builder Plugin System — Architecture Document

## 1. Vision

Jac Builder's plugin system follows the principle: **if the two hardest plugins work, any plugin works**.

The two default plugins are:
- **jaseci.jac-coder** — AI coding agent (subprocess management, streaming events, file operations, model switching, session persistence)
- **jaseci.jaclang** — Language intelligence (LSP subprocess, Monaco providers, formatting, diagnostics, graph visualization)

These capabilities are currently hardwired into jac-ide's core. We **rebuild** them as Jac plugins — not by moving existing code, but by writing new plugin implementations in Jac that use the same underlying tools (`jac-coder-server`, `jac lsp`) via the same protocols the VS Code extensions use (JSON-RPC over subprocess stdin/stdout). The VS Code extension source code (`vscode-jac-coder-main/`, `jac-vscode-main/`) serves as the **specification** for what the plugins must do.

By rebuilding as plugins, we:
1. **Reduce core complexity** — `main.jac` becomes a thin shell + plugin loader
2. **Prove the plugin API** — if it handles streaming AI + LSP subprocesses, it handles anything
3. **Enable an ecosystem** — third-party developers build Jac Builder plugins in Jac, following the same patterns as the two default plugins
4. **Gain missing features** — the VS Code extensions have 13+ capabilities (permission mode, plan mode, inline diffs, slash commands, image paste, token tracking, MCP management, etc.) that the current hardwired code does not

## 2. Plugin Format

A plugin is a **folder** containing a manifest + Jac source files:

```
~/.jac-ide/plugins/jaseci.jac-coder/
├── plugin.json              # Manifest — declares capabilities
├── plugin.jac               # Backend entry point
├── plugin.cl.jac            # Frontend entry point (optional)
├── services/                # Backend service modules
│   └── jaccoder_adapter.jac
├── views/                   # Frontend components
│   └── ChatPanel.cl.jac
├── hooks/                   # Frontend hooks
│   └── useChatMode.cl.jac
└── assets/                  # Icons, grammars, static files
    └── icon.svg
```

### 2.1 Plugin Manifest (`plugin.json`)

```json
{
  "$schema": "https://jac-builder.jaseci.org/schemas/plugin-v1.json",
  "id": "jaseci.jac-coder",
  "name": "JacCoder",
  "version": "0.1.7",
  "description": "AI coding agent for Jac — code generation, error fixing, and refactoring",
  "author": {
    "name": "Jaseci Labs",
    "url": "https://jaseci.org"
  },
  "icon": "assets/icon.svg",
  "license": "MIT",
  "engine": ">=1.0.0",

  "activationEvents": ["onStartup"],

  "backend": "plugin.jac",
  "frontend": "plugin.cl.jac",

  "contributes": {
    "sidebarViews": [...],
    "commands": [...],
    "statusBarItems": [...],
    "settings": [...],
    "walkers": [...],
    "editorProviders": [...],
    "cleanupHooks": [...]
  },

  "dependencies": {
    "python": ["jac-coder>=0.1.7"],
    "plugins": []
  }
}
```

**Manifest fields explained:**

| Field | Type | Purpose |
|-------|------|---------|
| `id` | string | Unique reverse-domain identifier (e.g., `jaseci.jac-coder`) |
| `name` | string | Human-readable display name |
| `version` | semver | Plugin version |
| `engine` | semver range | Required Jac Builder version |
| `activationEvents` | string[] | When to activate (see §3.4) |
| `backend` | string | Relative path to backend entry .jac file |
| `frontend` | string | Relative path to frontend entry .cl.jac file (optional) |
| `contributes` | object | Static capability declarations (see §2.2) |
| `dependencies.python` | string[] | pip packages to install in plugin venv |
| `dependencies.plugins` | string[] | Other plugins this depends on |

### 2.2 Contribution Points

Each contribution point is declared statically in the manifest and registered dynamically at activation.

#### `sidebarViews` — Sidebar Panels

```json
{
  "sidebarViews": [
    {
      "id": "jac-coder-chat",
      "label": "AI Chat",
      "icon": "Message01Icon",
      "shortcut": "Ctrl+Shift+A",
      "component": "views/ChatPanel.cl.jac",
      "position": "top",
      "order": 4
    }
  ]
}
```

| Field | Purpose |
|-------|---------|
| `id` | Unique view ID (used as `activeSidebarView` value) |
| `label` | ActivityBar tooltip text |
| `icon` | HugeIcons icon name (from `@hugeicons/core-free-icons`) |
| `shortcut` | Keyboard shortcut string |
| `component` | Relative path to the .cl.jac component file |
| `position` | `"top"` or `"bottom"` in ActivityBar |
| `order` | Sort order within position group |

The component receives an `ide` prop — the same IDE context object that built-in panels receive today.

#### `commands` — Command Palette Entries

```json
{
  "commands": [
    {
      "id": "jaccoder.newSession",
      "label": "New AI Chat Session",
      "category": "AI",
      "icon": "Message01Icon",
      "keybinding": "Ctrl+Shift+N"
    },
    {
      "id": "jaccoder.explainCode",
      "label": "Explain Selected Code",
      "category": "AI",
      "when": "hasSelection"
    },
    {
      "id": "jaccoder.fixError",
      "label": "Fix Error with AI",
      "category": "AI"
    }
  ]
}
```

Commands are shown in the CommandPalette. The `when` field supports conditions: `hasSelection`, `hasProject`, `isPreviewRunning`, `hasActiveTab`.

#### `statusBarItems` — Status Bar Indicators

```json
{
  "statusBarItems": [
    {
      "id": "jaccoder.model",
      "position": "right",
      "priority": 100
    }
  ]
}
```

The frontend plugin entry exports a renderer function for each status bar item (see §4.2).

#### `settings` — Plugin Configuration

```json
{
  "settings": [
    {
      "key": "aiModel",
      "type": "select",
      "label": "AI Model",
      "description": "Default model for code generation",
      "default": "gpt-5.4",
      "options": [
        {"value": "gpt-5.4", "label": "GPT 5.4"},
        {"value": "gpt-5.2", "label": "GPT 5.2"},
        {"value": "claude-opus-4-6", "label": "Claude Opus 4.6"},
        {"value": "claude-sonnet-4-6", "label": "Claude Sonnet 4.6"}
      ]
    },
    {
      "key": "editMode",
      "type": "select",
      "label": "Edit Mode",
      "default": "auto",
      "options": ["auto", "ask", "plan"]
    },
    {
      "key": "autoStart",
      "type": "boolean",
      "label": "Auto-start on activation",
      "default": true
    }
  ]
}
```

Settings are stored per-user in the graph as a `PluginSettings` node (see §5).

#### `walkers` — Backend API Endpoints

```json
{
  "walkers": ["ai_chat", "ai_events"]
}
```

Walker names declared here are registered as `POST /walker/{name}` endpoints. The actual walker definitions live in the backend entry point or imported service files.

#### `editorProviders` — Monaco Editor Extensions

```json
{
  "editorProviders": [
    {"type": "completion", "languages": ["jac"]},
    {"type": "hover", "languages": ["jac"]},
    {"type": "definition", "languages": ["jac"]},
    {"type": "references", "languages": ["jac"]},
    {"type": "rename", "languages": ["jac"]},
    {"type": "formatting", "languages": ["jac"]},
    {"type": "semanticTokens", "languages": ["jac"]},
    {"type": "diagnostics", "languages": ["jac"]}
  ]
}
```

Provider types map directly to Monaco API registrations. The frontend plugin entry exports provider factory functions (see §4.2).

#### `cleanupHooks` — Lifecycle Events

```json
{
  "cleanupHooks": ["onSessionEnd", "onProjectClose"]
}
```

| Event | Trigger |
|-------|---------|
| `onSessionEnd` | User session TTL expires or user logs out |
| `onProjectClose` | User switches away from a project |
| `onDeactivate` | Plugin is disabled or uninstalled |

---

## 3. Backend Plugin API — Handler-Based Architecture (Direction C)

### 3.0 Why Handlers, Not Walkers

Deep research into the Jac runtime revealed critical constraints:

1. **Walker registration is compile-time only.** `ModuleIntrospector` collects walkers via `inspect.getmembers()` at startup. No runtime API. Adding plugin walkers requires generated imports + server restart.
2. **All nodes share one graph per user.** Plugin nodes and core nodes live under the same Root. Untyped traversal can corrupt across boundaries.
3. **Walker name collisions are silent.** Two walkers with the same name → last import wins silently.
4. **Node types are safe.** Typed filters use class identity, not string names.
5. **`walker:pub` runs from guest root**, not global root.

**The solution: plugins don't define walkers at all.** Instead, the core defines two dispatcher walkers (`plugin_dispatch` for HTTP, `plugin_stream` for WebSocket). Plugins register **handler functions** at runtime via `activate()`. This solves all five problems:

| Problem | Walker-based (old) | Handler-based (Direction C) |
|---------|-------------------|---------------------------|
| Registration | Compile-time, needs restart | Runtime `register_handler()`, no restart |
| Name collisions | Silent shadowing | Namespaced: `{plugin_id}::{action}` |
| Graph isolation | Convention (PluginRoot) | **Enforced** — handler receives `PluginRoot`, never `Root` |
| Import generation | Must generate `_plugin_imports.jac` | Not needed — handlers are dict entries |
| Adding new actions | New walker per action | `register_handler("new_action", fn)` |

### 3.1 Core Dispatcher Walkers

The core defines exactly **two** walkers that handle all plugin requests:

```jac
"""In services/ideServer.jac — core walkers, never changes."""

# --- HTTP dispatcher (JWT-authenticated) ---
walker plugin_dispatch {
    has plugin_id: str = "",
        action: str = "",
        project_id: str = "",
        data: dict = {};

    can start with Root entry {
        user_id = _get_user_id();
        if not user_id {
            report {"success": False, "error": "Not authenticated"};
            return;
        }

        # Look up the handler
        handler_key = self.plugin_id + "::" + self.action;
        handler = _plugin_handlers.get(handler_key);
        if not handler {
            report {"success": False, "error": f"Unknown plugin action: {handler_key}"};
            return;
        }

        # Get plugin's isolated graph root (enforced, not convention)
        plugin_root = _get_or_create_plugin_root(user_id, self.plugin_id);

        # Build scoped context for this request
        req_ctx = PluginRequestContext(
            plugin_id=self.plugin_id,
            user_id=user_id,
            project_id=self.project_id,
            plugin_root=plugin_root,
            data=self.data
        );

        # Call the handler — wrapped in try/except so a crashing plugin
        # returns an error response instead of killing the server
        try {
            result = handler(req_ctx);
            report result;
        } except Exception as e {
            print(f"[plugin_dispatch] Plugin {self.plugin_id} action {self.action} failed: {e}");
            report {"success": False, "error": f"Plugin error: {str(e)}"};
        }
    }
}

# --- WebSocket dispatcher (for streaming events) ---
@restspec(protocol=APIProtocol.WEBSOCKET)
async walker plugin_stream {
    has plugin_id: str = "",
        action: str = "",
        project_id: str = "",
        data: dict = {},
        connection_id: str = "",
        request_id: str = "",
        user_id: str = "";

    async can handle with Root entry {
        user_id = self.user_id or _get_user_id_from_profile();
        if not user_id {
            report {"type": "error", "request_id": self.request_id,
                    "data": {"success": False, "error": "User not identified"}};
            return;
        }

        touch_session(user_id, self.project_id);

        # Look up handler
        handler_key = self.plugin_id + "::" + self.action;
        handler = _plugin_stream_handlers.get(handler_key);
        if not handler {
            report {"type": "error", "request_id": self.request_id,
                    "data": {"success": False, "error": f"Unknown stream action: {handler_key}"}};
            return;
        }

        plugin_root = _get_or_create_plugin_root(user_id, self.plugin_id);

        req_ctx = PluginRequestContext(
            plugin_id=self.plugin_id,
            user_id=user_id,
            project_id=self.project_id,
            plugin_root=plugin_root,
            data=self.data,
            connection_id=self.connection_id,
            request_id=self.request_id
        );

        try {
            result = handler(req_ctx);
            report {"type": self.action, "request_id": self.request_id, "data": result};
        } except Exception as e {
            report {"type": "error", "request_id": self.request_id,
                    "data": {"success": False, "error": str(e)}};
        }
    }
}
```

**Frontend calls look like:**
```
HTTP:      POST /walker/plugin_dispatch
           {plugin_id: "jaseci.jac-coder", action: "chat", project_id: "...", data: {...}}

WebSocket: /walker/plugin_stream
           {plugin_id: "jaseci.jac-coder", action: "poll_events", project_id: "...",
            connection_id: "...", request_id: "..."}
```

### 3.2 Plugin Context

When a plugin activates, it receives a `PluginContext`. The key method is `register_handler()` — this is how plugins define their API.

```jac
"""Plugin API — provided by jac-ide core to each plugin."""

obj PluginContext {
    has plugin_id: str,
        plugin_dir: str;

    # --- Handler registration (the core plugin mechanism) ---
    can register_handler(action: str, fn: Callable) -> None;
    """Register an HTTP handler. Called via POST /walker/plugin_dispatch
    with {plugin_id, action, data}. The fn receives PluginRequestContext."""

    can register_stream_handler(action: str, fn: Callable) -> None;
    """Register a WebSocket handler. Called via /walker/plugin_stream.
    Used for event polling, streaming, real-time updates."""

    # --- Session & lifecycle ---
    can register_cleanup(name: str, fn: Callable) -> None;

    # --- Event streaming ---
    can get_event_bus(user_id: str, project_id: str) -> EventBus;
    can create_event_bus(key: str) -> EventBus;

    # --- File access ---
    can get_project_path(user_id: str, project_id: str) -> str;
    can get_preview_path(user_id: str, project_id: str) -> str;
    can write_file(user_id: str, project_id: str, path: str, content: str) -> bool;
    can read_file(user_id: str, project_id: str, path: str) -> str;

    # --- Preview integration ---
    can get_preview_status(user_id: str, project_id: str) -> str;
    can get_preview_url(user_id: str, project_id: str) -> str;
    can restart_preview(user_id: str, project_id: str) -> None;

    # --- Settings ---
    can get_setting(user_id: str, key: str) -> Any;
    can set_setting(user_id: str, key: str, value: Any) -> None;
    can get_all_settings(user_id: str) -> dict;

    # --- Subprocess management ---
    can spawn_process(cmd: list, cwd: str, env: dict = {}) -> ProcessHandle;
    can get_process(key: str) -> ProcessHandle;

    # --- Inter-plugin calls ---
    can call_plugin(target_plugin_id: str, action: str, data: dict) -> dict;
    """Call another plugin's handler. E.g., jac-coder calls jaclang's jac_check."""

    # --- Logging ---
    can log(level: str, message: str) -> None;
}

obj PluginRequestContext {
    """Passed to every handler invocation. Scoped to one request."""
    has plugin_id: str,
        user_id: str,
        project_id: str,
        plugin_root: Any,      # This plugin's PluginRoot node (isolated graph)
        data: dict,            # Request payload
        connection_id: str = "",   # For stream handlers
        request_id: str = "";      # For stream handlers
}

obj ProcessHandle {
    has pid: int,
        stdin: Any,
        stdout: Any,
        stderr: Any,
        key: str;

    can send(data: str) -> None;
    can read_line() -> str;
    can kill() -> None;
    can is_alive() -> bool;
}
```

### 3.3 Backend Entry Point — JacCoder Plugin

```jac
"""plugin.jac — JacCoder plugin. No walkers — only handler functions."""

import subprocess;
import json;
import threading;

glob _ctx: Any = None;
glob _processes: dict = {};
glob _rpc_id: int = 0;

can activate(ctx: PluginContext) -> None {
    glob _ctx = ctx;

    # Register HTTP handlers (each becomes an action on plugin_dispatch)
    ctx.register_handler("chat", handle_chat);
    ctx.register_handler("cancel", handle_cancel);
    ctx.register_handler("session_create", handle_session_create);
    ctx.register_handler("session_list", handle_session_list);
    ctx.register_handler("session_close", handle_session_close);
    ctx.register_handler("model_get", handle_model_get);
    ctx.register_handler("model_set", handle_model_set);
    ctx.register_handler("permission_respond", handle_permission);
    ctx.register_handler("mcp_add", handle_mcp_add);
    ctx.register_handler("mcp_list", handle_mcp_list);
    ctx.register_handler("mcp_delete", handle_mcp_delete);

    # Register WebSocket handlers (for event streaming)
    ctx.register_stream_handler("poll_events", handle_poll_events);

    # Register cleanup
    ctx.register_cleanup("jaccoder", _on_session_end);

    ctx.log("info", "JacCoder plugin activated");
}

can deactivate() -> None {
    for key in list(_processes.keys()) {
        proc = _processes.pop(key, None);
        if proc { proc.kill(); }
    }
}

# --- Handler functions (receive PluginRequestContext, return dict) ---

can handle_chat(req: PluginRequestContext) -> dict {
    key = req.user_id + "::" + req.project_id;

    # Ensure server is running
    if key not in _processes {
        _start_server(req.user_id, req.project_id);
    }

    # Send JSON-RPC chat request
    _send_rpc(key, "chat", {
        "session_id": _get_session(req.plugin_root, req.project_id),
        "message": req.data.get("message", ""),
        "edit_mode": req.data.get("edit_mode", "auto"),
        "images": req.data.get("images", [])
    });

    return {"success": True, "status": "started"};
}

can handle_poll_events(req: PluginRequestContext) -> dict {
    """WebSocket handler — drain events from EventBus."""
    bus = _ctx.get_event_bus(req.user_id, req.project_id);
    events = bus.drain(req.connection_id);
    processing = key_in_processes(req.user_id, req.project_id);
    return {"success": True, "events": events, "processing": processing};
}

can handle_model_set(req: PluginRequestContext) -> dict {
    key = req.user_id + "::" + req.project_id;
    _send_rpc(key, "model.set", {"model": req.data.get("model", "")});
    return {"success": True};
}

can handle_cancel(req: PluginRequestContext) -> dict {
    key = req.user_id + "::" + req.project_id;
    _send_rpc_notify(key, "chat.cancel", {"session_id": req.data.get("session_id", "")});
    return {"success": True};
}

can handle_permission(req: PluginRequestContext) -> dict {
    key = req.user_id + "::" + req.project_id;
    _send_rpc_notify(key, "permission.response", {
        "session_id": req.data.get("session_id", ""),
        "decision": req.data.get("decision", "deny")
    });
    return {"success": True};
}

# ... more handlers for session_create, session_list, mcp_*, etc.

# --- Internal: subprocess management ---

can _start_server(user_id: str, project_id: str) -> None {
    key = user_id + "::" + project_id;
    workspace = _ctx.get_project_path(user_id, project_id);
    settings = _ctx.get_all_settings(user_id);

    env = dict(os.environ);
    if settings.get("openaiKey") { env["OPENAI_API_KEY"] = settings["openaiKey"]; }
    if settings.get("anthropicKey") { env["ANTHROPIC_API_KEY"] = settings["anthropicKey"]; }

    proc = subprocess.Popen(
        ["jac-coder-server"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        cwd=workspace, env=env
    );
    _processes[key] = proc;

    # Background thread reads stdout → publishes to EventBus
    bus = _ctx.get_event_bus(user_id, project_id);
    t = threading.Thread(target=_read_stdout, args=(key, proc, bus), daemon=True);
    t.start();

can _read_stdout(key: str, proc: Any, bus: EventBus) -> None {
    for line in proc.stdout {
        try {
            msg = json.loads(line.strip());
            if msg.get("method") == "chat.event" {
                bus.publish(msg["params"]);
            }
        } except Exception { ; }
    }
}

can _on_session_end(user_id: str, project_id: str) -> None {
    key = user_id + "::" + project_id;
    proc = _processes.pop(key, None);
    if proc { proc.kill(); }
}
```

**Key difference from old architecture:**
- **Zero walkers** in plugin code. No `walker jaccoder_ai_chat { ... }`.
- 11 HTTP handlers + 1 WebSocket handler, all registered at runtime.
- No import generation, no restart, no name collisions.
- Each handler receives `PluginRequestContext` with `plugin_root` (graph isolation enforced).
- Error isolation: dispatcher wraps each handler call in try/except.

### 3.4 Backend Entry Point — JacLang Plugin

```jac
"""plugin.jac — JacLang plugin. LSP subprocess + handlers."""

glob _ctx: Any = None;
glob _lsp_registry: dict = {};

can activate(ctx: PluginContext) -> None {
    glob _ctx = ctx;

    # HTTP handlers
    ctx.register_handler("start_lsp", handle_start_lsp);
    ctx.register_handler("stop_lsp", handle_stop_lsp);
    ctx.register_handler("restart_lsp", handle_restart_lsp);
    ctx.register_handler("graph_snapshot", handle_graph_snapshot);

    # WebSocket handlers (for LSP message passing)
    ctx.register_stream_handler("lsp_init", handle_lsp_init);
    ctx.register_stream_handler("lsp_message", handle_lsp_message);
    ctx.register_stream_handler("lsp_poll", handle_lsp_poll);

    ctx.register_cleanup("jaclang", _on_session_end);
    ctx.log("info", "JacLang plugin activated");
}

can handle_start_lsp(req: PluginRequestContext) -> dict {
    key = req.user_id + "::" + req.project_id;
    if key in _lsp_registry {
        return {"success": True, "status": "already_running"};
    }

    workspace = _ctx.get_preview_path(req.user_id, req.project_id);
    handle = _ctx.spawn_process(cmd=["jac", "lsp"], cwd=workspace);

    _lsp_registry[key] = {
        "handle": handle,
        "workspace": workspace,
        "outbox": collections.deque(maxlen=1000)
    };

    t = threading.Thread(target=_lsp_reader, args=(key,), daemon=True);
    t.start();

    return {"success": True, "status": "started"};
}

can handle_lsp_message(req: PluginRequestContext) -> dict {
    """WebSocket handler — send LSP request, return response."""
    key = req.user_id + "::" + req.project_id;
    entry = _lsp_registry.get(key);
    if not entry { return {"success": False, "error": "LSP not running"}; }

    # Send JSON-RPC to jac lsp stdin
    _send_lsp(entry, req.data);
    return {"success": True};
}

can handle_lsp_poll(req: PluginRequestContext) -> dict {
    """WebSocket handler — drain LSP notifications."""
    key = req.user_id + "::" + req.project_id;
    entry = _lsp_registry.get(key);
    if not entry { return {"success": True, "notifications": []}; }
    notifications = list(entry["outbox"]);
    entry["outbox"].clear();
    return {"success": True, "notifications": notifications};
}

can handle_graph_snapshot(req: PluginRequestContext) -> dict {
    """Return the user's graph as vis-network compatible JSON."""
    try {
        pg = __import__("jaclang.runtimelib.builtin", fromlist=["printgraph"]);
        data = pg.printgraph(format="json");
        return {"success": True, "graph": data};
    } except Exception as e {
        return {"success": False, "error": str(e)};
    }
}

can _on_session_end(user_id: str, project_id: str) -> None {
    key = user_id + "::" + project_id;
    entry = _lsp_registry.pop(key, None);
    if entry { entry["handle"].kill(); }
}
```

### 3.5 Inter-Plugin Communication

Plugins can call other plugins' handlers via `ctx.call_plugin()`:

```jac
# In jac-coder plugin: run jac check via jaclang plugin
can handle_validate(req: PluginRequestContext) -> dict {
    result = _ctx.call_plugin("jaseci.jaclang", "jac_check", {
        "file": "main.jac",
        "project_id": req.project_id
    });
    return result;
}
```

Internally, `call_plugin()` looks up the handler in `_plugin_handlers` and calls it directly — same-process function call, no HTTP overhead.

### 3.6 Activation Events

Plugins declare when they should activate:

| Event | Trigger | Example Use |
|-------|---------|-------------|
| `onStartup` | IDE server starts | jac-coder, jaclang (always needed) |
| `onProject` | User opens a project | Deploy plugins |
| `onFileOpen:<pattern>` | File matching glob opened | `.sql` → DB explorer plugin |
| `onCommand:<id>` | Command invoked | Lazy-loaded plugins |
| `onWalker:<name>` | Walker endpoint called | API-triggered plugins |

For the initial version, `onStartup` is sufficient. Lazy activation can be added later.

---

## 4. Frontend Plugin API

### 4.1 Frontend Entry Point Pattern

```jac
"""plugin.cl.jac — JacCoder plugin frontend entry point."""

import from ./views/ChatPanel { ChatPanel }
import from ./hooks/useChatMode { useChatMode }

# --- Sidebar view components ---
# Exported and referenced by id in plugin.json sidebarViews[].component

def:pub views() -> dict {
    return {
        "jac-coder-chat": ChatPanel
    };
}

# --- Command handlers ---
# Keyed by command id from plugin.json

def:pub commands() -> dict {
    return {
        "jaccoder.newSession": lambda(ctx: Any) {
            ctx.sendMessage("New session", True);
        },
        "jaccoder.explainCode": lambda(ctx: Any) {
            selection = ctx.getSelection();
            if selection {
                ctx.sendMessage("Explain this code: " + selection, False);
            }
        },
        "jaccoder.fixError": lambda(ctx: Any) {
            errors = ctx.getPreviewErrors();
            if errors {
                ctx.sendMessage("Fix these errors: " + errors.join(String.fromCharCode(10)), False);
            }
        }
    };
}

# --- Status bar item renderers ---
# Keyed by statusBarItem id from plugin.json

def:pub statusBarItems() -> dict {
    return {
        "jaccoder.model": lambda(ctx: Any) -> Any {
            model = ctx.getSetting("aiModel") or "gpt-5.4";
            isProcessing = ctx.isPluginActive();
            return {
                "text": ("AI: " + model),
                "icon": "Message01Icon",
                "color": ("success" if isProcessing else "muted"),
                "onClick": lambda { ctx.openSettings(); }
            };
        }
    };
}
```

### 4.2 Frontend Plugin Context

The host passes a context object to each plugin view component and command handler:

```jac
"""Plugin client context — provided to all frontend plugin components."""

obj PluginClientContext {
    # --- IDE state (read-only) ---
    has userId: str,
        projectId: str,
        activeFile: str,
        fileList: list,
        previewStatus: str,
        previewUrl: str;

    # --- Editor access ---
    can getSelection() -> str;         # Current editor selection text
    can getActiveFileContent() -> str;  # Full content of active file
    can openFile(path: str) -> None;    # Open file in editor tab
    can insertText(text: str) -> None;  # Insert at cursor

    # --- Preview ---
    can getPreviewErrors() -> list;     # Current preview error lines
    can restartPreview() -> None;

    # --- Plugin settings ---
    can getSetting(key: str) -> Any;
    can setSetting(key: str, value: Any) -> None;
    can openSettings() -> None;         # Open plugin settings panel

    # --- Events (bridges to backend EventBus) ---
    can subscribe(eventType: str, handler: Callable) -> None;
    can unsubscribe(eventType: str) -> None;

    # --- API calls ---
    can callWalker(name: str, data: dict) -> Promise;  # POST /walker/{name}

    # --- Notifications ---
    can notify(title: str, message: str, color: str) -> None;  # Toast

    # --- Plugin state ---
    can isPluginActive() -> bool;
    can sendMessage(msg: str, newSession: bool) -> None;  # For AI plugins
}
```

### 4.3 How the Host Loads Plugin UI

**Build time** (default plugins): Plugin `.cl.jac` components are imported and compiled alongside the main app. The plugin loader generates a registry module:

```jac
"""auto-generated: _plugin_registry.cl.jac"""

import from "~/.jac-ide/plugins/jaseci.jac-coder/plugin.cl" {
    views as jaccoder_views,
    commands as jaccoder_commands,
    statusBarItems as jaccoder_statusbar
}
import from "~/.jac-ide/plugins/jaseci.jaclang/plugin.cl" {
    views as jaclang_views,
    commands as jaclang_commands,
    statusBarItems as jaclang_statusbar
}

glob _plugin_views: dict = {};
glob _plugin_commands: dict = {};
glob _plugin_statusbar: dict = {};

def init_plugin_registry() -> None {
    # Merge all plugin contributions
    _plugin_views.update(jaccoder_views());
    _plugin_views.update(jaclang_views());
    _plugin_commands.update(jaccoder_commands());
    _plugin_commands.update(jaclang_commands());
    _plugin_statusbar.update(jaccoder_statusbar());
    _plugin_statusbar.update(jaclang_statusbar());
}
```

**ActivityBar becomes data-driven:**

```jac
# ActivityBar.cl.jac — reads from plugin registry + core items

def:pub ActivityBar(props: Any) -> Any {
    pluginViews = props.pluginViews or [];

    # Core items that are always present
    coreItems = [
        {"id": "files", "icon": CodesandboxIcon, "label": "Explorer",
         "shortcut": "Ctrl+Shift+E"}
    ];

    # Plugin-contributed items (from plugin.json sidebarViews)
    allItems = coreItems ++ pluginViews;

    return <div className="...">
        {allItems.map(lambda(item: Any) -> Any {
            # ... render each item (same as today)
        })}
    </div>;
}
```

**Sidebar dispatch becomes registry-based:**

```jac
# JacIDE.cl.jac — sidebar view rendering

# Instead of hardcoded if/elif:
#   {activeSidebarView == "chat" and <ChatPanel ... />}
#   {activeSidebarView == "git" and <GitPanel ... />}
#
# Becomes:

# Core views (always available, not plugins)
coreViews = {
    "files": lambda(p: Any) -> Any { return <FileTree {...p} />; },
    "search": lambda(p: Any) -> Any { return <SearchPanel {...p} />; },
    "git": lambda(p: Any) -> Any { return <GitPanel {...p} />; },
    "run": lambda(p: Any) -> Any { return <RunPanel {...p} />; },
    "export": lambda(p: Any) -> Any { return <ExportPanel {...p} />; },
    "settings": lambda(p: Any) -> Any { return <SettingsPanel {...p} />; }
};

# Merge with plugin views
allViews = Object.assign({}, coreViews, pluginRegistry.getViews());

# Render active view
viewRenderer = allViews[activeSidebarView];
if viewRenderer {
    viewRenderer.call(None, viewProps);
}
```

**CommandPalette becomes extensible:**

```jac
# CommandPalette.cl.jac — merges core + plugin commands

pluginCommands = pluginRegistry.getCommands();

# In the JSX:
{pluginCommands.length > 0 and <CommandGroup heading="Plugins">
    {pluginCommands.map(lambda(cmd: Any) -> Any {
        return <CommandItem key={cmd.id}
            onSelect={lambda { runAction(lambda { cmd.handler(pluginCtx); }); }}>
            <HugeiconsIcon icon={cmd.icon} strokeWidth={2} className="size-4 mr-2" />
            <span>{cmd.label}</span>
        </CommandItem>;
    })}
</CommandGroup> or None}
```

---

## 5. Plugin Settings, State & Graph Isolation

### 5.1 Graph Model

Each plugin gets two types of nodes on the user root:
- **`PluginRoot`** — namespace node for plugin-specific data (sessions, messages, etc.)
- **`PluginSettings`** — configuration node (settings, enabled flag)

```
user_root
    → UserProfile                              (jac-builder core)
    → Project                                  (jac-builder core)
    → PluginRoot(plugin_id="jaseci.jac-coder") (plugin namespace)
    │   → JacCoderSession                      (plugin data — isolated)
    │   → JacCoderMessage
    → PluginRoot(plugin_id="jaseci.jaclang")   (plugin namespace)
    │   → LSPState
    → PluginSettings(plugin_id="jaseci.jac-coder")  (settings)
    → PluginSettings(plugin_id="jaseci.jaclang")     (settings)
```

```jac
node PluginRoot {
    has plugin_id: str = "";
}

node PluginSettings {
    has plugin_id: str = "",
        settings: dict = {},
        enabled: bool = True,
        installed_at: str = "",
        version: str = "";
}
```

**Graph isolation rule**: Plugin walkers MUST traverse from their `PluginRoot`, never from user root directly. This prevents plugins from seeing or corrupting jac-builder core nodes or other plugins' data.

```jac
# CORRECT — traverse from plugin namespace
can start with Root entry {
    plugin_root = _ctx.get_plugin_root(self.user_id);
    sessions = [plugin_root -->(?:JacCoderSession)];
}

# WRONG — traverses ALL nodes under user root (dangerous!)
can start with Root entry {
    sessions = [-->(?:JacCoderSession)];  # May also see UserProfile, Project, etc.
}
```

### 5.2 Settings Walker

```jac
walker plugin_settings_ops {
    has action: str = "get",    # get | save | list_plugins | toggle
        plugin_id: str = "",
        settings: dict = {};

    can start with Root entry {
        # PluginSettings nodes are directly on user root (not on UserProfile)
        # This is a core walker, not a plugin walker, so it can access user root

        if action == "get" {
            nodes = [-->(?:PluginSettings)].filter(
                lambda n: Any { n.plugin_id == plugin_id; }
            );
            if nodes {
                report {"success": True, "settings": nodes[0].settings,
                        "enabled": nodes[0].enabled};
            } else {
                report {"success": True, "settings": {}, "enabled": True};
            }
        }
        elif action == "save" {
            nodes = [-->(?:PluginSettings)].filter(
                lambda n: Any { n.plugin_id == plugin_id; }
            );
            if nodes {
                nodes[0].settings = settings;
            } else {
                here ++> PluginSettings(
                    plugin_id=plugin_id, settings=settings,
                    enabled=True, installed_at=_utc_now(),
                    version=""
                );
            }
            report {"success": True};
        }
        elif action == "list_plugins" {
            all_settings = [-->(?:PluginSettings)];
            report {"success": True, "plugins": [
                {"plugin_id": n.plugin_id, "enabled": n.enabled,
                 "version": n.version}
                for n in all_settings
            ]};
        }
        elif action == "toggle" {
            nodes = [-->(?:PluginSettings)].filter(
                lambda n: Any { n.plugin_id == plugin_id; }
            );
            if nodes {
                nodes[0].enabled = not nodes[0].enabled;
                report {"success": True, "enabled": nodes[0].enabled};
            }
        }
    }
}
```

---

## 6. Plugin Lifecycle

### 6.1 Installation Flow

```
User clicks "Install" in Plugin Marketplace sidebar
    ↓
1. Download .jacplugin file (zip) from registry
    ↓
2. Extract to ~/.jac-ide/plugins/{plugin-id}/
    ↓
3. Validate plugin.json manifest (schema check)
    ↓
4. Install Python dependencies: pip install into server venv
    ↓
5. Dynamic import plugin.jac module
    ↓
6. Call plugin.jac:activate(ctx) → registers handlers at runtime
    ↓
7. Create PluginSettings + PluginRoot nodes on user graph
    ↓
8. Frontend reloads plugin registry → sidebar views/commands available
    ↓
✅ No server restart required!
```

**Why no restart**: Plugins register handler functions (not walkers). Handlers are stored in a `glob` dict. The two core dispatcher walkers (`plugin_dispatch` + `plugin_stream`) are defined once in `ideServer.jac` and never change. New plugins just add entries to the handler dict.

### 6.2 Activation Flow (Server Startup)

In `main.jac`:

```jac
import from services.plugin_loader {
    discover_plugins,
    activate_plugins,
    get_all_plugin_cleanups
}

with entry {
    load_dotenv();
    init_session_manager();

    # --- Plugin system ---
    # Scan ~/.jac-ide/plugins/*/plugin.json, dynamic import each,
    # call activate(ctx) which registers handlers in _plugin_handlers dict
    plugins = discover_plugins();
    activate_plugins(plugins);

    # Register all plugin cleanup hooks with session manager
    for (name, fn) in get_all_plugin_cleanups() {
        register_cleanup(name, fn);
    }
}
```

Note: `main.jac` does NOT import plugin modules directly. The plugin loader uses Python's `importlib` for dynamic imports. No `_plugin_imports.jac` generation needed.

### 6.3 Plugin Loader Service (`services/plugin_loader.jac`)

```jac
"""Plugin Loader — discovers, validates, and activates plugins."""

import os;
import json;

glob PLUGINS_ROOT: str = os.path.join(str(Path.home()), ".jac-ide", "plugins");
glob _active_plugins: dict = {};   # plugin_id -> {manifest, module, ctx}
glob _plugin_walkers: dict = {};   # walker_name -> walker_class
glob _plugin_cleanups: list = [];  # [(name, fn)]

def discover_plugins() -> list {
    """Scan plugins directory, return list of valid manifests."""
    plugins: list = [];
    if not os.path.isdir(PLUGINS_ROOT) {
        return plugins;
    }
    for dirname in os.listdir(PLUGINS_ROOT) {
        manifest_path = os.path.join(PLUGINS_ROOT, dirname, "plugin.json");
        if os.path.isfile(manifest_path) {
            try {
                with open(manifest_path, "r") as f {
                    manifest = json.load(f);
                }
                manifest["_dir"] = os.path.join(PLUGINS_ROOT, dirname);
                plugins.append(manifest);
            } except Exception as e {
                print(f"[plugin_loader] Invalid manifest in {dirname}: {e}");
            }
        }
    }
    # Sort by id for deterministic load order
    plugins.sort(key=lambda p: p.get("id", ""));
    return plugins;
}

def activate_plugins(plugins: list) -> None {
    """Activate each discovered plugin."""
    for manifest in plugins {
        plugin_id = manifest.get("id", "");
        plugin_dir = manifest.get("_dir", "");
        backend_entry = manifest.get("backend", "plugin.jac");

        try {
            # Build plugin context
            ctx = PluginContext(
                plugin_id=plugin_id,
                plugin_dir=plugin_dir
            );

            # Dynamic import of the plugin backend
            # (Jac runtime supports dynamic module loading)
            plugin_module = _import_plugin(plugin_dir, backend_entry);

            # Call activate
            if hasattr(plugin_module, "activate") {
                plugin_module.activate(ctx);
            }

            _active_plugins[plugin_id] = {
                "manifest": manifest,
                "module": plugin_module,
                "ctx": ctx
            };

            print(f"[plugin_loader] Activated: {plugin_id} v{manifest.get('version', '?')}");
        } except Exception as e {
            print(f"[plugin_loader] Failed to activate {plugin_id}: {e}");
        }
    }
}

def get_all_plugin_cleanups() -> list {
    return list(_plugin_cleanups);
}

def get_plugin_walkers() -> dict {
    return dict(_plugin_walkers);
}
```

---

## 7. Plugin Marketplace (Frontend)

### 7.1 Marketplace Sidebar Panel

A new sidebar view in the ActivityBar — the "Plugins" panel (like VS Code's Extensions view):

```
┌──────────────────────────────┐
│ 🔍 Search plugins...         │
├──────────────────────────────┤
│ INSTALLED                     │
│ ┌──────────────────────────┐ │
│ │ 🤖 JacCoder       v0.1.7│ │
│ │ AI coding agent          │ │
│ │ [Enabled ✓] [Settings ⚙]│ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ 📝 Jac Language   v2026 │ │
│ │ LSP, formatting, diag    │ │
│ │ [Enabled ✓] [Settings ⚙]│ │
│ └──────────────────────────┘ │
├──────────────────────────────┤
│ AVAILABLE                     │
│ ┌──────────────────────────┐ │
│ │ 🚀 Deploy to Vercel v1.0│ │
│ │ One-click Vercel deploy  │ │
│ │ [Install]                │ │
│ └──────────────────────────┘ │
│ ┌──────────────────────────┐ │
│ │ 🗄️ DB Explorer     v0.3│ │
│ │ Browse graph data        │ │
│ │ [Install]                │ │
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

### 7.2 Plugin Registry Backend

```jac
"""services/plugin_registry.jac — plugin marketplace backend."""

glob REGISTRY_PATH: str = os.path.join(
    str(Path.home()), ".jac-ide", "plugin-registry"
);

def list_available_plugins(search: str = "", category: str = "") -> list {
    """List plugins from the registry (local manifest + remote fetch)."""
    # Phase 1: Local registry.json (curated list)
    # Phase 2: Fetch from https://plugins.jaseci.org/api/v1/list
    ...
}

def install_plugin(plugin_id: str, source_url: str = "") -> dict {
    """Download and install a plugin."""
    # 1. Download .jacplugin (zip) from source_url or registry
    # 2. Extract to ~/.jac-ide/plugins/{plugin_id}/
    # 3. Validate manifest
    # 4. Install Python deps
    # 5. Return success/error
    ...
}

def uninstall_plugin(plugin_id: str) -> dict {
    """Remove a plugin."""
    # 1. Call deactivate() if active
    # 2. Remove ~/.jac-ide/plugins/{plugin_id}/
    # 3. Remove PluginSettings node
    ...
}

def get_installed_plugins() -> list {
    """List all installed plugins with their manifests."""
    ...
}

walker plugin_ops {
    has action: str = "list_installed",   # list_installed | list_available |
        plugin_id: str = "",              # install | uninstall | toggle
        source_url: str = "",
        search: str = "",
        category: str = "";

    can start with Root entry {
        if action == "list_installed" {
            report {"success": True, "plugins": get_installed_plugins()};
        }
        elif action == "list_available" {
            report {"success": True, "plugins": list_available_plugins(search, category)};
        }
        elif action == "install" {
            report install_plugin(plugin_id, source_url);
        }
        elif action == "uninstall" {
            report uninstall_plugin(plugin_id);
        }
    }
}
```

### 7.3 Plugin Registry Sources

**Phase 1 (Local)**: A `default-plugins.json` ships with jac-ide listing curated plugins from Jaseci Labs.

**Phase 2 (Central)**: `https://plugins.jaseci.org/api/v1/` — a simple REST API:
- `GET /list?search=&category=` — list available plugins
- `GET /plugin/{id}` — plugin metadata + download URL
- `POST /publish` — submit a plugin (authenticated, Jaseci team review)

The central registry stores metadata only — actual `.jacplugin` files hosted on GitHub Releases or S3.

---

## 8. Concrete Examples

### 8.1 jaseci.jac-coder — Full Plugin Structure

**What moves out of jac-ide core:**
| Current Location | Plugin Location |
|-----------------|-----------------|
| `services/jaccoder_adapter.jac` | `plugins/jaseci.jac-coder/services/jaccoder_adapter.jac` |
| `hooks/useChatMode.cl.jac` | `plugins/jaseci.jac-coder/hooks/useChatMode.cl.jac` |
| `components/ide/ChatPanel.cl.jac` | `plugins/jaseci.jac-coder/views/ChatPanel.cl.jac` |
| `services/ai_service.jac` | `plugins/jaseci.jac-coder/services/ai_service.jac` |
| `ai_chat` walker in `ideServer.jac` | `plugins/jaseci.jac-coder/plugin.jac` |
| AI-related imports in `main.jac` | Removed (plugin loader handles) |

**What stays in jac-ide core:**
- `EventBus` — host service
- `session_manager` — host service
- `preview_manager` — host service (plugin accesses via `PluginContext`)
- `file_sync` — host service

### 8.2 jaseci.jaclang — Full Plugin Structure

**What moves out of jac-ide core:**
| Current Location | Plugin Location |
|-----------------|-----------------|
| `services/lsp_manager.jac` | `plugins/jaseci.jaclang/services/lsp_manager.jac` |
| `hooks/useLSP.cl.jac` | `plugins/jaseci.jaclang/hooks/useLSP.cl.jac` |
| `utils/lsp_client.cl.jac` | `plugins/jaseci.jaclang/utils/lsp_client.cl.jac` |
| `utils/monaco_initializer.cl.jac` | `plugins/jaseci.jaclang/utils/monaco_initializer.cl.jac` |
| `assets/jac.tmLanguage.json` | `plugins/jaseci.jaclang/syntaxes/jac.tmLanguage.json` |
| `lsp_stream` walker in `ideServer.jac` | `plugins/jaseci.jaclang/plugin.jac` |
| LSP-related imports in `main.jac` | Removed |

**New in plugin:**
- `views/GraphVisualizer.cl.jac` — graph visualization panel (ported from VS Code extension's vis-network webview)
- Full LSP provider registration (completion, hover, definition, references, rename, formatting, semantic tokens)

### 8.3 Example Third-Party Plugin: "Deploy to Vercel"

A simple plugin demonstrating the minimum viable structure:

```
~/.jac-ide/plugins/community.vercel-deploy/
├── plugin.json
├── plugin.jac
├── plugin.cl.jac
└── views/
    └── DeployPanel.cl.jac
```

**plugin.json:**
```json
{
  "id": "community.vercel-deploy",
  "name": "Deploy to Vercel",
  "version": "1.0.0",
  "description": "One-click deployment to Vercel",
  "author": {"name": "Community Contributor"},
  "icon": "assets/vercel.svg",
  "activationEvents": ["onStartup"],
  "backend": "plugin.jac",
  "frontend": "plugin.cl.jac",
  "contributes": {
    "sidebarViews": [
      {"id": "vercel-deploy", "label": "Vercel", "icon": "Rocket01Icon",
       "component": "views/DeployPanel.cl.jac", "position": "top", "order": 10}
    ],
    "commands": [
      {"id": "vercel.deploy", "label": "Deploy to Vercel", "category": "Deploy"}
    ],
    "settings": [
      {"key": "vercelToken", "type": "password", "label": "Vercel API Token", "default": ""},
      {"key": "projectName", "type": "string", "label": "Vercel Project Name", "default": ""}
    ],
    "walkers": ["vercel_ops"]
  },
  "dependencies": {
    "python": ["httpx>=0.27.0"]
  }
}
```

**plugin.jac** (34 lines):
```jac
import httpx;

glob _ctx: Any = None;

can activate(ctx: PluginContext) -> None {
    glob _ctx = ctx;
    ctx.log("info", "Vercel Deploy plugin activated");
}

can deactivate() -> None { ; }

walker vercel_ops {
    has action: str = "deploy",
        project_id: str = "";

    can start with Root entry {
        if action == "deploy" {
            token = _ctx.get_setting(self.user_id, "vercelToken");
            project_path = _ctx.get_project_path(self.user_id, project_id);
            # ... build + deploy via Vercel API
            report {"success": True, "url": "https://myapp.vercel.app"};
        }
    }
}
```

This demonstrates that a useful plugin can be built in under 50 lines of Jac.

---

## 9. jac-ide Core After Plugin Extraction

### 9.1 What Remains in Core

After extracting jac-coder and jaclang into plugins, jac-ide core is:

| Component | Purpose |
|-----------|---------|
| `main.jac` | Entry point: load dotenv, init session manager, discover + activate plugins |
| `frontend.cl.jac` | Router: routes to pages |
| `pages/JacIDE.cl.jac` | IDE shell: ActivityBar + sidebar + editor + preview layout |
| `pages/DashboardPage.cl.jac` | Project grid, community gallery, user settings |
| `pages/AuthPage.cl.jac` | Login/signup |
| `services/plugin_loader.jac` | **NEW** — discover, validate, activate plugins |
| `services/plugin_registry.jac` | **NEW** — marketplace backend (install/uninstall/list) |
| `services/plugin_api.jac` | **NEW** — PluginContext implementation |
| `services/session_manager.jac` | Session TTL, cleanup hooks |
| `services/event_bus.jac` | Fan-out pub/sub |
| `services/preview_manager.jac` | Sandbox lifecycle |
| `services/sandbox_store.jac` | K8s sandbox management |
| `services/project_manager.jac` | Project CRUD, templates, autosave |
| `services/community_manager.jac` | Community gallery |
| `services/git_service.jac` | Git operations |
| `services/github_service.jac` | GitHub integration |
| `services/file_sync.jac` | Debounced file sync |
| `services/file_watcher.jac` | Filesystem change detection |
| `services/ideServer.jac` | Core walkers: `me`, `project_ops`, `version_ops`, `ide_file_ops`, `preview_control`, `ide_preview_stream`, `git_ops`, `community_ops`, `community_submit`, `env_ops`, `deploy_ops`, `plugin_ops`, `plugin_settings_ops` |
| `hooks/useIDE.cl.jac` | Core IDE state |
| `hooks/useGit.cl.jac` | Git state |
| `hooks/useDashboard.cl.jac` | Dashboard state |
| `hooks/useCommunity.cl.jac` | Community gallery state |
| `hooks/usePlugins.cl.jac` | **NEW** — plugin registry state for frontend |
| `components/ide/FileTree.cl.jac` | File tree (core) |
| `components/ide/GitPanel.cl.jac` | Git panel (core) |
| `components/ide/ActivityBar.cl.jac` | Activity bar (data-driven from plugin registry) |
| `components/ide/StatusBar.cl.jac` | Status bar (extensible with plugin items) |
| `components/ide/CommandPalette.cl.jac` | Command palette (extensible with plugin commands) |
| `components/ide/PluginMarketplace.cl.jac` | **NEW** — plugin browser/installer panel |
| `components/ide/PluginSettingsPanel.cl.jac` | **NEW** — per-plugin settings UI |

### 9.2 What Gets Deleted from Core

These files are **deleted** from jac-ide core. They are NOT moved — the plugins are **rebuilt in Jac** using the VS Code extension source as the specification for protocols and capabilities.

| Deleted from Core | Replaced by | Why rebuild, not move |
|-------------------|-------------|----------------------|
| `services/jaccoder_adapter.jac` (900 lines) | `jaseci.jac-coder` plugin | Old code calls `jac-coder` Python library directly. New plugin spawns `jac-coder-server` subprocess + JSON-RPC (same as VS Code extension). Gains: permission mode, plan mode, model switching, MCP management. |
| `services/ai_service.jac` (200 lines) | `jaseci.jac-coder` plugin | LLM calling handled by `jac-coder-server` internally. No separate service needed. |
| `services/lsp_manager.jac` (540 lines) | `jaseci.jaclang` plugin | Old code spawns `jac lsp` but only declares 6 LSP capabilities. New plugin declares all 12+ (adds rename, formatting, semantic tokens, signature help, snippetSupport). |
| `services/claude_adapter.jac` (1000 lines) | Deleted entirely | jac-builder only uses jac-coder |
| `hooks/useChatMode.cl.jac` (350 lines) | `jaseci.jac-coder` plugin | Old code: flat message list + 500ms polling. New plugin: streaming state machine with interleaved tool timeline, LCS diffs, slash commands, image paste (modeled on VS Code extension's `ExtensionState.tsx`). |
| `hooks/useClaudeChat.cl.jac` (400 lines) | Deleted entirely | claude adapter removed |
| `hooks/useLSP.cl.jac` (400 lines) | `jaseci.jaclang` plugin | Old code: 6 providers. New plugin: all providers + snippetSupport + signature help. |
| `utils/lsp_client.cl.jac` | `jaseci.jaclang` plugin | Rebuilt with full capability declaration |
| `utils/monaco_initializer.cl.jac` | `jaseci.jaclang` plugin | Plus `#* *#` auto-close from VS Code extension's `language-configuration.json` |
| `components/ide/ChatPanel.cl.jac` (838 lines) | `jaseci.jac-coder` plugin | Rebuilt with all 13 features from VS Code extension webview |
| `components/ide/ActivityTimeline.cl.jac` (240 lines) | `jaseci.jac-coder` plugin | Replaced by inline tool step cards (VS Code extension pattern) |
| `components/ide/MarkdownMessage.cl.jac` (100 lines) | `jaseci.jac-coder` plugin | Part of new MessageBubble component |
| `ai_chat` walker in ideServer.jac | `jaseci.jac-coder` plugin | Rebuilt to use JSON-RPC protocol |
| `claude_chat` + `claude_history` walkers | Deleted entirely | claude adapter removed |
| `lsp_stream` walker in ideServer.jac | `jaseci.jaclang` plugin | Rebuilt with full LSP pass-through |
| **Total deleted: ~5,700 lines** | | |

### 9.3 Lines of Code Impact (Estimated)

| | Before | After (Core) | Delta |
|---|---|---|---|
| `ideServer.jac` | ~4,560 lines | ~2,800 lines | -1,760 |
| `main.jac` | 99 lines | ~40 lines | -59 |
| Total backend services | ~6,500 lines | ~3,500 lines + 3 new plugin API files (~500 lines) | Net -2,500 from core |
| Total frontend hooks | ~2,200 lines | ~1,200 lines + 1 new plugin hook (~150 lines) | Net -850 from core |

Core becomes **~40% smaller** while gaining extensibility.

---

## 10. Implementation Phases

### Phase A: Plugin API Foundation (1 week)
1. Create `services/plugin_api.jac` — `PluginContext` implementation (including `get_plugin_root()` for graph isolation)
2. Create `services/plugin_loader.jac` — discovery, validation, activation, `_plugin_imports.jac` generation
3. Create `PluginRoot` + `PluginSettings` node types in `ideServer.jac`
4. Create `plugin_settings_ops` walker
5. Modify `main.jac` — import from `_plugin_imports`, call plugin loader
6. Add walker name prefix validation (uniqueness check at activation)

### Phase B: Build jaseci.jaclang Plugin (1 week)
Reference: VS Code extension source at `jac-vscode-main/`
1. Create `plugin.json` manifest declaring all 12+ LSP capabilities, graph viz sidebar, commands (restart LSP, format, lintfix)
2. Write `plugin.jac` — activate spawns `jac lsp` via `ctx.spawn_process()`, registers cleanup, registers `lsp_stream` walker
3. Write `plugin.cl.jac` — rebuild Monaco providers with full capabilities (add rename, formatting, semantic tokens, signature help, snippetSupport=True). Reference `jac-vscode-main/src/lsp/lsp_manager.ts` for capability spec.
4. Write `views/GraphVisualizer.cl.jac` — port vis-network graph rendering from `jac-vscode-main/src/visual_debugger/index.html`
5. Add `#* *#` block comment auto-close from `jac-vscode-main/language-configuration.json`
6. Delete old files from core (`lsp_manager.jac`, `useLSP.cl.jac`, `lsp_client.cl.jac`, `monaco_initializer.cl.jac`, `lsp_stream` walker)
7. Verify LSP, completion, hover, definition, formatting, rename all work end-to-end

### Phase C: Build jaseci.jac-coder Plugin (1.5 weeks)
Reference: VS Code extension source at `vscode-jac-coder-main/`
1. Create `plugin.json` manifest declaring chat sidebar, commands, status bar, settings (model, editMode)
2. Write `plugin.jac` — activate spawns `jac-coder-server` subprocess, JSON-RPC over stdin/stdout (same protocol as `vscode-jac-coder-main/src/core/JacCoderClient.ts`). Map `chat.event` notifications → EventBus. Support all RPC methods: `session.create/list/get/close`, `chat`, `chat.cancel`, `permission.response`, `model.get/set`, `mcp.*`
3. Write `plugin.cl.jac` — rebuild the chat UI in Jac with all features from `vscode-jac-coder-main/webview-ui/src/`:
   - Streaming message assembly (reference `ExtensionState.tsx` reducer)
   - Inline tool step cards with LCS diffs (reference `ToolCallCard.tsx`)
   - Permission/ask mode approval banner (reference `PermissionPrompt.tsx`)
   - Plan mode (generate plan → user approves → execute)
   - Slash commands, image paste, file attachments (reference `InputBox.tsx`)
   - Token usage tracking (reference `TokenBar.tsx`)
   - Session list with rename/delete (reference `SessionSwitcher.tsx`)
   - Edit-and-resend, auto-titling, extended thinking blocks
4. Delete old files from core (`jaccoder_adapter.jac`, `ai_service.jac`, `claude_adapter.jac`, `useChatMode.cl.jac`, `useClaudeChat.cl.jac`, `ChatPanel.cl.jac`, `ActivityTimeline.cl.jac`, `MarkdownMessage.cl.jac`, all claude/ai_chat walkers)
5. Verify AI chat with streaming, tool timeline, permission mode, model switching all work end-to-end

### Phase D: Frontend Plugin Framework (1 week)
1. Make ActivityBar data-driven (read from plugin registry)
2. Make sidebar dispatch registry-based (replace if/elif chain)
3. Make CommandPalette extensible (merge plugin commands)
4. Make StatusBar extensible (render plugin status items)
5. Create `hooks/usePlugins.cl.jac` — plugin state management
6. Create `components/ide/PluginMarketplace.cl.jac` — marketplace panel
7. Create `components/ide/PluginSettingsPanel.cl.jac` — settings UI

### Phase E: Marketplace & Distribution (1 week)
1. Create `services/plugin_registry.jac` — install/uninstall/list
2. Create `plugin_ops` walker
3. Create `.jacplugin` packaging format (zip with manifest)
4. Seed `default-plugins.json` with jaseci.jac-coder + jaseci.jaclang
5. Add "Plugins" icon to ActivityBar
6. End-to-end test: install a third-party plugin from marketplace

---

## 11. Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin language | Jac (`.jac` + `.cl.jac`) | Dogfooding — Jac can do anything |
| Runtime isolation | None (same process) | Simplicity; Obsidian model. Add isolation later if needed. |
| Plugin format | Folder with `plugin.json` manifest | Simple, inspectable, git-friendly |
| Distribution | `.jacplugin` zip files | Reuses jacpack infrastructure |
| Settings storage | Graph nodes (`PluginSettings` on user root) | Consistent with existing Jac Builder state model |
| Graph isolation | `PluginRoot` namespace node per plugin | **Enforced by core** — dispatcher passes `plugin_root` to handler, not `Root`. Plugin code never sees user root. |
| Plugin mechanism | Handler functions, not walkers (Direction C) | Jac runtime only registers walkers at compile-time. Handlers are dict entries — registered at runtime, no restart, no import generation, no name collisions. |
| Core walkers | Two dispatchers: `plugin_dispatch` (HTTP) + `plugin_stream` (WS) | All plugin requests route through these. One handler dict lookup per request. Error isolation via try/except. |
| No restart on install | Handlers registered at runtime via `register_handler()` | Unlike VS Code (requires "Reload Window"), plugins activate immediately. |
| Inter-plugin calls | `ctx.call_plugin(target_id, action, data)` | Direct function call — no HTTP overhead. Enables jac-coder to call jaclang for jac_check. |
| Default plugins | jaseci.jac-coder + jaseci.jaclang rebuilt in Jac | Not moved from existing code — rebuilt using VS Code extension source as spec. Gains 13+ features the old code doesn't have. |
| Frontend loading | Compiled at build time (default plugins) | Jac compiler handles .cl.jac → JS; no dynamic eval needed |
| Marketplace | Sidebar panel in IDE | Matches VS Code UX pattern; users expect it there |
| Frontend extension | Component + command + status bar registries | Data-driven instead of hardcoded; minimal framework needed |
