# jac-mcp (ProtoMcp) — Windows Changes

Scope: the ProtoMcp desktop app (`jac-mcp-playground`), including its Rust
Tauri shell, Python sidecar entry, and jac service layer.

## Summary

ProtoMcp is largely derived from jacBuilder and inherits the same architecture
(Tauri + Python sidecar). Most of the general Windows rules in [rules.md](rules.md)
apply directly. Below are the **ProtoMcp-specific** changes that aren't shared
with jacBuilder.

## Changes

### `src-tauri/src/main.rs` (Rust Tauri shell)

| Change | Why |
|--------|-----|
| `#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]` | Suppress console window on Windows release builds |
| `#[cfg(windows)]` → uses `CommandExt` + `CREATE_NO_WINDOW` flag (`0x08000000`) | Hide sidecar console popup |
| Platform sidecar resolution: `.exe`/`.bat` on Windows, bare/`.sh` on Unix | Binary naming differs |
| Data path: `LOCALAPPDATA` (fallback `USERPROFILE/AppData/Local/`) on Windows; `HOME/.local/share/jac-app` on Unix | OS-specific app data convention |
| Command wrap: `cmd /C` for `.bat`, `sh` for `.sh` | Shell invocation differs |

### `src-tauri/sidecar_entry.py` (PyInstaller entry)

| Change | Why |
|--------|-----|
| `os.environ["PYTHONUTF8"] = "1"` before any other import | Prevent `charmap` codec errors on Windows |
| `if sys.platform == "win32": multiprocessing.freeze_support()` | **REQUIRED** for PyInstaller + multiprocessing (FastAPI + APScheduler both use worker pools) |

### `src-tauri/rthook_utf8.py` (runtime hook)

| Change | Why |
|--------|-----|
| Sets `PYTHONUTF8=1` at runtime hook | Force UTF-8 before app startup, even before `sidecar_entry.py` runs |

### `src-tauri/tauri.conf.json`

| Change | Why |
|--------|-----|
| `"targets": ["nsis"]` | Windows NSIS installer only (skip MSI) |
| Both `icon.png` and `icon.ico` in icon array | Windows bundler requires `.ico` |

### `jac.toml`

| Change | Why |
|--------|-----|
| `[desktop.platforms]` with `windows = true`, `macos = true`, `linux = true` | Enable all three targets |

## Known porting gap

[services/impl/mcp_server_launcher.impl.jac:99](../../ProtoMcp/services/impl/mcp_server_launcher.impl.jac#L99)
— `_resolve_python_exe()` hardcodes `venv/bin/python` (Unix-only). On Windows
it needs a `Scripts\python.exe` fallback:

```python
if sys.platform == "win32":
    python_exe = venv_path / "Scripts" / "python.exe"
else:
    python_exe = venv_path / "bin" / "python"
```

Without this fix, launching jasketch server inside a venv will fail on Windows.
