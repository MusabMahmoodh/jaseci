# Windows Port — Load-Bearing Patterns

Two architectural patterns underpin most of the Windows fixes. Understand these
before touching sidecar or plugin code.

## 1. Multi-mode sidecar (`--jac-cli`)

The sidecar exe (`jac-sidecar.exe`) serves two roles from one binary:

1. **Server mode** (default) — runs the Jac API server with Tauri
2. **CLI mode** (`--jac-cli`) — acts as a `jac` CLI proxy

### Example

```bash
jac-sidecar.exe --jac-cli create myproject --use template.jacpack --force
```

### Why this exists

In a frozen PyInstaller app, `sys.executable` is the sidecar exe, not Python.
`[sys.executable, "-m", "jaclang.cli"]` does not work — there's no module
resolution at that level. Shipping a separate `jac.exe` would double the binary
size because PyInstaller can't share `_internal/` across exes cleanly.

### How to use it

All services spawn jac CLI commands via:

```python
if getattr(sys, "frozen", False):
    cmd = [sys.executable, "--jac-cli", *args]
else:
    cmd = ["jac", *args]  # or sys.executable, "-m", "jaclang.cli"
```

Affected services: `project_manager`, `lsp_manager`, `preview_manager`,
`claude_adapter`, and `local_sandbox` (in jac-scale).

### Handler location

`jac-client/sidecar/main.py` — `_run_jac_cli()` intercepts `--jac-cli` before
FastAPI/uvicorn startup.

## 2. `__init__.py` + `__init__.jac` coexistence

For directories with `__init__.jac` (like `jac_client/plugin/`,
`jac_client/plugin/src/`), you MUST also have `__init__.py` that:

1. `import jaclang` — registers `JacMetaImporter`
2. Re-imports the same symbols from `.jac` submodules via Python import statements

### Why this exists

In a frozen app, Python creates **namespace packages** for directories without
`__init__.py`. Namespace packages bypass the Jac meta-importer, so:

- `__init__.jac` is never loaded
- Exports like `ViteCompiler` are missing
- `import from .src { ViteCompiler }` fails at runtime

### Example `__init__.py`

```python
import jaclang  # MUST be first — registers JacMetaImporter

from .src import ViteCompiler
from .utils import build_helper
# ...re-export every symbol that __init__.jac exports
```

### Build integration

- `collect_all('jac_client')` in the PyInstaller spec handles bundling once
  `__init__.py` exists
- Do NOT generate `__init__.py` at build time in the spec — add them to source
  so the namespace-package trap is closed in development too

## Related

- Rule #5: [rules.md#5-subprocess-in-frozen-apps-pyinstaller-sidecar](rules.md#5-subprocess-in-frozen-apps-pyinstaller-sidecar)
- Rule #8: [rules.md#8-jac_client-packaging-critical-for-frozen-apps](rules.md#8-jac_client-packaging-critical-for-frozen-apps)
