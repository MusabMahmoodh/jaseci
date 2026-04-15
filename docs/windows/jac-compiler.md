# jac compiler — Windows Changes

Scope: the Jac compiler itself (`jac/` or `jaclang/` in-tree).

## Summary

Compiler-side Windows fixes are entirely about file encoding. The compiler
reads `.jac` source files and writes generated templates — both sides crashed
on Windows because `open()` defaulted to `cp1252` and user source files
contain emoji/Unicode.

See [rule #1 in rules.md](rules.md#1-file-encoding).

## Changes

| File | Change | Why |
|------|--------|-----|
| `cfg_build_pass.impl.jac` | `encoding="utf-8"` on `open()` | `cp1252` decode error reading `.jac` files |
| `core.impl.jac` (na_ir_gen) | `encoding="utf-8"` on `open()` | Same |
| `project.impl.jac` | `encoding="utf-8"` on all `open()` write calls | Emoji in templates crash `cp1252` encoder |
| `tools.impl.jac` | `encoding="utf-8"` on config read/write | Same |

## Going forward

Every `open()` added to the compiler must specify `encoding="utf-8"`. A
reviewer rule of thumb: grep for `open(` in any PR that touches the compiler,
and flag any call that lacks the encoding kwarg.
