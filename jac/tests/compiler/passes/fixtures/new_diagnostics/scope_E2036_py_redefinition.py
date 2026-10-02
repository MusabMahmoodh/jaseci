"""Fixture for E2036: a Python module may redefine a name."""


def pick() -> int:
    return 1


def pick() -> int:  # noqa: F811
    return 2
