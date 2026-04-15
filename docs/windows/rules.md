# Windows Development Rules

**ALWAYS follow these rules when writing code that runs on Windows.** They apply
across all projects in this repo — sidecar, services, compiler, tooling.

## 1. File encoding

- **ALWAYS** use `encoding="utf-8"` on every `open()` call (read AND write)
- Windows defaults to `cp1252`, which crashes on emojis and non-ASCII chars
- Also add `encoding="utf-8"` to `subprocess.run(text=True, encoding="utf-8")`
- For safety: `(result.stdout or "").strip()` — subprocess can return `None` on encoding crash

## 2. No Unix-only modules at module level

- `pty`, `fcntl`, `termios`, `select`, `resource`, `pwd`, `grp` don't exist on Windows
- Use `importlib.import_module()` with `sys.platform != "win32"` guard, or `try/except ImportError`
- Never use `os.setsid`, `os.killpg`, `os.getpgid` — use `process.terminate()` / `process.kill()` on Windows

## 3. No Unix paths

- Never hardcode `/tmp/` — use `tempfile.gettempdir()`
- Never hardcode `/bin/bash`, `/usr/local/bin/` — use platform checks
- Venv binaries: `Scripts/jac.exe` on Windows, `bin/jac` on Unix
- Activate scripts: `Scripts/activate.bat` on Windows, `bin/activate` on Unix

## 4. No bash syntax in shell commands

- `source` → `call` on Windows
- `set -a; source file; set +a` → skip on Windows (load env via Python)
- `executable="/bin/bash"` → `None` on Windows
- `preexec_fn=os.setsid` → skip on Windows
- Always use `if sys.platform == "win32"` guards

## 5. Subprocess in frozen apps (PyInstaller sidecar)

- `sys.executable` is the sidecar exe, NOT Python
- Never use `[sys.executable, "-m", "jaclang.cli"]` — it won't work
- Use `[sys.executable, "--jac-cli"]` — the sidecar's multi-mode CLI handler
- For long-running processes (LSP, preview), spawn as subprocess via `--jac-cli`
- For one-shot commands (create, install), also use subprocess to avoid runtime state corruption

See [architecture.md](architecture.md) for how the multi-mode sidecar works.

## 6. Tauri/desktop build — platform-specific icons

Always ensure the correct icon exists per target OS:

- **Windows**: `icon.ico` (required by MSI/NSIS bundlers). Generate from PNG via `Pillow`:
  ```python
  img.save("icon.ico", format="ICO", sizes=[16, 32, 48, 64, 128, 256])
  ```
- **macOS**: `icon.icns` (required by DMG/app bundle). Generate via `iconutil -c icns icon.iconset` or `png2icns`
- **Linux**: `icon.png` at multiple sizes (32×32, 128×128, 256×256) for AppImage/deb

Include ALL three in `tauri.conf.json` icon array so cross-platform builds don't
fail. Build regenerates `tauri.conf.json` — manual edits get overwritten.

Use `"targets": "nsis"` to skip MSI on Windows (faster, avoids WiX long-path issues).

## 7. Jac compiler cache

- If styles or imports break mysteriously, run `jac purge --all` first
- Stale bytecode cache causes phantom errors unrelated to code changes

## 8. jac_client packaging (CRITICAL for frozen apps)

- Dirs with `__init__.jac` MUST also have `__init__.py` that re-exports via Python imports
- Without `__init__.py`, Python creates namespace packages → `__init__.jac` never executes
- `__init__.py` must `import jaclang` first (registers JacMetaImporter), then import from `.jac` submodules
- `collect_all('jac_client')` in the PyInstaller spec handles bundling when `__init__.py` exists
- Do NOT generate `__init__.py` at build time in the spec — add them to the source

See [architecture.md](architecture.md) for the full rationale.

## 9. Building for distribution

- Install `jac-client` and `jaclang` from **local source** (not PyPI) before building:
  ```bash
  pip install /path/to/jac-client --no-deps --force-reinstall
  pip install /path/to/jac --no-deps --force-reinstall
  ```
- This ensures your fixes are bundled, not the PyPI version
- After build, switch back to editable: `pip install -e jac-client -e jac`
- Increase preview timeouts to 300s for first-run compilation in frozen apps
