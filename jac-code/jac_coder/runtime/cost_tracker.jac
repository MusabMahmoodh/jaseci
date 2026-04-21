"""Simple cost tracking for JacCoder.
Enable with JACCODER_TRACK_COST=1 env var.
Captures per-call token usage from byllm's usage events."""

import os;
import json;
import threading;

glob _enabled: bool = os.environ.get("JACCODER_TRACK_COST", "") in ("1", "true", "yes");
glob _lock = threading.Lock();
glob _session_data: dict = {
    "calls": [],
    "totals": {
        "input_tokens": 0,
        "output_tokens": 0,
        "cached_tokens": 0,
        "total_tokens": 0
    }
};


def is_cost_tracking_enabled() -> bool {
    return _enabled;
}

def enable_cost_tracking() -> None {
    global _enabled;
    _enabled = True;
}

def disable_cost_tracking() -> None {
    global _enabled;
    _enabled = False;
}

def record_usage(usage_data: dict, agent: str = "main") -> None;
def save_to_file(filepath: str = "") -> str;
def get_per_call_data() -> list;
def get_summary() -> dict;
def reset() -> None;

