# jac-scale — Windows Changes

Scope: jac-scale's local sandbox — the component that runs user Jac code in
an isolated subprocess.

## Summary

The sandbox was heavily Unix-biased:

- Used `/tmp/` for staging
- Used `os.setsid` + `os.killpg` for process group management
- Used `executable="/bin/bash"` with bash-only syntax
- Copied the project to a temp dir (broken on Windows due to `.git/objects` read-only)

All of this needed platform branches.

## Changes

| File | Change | Why |
|------|--------|-----|
| `local_sandbox.jac` | `process.terminate()` / `kill()` instead of `os.killpg()` on Windows | Unix-only |
| `local_sandbox.jac` | Skip `executable="/bin/bash"` and `preexec_fn=os.setsid` on Windows | Unix-only |
| `local_sandbox.jac` | Use project dir directly instead of copying to temp | `.git/objects` is read-only on Windows |
| `local_sandbox.jac` | `tempfile.gettempdir()` instead of `/tmp/` | Cross-platform |
| `local_sandbox.jac` | Windows-compatible shell commands (`call` instead of `source`) | bash syntax fails |
| `local_sandbox.jac` | `_find_jac_binary()`: `--jac-cli` for frozen, `Scripts/jac.exe` on Windows | Preview failed in sidecar |
| `local_sandbox.jac` | Readiness timeout increased to 300s | First-run compilation takes >120s in frozen apps |

## Related

- Rule #2 (no Unix-only modules): [rules.md](rules.md#2-no-unix-only-modules-at-module-level)
- Rule #4 (no bash syntax): [rules.md](rules.md#4-no-bash-syntax-in-shell-commands)
- Rule #5 (frozen subprocess): [rules.md](rules.md#5-subprocess-in-frozen-apps-pyinstaller-sidecar)
