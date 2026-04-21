import os;

import from jac_coder.tool.shell { bash_exec }
import from jac_coder.util.colors { YELLOW, DIM, RESET }
import from jac_coder.permission { permission_engine }
import from jac_coder.tool.filesystem { write_file, edit_file }


def _check_permission(tool_id: str, resource: str) -> str;
def _ask_user(tool_id: str, resource: str) -> str;

"""Write a file with permission check."""
def write_file_guarded(file_path: str, content: str) -> str;

"""Find-and-replace with permission check."""
def edit_file_guarded(
    file_path: str, old_string: str, new_string: str, replace_all: bool = False
) -> str;

"""Run a shell command with permission check."""
def run_command(
    command: str, workdir: str = ".", timeout: int = 120, background: bool = False
) -> str;
