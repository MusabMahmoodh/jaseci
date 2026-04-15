# Windows Desktop Port — Documentation Index

This folder documents all work done to make the Jaseci desktop stack (sidecar,
Tauri shell, and supporting services) build and run on Windows. It replaces the
single-file `windows-desktop-changes.md` with a per-project breakdown so each
team can own their own doc.

## Read in this order

1. [flow.md](flow.md) — end-to-end Windows build & run flow, from dev install
   through bundled `.exe` distribution
2. [rules.md](rules.md) — the 9 rules to follow when writing any code that
   must run on Windows (encoding, paths, subprocess, shell, icons, packaging)
3. [architecture.md](architecture.md) — two load-bearing patterns:
   multi-mode sidecar (`--jac-cli`) and `__init__.py` + `__init__.jac`
   coexistence for frozen apps

## Per-project change logs

| Project | Doc | Scope |
|---------|-----|-------|
| jac-client | [jac-client.md](jac-client.md) | Sidecar entry point, desktop target, plugin packaging |
| jacBuilder | [jacbuilder.md](jacbuilder.md) | Service layer (LSP, preview, terminal, project, claude, ide) |
| jac-coder | [jac-coder.md](jac-coder.md) | File I/O encoding fixes |
| jac-mcp (ProtoMcp) | [jac-mcp.md](jac-mcp.md) | Rust Tauri shell, sidecar entry, UTF-8, icons |
| jac-scale | [jac-scale.md](jac-scale.md) | Local sandbox (subprocess, paths, shell) |
| jac compiler | [jac-compiler.md](jac-compiler.md) | Compiler-internal encoding fixes |

## Known issues

See [flow.md#known-issues](flow.md#known-issues).

---

The original consolidated doc [../../windows-desktop-changes.md](../../windows-desktop-changes.md)
is kept in place as a historical reference — the content here supersedes it.
