import os;
import json;
import threading;
import from pathlib { Path }
import from dotenv { load_dotenv }
import from byllm.lib { Model }


obj JacCoderConfig {
    has default_model: str = "gpt-5.2-2025-12-11",
        temperature: float = 0.2,
        max_tokens: int = 8192,
        max_react_iterations: int = 30,
        project_dir: str = "";
}

glob _config: JacCoderConfig = JacCoderConfig();
glob model_name: str = _config.default_model;

# Thread-safe per-session model override.
# SessionAwareModel overrides invoke() to check thread-local state.
# `by llm()` calls llm.invoke(mt_run) → our override creates a
# per-call Model with the thread's model_name/api_key if set.
# No global mutation, no cross-thread contamination.
import from jaclang.jac0core.runtime { MTRuntime }

glob _tl = threading.local();

obj SessionAwareModel(Model) {
    override def invoke(mt_run: MTRuntime) -> object {
        import logging;
        _logger = logging.getLogger("jac_coder.infra.config");
        tl_model = getattr(_tl, "model_name", "");
        _logger.info(f"SessionAwareModel.invoke() tl_model={tl_model} default={self.model_name}");
        if tl_model {
            tl_key = getattr(_tl, "api_key", "");
            temp = Model(model_name=tl_model, api_key=tl_key) if tl_key else Model(model_name=tl_model);
            _logger.info(f"Delegating to temp Model: {tl_model} has_key={bool(tl_key)}");
            return temp.invoke(mt_run);
        }
        return super.invoke(mt_run);
    }
}

glob llm = SessionAwareModel(
    model_name=model_name,
    call_params={"max_tool_result_length": 20000}
);

"""Set a thread-local model override. Fully concurrent — no locks, no global mutation."""
def set_session_llm(model_name_override: str, api_key_override: str = "") {
    import logging;
    _tl.model_name = model_name_override;
    _tl.api_key = api_key_override;
    logging.getLogger("jac_coder.infra.config").info(
        f"Session LLM set: thread={threading.current_thread().name} model={model_name_override} has_key={bool(api_key_override)}"
    );
}

"""Clear the thread-local model override."""
def clear_session_llm() {
    import logging;
    prev = getattr(_tl, "model_name", "");
    _tl.model_name = "";
    _tl.api_key = "";
    if prev {
        logging.getLogger("jac_coder.infra.config").info(
            f"Session LLM cleared: thread={threading.current_thread().name} was={prev}"
        );
    }
}

# --- Config ---
def _merge_from_file(config: JacCoderConfig, path: str) -> None;
def load_config(project_dir: str = "") -> JacCoderConfig;
def get_config() -> JacCoderConfig;
def get_home_dir() -> str;
def get_data_dir() -> str;

# --- Model management ---
def set_model(model: str) -> dict;
def get_model() -> dict;

with entry {
    load_dotenv(override=True);
    load_config();
    # Sync the default LLM with loaded config — created at module load time
    # with the hardcoded default before load_config() runs.
    model_name = _config.default_model;
    llm.model_name = model_name;
}