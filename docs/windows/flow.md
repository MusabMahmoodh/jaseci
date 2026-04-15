# Windows Build & Run Flow

End-to-end flow for developing, testing, and distributing the Jaseci desktop
stack on Windows.

## 1. Development setup

```bash
# editable installs for live iteration
pip install -e jac-client -e jac
```

Run the sidecar in server mode:

```bash
python -m jac_client.sidecar.main
```

## 2. Iteration loop

When editing `.jac` files in `jac-client/plugin/` or similar, remember:

- Every dir with `__init__.jac` also needs `__init__.py` — see [architecture.md](architecture.md)
- If imports break mysteriously, `jac purge --all` to clear bytecode cache
- UTF-8 everywhere — see [rules.md#1-file-encoding](rules.md#1-file-encoding)

## 3. Building a frozen distribution

### Step 1 — install from local source

```bash
pip install /path/to/jac-client --no-deps --force-reinstall
pip install /path/to/jac --no-deps --force-reinstall
```

This ensures your local fixes are bundled, not the PyPI version.

### Step 2 — generate platform icons

Before any Tauri build:

- Windows: `icon.ico` (all sizes 16–256)
- macOS: `icon.icns`
- Linux: `icon.png` at 32/128/256

All three must be listed in `tauri.conf.json` `icon` array, or cross-platform
builds fail. See [rules.md#6-tauridesktop-build--platform-specific-icons](rules.md#6-tauridesktop-build--platform-specific-icons).

### Step 3 — build

The desktop target invokes PyInstaller + Tauri. On Windows:

- `"targets": "nsis"` in `tauri.conf.json` (skip MSI)
- `capture_output=False` in build invocation — stream logs in real time
- Timeout set to 7200s (2 hours) for large projects

### Step 4 — switch back

After the build completes:

```bash
pip install -e jac-client -e jac
```

## 4. Testing the frozen app

```bash
bash sidecar-test-flow.sh 8000
```

Expected: **16/16 endpoints pass.** Preview takes ~165s on first run
(compilation + `npm install`), subsequent runs are cached.

## 5. Multi-mode sidecar in action

The same `jac-sidecar.exe` binary runs in two modes depending on arguments:

- `jac-sidecar.exe` (no args) — server mode, boots FastAPI + Tauri
- `jac-sidecar.exe --jac-cli create myproject --use template.jacpack` — CLI proxy

All internal services (`project_manager`, `lsp_manager`, `preview_manager`,
`claude_adapter`, `local_sandbox`) use `--jac-cli` when `sys.frozen` is True.
Details in [architecture.md](architecture.md#1-multi-mode-sidecar---jac-cli).

## Known issues

1. **Terminal disabled on Windows** — needs ConPTY implementation.
   `pty.fork()` is Unix-only; subprocess pipes block the GIL.
2. **Build regenerates `tauri.conf.json`** — manual edits get overwritten each build.
3. **First-run preview is slow** (~3 min) — subsequent runs are fast (cached).
4. **`jac purge --all` needed** after switching branches — stale cache causes issues.
5. **jac-mcp venv Python path** — `_resolve_python_exe()` in
   `ProtoMcp/services/impl/mcp_server_launcher.impl.jac:99` hardcodes
   `venv/bin/python` and will fail on Windows venvs. See [jac-mcp.md](jac-mcp.md#known-porting-gap).
