impl _check_permission(tool_id: str, resource: str) -> str {
    action = permission_engine.check(tool_id, resource);

    if action == "deny" {
        return f"Permission denied: {tool_id} on {resource} is not allowed in this agent mode.";
    }

    if action == "ask" {
        decision = _ask_user(tool_id, resource);
        if decision == "deny" {
            return f"Permission denied by user: {tool_id} on {resource}";
        }
        if decision == "always" {
            permission_engine.remember_allow(tool_id, "*");
        }
    }

    return "allow";
}


impl _ask_user(tool_id: str, resource: str) -> str {
    if os.environ.get("JACCODER_WEB_MODE", "") {
        return "allow";
    }
    display = resource[:80] + "..." if len(resource) > 80 else resource;
    print(f"\n{YELLOW}[Permission]{RESET} {tool_id}: {display}");
    print(f"  {DIM}(y)es / (n)o / (a)lways allow {tool_id}{RESET}");
    try {
        answer = input("  Allow? ").strip().lower();
    } except (EOFError, KeyboardInterrupt) {
        return "deny";
    }
    if answer in ["a", "always"] {
        return "always";
    }
    if answer in ["y", "yes", ""] {
        return "allow";
    }
    return "deny";
}


impl write_file_guarded(file_path: str, content: str) -> str {
    verdict = _check_permission("write_file", file_path);
    if verdict != "allow" {
        return verdict;
    }
    return write_file(file_path, content);
}


impl edit_file_guarded(
    file_path: str, old_string: str, new_string: str, replace_all: bool = False
) -> str {
    verdict = _check_permission("edit_file", file_path);
    if verdict != "allow" {
        return verdict;
    }
    return edit_file(file_path, old_string, new_string, replace_all);
}


impl run_command(
    command: str, workdir: str = ".", timeout: int = 120, background: bool = False
) -> str {
    verdict = _check_permission("bash_exec", command);
    if verdict != "allow" {
        return verdict;
    }
    return bash_exec(command, workdir, timeout, background);
}
