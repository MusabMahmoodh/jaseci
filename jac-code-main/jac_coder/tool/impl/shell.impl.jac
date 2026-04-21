impl bash_exec(
    command: str, workdir: str = ".", timeout: int = 120, background: bool = False
) -> str {
    blocked = ["rm -rf /", "rm -rf ~", "mkfs", "dd if=", "> /dev/sd"];
    for pattern in blocked {
        if pattern in command {
            return "Error: Blocked dangerous command";
        }
    }

    timeout = min(timeout, 600);
    tool_status("bash", command);

    sroot = get_sandbox_root();
    if sroot {
        (workdir, err) = sandbox_path(workdir);
        if err {
            return err;
        }
        if not workdir or not os.path.isdir(workdir) {
            workdir = sroot;
        }
    } else {
        if not workdir or not os.path.isdir(workdir) {
            workdir = os.getcwd();
        }
    }

    if background {
        try {
            proc = subprocess.Popen(
                ["bash", "-c", command],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=workdir,
                start_new_session=True
            );
            return f"Background process started (PID: {proc.pid}). Use `kill {proc.pid}` to stop it.";
        } except Exception as e {
            return f"Error starting background process: {str(e)}";
        }
    }

    # Append pwd to capture final CWD after command
    wrapped = command + '\necho "\n__JACCODER_CWD__:$(pwd)"';

    try {
        result = subprocess.run(
            ["bash", "-c", wrapped],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=workdir
        );
    } except subprocess.TimeoutExpired {
        return f"Error: Command timed out after {timeout} seconds. If this is a long-running process (server, watcher), use background=True instead.";
    } except Exception as e {
        return f"Error: {str(e)}";
    }

    stdout = result.stdout or "";
    cwd_marker = "__JACCODER_CWD__:";
    if cwd_marker in stdout {
        parts = stdout.rsplit(cwd_marker, 1);
        stdout = parts[0].rstrip("\n");
    }

    output_parts = [];
    if stdout {
        output_parts.append(stdout);
    }
    if result.stderr {
        output_parts.append(f"STDERR:\n{result.stderr}");
    }

    output = "\n".join(output_parts) if output_parts else "(no output)";

    if result.returncode != 0 {
        output = f"Exit code: {result.returncode}\n{output}";
        tool_end(f"-> exit {result.returncode}", error=True);
    } else {
        out_lines = len(output.splitlines());
        tool_end(f"-> {out_lines} lines");
    }

    (output, _) = truncate_output(output);

    return output;
}
