"""Browser testing via agent-browser CLI.

Uses Vercel's agent-browser (Rust CLI) for fast, token-efficient browser
automation.  All browser operations are subprocess calls — no Python browser
deps required.  The daemon starts on first use and persists across commands
for <50ms latency after the initial boot.

Install:  npm install -g agent-browser && agent-browser install
"""

import os;
import shutil;
import subprocess;
import threading;

import from jac_coder.util.tool_output { truncate_output, tool_status, tool_end }
import from jac_coder.util.sandbox { get_browser_exec, get_sandbox_root }
import from jac_coder.runtime.events { track_validate_result }

# Thread-local storage for per-request state (preview URL, session).
glob _tl = threading.local();

# Subprocess timeout for agent-browser commands (seconds).
glob _CMD_TIMEOUT: int = 30;
glob _OPEN_TIMEOUT: int = 45;


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Find the agent-browser binary, checking common locations."""
def _find_binary() -> str {
    # Allow explicit override via env var
    override = os.environ.get("AGENT_BROWSER_BIN", "");
    if override and shutil.which(override) {
        return override;
    }
    # Check PATH
    found = shutil.which("agent-browser");
    if found {
        return found;
    }
    # Common npm global install locations
    for candidate in [
        os.path.expanduser("~/.npm-global/bin/agent-browser"),
        "/usr/local/bin/agent-browser",
        os.path.expanduser("~/.local/bin/agent-browser")
    ] {
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK) {
            return candidate;
        }
    }
    return "";
}


"""Run an agent-browser CLI command and return (success, stdout, stderr).

If a remote browser exec function is set (via set_browser_exec), routes the
command to the sandbox pod. Otherwise falls back to local subprocess."""
def _run_cmd(args: list, timeout: int = _CMD_TIMEOUT) -> tuple {
    # Check for remote exec (sandbox pod)
    remote_exec = get_browser_exec();
    if remote_exec {
        try {
            return remote_exec(args, timeout);
        } except Exception as e {
            return (False, "", f"Remote browser exec failed: {str(e)}");
        }
    }

    # Local fallback
    binary = _find_binary();
    if not binary {
        return (
            False,
            "",
            "agent-browser not found. Install: npm install -g agent-browser && agent-browser install"
        );
    }
    cmd = [binary] + args;
    try {
        result = subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout
        );
        if result.returncode == 0 {
            return (True, result.stdout.strip(), "");
        } else {
            err = result.stderr.strip() or result.stdout.strip() or f"exit code {result.returncode}";
            return (False, "", err);
        }
    } except subprocess.TimeoutExpired {
        return (False, "", f"Command timed out after {timeout}s");
    } except Exception as e {
        return (False, "", str(e));
    }
}


"""Get the preview URL from thread-local or env var fallback."""
def _get_preview_url() -> str {
    return getattr(_tl, "preview_url", "") or os.environ.get("JACCODER_PREVIEW_URL", "");
}


# ---------------------------------------------------------------------------
# Tool implementations
# ---------------------------------------------------------------------------

impl set_preview_url(url: str) -> None {
    _tl.preview_url = url;
}


impl browser_open(url: str = "") -> str {
    target_url = url or _get_preview_url();
    tool_status("browser_open", target_url or "(no url)");

    if not target_url {
        tool_end("-> no URL", error=True);
        return (
            "Error: No URL provided and no preview URL set. "
            "Pass a URL or set JACCODER_PREVIEW_URL."
        );
    }

    # Open the page — daemon starts automatically on first command
    (ok, stdout, stderr) = _run_cmd(["open", target_url], timeout=_OPEN_TIMEOUT);
    if not ok {
        tool_end(f"-> failed: {stderr}", error=True);
        return f"Error: Failed to open browser — {stderr}";
    }

    # Wait for page to settle, then get snapshot with interactive elements
    (ok2, snapshot, stderr2) = _run_cmd(["snapshot", "-i"]);
    if not ok2 {
        # Page opened but snapshot failed — return what we have
        tool_end("-> opened, snapshot unavailable");
        return f"Browser opened: {target_url}\n\n(Page snapshot unavailable: {stderr2})";
    }

    # Mark session as active in thread-local
    _tl.browser_active = True;

    (output, _) = truncate_output(snapshot);
    tool_end(f"-> opened {target_url}");
    return f"Browser opened: {target_url}\n\nPage snapshot:\n{output}";
}


impl browser_do(command: str) -> str {
    tool_status("browser_do", command[:80] + "..." if len(command) > 80 else command);

    if not command or not command.strip() {
        tool_end("-> empty command", error=True);
        return "Error: command is required. Example: 'click @e1'";
    }

    # Split command string into args for subprocess
    try {
        args = shlex.split(command.strip());
    } except ValueError as e {
        tool_end(f"-> parse error: {e}", error=True);
        return f"Error: Failed to parse command — {e}";
    }

    (ok, stdout, stderr) = _run_cmd(args);
    if not ok {
        tool_end(f"-> failed: {stderr}", error=True);
        return f"Error: {stderr}";
    }

    action_result = stdout.strip() if stdout else "Done.";
    action_name = args[0] if args else "";

    (output, _) = truncate_output(action_result);
    tool_end(f"-> {action_name or 'done'}");
    return output;
}


impl browser_state() -> str {
    tool_status("browser_state");

    # snapshot -i returns interactive elements only (token-efficient)
    (ok, stdout, stderr) = _run_cmd(["snapshot", "-i"]);
    if not ok {
        tool_end(f"-> failed: {stderr}", error=True);
        return f"Error: {stderr}";
    }

    (output, _) = truncate_output(stdout);
    tool_end("-> got page snapshot");
    return output;
}


impl browser_validate(url: str = "") -> str {
    target_url = url or _get_preview_url();
    tool_status("browser_validate", target_url or "(no url)");

    if not target_url {
        tool_end("-> no URL", error=True);
        return (
            "Error: No URL provided and no preview URL set. "
            "Pass a URL or set JACCODER_PREVIEW_URL."
        );
    }

    # Step 1: Open page (close stale session first)
    _run_cmd(["close"]);
    (ok, stdout, stderr) = _run_cmd(["open", target_url], timeout=_OPEN_TIMEOUT);
    if not ok {
        tool_end(f"-> FAIL: cannot open", error=True);
        return f"FAIL: Could not open {target_url} — {stderr}\nIs the server running?";
    }

    # Step 2: Wait for page load + take snapshot with retries
    time.sleep(5);
    snapshot_text = "";
    for _attempt in range(3) {
        (ok_snap, snap_out, _) = _run_cmd(["snapshot", "-i"]);
        if ok_snap and snap_out {
            (snapshot_text, _) = truncate_output(snap_out);
        }
        if len(snapshot_text.strip()) > 50 {
            break;
        }
        time.sleep(5);
    }

    # Step 3: Detect errors from snapshot
    _tl.browser_active = True;
    error_text = "";
    source_file = "";
    has_error_screen = False;

    # Check for visible error screens
    error_screens = [
        "Something went wrong",
        "503 Service Unavailable",
        "500 Internal Server Error",
        "Unhandled Runtime Error",
        "Application error"
    ];
    for pattern in error_screens {
        if pattern in snapshot_text {
            has_error_screen = True;
            idx = snapshot_text.find(pattern);
            error_text = snapshot_text[max(0, idx - 50):idx + 300].strip();
            cl_match = re.search(r'([\w./\-]+\.cl\.jac)', error_text);
            if cl_match { source_file = cl_match.group(1); }
            break;
        }
    }

    # Check for runtime error patterns in snapshot
    if not has_error_screen {
        runtime_errors = [
            "Cannot use 'in' operator",
            "is not a function",
            "is not defined",
            "Cannot read properties of undefined",
            "Cannot read properties of null"
        ];
        for pattern in runtime_errors {
            if pattern in snapshot_text {
                has_error_screen = True;
                idx = snapshot_text.find(pattern);
                error_text = snapshot_text[max(0, idx - 50):idx + 300].strip();
                cl_match2 = re.search(r'([\w./\-]+\.cl\.jac)', error_text);
                if cl_match2 { source_file = cl_match2.group(1); }
                break;
            }
        }
    }

    # Step 3b: 503 auto-diagnosis — read .jac-server.log to find the real error
    # 503 almost always means the frontend build failed, not a code runtime bug
    server_log_info = "";
    missing_deps: list = [];
    compile_errors: list = [];
    is_503 = "503 Service Unavailable" in snapshot_text;

    if is_503 {
        log_path = "";
        sroot = get_sandbox_root();
        if sroot {
            candidate = os.path.join(sroot, ".jac-server.log");
            if os.path.isfile(candidate) {
                log_path = candidate;
            }
        }
        if not log_path {
            # Try relative to cwd
            if os.path.isfile(".jac-server.log") {
                log_path = os.path.abspath(".jac-server.log");
            }
        }

        if log_path {
            try {
                with open(log_path, "r", encoding="utf-8", errors="replace") as _lf {
                    log_lines = _lf.readlines();
                }
                # Take last 150 lines
                recent_log = log_lines[-150:] if len(log_lines) > 150 else log_lines;
                log_text = "".join(recent_log);

                # Detect missing npm dependencies
                dep_patterns = [
                    r'Failed to resolve import ["\']([^"\']+)["\']',
                    r'Module not found.*["\']([^"\']+)["\']',
                    r'Cannot find module ["\']([^"\']+)["\']',
                    r'Could not resolve ["\']([^"\']+)["\']'
                ];
                for dp in dep_patterns {
                    for m in re.finditer(dp, log_text) {
                        dep = m.group(1);
                        # Only track npm-style deps (not relative paths)
                        if dep and not dep.startswith(".") and not dep.startswith("/") {
                            # Extract package name (e.g. "react-hook-form" from "react-hook-form/dist/index")
                            pkg = dep.split("/")[0];
                            if dep.startswith("@") and "/" in dep {
                                pkg = "/".join(dep.split("/")[:2]);
                            }
                            if pkg and pkg not in missing_deps {
                                missing_deps.append(pkg);
                            }
                        }
                    }
                }
                missing_deps = missing_deps[:5];

                # Detect compile errors
                err_patterns = [
                    r'✖ Error:.*',
                    r'error\[E\d+\]:.*',
                    r'SyntaxError:.*',
                    r'ICE:.*'
                ];
                for ep in err_patterns {
                    for m in re.finditer(ep, log_text) {
                        line = m.group(0).strip()[:200];
                        if line and line not in compile_errors {
                            compile_errors.append(line);
                        }
                    }
                }
                compile_errors = compile_errors[:5];

                # Build summary
                parts_log: list = [];
                if compile_errors {
                    parts_log.append("Compile errors from .jac-server.log:");
                    for ce in compile_errors {
                        parts_log.append(f"  - {ce}");
                    }
                }
                if missing_deps {
                    parts_log.append("Missing npm dependencies:");
                    for md in missing_deps {
                        parts_log.append(f"  - {md}");
                    }
                }
                if not parts_log {
                    # No specific errors found — include last 20 lines for context
                    tail = "".join(recent_log[-20:]).strip();
                    if tail {
                        parts_log.append("Recent server log (last 20 lines):");
                        parts_log.append(tail[:1000]);
                    }
                }
                if parts_log {
                    server_log_info = "\n".join(parts_log);
                }
            } except Exception {
                server_log_info = "";
            }
        }
    }

    # Step 4: Capture JS errors and console errors via agent-browser built-in commands
    js_errors: list = [];
    console_errors: list = [];

    # Get uncaught JS exceptions
    (ok_errs, errs_out, _) = _run_cmd(["errors"]);
    if ok_errs and errs_out and errs_out.strip() {
        for line in errs_out.strip().split("\n") {
            line = line.strip();
            if line and len(line) > 5 {
                js_errors.append(line[:300]);
            }
        }
        js_errors = js_errors[:5];
    }

    # Get console.error output
    (ok_cons, cons_out, _) = _run_cmd(["console"]);
    if ok_cons and cons_out and cons_out.strip() {
        for line in cons_out.strip().split("\n") {
            line = line.strip();
            # Only capture error-level messages
            if line and ("error" in line.lower() or "Error" in line or "fail" in line.lower()) and len(line) > 5 {
                console_errors.append(line[:300]);
            }
        }
        console_errors = console_errors[:5];
    }

    # Step 5: PASS/FAIL decision
    has_content = len(snapshot_text.strip()) > 50;
    has_js_errors = len(js_errors) > 0;
    is_pass = has_content and not has_error_screen and not has_js_errors;

    # Step 5b: Auth-aware fallback — if root is blank with no errors,
    # automatically check /login and /signup before declaring FAIL
    # A "root" URL is just host+port with no meaningful path, e.g. http://localhost:8009/
    _stripped = target_url.rstrip("/");
    # After stripping protocol (http://), count remaining slashes — root has 0
    _after_protocol = _stripped.split("://", 1)[-1] if "://" in _stripped else _stripped;
    is_root = "/" not in _after_protocol;
    auth_redirect_detected = False;

    if not is_pass and not has_content and not has_error_screen and not has_js_errors and is_root {
        # Root is blank but no errors — likely auth-gated. Try /login
        for auth_path in ["/login", "/signup"] {
            auth_url = target_url.rstrip("/") + auth_path;
            _run_cmd(["close"]);
            (ok_auth, _, _) = _run_cmd(["open", auth_url], timeout=_OPEN_TIMEOUT);
            if ok_auth {
                time.sleep(3);
                (ok_auth_snap, auth_snap, _) = _run_cmd(["snapshot", "-i"]);
                if ok_auth_snap and auth_snap and len(auth_snap.strip()) > 50 {
                    auth_redirect_detected = True;
                    # Re-open original URL for consistent state
                    _run_cmd(["close"]);
                    _run_cmd(["open", target_url], timeout=_OPEN_TIMEOUT);
                    break;
                }
            }
        }
    }

    status = "PASS" if is_pass else "FAIL";

    # Track consecutive failures for escalating guidance
    fail_count = track_validate_result(target_url, is_pass);

    # Step 6: Build result
    parts: list = [f"Validation: {status} — {target_url}"];

    if auth_redirect_detected {
        parts.append("Page is BLANK at root — BUT /login or /signup page RENDERS correctly.");
        parts.append("This is EXPECTED for auth-gated apps. The app works — root redirects to login when not authenticated.");
        parts.append("\n[AUTH APP DETECTED: Do NOT try to fix the blank root. Instead:");
        parts.append("  1) browser_validate(url + '/login') to validate the login page");
        parts.append("  2) Or browser_do('fill ...') to login first, then test protected pages");
        parts.append("  3) The blank '/' is AuthGuard working correctly, NOT a bug.]");

        # Clear error buffers
        _run_cmd(["errors", "--clear"]);
        _run_cmd(["console", "--clear"]);

        tool_end(f"-> FAIL (auth-gated, /login works)");
        return "\n".join(parts);
    }

    # Step 6b: Detect skeleton/placeholder pages — PASS on a placeholder is NOT final
    # A real app has interactive elements (buttons, links, inputs, textboxes, forms).
    # A bisect skeleton has almost none — just a div with text.
    is_skeleton = False;
    if is_pass and snapshot_text {
        snap_lower = snapshot_text.strip().lower();

        # Method 1: Explicit placeholder keywords
        has_placeholder_text = (
            "placeholder" in snap_lower
            or "skeleton" in snap_lower
            or "bisect" in snap_lower
            or "test shell" in snap_lower
        );

        # Method 2: Count interactive elements from the accessibility snapshot
        # agent-browser snapshots use patterns like: button, textbox, link, [ref=eN]
        interactive_count = 0;
        for marker in ["button", "textbox", "link", "checkbox", "combobox", "menuitem"] {
            interactive_count += snap_lower.count(marker);
        }
        # Also count @e refs (each interactive element gets a ref like @e1, @e2)
        ref_count = len(re.findall(r'ref=e\d+', snap_lower));

        # Skeleton if: placeholder text detected, OR very few interactive elements
        # A real app page typically has 3+ interactive elements (nav links, buttons, inputs)
        if has_placeholder_text and len(snap_lower) < 300 {
            is_skeleton = True;
        } elif ref_count <= 1 and len(snap_lower) < 300 {
            # Only 0-1 interactive elements and short page — likely a skeleton
            is_skeleton = True;
        }
    }

    if has_error_screen {
        parts.append(f"Error screen detected: {error_text}");
        if source_file {
            parts.append(f"Error source: {source_file}");
        }
        # 503 auto-diagnosis — inject server log findings directly
        if is_503 and server_log_info {
            parts.append(f"\n[503 AUTO-DIAGNOSIS from .jac-server.log]\n{server_log_info}");
            if missing_deps {
                deps_str = '", "'.join(missing_deps);
                parts.append(f'\n[FIX: Add missing deps to jac.toml under [dependencies] npm section:');
                parts.append(f'  npm = ["{deps_str}"]');
                parts.append(f'  Then run: run_command("jac install", workdir="<project_dir>")');
                parts.append(f'  Then restart: kill server → jac start --dev main.jac]');
            } elif compile_errors {
                parts.append("\n[FIX: These are COMPILE errors, not runtime bugs. Read the source files listed in the errors above, fix the syntax, then restart the server.]");
            }
        } elif is_503 and not server_log_info {
            parts.append("\n[503 = frontend build failed. Read .jac-server.log for the real error:");
            parts.append("  run_command('tail -n 100 .jac-server.log', workdir='<project_dir>')]");
        }
    } elif not has_content {
        parts.append("Page is BLANK — no content rendered.");
    } elif is_skeleton {
        parts.append("Page renders — but this is a SKELETON/PLACEHOLDER page, not the real app.");
    } else {
        parts.append("Page rendered successfully.");
    }

    if js_errors {
        parts.append(f"\nJS errors ({len(js_errors)}):");
        for je in js_errors {
            parts.append(f"  - {je}");
            if not source_file {
                je_match = re.search(r'([\w./\-]+\.cl\.jac)', je);
                if je_match { source_file = je_match.group(1); }
            }
        }
    }

    if console_errors {
        parts.append(f"\nConsole errors ({len(console_errors)}):");
        for ce in console_errors {
            parts.append(f"  - {ce}");
        }
    }

    if snapshot_text {
        parts.append(f"\nPage snapshot:\n{snapshot_text}");
    }

    # Skeleton PASS — instruct agent to restore components
    if is_pass and is_skeleton {
        parts.append("\n[SKELETON PASS — this is NOT done. You stripped Layout for bisect debugging.");
        parts.append("Now you MUST restore the real UI by adding components back one at a time:");
        parts.append("  1) Add the FIRST real component back to Layout.cl.jac (e.g. Router + login route)");
        parts.append("  2) Restart server → browser_validate → must PASS");
        parts.append("  3) Add the NEXT component → restart → browser_validate → must PASS");
        parts.append("  4) Repeat until ALL components are restored and the full app renders");
        parts.append("  5) If any addition causes FAIL → that component is the bug. Fix it before continuing.");
        parts.append("Do NOT stop here. Do NOT report 'app works' with a placeholder page.]");
    }

    # Escalating action guidance based on consecutive failure count
    if not is_pass {
        if fail_count >= 3 {
            # 3rd+ FAIL on same URL — MANDATORY bisect
            parts.append(f"\n[MANDATORY — FAIL #{fail_count} on this URL. STOP fixing individual files.]");
            parts.append("[You have failed " + str(fail_count) + " times on this URL. Use the BISECT strategy NOW:");
            parts.append("  1) Edit Layout.cl.jac — replace ALL child components with <div>placeholder</div>");
            parts.append("  2) browser_validate to confirm the shell renders");
            parts.append("  3) Add components back ONE AT A TIME, browser_validate after each");
            parts.append("  4) The first component that breaks it is the bug — fix THAT one only.]");
        } elif fail_count == 2 {
            # 2nd FAIL — strong warning
            if source_file {
                parts.append(f"\n[ACTION: Read {source_file}, fix the error, restart server, then browser_validate again.]");
            }
            parts.append("\n[WARNING — 2nd FAIL on this URL. If the next attempt also fails, you MUST use the BISECT strategy.");
            parts.append(" Do NOT keep editing random files. Strip Layout.cl.jac to skeleton and add back one-by-one.]");
        } else {
            # 1st FAIL — standard guidance
            if source_file {
                parts.append(f"\n[ACTION: Read {source_file}, fix the error, restart server, then browser_validate again.]");
            } elif js_errors or console_errors {
                parts.append("\n[ACTION: Fix the errors above. Read the failing files, fix the code, restart server, then browser_validate again.]");
            } else {
                parts.append("\n[ACTION: Page blank, no errors. Debugging steps:");
                parts.append("  1) Read .jac-server.log for server startup errors");
                parts.append("  2) Read main.jac — verify it mounts the app correctly and all imports resolve");
                parts.append("  3) Check if this is an auth-gated app — try browser_validate(url + '/login')]");
            }
        }
    }

    # Clear error buffers for next validate call
    _run_cmd(["errors", "--clear"]);
    _run_cmd(["console", "--clear"]);

    tool_end(f"-> {status}");
    return "\n".join(parts);
}


impl browser_close() -> str {
    tool_status("browser_close");

    (ok, stdout, stderr) = _run_cmd(["close"]);
    _tl.browser_active = False;

    if not ok {
        tool_end(f"-> failed: {stderr}", error=True);
        return f"Error: {stderr}";
    }

    tool_end("-> closed");
    return "Browser session closed.";
}
