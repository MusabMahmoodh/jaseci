# ---------------------------------------------------------------------------
# Anti-pattern detection — catch React/Python/JS patterns in .jac files
# ---------------------------------------------------------------------------

# Hard blocks — these are definitely wrong in Jac and should prevent the write
# (regex_pattern, message, suggestion_query)
# NOTE: These run against actual code content. We strip comments before matching
# to avoid false positives on documentation/examples in comments.
glob _HARD_ANTIPATTERNS: list = [
    (r'\bimport\s+.*\bfrom\s+["\']react["\']', "ANTI-PATTERN: Direct React import detected. Jac components use 'has' for state, 'can with entry' for effects.", "frontend state effects lifecycle"),
    (r'\buseState\s*\(', "ANTI-PATTERN: useState() is React. In Jac .cl.jac, use 'has varname: type = default;' for component state.", "frontend state has variable"),
    (r'\buseEffect\s*\(', "ANTI-PATTERN: useEffect() is React. In Jac .cl.jac, use 'can with entry { ... }' for side effects.", "frontend effects lifecycle can with entry"),
    (r'^class\s+\w+\s*[({:]', "ANTI-PATTERN: 'class' is Python/JS. In Jac, use 'obj', 'node', or 'walker' instead.", "obj node walker definition"),
    (r'^def\s+\w+\s*\([^)]*\)\s*:\s*$', "ANTI-PATTERN: Python function syntax (colon after parens). Jac uses 'def name(...) -> type { }' with braces.", "function definition syntax"),
    (r'^from\s+\w+\s+import\s+', "ANTI-PATTERN: Python-style 'from X import Y'. Jac uses 'import from X { Y };'", "imports syntax"),
    (r'\bwindow\.addEventListener\s*\(\s*["\']popstate', "ANTI-PATTERN: Manual popstate listener. Use @jac/runtime Router/Routes/Route for routing.", "frontend routing Router Routes")
];

# Soft warnings — appended to result but don't block the write
glob _SOFT_WARNINGS: list = [
    (r'\buuid4\s*\(\s*\)', "HINT: Manual uuid4 for node IDs is often unnecessary. Consider jid(node) for node identity.", "node identity jid persistence")
];


"""Strip single-line comments from code so regexes don't match inside comments."""
def _strip_comments(content: str) -> str {
    lines: list = [];
    for line in content.split("\n") {
        # Remove # comments (but not inside strings — simple heuristic: only strip
        # if # is not preceded by a quote on the same line before it)
        stripped = line.split("#")[0] if "#" in line else line;
        lines.append(stripped);
    }
    return "\n".join(lines);
}

"""Scan content for hard anti-patterns that should BLOCK the write."""
def _detect_hard_antipatterns(content: str, file_path: str) -> list {
    warnings: list = [];
    is_cl = file_path.endswith(".cl.jac");

    # Strip comments to avoid false positives on examples/docs in comments
    code_only = _strip_comments(content);

    for (pattern, message, _query) in _HARD_ANTIPATTERNS {
        if re.search(pattern, code_only, re.MULTILINE) {
            warnings.append(message);
        }
    }

    # .cl.jac-specific checks
    if is_cl {
        if "import from react" in code_only.lower() or "from 'react'" in code_only or 'from "react"' in code_only {
            warnings.append("ANTI-PATTERN: Never import from React directly in .cl.jac files.");
        }
    }

    return warnings[:5];
}


"""Scan content for soft warnings that don't block but inform."""
def _detect_soft_warnings(content: str, file_path: str) -> list {
    warnings: list = [];
    for (pattern, message, _query) in _SOFT_WARNINGS {
        if re.search(pattern, content, re.MULTILINE) {
            warnings.append(message);
        }
    }
    return warnings[:3];
}


"""Return jac_docs queries for detected anti-patterns."""
def _get_antipattern_queries(content: str) -> list {
    queries: list = [];
    for (pattern, _msg, query) in _HARD_ANTIPATTERNS {
        if re.search(pattern, content, re.MULTILINE) {
            if query not in queries {
                queries.append(query);
            }
        }
    }
    return queries[:3];
}


# ---------------------------------------------------------------------------
# jac_docs reminder — soft, non-blocking nudge appended to write results.
# ---------------------------------------------------------------------------

"""SOFT WARNING: Appended after write if too many writes since last jac_docs call.
Escalates from gentle to strong but never blocks."""
def _check_jac_docs_reminder(file_path: str) -> str {
    if not file_path.endswith(".jac") {
        return "";
    }
    writes = get_writes_since_jac_docs();
    if writes < 3 {
        return "";
    }

    # Build a context-aware suggestion based on what the agent is writing
    is_cl = file_path.endswith(".cl.jac");
    is_sv = file_path.endswith(".sv.jac");
    if is_cl {
        suggestion = "jac_docs('frontend state effects') or jac_docs('frontend styling tailwind')";
    } elif is_sv {
        suggestion = "jac_docs('endpoint service def:pub')";
    } else {
        suggestion = "jac_docs('syntax')";
    }

    if writes >= 6 {
        # Strong warning — agent is deep in a writing streak without refreshing
        return (
            "\n\n[WARNING: " + str(writes) + " files written without calling jac_docs(). "
            "Syntax drift is likely — errors compound silently across files. "
            "Call " + suggestion + " NOW to catch mistakes before they multiply.]"
        );
    }

    # Gentle nudge at 3-5 writes
    return (
        "\n\n[REMINDER: " + str(writes) + " files since last jac_docs() call. "
        "Consider calling " + suggestion + " to verify you're using current syntax.]"
    );
}


# ---------------------------------------------------------------------------
# Validation enforcement — append jac_check errors + actionable guidance
# ---------------------------------------------------------------------------

def _enforce_check(result: str, file_path: str) -> str {
    if "Error:" in result
    and (
        "Permission denied" in result
        or "File not found" in result
        or "old_string not found" in result
    ) {
        return result;
    }

    if not file_path.endswith(".jac") {
        return result;
    }

    if "VALIDATION ERRORS" in result {
        return result + "\n\n[ACTION REQUIRED: Call jac_docs(query) to look up the correct Jac syntax BEFORE attempting to fix. Do NOT guess — look it up first, then fix.]";
    }

    if "RUNTIME ERRORS" in result {
        return result + "\n\n[ACTION REQUIRED: Call jac_docs(query) to look up the correct Jac syntax BEFORE attempting to fix. Do NOT guess — look it up first, then fix.]";
    }

    return result;
}


# ---------------------------------------------------------------------------
# Checked tool implementations
# ---------------------------------------------------------------------------

impl write_code(file_path: str, content: str) -> str {
    loop_msg = check_tool_loop("write_code", file_path);
    if loop_msg {
        return loop_msg;
    }

    # Anti-pattern detection — HARD BLOCK on known foot-guns only
    if file_path.endswith(".jac") {
        hard = _detect_hard_antipatterns(content, file_path);
        if hard {
            queries = _get_antipattern_queries(content);
            msg = "BLOCKED: Anti-patterns detected in your code:\n";
            for w in hard {
                msg += f"  - {w}\n";
            }
            msg += "\n[ACTION REQUIRED: Call jac_docs() to look up correct Jac patterns BEFORE rewriting.";
            if queries {
                msg += " Suggested queries: " + ", ".join([f"jac_docs('{q}')" for q in queries]);
            }
            msg += "]";
            return msg;
        }
    }

    # Write the file
    result = write_file_guarded(file_path, content);

    # Track this write for jac_docs enforcement
    if file_path.endswith(".jac") {
        track_write_call();
    }

    result = _enforce_check(result, file_path);

    # Append soft warnings (don't block, just inform)
    if file_path.endswith(".jac") {
        soft = _detect_soft_warnings(content, file_path);
        if soft {
            result += "\n\n[HINTS:";
            for w in soft {
                result += f"\n  - {w}";
            }
            result += "]";
        }
    }

    # Append jac_docs reminder if too many writes without a refresh
    reminder = _check_jac_docs_reminder(file_path);
    if reminder {
        result += reminder;
    }

    return result;
}


impl edit_code(
    file_path: str, old_string: str, new_string: str, replace_all: bool = False
) -> str {
    loop_msg = check_tool_loop("edit_code", file_path + "::" + old_string[:50]);
    if loop_msg {
        return loop_msg;
    }

    # Anti-pattern detection on the new content — HARD BLOCK on foot-guns only
    if file_path.endswith(".jac") and new_string {
        hard = _detect_hard_antipatterns(new_string, file_path);
        if hard {
            queries = _get_antipattern_queries(new_string);
            msg = "BLOCKED: Anti-patterns detected in your edit:\n";
            for w in hard {
                msg += f"  - {w}\n";
            }
            msg += "\n[ACTION REQUIRED: Call jac_docs() to look up correct Jac patterns BEFORE editing.";
            if queries {
                msg += " Suggested queries: " + ", ".join([f"jac_docs('{q}')" for q in queries]);
            }
            msg += "]";
            return msg;
        }
    }

    # Perform the edit
    result = edit_file_guarded(file_path, old_string, new_string, replace_all);

    # Track this write for jac_docs enforcement
    if file_path.endswith(".jac") {
        track_write_call();
    }

    result = _enforce_check(result, file_path);

    # Append soft warnings (don't block, just inform)
    if file_path.endswith(".jac") and new_string {
        soft = _detect_soft_warnings(new_string, file_path);
        if soft {
            result += "\n\n[HINTS:";
            for w in soft {
                result += f"\n  - {w}";
            }
            result += "]";
        }
    }

    # Append jac_docs reminder if too many writes without a refresh
    reminder = _check_jac_docs_reminder(file_path);
    if reminder {
        result += reminder;
    }

    return result;
}
