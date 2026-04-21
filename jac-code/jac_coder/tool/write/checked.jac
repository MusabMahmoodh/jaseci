import re;

import from jac_coder.tool.run.guarded { write_file_guarded, edit_file_guarded }
import from jac_coder.runtime.events {
    check_tool_loop,
    get_writes_since_jac_docs,
    track_write_call
}


"""Write a file with auto-validation."""
def write_code(file_path: str, content: str) -> str;

"""Find-and-replace with auto-validation."""
def edit_code(
    file_path: str, old_string: str, new_string: str, replace_all: bool = False
) -> str;
