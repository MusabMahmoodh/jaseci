import from typing { overload }

# Keyword arguments spread from a dict literal take part in overload
# resolution, like `subprocess.run(..., **{"capture_output": True})`: a spread
# that does not supply the required `text` must not pick the overload that
# requires it.
@overload
def fetch(url: str, *, text: Literal[True], timeout: int = 0) -> str {}

@overload
def fetch(url: str, *, timeout: int = 0) -> bytes {}

with entry {
    a: bytes = fetch("u", timeout=3);  # <-- Ok
    b: bytes = fetch("u", **{"timeout": 3});  # <-- Ok
    c: str = fetch("u", **{"text": True, "timeout": 3});  # <-- Ok
    d: str = fetch("u", **{"timeout": 3});  # <-- Error
}
