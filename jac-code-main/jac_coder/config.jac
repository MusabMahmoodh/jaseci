import os;
import json;

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

def get_home_dir() -> str;
def _merge_from_file(config: JacCoderConfig, path: str) -> None;
def load_config(project_dir: str = "") -> JacCoderConfig;
def get_config() -> JacCoderConfig;
def get_data_dir() -> str;

with entry {
    load_dotenv(override=True);
    load_config();
}

glob model_name: str = _config.default_model;
glob llm = Model(model_name=model_name);
