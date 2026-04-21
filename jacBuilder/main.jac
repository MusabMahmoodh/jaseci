"""Backend entry point for Jac IDE application."""

import from dotenv { load_dotenv }
import from services.session_manager {
        init_session_manager,
        register_cleanup
    }
import from services.jaccoder_adapter { init_jaccoder_web_mode }
import from services.preview_manager { init_preview_warmpool, cleanup_preview }
import from services.sandbox_store { init_warmpool as init_sandbox_warmpool }
import from services.sandbox_reconciler { start_reconciler, stop_reconciler }
import from services.file_sync { cleanup_all as cleanup_file_sync }
import from services.lsp_manager { stop_lsp }
import from services.claude_adapter { stop_claude_session }
import from services.jaccoder_adapter { clear_session as jaccoder_clear_session }
import from services.file_watcher { stop_watcher }
import from services.ideServer {
        env_ops,
        community_ops,
        community_submit,
        me,
        Router,
        template_ops,
        project_ops,
        version_ops,
        ide_file_ops,
        preview_control,
        preview_screenshot,
        ide_preview_stream,
        ai_chat,
        claude_chat,
        git_ops,
        deploy_ops,
        lsp_stream,
        claude_history,
        github_ops,
        reconcile_sandboxes
    }

def _cleanup_lsp(user_id: str, project_id: str) -> None {
    try { stop_lsp(user_id, project_id); } except Exception { ; }
}

def _cleanup_claude(user_id: str, project_id: str) -> None {
    try { stop_claude_session(user_id, project_id); } except Exception { ; }
}

def _cleanup_jaccoder(user_id: str, project_id: str) -> None {
    try { jaccoder_clear_session(user_id, project_id); } except Exception { ; }
}

def _cleanup_watcher(user_id: str, project_id: str) -> None {
    try { stop_watcher(user_id, project_id); } except Exception { ; }
}

def _cleanup_preview(user_id: str, project_id: str) -> None {
    try { cleanup_preview(user_id, project_id); } except Exception { ; }
}

def _cleanup_file_sync(user_id: str, project_id: str) -> None {
    try { cleanup_file_sync(); } except Exception { ; }
}

def _cleanup_reconciler(user_id: str, project_id: str) -> None {
    try { stop_reconciler(); } except Exception { ; }
}

with entry {
    load_dotenv();

    # Initialize session manager first — TTL cleanup + graceful shutdown
    init_session_manager();

    # Register cleanup callbacks (order matters — stop subprocesses before preview)
    register_cleanup("claude_adapter", _cleanup_claude);
    register_cleanup("jaccoder_adapter", _cleanup_jaccoder);
    register_cleanup("lsp_manager", _cleanup_lsp);
    register_cleanup("file_watcher", _cleanup_watcher);
    register_cleanup("file_sync", _cleanup_file_sync);
    register_cleanup("preview_manager", _cleanup_preview);
    register_cleanup("reconciler", _cleanup_reconciler);

    init_jaccoder_web_mode();
    init_preview_warmpool();

    # Start the sandbox reconciler background loop
    start_reconciler();
    # Initialize warm pool via new sandbox_store (runs alongside legacy init)
    init_sandbox_warmpool();
}

# Client-side code
cl {
    import from .frontend { app as ClientApp }

    def:pub app() -> Any {
        return <ClientApp />;
    }
}
