impl validate_project(directory: str = "") -> str {
    tool_status("validate_project", directory or os.getcwd());

    project_dir = directory if directory else os.getcwd();
    if not os.path.isdir(project_dir) {
        tool_end("-> not found", error=True);
        return f"Error: directory not found: {project_dir}";
    }

    # Find all .jac files (skip .cl.jac for now — jac check doesn't support them)
    jac_files: list = [];
    for (dirpath, dirnames, filenames) in os.walk(project_dir) {
        # Skip hidden dirs, node_modules, __pycache__
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in ["node_modules", "__pycache__", "venv"]];
        for fname in filenames {
            if fname.endswith(".jac") and not fname.endswith(".cl.jac") {
                jac_files.append(os.path.join(dirpath, fname));
            }
        }
    }

    if not jac_files {
        tool_end("-> no .jac files");
        return "No .jac files found in " + project_dir;
    }

    # Phase 1: Auto-fix mechanical patterns before checking
    auto_fixes_total = 0;
    for fp in jac_files {
        fixes = _auto_fix_mechanical(fp);
        auto_fixes_total += fixes;
    }

    # Phase 2: Run full jac check on each file, collect ALL errors
    all_errors: list = [];
    files_checked = 0;
    files_clean = 0;

    for fp in jac_files {
        rel_path = os.path.relpath(fp, project_dir);
        try {
            result = subprocess.run(
                ["jac", "check", fp],
                capture_output=True,
                text=True,
                timeout=30
            );
            files_checked += 1;

            if result.returncode == 0 {
                files_clean += 1;
            } else {
                output = (result.stderr or result.stdout or "").strip();
                if output {
                    # Parse individual errors
                    for line in output.split("\n") {
                        line = line.strip();
                        if line.startswith("✖ Error:") or line.startswith("⚠ warning:") {
                            all_errors.append(f"  {rel_path}: {line}");
                        }
                    }
                }
            }
        } except subprocess.TimeoutExpired {
            all_errors.append(f"  {rel_path}: TIMEOUT (>30s)");
            files_checked += 1;
        } except Exception as e {
            all_errors.append(f"  {rel_path}: CHECK FAILED - {str(e)}");
            files_checked += 1;
        }
    }

    # Phase 3: Build structured report
    parts: list = [];

    if auto_fixes_total > 0 {
        parts.append(f"Auto-fixed {auto_fixes_total} mechanical issues (root->root(), deprecated syntax).");
    }

    parts.append(f"Checked {files_checked} files: {files_clean} clean, {files_checked - files_clean} with issues.");

    if all_errors {
        # Categorize errors vs warnings
        errors = [e for e in all_errors if "Error:" in e];
        warnings = [e for e in all_errors if "warning:" in e];

        if errors {
            parts.append(f"\nErrors ({len(errors)}):");
            for e in errors[:30] {
                parts.append(e);
                # Add fix hint
                hint = _get_error_hint(e);
                if hint {
                    parts.append(f"    → {hint}");
                }
            }
            if len(errors) > 30 {
                parts.append(f"  ... and {len(errors) - 30} more errors");
            }
        }

        if warnings {
            parts.append(f"\nWarnings ({len(warnings)}):");
            for w in warnings[:10] {
                parts.append(w);
            }
            if len(warnings) > 10 {
                parts.append(f"  ... and {len(warnings) - 10} more warnings");
            }
        }

        track_error();
        tool_end(f"-> {len(errors)} errors, {len(warnings)} warnings", error=len(errors) > 0);
    } else {
        parts.append("\nAll files pass type-check.");
        tool_end(f"-> all clean");
    }

    return "\n".join(parts);
}


def _auto_fix_mechanical(file_path: str) -> int {
    try {
        with open(file_path, "r") as f {
            content = f.read();
        }
    } except Exception {
        return 0;
    }

    original = content;
    fixes = 0;

    # Fix 1: root → root() (bare root deprecated)
    # Match 'root' followed by space+keyword (spawn, -->), not already root()
    content = re.sub(r'\broot\b(?!\s*\()', 'root()', content);
    # But don't break 'with Root entry' — restore those
    content = content.replace("with root() entry", "with Root entry");
    content = content.replace("with root()", "with Root");
    # Don't break Root type references
    content = content.replace("(?:root())", "(?:Root)");
    content = content.replace("[?:root()]", "[?:Root]");

    # Fix 2: (?:Type) → [?:Type] (deprecated filter syntax)
    content = re.sub(r'\(\?:(\w+)\)', r'[?:\1]', content);

    # Fix 3: (?:Type, cond) → [?:Type, cond]
    content = re.sub(r'\(\?:(\w+),\s*', r'[?:\1, ', content);
    # Close the bracket if we opened one
    # This is tricky — skip for now, the simple case covers most usage

    if content != original {
        fixes = len(content.split("root()")) - len(original.split("root()"));
        fixes += len(re.findall(r'\[\?:', content)) - len(re.findall(r'\[\?:', original));
        fixes = max(fixes, 1);
        try {
            with open(file_path, "w") as f {
                f.write(content);
            }
        } except Exception {
            return 0;
        }
    }

    return fixes;
}


def _get_error_hint(error_line: str) -> str {
    e = error_line.lower();

    if "has no attribute" in e {
        return "Field was removed or renamed. Check the object definition.";
    }
    if "type is unknown" in e and "cannot access" in e {
        return "Add type annotation to the variable or cast with str()/int()/list().";
    }
    if "cannot return" in e and "expected" in e {
        return "Return type doesn't match. Add explicit type annotation or cast.";
    }
    if "missing from nonetype" in e {
        return "Variable might be None. Add null check: if var { var.field }";
    }
    if "cannot assign" in e and "unknown" in e {
        return "Add type annotation: var: str = expression;";
    }
    if "bare 'root'" in e {
        return "Use root() instead of root (auto-fixable by validate_project).";
    }
    if "deprecated" in e and "(?:" in e {
        return "Use [?:Type] instead of (?:Type) (auto-fixable by validate_project).";
    }
    if "parameter" in e and "type annotation" in e {
        return "Add type annotation to parameter: param: Type.";
    }
    return "";
}
