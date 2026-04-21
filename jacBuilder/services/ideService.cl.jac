sv import from .ideServer {
    me, template_ops, project_ops, ide_file_ops, version_ops,
    preview_control, ai_chat, claude_chat, claude_history,
    git_ops, community_ops, community_submit,
    env_ops, deploy_ops, preview_screenshot, github_ops
}

glob _ERR_REPORT: dict = {"reports": [{"success": False, "error": ""}]};

"""Build an error result in reports format."""
def _errResult(msg: str) -> dict {
    return {"reports": [{"success": False, "error": msg}]};
}

"""Get current authenticated user's profile (creates on first call).
Also captures the ws_token for authenticated WebSocket communication."""
async def:pub ideGetMe() -> Any {
    hint = localStorage.getItem("jac_display_name") or "";
    try {
        result = root spawn me(display_name_hint=hint);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success and rpt.ws_token {
            _wsAuth["token"] = rpt.ws_token;
        }
        return result;
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""File workspace setup for a project."""
async def:pub ideSetup(projectId: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="setup");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List files in a project preview workspace."""
async def:pub ideListFiles(projectId: str, path: str = ".") -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="list", path=path);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Read file from active project workspace."""
async def:pub ideReadFile(projectId: str, path: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="read", path=path);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Write file to active project workspace (autosave/versioning on backend)."""
async def:pub ideWriteFile(projectId: str, path: str, content: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="write", path=path, content=content);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Batch-write multiple files to workspace (single commit)."""
async def:pub ideBatchWrite(projectId: str, files: list) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="batch_write", files=files);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Copy file to a new path in workspace."""
async def:pub ideCopyFile(projectId: str, srcPath: str, destPath: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="copy", path=srcPath, new_path=destPath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Delete file/directory from workspace."""
async def:pub ideDeleteFile(projectId: str, path: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="delete", path=path);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Rename or move file/directory in workspace."""
async def:pub ideRenameFile(projectId: str, oldPath: str, newPath: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="rename", path=oldPath, new_path=newPath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Create a directory in workspace."""
async def:pub ideMkdir(projectId: str, path: str) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="mkdir", path=path);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Search file contents across project workspace."""
async def:pub ideSearchFiles(projectId: str, query: str, caseSensitive: bool = False) -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="search", query=query, case_sensitive=caseSensitive);
    } except Exception as e {
        return _errResult(String(e));
    }
}

async def:pub ideReplaceInFiles(projectId: str, query: str, replaceText: str, caseSensitive: bool = False, fileFilter: str = "") -> Any {
    try {
        return root spawn ide_file_ops(project_id=projectId, action="replace", query=query, replace_text=replaceText, case_sensitive=caseSensitive, file_filter=fileFilter);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List curated jacpack templates."""
async def:pub ideListTemplates() -> Any {
    try {
        return root spawn template_ops(action="list");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List projects for current authenticated user."""
async def:pub ideListProjects() -> Any {
    try {
        return root spawn project_ops(action="list");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Create a project from selected template."""
async def:pub ideCreateProject(name: str, templateId: str) -> Any {
    try {
        return root spawn project_ops(action="create", name=name, template_id=templateId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Import project from uploaded jacpack file (base64) or URL."""
async def:pub ideImportProject(name: str, jacpackUrl: str, jacpackContentBase64: str) -> Any {
    try {
        return root spawn project_ops(action="import", name=name, jacpack_url=jacpackUrl, jacpack_content_base64=jacpackContentBase64);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Open project status."""
async def:pub ideOpenProject(projectId: str) -> Any {
    try {
        return root spawn project_ops(action="open", project_id=projectId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Rename project display name."""
async def:pub ideRenameProject(projectId: str, name: str) -> Any {
    try {
        return root spawn project_ops(action="rename", project_id=projectId, name=name);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Delete project and its workspace."""
async def:pub ideDeleteProject(projectId: str) -> Any {
    try {
        return root spawn project_ops(action="delete", project_id=projectId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get version list for active project."""
async def:pub ideListVersions(projectId: str) -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="list");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Capture a new version from current project working tree."""
async def:pub ideCaptureVersion(projectId: str) -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="capture");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Checkout version by version id or commit."""
async def:pub ideCheckoutVersion(projectId: str, versionId: str = "", commitSha: str = "") -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="checkout", version_id=versionId, commit_sha=commitSha);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Export version jacpack file."""
async def:pub ideExportVersion(projectId: str, versionId: str = "", outputPath: str = "") -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="export_jacpack", version_id=versionId, output_path=outputPath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Export version as downloadable jacpack payload."""
async def:pub ideExportVersionDownload(projectId: str, versionId: str = "") -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="export_jacpack_download", version_id=versionId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Export project as downloadable zip."""
async def:pub ideExportZipDownload(projectId: str) -> Any {
    try {
        return root spawn version_ops(project_id=projectId, action="export_zip_download");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Start AI chat processing (non-blocking). Returns immediately.
Frontend then polls for events via WebSocket ai_events."""
async def:pub ideChatStart(
    projectId: str,
    message: str,
    currentFilePath: str = "",
    images: list = []
) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, message=message, current_file_path=currentFilePath, action="start", images=images);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Stop the running JacCoder agent for a project."""
async def:pub ideChatStop(projectId: str) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, action="stop");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Load persisted JacCoder chat history for a project."""
async def:pub ideChatLoadHistory(projectId: str) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, action="load_history");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Clear all JacCoder chat history for a project."""
async def:pub ideChatClearHistory(projectId: str) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, action="clear_history");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Persist assistant/error response and create git version after WS polling completes."""
async def:pub ideChatPersistResult(
    projectId: str,
    responseText: str,
    promotedFiles: list,
    isError: bool = False,
    checkpointRef: str = "",
    activitiesLog: list = []
) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, action="persist_done", response_text=responseText, promoted_files=promotedFiles, is_error=isError, checkpoint_ref=checkpointRef, activities_log=activitiesLog);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Revert to a previous AI turn's checkpoint (non-destructive, stays on branch)."""
async def:pub ideChatRevertToMessage(projectId: str, checkpointRef: str) -> Any {
    try {
        return root spawn ai_chat(project_id=projectId, action="revert_to_message", checkpoint_ref=checkpointRef);
    } except Exception as e {
        return _errResult(String(e));
    }
}

# --- Shared persistent preview WebSocket ---

glob _previewWs: Any = None;
glob _previewWsState: str = "closed";
glob _previewWsOutbox: list = [];
glob _previewWsPending: list = [];
glob _wsAuth: dict = {"token": ""};
glob _wsTokenRefreshing: bool = False;
glob _TAB_ID: str = crypto.randomUUID();
glob _previewWsPendingMap: Any = Reflect.construct(Map, []);

"""Refresh ws_token by calling ideGetMe again. Used when backend rejects stale token."""
async def _refreshWsToken() -> bool {
    if _wsTokenRefreshing { return False; }
    _wsTokenRefreshing = True;
    try {
        hint = localStorage.getItem("jac_display_name") or "";
        result = root spawn me(display_name_hint=hint);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success and rpt.ws_token {
            _wsAuth["token"] = rpt.ws_token;
            _wsTokenRefreshing = False;
            return True;
        }
        _wsTokenRefreshing = False;
        return False;
    } except Exception {
        _wsTokenRefreshing = False;
        return False;
    }
}

"""Check if a WS response indicates an auth error. For JWT-authenticated walkers
this means the JWT expired or is invalid."""
def _checkWsTokenError(msg: Any) -> None {
    if not msg { return; }
    errMsg = "";
    if msg.error and msg.error.code {
        errMsg = String(msg.error.code);
    } elif msg.type == "error" and msg.data and msg.data.error {
        errMsg = String(msg.data.error);
    }
    if errMsg and (errMsg.indexOf("UNAUTHORIZED") >= 0 or errMsg.indexOf("Invalid or missing") >= 0) and not _wsTokenRefreshing {
        console.warn("WS auth rejected, refreshing JWT...");
        _refreshWsToken().then(lambda(ok: Any) {
            if ok {
                console.log("WS auth refreshed successfully");
            } else {
                console.error("WS auth refresh failed — may need to re-login");
            }
        });
    }
}

def _previewWsUrl() -> str {
    base = globalThis.__JAC_API_BASE_URL__;
    if base {
        url = Reflect.construct(URL, [String(base)]);
        protocol = "wss:";
        if url.protocol == "http:" {
            protocol = "ws:";
        }
        return protocol + "//" + url.host + "/ws/ide_preview_stream";
    }
    protocol = "ws:";
    if window.location.protocol == "https:" {
        protocol = "wss:";
    }
    return protocol + "//" + window.location.host + "/ws/ide_preview_stream";
}

def _notifyWsHandler(handler: Any, msg: Any) -> None {
    if not handler { return; }
    try {
        handler.call(None, msg);
    } except Exception as e {
        console.error("WS handler error:", e);
    }
}

def _failWsEntries(entries: list, errorMsg: str) -> None {
    err = {
        "ok": False,
        "error": {"code": "WS_DISCONNECTED", "message": errorMsg}
    };
    if entries and entries.length > 0 {
        while entries.length > 0 {
            entry = entries.shift();
            if entry and entry.handler {
                _notifyWsHandler(entry.handler, err);
            }
        }
    }
    _previewWsPendingMap.forEach(lambda(handler: Any, _rid: Any) {
        _notifyWsHandler(handler, err);
    });
    _previewWsPendingMap.clear();
}

def _flushWsOutbox() -> None {
    if _previewWsState != "open" or not _previewWs { return; }
    while _previewWsOutbox.length > 0 and _previewWsState == "open" and _previewWs {
        entry = _previewWsOutbox.shift();
        try {
            _previewWs.send(entry.payload);
            if entry.requestId {
                _previewWsPendingMap.set(entry.requestId, entry.handler);
            } else {
                _previewWsPending.push(entry);
            }
        } except Exception as e {
            _previewWsOutbox.unshift(entry);
            console.warn("WS send failed, will reconnect:", e);
            try {
                _previewWs.close();
            } except Exception {
            }
            break;
        }
    }
}

def _extractWsReport(data: Any) -> Any {
    if data and data.ok and data.data and data.data.reports and data.data.reports.length > 0 {
        return data.data.reports[data.data.reports.length - 1];
    }
    if data and data.data and data.data.reports and data.data.reports.length > 0 {
        return data.data.reports[data.data.reports.length - 1];
    }
    return data;
}

def _ensurePreviewWs() -> None {
    if _previewWsState == "open" or _previewWsState == "connecting" {
        return;
    }
    wsUrl = _previewWsUrl();
    _previewWsState = "connecting";
    _previewWs = Reflect.construct(WebSocket, [wsUrl]);

    _previewWs.onopen = lambda {
        _previewWsState = "open";
        _flushWsOutbox();
    };
    _previewWs.onmessage = lambda(event: Any) {
        data = JSON.parse(event.data);
        msg = _extractWsReport(data);
        _checkWsTokenError(msg);
        rid = "";
        if msg and msg.request_id { rid = msg.request_id; }
        if rid and _previewWsPendingMap.has(rid) {
            handler = _previewWsPendingMap.get(rid);
            _previewWsPendingMap.delete(rid);
            _notifyWsHandler(handler, msg);
        } elif _previewWsPending.length > 0 {
            entry = _previewWsPending.shift();
            if entry and entry.handler {
                _notifyWsHandler(entry.handler, msg);
            }
        }
    };
    _previewWs.onerror = lambda(e: Any) {
        console.warn("WS error:", e);
    };
    _previewWs.onclose = lambda(_: Any) {
        _previewWs = None;
        _previewWsState = "closed";
        _failWsEntries(_previewWsPending, "WebSocket closed before response");
        _failWsEntries(_previewWsOutbox, "WebSocket closed before send");
    };
}

"""Queue a WS request for preview stream walker.
Includes ws_token for authentication against the pub WS walker.
Each request gets a unique request_id for response correlation."""
def:pub sendWsRequest(action: str, userId: str, projectId: str, logOffset: int, onResponse: Any) -> None {
    reqId = crypto.randomUUID();
    jwtToken = localStorage.getItem("jac_token") or "";
    entry = {
        "payload": JSON.stringify(
            {
                "user_id": userId,
                "project_id": projectId,
                "action": action,
                "log_offset": logOffset,
                "token": jwtToken,
                "connection_id": _TAB_ID,
                "request_id": reqId
            }
        ),
        "requestId": reqId,
        "handler": onResponse
    };
    _previewWsOutbox.push(entry);
    _ensurePreviewWs();
    _flushWsOutbox();
}

"""List public community gallery items."""
async def:pub communityList(search: str = "", tag: str = "") -> Any {
    try {
        return root spawn community_ops(action="list", search=search, tag=tag);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Submit a project to community gallery."""
async def:pub communitySubmit(name: str, description: str, tags: list, jacpackBase64: str) -> Any {
    try {
        return root spawn community_submit(action="submit", name=name, description=description, tags=tags, jacpack_content_base64=jacpackBase64);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Clone a community item into user's own projects."""
async def:pub communityClone(commId: str, projectName: str) -> Any {
    try {
        return root spawn community_submit(action="clone", comm_id=commId, project_name=projectName);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Remove own community submission."""
async def:pub communityRemove(commId: str) -> Any {
    try {
        return root spawn community_submit(action="remove", comm_id=commId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Environment variable operations: list/save project env file."""
async def:pub ideEnvOps(projectId: str, action: str, envList: list) -> Any {
    try {
        return root spawn env_ops(project_id=projectId, action=action, env_list=envList);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""User-level global env operations (no project required)."""
async def:pub ideUserEnvOps(action: str, envList: list) -> Any {
    try {
        return root spawn env_ops(action=action, env_list=envList);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Deploy the current project to K8s."""
async def:pub ideDeployProject(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="deploy");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get deployment status for a project."""
async def:pub ideDeployStatus(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="status");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Destroy a project's deployment."""
async def:pub ideDestroyDeployment(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="destroy");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Deploy project as a sandbox (1-week TTL)."""
async def:pub ideSandboxDeploy(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="deploy", deploy_mode="sandbox");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get sandbox deployment status."""
async def:pub ideSandboxStatus(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="status", deploy_mode="sandbox");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Destroy a project's sandbox deployment."""
async def:pub ideSandboxDestroy(projectId: str) -> Any {
    try {
        return root spawn deploy_ops(project_id=projectId, action="destroy", deploy_mode="sandbox");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Capture a screenshot of a project's running preview or a direct URL."""
async def:pub idePreviewScreenshot(
    projectId: str = "",
    url: str = "",
    viewport: str = "desktop",
    format: str = "jpeg",
    fullPage: bool = False,
    delay: int = 3000
) -> Any {
    try {
        return root spawn preview_screenshot(project_id=projectId, url=url, viewport=viewport, format=format, full_page=fullPage, delay=delay);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Fetch a project's thumbnail image (base64)."""
async def:pub ideGetProjectThumbnail(projectId: str) -> Any {
    try {
        return root spawn project_ops(action="get_thumbnail", project_id=projectId);
    } except Exception as e {
        return _errResult(String(e));
    }
}

# --- Shared persistent LSP WebSocket ---

glob _lspWs: Any = None;
glob _lspWsState: str = "closed";
glob _lspWsOutbox: list = [];
glob _lspWsPending: list = [];

def _lspWsUrl() -> str {
    base = globalThis.__JAC_API_BASE_URL__;
    if base {
        url = Reflect.construct(URL, [String(base)]);
        protocol = "wss:";
        if url.protocol == "http:" {
            protocol = "ws:";
        }
        return protocol + "//" + url.host + "/ws/lsp_stream";
    }
    protocol = "ws:";
    if window.location.protocol == "https:" {
        protocol = "wss:";
    }
    return protocol + "//" + window.location.host + "/ws/lsp_stream";
}

def _flushLspOutbox() -> None {
    if _lspWsState != "open" or not _lspWs { return; }
    while _lspWsOutbox.length > 0 and _lspWsState == "open" and _lspWs {
        entry = _lspWsOutbox.shift();
        try {
            _lspWs.send(entry.payload);
            _lspWsPending.push(entry);
        } except Exception as e {
            _lspWsOutbox.unshift(entry);
            console.warn("LSP WS send failed:", e);
            try { _lspWs.close(); } except Exception { }
            break;
        }
    }
}

def _ensureLspWs() -> None {
    if _lspWsState == "open" or _lspWsState == "connecting" {
        return;
    }
    wsUrl = _lspWsUrl();
    _lspWsState = "connecting";
    _lspWs = Reflect.construct(WebSocket, [wsUrl]);

    _lspWs.onopen = lambda {
        _lspWsState = "open";
        _flushLspOutbox();
    };
    _lspWs.onmessage = lambda(event: Any) {
        data = JSON.parse(event.data);
        msg = _extractWsReport(data);
        _checkWsTokenError(msg);
        if _lspWsPending.length == 0 { return; }
        entry = _lspWsPending.shift();
        if entry and entry.handler {
            _notifyWsHandler(entry.handler, msg);
        }
    };
    _lspWs.onerror = lambda(e: Any) {
        console.warn("LSP WS error:", e);
    };
    _lspWs.onclose = lambda(_: Any) {
        _lspWs = None;
        _lspWsState = "closed";
        _failWsEntries(_lspWsPending, "LSP WebSocket closed before response");
        _failWsEntries(_lspWsOutbox, "LSP WebSocket closed before send");
    };
}

"""Queue a WS request for LSP stream walker.
Includes ws_token for authentication against the pub WS walker."""
def:pub sendLspRequest(action: str, userId: str, projectId: str, data: Any, onResponse: Any) -> None {
    entry = {
        "payload": JSON.stringify(
            {
                "user_id": userId,
                "project_id": projectId,
                "action": action,
                "data": (data if data else {}),
                "ws_token": _wsAuth["token"]
            }
        ),
        "handler": onResponse
    };
    _lspWsOutbox.push(entry);
    _ensureLspWs();
    _flushLspOutbox();
}

"""Close shared LSP WebSocket and clear pending queue."""
def:pub closeLspWs() -> None {
    _failWsEntries(_lspWsPending, "LSP WebSocket closed");
    _failWsEntries(_lspWsOutbox, "LSP WebSocket closed");
    if _lspWs {
        try { _lspWs.close(); } except Exception { }
    }
    _lspWs = None;
    _lspWsState = "closed";
}

"""Close shared preview WebSocket and clear pending queues."""
def:pub closePreviewWs() -> None {
    _failWsEntries(_previewWsPending, "WebSocket closed");
    _failWsEntries(_previewWsOutbox, "WebSocket closed");
    if _previewWs {
        try {
            _previewWs.close();
        } except Exception {
        }
    }
    _previewWs = None;
    _previewWsState = "closed";
}


# ===========================================================================
# Claude Code CLI
# ===========================================================================

"""Check if Claude CLI is available on the server."""
async def:pub claudeCheck() -> Any {
    try {
        return root spawn claude_chat(project_id="", action="check");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Start a Claude Code turn (non-blocking)."""
async def:pub claudeChatStart(
    projectId: str,
    message: str,
    model: str = "",
    allowedTools: str = "Read,Edit,Bash,Glob,Grep,Write",
    threadId: str = "",
    envMode: str = "local",
    branch: str = "",
    images: list = []
) -> Any {
    try {
        return root spawn claude_chat(project_id=projectId, thread_id=threadId, message=message, action="start", model=model, allowed_tools=allowedTools, env_mode=envMode, branch=branch, images=images);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Interrupt a running Claude turn."""
async def:pub claudeChatInterrupt(projectId: str) -> Any {
    try {
        return root spawn claude_chat(project_id=projectId, action="interrupt");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Stop Claude session entirely."""
async def:pub claudeChatStop(projectId: str, threadId: str = "") -> Any {
    try {
        return root spawn claude_chat(project_id=projectId, thread_id=threadId, action="stop");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get Claude session info."""
async def:pub claudeChatInfo(projectId: str, threadId: str = "") -> Any {
    try {
        return root spawn claude_chat(project_id=projectId, thread_id=threadId, action="info");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Persist assistant message and activities to thread after WS-based turn completes."""
async def:pub claudePersistTurn(projectId: str, threadId: str, content: str, activities: list = []) -> Any {
    try {
        return root spawn claude_chat(project_id=projectId, thread_id=threadId, message=content, action="persist", activities=activities);
    } except Exception as e {
        return _errResult(String(e));
    }
}


# ===========================================================================
# Claude History
# ===========================================================================

"""List all Claude threads for a project."""
async def:pub claudeListThreads(projectId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, action="list_threads");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get a specific thread with all messages and activities."""
async def:pub claudeGetThread(projectId: str, threadId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, thread_id=threadId, action="get_thread");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Delete a Claude thread."""
async def:pub claudeDeleteThread(projectId: str, threadId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, thread_id=threadId, action="delete_thread");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Rename a Claude thread."""
async def:pub claudeRenameThread(projectId: str, threadId: str, title: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, thread_id=threadId, message=title, action="rename_thread");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Merge a worktree thread's branch into the project's active branch."""
async def:pub claudeMergeThread(projectId: str, threadId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, thread_id=threadId, action="merge_thread");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Clear all messages and activities from a thread (keeps the thread node)."""
async def:pub claudeClearThread(projectId: str, threadId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, thread_id=threadId, action="clear_thread");
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Clean up orphaned worktrees (not linked to any thread)."""
async def:pub claudeCleanupWorktrees(projectId: str) -> Any {
    try {
        return root spawn claude_history(project_id=projectId, action="cleanup_worktrees");
    } except Exception as e {
        return _errResult(String(e));
    }
}


# ===========================================================================
# Git Operations
# ===========================================================================

"""Create a git worktree."""
async def:pub gitWorktreeCreate(projectId: str, baseBranch: str, newBranch: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="worktree_create", branch=baseBranch, new_branch=newBranch);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Remove a git worktree."""
async def:pub gitWorktreeRemove(projectId: str, worktreePath: str) -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="worktree_remove", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List git worktrees."""
async def:pub gitWorktreeList(projectId: str) -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="worktree_list");
    } except Exception as e {
        return _errResult(String(e));
    }
}

async def:pub githubOps(action: str, params: Any = {}) -> Any {
    try {
        return root spawn github_ops(
            action=action,
            project_id=params.project_id or "",
            code=params.code or "",
            state=params.state or "",
            installation_id=params.installation_id or "",
            repo_name=params.repo_name or "",
            repo_private=(params.repo_private if params.repo_private != None else True),
            repo_description=params.repo_description or "",
            clone_url=params.clone_url or "",
            pr_title=params.pr_title or "",
            pr_head=params.pr_head or "",
            pr_base=params.pr_base or "main",
            pr_body=params.pr_body or "",
            page=(params.page if params.page else 1),
            per_page=(params.per_page if params.per_page else 30)
        );
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get git status for a project."""
async def:pub gitStatus(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="status", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List git branches."""
async def:pub gitBranches(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="branches", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Checkout a branch."""
async def:pub gitCheckout(projectId: str, branch: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="checkout", branch=branch, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Create a new branch."""
async def:pub gitCreateBranch(projectId: str, branch: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="create_branch", branch=branch, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get git diff."""
async def:pub gitDiff(projectId: str, fromRef: str = "", toRef: str = "", worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="diff", from_ref=fromRef, to_ref=toRef, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get working tree diff."""
async def:pub gitDiffWorking(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="diff_working", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get staged diff."""
async def:pub gitDiffStaged(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="diff_staged", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get last commit diff (HEAD~1..HEAD)."""
async def:pub gitDiffLastCommit(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="diff_last_commit", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get file content at a specific git ref."""
async def:pub gitShowFile(projectId: str, ref: str, filePath: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="show_file", from_ref=ref, file_path=filePath, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Read file content from working tree on disk."""
async def:pub gitReadWorkingFile(projectId: str, filePath: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="read_working_file", file_path=filePath, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Commit all changes."""
async def:pub gitCommit(projectId: str, message: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="commit", message=message, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Stage a single file."""
async def:pub gitStageFile(projectId: str, filePath: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="stage_file", file_path=filePath, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Unstage a single file."""
async def:pub gitUnstageFile(projectId: str, filePath: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="unstage_file", file_path=filePath, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Commit only staged files."""
async def:pub gitCommitStaged(projectId: str, message: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="commit_staged", message=message, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Delete a branch."""
async def:pub gitDeleteBranch(projectId: str, branch: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="delete_branch", branch=branch, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Push to remote."""
async def:pub gitPush(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="push", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Pull from remote."""
async def:pub gitPull(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="pull", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get commit log."""
async def:pub gitLog(projectId: str, limit: int = 20, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="log", limit=limit, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Add remote origin."""
async def:pub gitRemoteAdd(projectId: str, remoteUrl: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="remote_add", remote_url=remoteUrl, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""List remotes."""
async def:pub gitRemotes(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="remotes", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Remove a remote by name."""
async def:pub gitRemoteRemove(projectId: str, remoteName: str = "origin", worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="remote_remove", remote_name=remoteName, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Merge a branch into the current branch (on main repo)."""
async def:pub gitMerge(projectId: str, branch: str) -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="merge", branch=branch);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Create a checkpoint."""
async def:pub gitCheckpointCreate(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="checkpoint_create", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Restore a checkpoint."""
async def:pub gitCheckpointRestore(projectId: str, checkpointRef: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="checkpoint_restore", from_ref=checkpointRef, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Get diff from checkpoint."""
async def:pub gitCheckpointDiff(projectId: str, checkpointRef: str, worktreePath: str = "") -> Any {
    try {
        return root spawn git_ops(project_id=projectId, action="checkpoint_diff", from_ref=checkpointRef, worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}

"""Stop preview via HTTP (awaitable, unlike the fire-and-forget WS stop)."""
async def:pub idePreviewStop(projectId: str) -> Any {
    try {
        return root spawn preview_control(project_id=projectId, action="stop");
    } except Exception as e {
        return _errResult(String(e));
    }
}

async def:pub idePreviewStartWithWorktree(projectId: str, worktreePath: str = "") -> Any {
    try {
        return root spawn preview_control(project_id=projectId, action="start", worktree_path=worktreePath);
    } except Exception as e {
        return _errResult(String(e));
    }
}
