impl record_usage(usage_data: dict, agent: str = "main") -> None {
    if not _enabled {
        return;
    }

    per_call = usage_data.get("per_call", []);

    with _lock {
        # Record each individual LLM call and accumulate totals from per-call data
        # (the top-level `total` dict often omits cached_tokens, so summing per-call
        # is the reliable source of truth)
        for (i, call) in enumerate(per_call) {
            call_record = {
                "agent": agent,
                "iteration": len(_session_data["calls"]) + 1,
                "input_tokens": int(call.get("input_tokens", 0) or call.get("prompt_tokens", 0) or 0),
                "output_tokens": int(call.get("output_tokens", 0) or call.get("completion_tokens", 0) or 0),
                "cached_tokens": int(
                    call.get("cached_tokens", 0)
                    or call.get("cache_read_input_tokens", 0)
                    or (call.get("prompt_tokens_details") or {}).get("cached_tokens", 0)
                    or 0
                ),
                "total_tokens": int(call.get("total_tokens", 0) or 0)
            };
            # Calculate total if not provided
            if not call_record["total_tokens"] {
                call_record["total_tokens"] = call_record["input_tokens"] + call_record["output_tokens"];
            }
            _session_data["calls"].append(call_record);

            # Accumulate into running totals from this call
            _session_data["totals"]["input_tokens"] += call_record["input_tokens"];
            _session_data["totals"]["output_tokens"] += call_record["output_tokens"];
            _session_data["totals"]["cached_tokens"] += call_record["cached_tokens"];
            _session_data["totals"]["total_tokens"] += call_record["total_tokens"];
        }
    }
}


impl get_summary() -> dict {
    with _lock {
        num_calls = len(_session_data["calls"]);
        totals = dict(_session_data["totals"]);
        totals["num_calls"] = num_calls;
        # Effective input tokens — input that wasn't served from cache, billed at full rate
        totals["effective_input_tokens"] = max(totals["input_tokens"] - totals["cached_tokens"], 0);
        if num_calls > 0 {
            totals["avg_input_per_call"] = totals["input_tokens"] // num_calls;
            totals["avg_output_per_call"] = totals["output_tokens"] // num_calls;
            totals["cache_hit_rate"] = round(
                (totals["cached_tokens"] / max(totals["input_tokens"], 1)) * 100, 1
            );
        }
        return totals;
    }
}


impl get_per_call_data() -> list {
    with _lock {
        return list(_session_data["calls"]);
    }
}


impl reset() -> None {
    with _lock {
        _session_data["calls"] = [];
        _session_data["totals"] = {
            "input_tokens": 0,
            "output_tokens": 0,
            "cached_tokens": 0,
            "total_tokens": 0
        };
    }
}


impl save_to_file(filepath: str = "") -> str {
    if not filepath {
        filepath = "jaccoder_cost.json";
    }
    # Get data without nesting locks
    summary = get_summary();
    per_call = get_per_call_data();
    data = {
        "summary": summary,
        "per_call": per_call
    };
    with open(filepath, "w") as f {
        json.dump(data, f, indent=2);
    }
    return filepath;
}
