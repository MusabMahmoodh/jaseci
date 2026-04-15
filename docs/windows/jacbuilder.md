# jacBuilder — Windows Changes

Scope: jacBuilder's service layer — the managers and adapters that sit
between the Tauri shell and the Jac runtime. Applies to both `jacBuilder-dev`
and `jacBuilder-e` (service files shared).

## Summary

Most Windows fixes in jacBuilder are about two things:

1. Replacing Unix-only subprocess patterns (bash syntax, `pty`, `os.setsid`)
2. Routing jac CLI invocations through the sidecar's `--jac-cli` handler when
   frozen — see [architecture.md](architecture.md#1-multi-mode-sidecar---jac-cli)

## Changes

| # | File | Change | Why |
|---|------|--------|-----|
| 1 | `terminal_manager.jac` | `importlib.import_module()` guard for `pty`, `fcntl`, `termios`, `select` | Unix-only modules crash on Windows at import |
| 2 | `src-tauri/icons/icon.ico`, `tauri.conf.json` | Generated `.ico`, added to icon array, set `"targets": "nsis"` | Tauri NSIS/MSI bundler requires `.ico` |
| 3 | `project_manager.jac` | `_run_jac_command()` with `--jac-cli` subprocess, `encoding="utf-8"`, `(result.stdout or "").strip()` | Frozen exe can't use `sys.executable -m`; cp1252 crashes on emoji output |
| 4 | `project_manager.jac` | `TEMPLATE_MANIFEST_PATH` uses `sys._MEIPASS` when frozen | Sidecar changes CWD, can't find templates |
| 5 | `lsp_manager.jac` | `_find_jac_cmd()` with `--jac-cli`, `_build_env_prefix()` returns `""` on Windows, `call` instead of `source` | bash syntax fails on Windows |
| 6 | `preview_manager.jac` | `_find_jac_cmd()` with `--jac-cli`, `tempfile.gettempdir()`, timeout 300s | `/tmp/` doesn't exist; bash syntax fails; first-run compilation slow |
| 7 | `claude_adapter.jac` | `--jac-cli` for frozen, `Scripts/claude.exe` on Windows | Unix paths and frozen exe issue |
| 8 | `ideServer.jac` | `tempfile.gettempdir()` for preview cleanup | Hardcoded `/tmp/` |
| 9 | `jaccoder_adapter.jac` | Cross-platform regex in `_clean_path()` using `tempfile.gettempdir()` | `/tmp/` regex patterns |
| 10 | `terminal_manager.jac` | Disabled on Windows (returns error), `COMSPEC` for shell | `pty.fork()` is Unix-only; subprocess pipes block GIL |

## Known limitations

- **Terminal is disabled on Windows.** Reinstating it requires a ConPTY
  implementation. See [flow.md#known-issues](flow.md#known-issues).
