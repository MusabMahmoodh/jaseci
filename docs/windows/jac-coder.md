# jac-coder — Windows Changes

Scope: jac-code-main (the `jac_coder` package).

## Summary

jac-coder's Windows changes are narrowly about file encoding. Several rule
files (`.md`) and config files contain non-ASCII bytes (emojis, Unicode
punctuation) that crash Windows' default `cp1252` decoder.

See [rule #1 in rules.md](rules.md#1-file-encoding).

## Changes

| File | Change | Why |
|------|--------|-----|
| `nodes.jac` (2 occurrences) | `encoding="utf-8"` on `open()` | `.md` rule files have non-ASCII bytes |
| `impl/config.impl.jac` | `encoding="utf-8"` | Same |
| `impl/memory.impl.jac` | `encoding="utf-8"` | Same |
| `tool/impl/filesystem.impl.jac` | `encoding="utf-8"` | Same |
| `tool/impl/jac_docs.impl.jac` | `encoding="utf-8"` | Same |
| `tool/impl/validate.impl.jac` | `encoding="utf-8"` | Same |

## Going forward

Every new `open()` call in jac-coder — read or write — must specify
`encoding="utf-8"`. This applies even on macOS/Linux (where UTF-8 is the
default) for consistency.
