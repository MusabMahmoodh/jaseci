# jac-client — Windows Changes

Scope: sidecar entry point, desktop build target, and plugin packaging for
frozen distribution.

## Summary

jac-client is the foundation of the Windows port. It provides:

- The **multi-mode sidecar** (`jac-sidecar.exe` with `--jac-cli` flag) —
  see [architecture.md](architecture.md#1-multi-mode-sidecar---jac-cli)
- The **`__init__.py` shadow modules** that make `__init__.jac` work inside
  PyInstaller — see [architecture.md](architecture.md#2-__init__py--__init__jac-coexistence)
- The **desktop build target** that produces the final `.exe` + NSIS installer

## Changes

| File | Change | Why |
|------|--------|-----|
| `sidecar/main.py` | `_run_jac_cli()` handler for `--jac-cli` flag | Multi-mode sidecar: one binary, multiple roles |
| `sidecar/main.py` | `_register_frozen_plugins()` registers `jac_scale`, `jac_client`, `byllm` | Entry point discovery fails in frozen apps |
| `sidecar/main.py` | Loads `.env` from `sys._MEIPASS` before CWD change | API keys not found after `os.chdir(data_path)` |
| `sidecar/main.py` | `NO_COLOR=1`, `reconfigure(encoding="utf-8")` in CLI mode | Rich emojis crash `cp1252` in frozen apps |
| `plugin/__init__.py` | Python imports mirroring `__init__.jac` exports | Namespace package fix for frozen PyInstaller |
| `plugin/src/__init__.py` | Python imports mirroring `__init__.jac` exports (ViteCompiler etc.) | `import from .src { ViteCompiler }` fails without this |
| `plugin/utils/__init__.py` | Python imports mirroring `__init__.jac` exports | Same |
| `desktop_target.impl.jac` | `capture_output=False` for PyInstaller build | See build logs in real-time |
| `desktop_target.impl.jac` | Timeout increased to 7200s (2 hours) | Large projects need more time |
| `desktop_target.impl.jac` | UTF-8 runtime hook (`rthook_utf8.py`) | Force UTF-8 in frozen Python |
| `desktop_target.impl.jac` | Auto-bundles `assets/` and `.env` | Templates and config needed at runtime |
| `desktop_target.impl.jac` | `collect_all('jac_client')` in core packages | Proper bundling with `__init__.py` |

## Critical rules when working here

- **Every new `__init__.jac` needs an `__init__.py` shadow** — see rule 8 in
  [rules.md](rules.md#8-jac_client-packaging-critical-for-frozen-apps)
- **Never call `sys.executable -m something` from a frozen app** — use
  `--jac-cli` instead
- **Desktop target writes `tauri.conf.json`** — don't hand-edit it, change the
  jac source that generates it
