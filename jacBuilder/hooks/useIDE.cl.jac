"""IDE state management hook — project/files/tabs/preview/versions for a single project."""

import from react { useState, useEffect, useRef }
import from "@jac/runtime" { useParams }
import from ..services.ideService {
    ideSetup,
    ideListFiles,
    ideReadFile,
    ideWriteFile,
    ideDeleteFile,
    ideRenameFile,
    ideMkdir,
    ideListTemplates,
    ideListProjects,
    ideOpenProject,
    ideListVersions,
    ideCaptureVersion,
    ideCheckoutVersion,
    ideExportVersion,
    ideExportVersionDownload,
    ideGetMe,
    sendWsRequest,
    closePreviewWs,
    ideDeployProject,
    ideDeployStatus,
    ideDestroyDeployment,
    ideSandboxDeploy,
    ideSandboxStatus,
    ideSandboxDestroy,
    idePreviewScreenshot,
    ideCopyFile
}

"""Parse new preview log content and return a deduplicated list of error lines."""
glob _PREVIEW_ERROR_PATTERNS: list = [
    "✖ Error:", "✗ Error:", "Compile error in",
    "Failed to resolve", "[vite] error", "[plugin:vite",
    "TypeError:", "ReferenceError:", "SyntaxError:",
    "Uncaught Error", "Cannot read properties of", "is not defined"
];

def _parsePreviewErrors(content: str) -> list {
    _NL = String.fromCharCode(10);
    lines = content.split(_NL);
    found: list = [];
    for line in lines {
        trimmed = line.trim();
        if not trimmed { continue; }
        for pattern in _PREVIEW_ERROR_PATTERNS {
            if trimmed.includes(pattern) {
                if not found.includes(trimmed) {
                    found.push(trimmed);
                }
                break;
            }
        }
    }
    return found;
}

"""Hook for managing IDE state: user, project, files, tabs, preview, versions."""
def:pub useIDE() -> Any {
    has userId: str = "";
    has projectId: str = "";
    has project: Any = None;
    has projectType: str = "fullstack";
    has isSetup: bool = False;
    has isLoading: bool = False;

    has templates: list = [];
    has versions: list = [];

    has fileList: list = [];
    has openTabs: list = [];
    has activeTab: str = "";
    has terminalContent: str = "";
    has previewUrl: str = "";
    has previewStatus: str = "stopped";
    has previewPort: int = 0;
    has apiPort: int = 0;
    has previewRefreshKey: int = 0;
    has previewErrors: list = [];
    has deploymentStatus: str = "";
    has deploymentUrl: str = "";
    has sandboxStatus: str = "";
    has sandboxUrl: str = "";

    logOffsetRef = useRef(0);
    deployPollRef = useRef(None);
    sandboxPollRef = useRef(None);
    previewStatusRef = useRef("stopped");
    idleCountRef = useRef(0);
    previewRetryRef = useRef(0);
    autoSaveTimerRef = useRef(None);
    recoveryAttemptRef = useRef(0);
    recoveryTimerRef = useRef(None);

    params = useParams();

    def _clearAutoSaveTimer() -> None {
        if autoSaveTimerRef.current {
            clearTimeout(autoSaveTimerRef.current);
            autoSaveTimerRef.current = None;
        }
    }

    useEffect(lambda {
        previewStatusRef.current = previewStatus;
        # Auto-recovery: when preview hits "error" after retries exhausted,
        # attempt full session recovery (re-setup + re-start) up to 2 times.
        if previewStatus == "error" and projectId {
            attempts = recoveryAttemptRef.current;
            if attempts < 2 {
                delay = (3000 if attempts == 0 else 8000);
                console.log("[recovery] Preview error, scheduling recovery attempt " + String(attempts + 1) + "/2 in " + String(delay) + "ms");
                recoveryTimerRef.current = setTimeout(lambda {
                    recoveryAttemptRef.current = recoveryAttemptRef.current + 1;
                    previewRetryRef.current = 0;
                    console.log("[recovery] Running session recovery...");
                    ideSetup(projectId).then(lambda(setupRes: Any) {
                        setupReport = setupRes.reports[0] if setupRes and setupRes.reports and setupRes.reports.length > 0 else None;
                        if setupReport and setupReport.success {
                            previewStatus = "starting";
                            previewStatusRef.current = "starting";
                            terminalContent = "";
                            logOffsetRef.current = 0;
                            uid = userId;
                            pid = projectId;
                            sendWsRequest("start", uid, pid, 0, lambda(msg: Any) {
                                if msg and msg.data and msg.data.success {
                                    previewUrl = msg.data.url or "";
                                    previewPort = msg.data.port or 0;
                                    apiPort = msg.data.api_port or 0;
                                }
                            });
                            startWsPolling(uid, pid);
                        } else {
                            console.warn("[recovery] Setup failed during recovery");
                        }
                    });
                }, delay);
            } else {
                console.log("[recovery] Max recovery attempts reached, giving up");
            }
        }
        # Reset recovery counter on successful start
        if previewStatus == "running" {
            recoveryAttemptRef.current = 0;
            if recoveryTimerRef.current {
                clearTimeout(recoveryTimerRef.current);
                recoveryTimerRef.current = None;
            }
        }
    }, [previewStatus]);

    async def _refreshVersions(pid: str) -> None {
        if not pid { return; }
        result = await ideListVersions(pid);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            versions = rpt.versions or [];
        }
    }

    async def doRefreshFiles(pid: str = "") -> None {
        targetPid = pid or projectId;
        if not targetPid { return; }
        result = await ideListFiles(targetPid);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            fileList = rpt.files or [];
        }
    }

    async def _setupProjectWorkspace(pid: str) -> bool {
        if not pid { return False; }
        setupRaw = await ideSetup(pid);
        setup = setupRaw.reports[0] if setupRaw and setupRaw.reports and setupRaw.reports.length > 0 else None;
        if not setup or not setup.success {
            console.warn("[useIDE] setup failed, retrying in 2s...");
            await (Reflect.construct(Promise, [lambda(resolve: Any) { setTimeout(resolve, 2000); }]));
            setupRaw = await ideSetup(pid);
            setup = setupRaw.reports[0] if setupRaw and setupRaw.reports and setupRaw.reports.length > 0 else None;
            if not setup or not setup.success {
                console.warn("[useIDE] setup failed twice, retrying in 5s...");
                await (Reflect.construct(Promise, [lambda(resolve: Any) { setTimeout(resolve, 5000); }]));
                setupRaw = await ideSetup(pid);
                setup = setupRaw.reports[0] if setupRaw and setupRaw.reports and setupRaw.reports.length > 0 else None;
            }
        }
        await Promise.all([doRefreshFiles(pid), _refreshVersions(pid)]);
        return (setup and setup.success) or False;
    }

    async def _initializeProject() -> None {
        isLoading = True;

        pid = params.projectId or "";
        if not pid {
            meRaw = await ideGetMe();
            meReport = meRaw.reports[0] if meRaw and meRaw.reports and meRaw.reports.length > 0 else None;
            if meReport and meReport.success and meReport.user {
                userId = meReport.user.user_id or "";
            }
            isLoading = False;
            isSetup = True;
            return;
        }
        projectId = pid;

        results = await Promise.all([ideGetMe(), ideListTemplates(), ideOpenProject(pid)]);
        meRaw = results[0];
        templateRaw = results[1];
        openRaw = results[2];

        meResult = meRaw.reports[0] if meRaw and meRaw.reports and meRaw.reports.length > 0 else None;
        templateRes = templateRaw.reports[0] if templateRaw and templateRaw.reports and templateRaw.reports.length > 0 else None;
        openResult = openRaw.reports[0] if openRaw and openRaw.reports and openRaw.reports.length > 0 else None;

        if meResult and meResult.success and meResult.user {
            userId = meResult.user.user_id or "";
        }
        templates = templateRes.templates if templateRes and templateRes.success else [];
        if openResult and openResult.success and openResult.project {
            project = openResult.project;
            projectType = openResult.project.project_type or "fullstack";
            deploymentStatus = openResult.project.deployment_status or "";
            deploymentUrl = openResult.project.deployment_url or "";
            if deploymentStatus == "deploying" {
                _startDeployPoll(pid);
            }
            sandboxStatus = openResult.project.sandbox_status or "";
            sandboxUrl = openResult.project.sandbox_url or "";
            if sandboxStatus == "deploying" {
                _startSandboxPoll(pid);
            }
        }

        await _setupProjectWorkspace(pid);

        # Recover preview state if sandbox is already running (e.g. after browser refresh).
        # Without this, previewStatus stays "stopped" and user sees "No Preview Running"
        # even though the backend process is still alive.
        uid = userId;
        if uid and pid {
            sendWsRequest("status", uid, pid, 0, lambda(msg: Any) {
                if not msg or not msg.data { return; }
                data = msg.data;
                if data.status == "running" and data.url {
                    previewUrl = data.url or "";
                    previewPort = data.port or 0;
                    apiPort = data.api_port or (data.port + 1 if data.port else 0);
                    previewStatus = "running";
                    previewStatusRef.current = "running";
                } elif data.status == "starting" {
                    previewStatus = "starting";
                    previewStatusRef.current = "starting";
                    startWsPolling(uid, pid);
                }
            });
        }

        isSetup = True;
        isLoading = False;
    }

    useEffect(lambda {
        _initializeProject();
    }, []);

    # File event polling — runs independently of preview status.
    # Detects terminal file creates/deletes/edits and syncs the IDE.
    fileEventTimerRef = useRef(None);
    openTabsRef = useRef([]);
    useEffect(lambda { openTabsRef.current = openTabs; }, [openTabs]);
    activeTabRef = useRef("");
    useEffect(lambda { activeTabRef.current = activeTab; }, [activeTab]);

    useEffect(lambda -> Any {
        if not projectId or not userId { return; }
        pid = projectId;
        uid = userId;

        def pollFileEvents() -> None {
            if not pid { return; }
            sendWsRequest("file_events", uid, pid, 0, lambda(msg: Any) {
                if not msg or not msg.data or not msg.data.success { return; }
                events = msg.data.events;
                if not events or events.length == 0 { return; }

                needsRefresh = False;
                modifiedPaths = [];

                for evt in events {
                    evtType = evt.type or "";
                    evtPath = evt.path or "";

                    if evtType == "file_created" or evtType == "file_deleted" or evtType == "dir_created" or evtType == "dir_deleted" or evtType == "file_moved" or evtType == "dir_moved" {
                        needsRefresh = True;
                    } elif evtType == "file_modified" {
                        modifiedPaths.push(evtPath);
                    }
                }

                if needsRefresh {
                    doRefreshFiles(pid);
                }

                # Reload open tabs that were modified externally
                if modifiedPaths.length > 0 {
                    currentTabs = openTabsRef.current or [];
                    currentActive = activeTabRef.current or "";
                    for modPath in modifiedPaths {
                        for tab in currentTabs {
                            if tab.path == modPath and not tab.isDirty {
                                closeTab(modPath);
                                openFile(modPath);
                                break;
                            }
                        }
                    }
                }
            });
            fileEventTimerRef.current = setTimeout(pollFileEvents, 2000);
        }

        fileEventTimerRef.current = setTimeout(pollFileEvents, 2000);

        return lambda {
            if fileEventTimerRef.current {
                clearTimeout(fileEventTimerRef.current);
            }
        };
    }, [projectId, userId]);

    async def openFile(path: str) -> None {
        if not projectId or not path { return; }
        existing = None;
        for tab in openTabs {
            if tab.path == path {
                existing = tab;
                break;
            }
        }
        if existing {
            activeTab = path;
            return;
        }

        result = await ideReadFile(projectId, path);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            newTab = {
                "path": path,
                "content": rpt.content or "",
                "isDirty": False,
                "isBinary": rpt.is_binary or False,
                "mimeType": rpt.mime_type or ""
            };
            openTabs = lambda prev: Any -> Any { return prev.concat([newTab]); };
            activeTab = path;
        }
    }

    def openDiffTab(diffPath: str, diffData: Any) -> None {
        for tab in openTabs {
            if tab.path == diffPath {
                activeTab = diffPath;
                return;
            }
        }
        newTab = {
            "path": diffPath,
            "content": "",
            "isDirty": False,
            "isBinary": False,
            "mimeType": "",
            "isDiff": True,
            "diffData": diffData
        };
        openTabs = lambda prev: Any -> Any { return prev.concat([newTab]); };
        activeTab = diffPath;
    }

    def closeTab(path: str) -> None {
        openTabs = lambda prev: Any -> Any {
            return prev.filter(lambda t: Any -> bool { return t.path != path; });
        };
        if activeTab == path {
            activeTab = "";
        }
    }

    def updateTabContent(path: str, newContent: str) -> None {
        openTabs = lambda prev: Any -> Any {
            return prev.map(lambda t: Any -> Any {
                if t.path == path {
                    return {
                        "path": t.path,
                        "content": newContent,
                        "isDirty": True,
                        "isBinary": t.isBinary or False,
                        "mimeType": t.mimeType or ""
                    };
                }
                return t;
            });
        };
    }

    useEffect(lambda {
        hasDirty = False;
        for t in openTabs {
            if t.isDirty and not t.isDiff {
                hasDirty = True;
                break;
            }
        }

        if hasDirty and activeTab and not activeTab.startsWith("diff://") {
            _clearAutoSaveTimer();
            autoSaveTimerRef.current = setTimeout(lambda {
                saveFile();
            }, 2000);
        }

        return lambda -> None {
            _clearAutoSaveTimer();
        };
    }, [openTabs, activeTab, projectId]);

    async def saveFile(path: str = "") -> None {
        if not projectId { return; }
        targetPath = path or activeTab;
        if not targetPath { return; }

        tabContent = "";
        targetTab = None;
        for t in openTabs {
            if t.path == targetPath {
                targetTab = t;
                tabContent = t.content;
                break;
            }
        }

        if not targetTab {
            console.warn("saveFile skipped: target tab is not open", targetPath);
            return;
        }

        if targetTab.isBinary {
            console.warn("saveFile skipped: binary tab", targetPath);
            return;
        }

        if targetTab.isDiff {
            return;
        }

        result = await ideWriteFile(projectId, targetPath, tabContent);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            writeVersion = rpt.version if rpt and rpt.version else None;

            if writeVersion and writeVersion.success and writeVersion.skipped {
                await ideCaptureVersion(projectId);
            }

            openTabs = lambda prev: Any -> Any {
                return prev.map(lambda t: Any -> Any {
                    if t.path == targetPath {
                        return {
                            "path": t.path,
                            "content": t.content,
                            "isDirty": False,
                            "isBinary": t.isBinary or False,
                            "mimeType": t.mimeType or ""
                        };
                    }
                    return t;
                });
            };
            await Promise.all([doRefreshFiles(), _refreshVersions(projectId)]);
        }
    }

    async def createFile(fileName: str) -> None {
        if not projectId or not fileName { return; }
        result = await ideWriteFile(projectId, fileName, "");
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            await doRefreshFiles();
            await openFile(fileName);
            _refreshVersions(projectId);
        }
    }

    async def deleteFile(path: str) -> None {
        if not projectId { return; }
        result = await ideDeleteFile(projectId, path);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            closeTab(path);
            await Promise.all([doRefreshFiles(), _refreshVersions(projectId)]);
        }
    }

    async def renameFile(oldPath: str, newPath: str) -> None {
        if not projectId or not oldPath or not newPath { return; }
        result = await ideRenameFile(projectId, oldPath, newPath);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            openTabs = lambda prev: Any -> Any {
                return prev.map(lambda t: Any -> Any {
                    if t.path == oldPath {
                        return {
                            "path": newPath,
                            "content": t.content,
                            "isDirty": t.isDirty,
                            "isBinary": t.isBinary or False,
                            "mimeType": t.mimeType or ""
                        };
                    }
                    return t;
                });
            };
            if activeTab == oldPath {
                activeTab = newPath;
            }
            await Promise.all([doRefreshFiles(), _refreshVersions(projectId)]);
        }
    }

    async def createDir(dirPath: str) -> None {
        if not projectId or not dirPath { return; }
        result = await ideMkdir(projectId, dirPath);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            await Promise.all([doRefreshFiles(), _refreshVersions(projectId)]);
        }
    }

    async def copyFile(srcPath: str, destPath: str) -> None {
        if not projectId or not srcPath or not destPath { return; }
        result = await ideCopyFile(projectId, srcPath, destPath);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            await doRefreshFiles();
            openFile(destPath);
        }
    }

    async def duplicateFile(path: str) -> None {
        if not projectId or not path { return; }
        parts = path.split("/");
        fileName = parts[parts.length - 1];
        dotIdx = fileName.lastIndexOf(".");
        baseName = fileName;
        ext = "";
        if dotIdx > 0 {
            baseName = fileName.substring(0, dotIdx);
            ext = fileName.substring(dotIdx);
        }
        newName = baseName + "-copy" + ext;
        parts[parts.length - 1] = newName;
        destPath = parts.join("/");
        await copyFile(path, destPath);
    }

    async def checkoutVersion(versionId: str = "", commitSha: str = "") -> Any {
        if not projectId { return {"success": False, "error": "No active project"}; }
        _clearAutoSaveTimer();
        result = await ideCheckoutVersion(projectId, versionId, commitSha);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            previewStatus = "stopped";
            previewStatusRef.current = "stopped";
            previewUrl = "";
            previewPort = 0;
            logOffsetRef.current = 0;
            closePreviewWs();
            openTabs = [];
            activeTab = "";
            terminalContent = "";
            await _setupProjectWorkspace(projectId);
        }
        return rpt;
    }

    async def exportVersion(versionId: str = "", outputPath: str = "") -> Any {
        if not projectId { return {"success": False, "error": "No active project"}; }
        result = await ideExportVersionDownload(projectId, versionId);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            return rpt;
        }
        fallbackResult = await ideExportVersion(projectId, versionId, outputPath);
        fallbackReport = fallbackResult.reports[0] if fallbackResult and fallbackResult.reports and fallbackResult.reports.length > 0 else None;
        return fallbackReport;
    }

    def startWsPolling(uid: str, pid: str) -> None {
        def pollStatus() -> None {
            if previewStatusRef.current != "starting" { return; }
            sendWsRequest("status", uid, pid, 0, lambda(msg: Any) {
                if not msg or not msg.data { return; }
                data = msg.data;
                if data.status == "running" {
                    previewUrl = data.url or "";
                    previewPort = data.port or 0;
                    apiPort = data.api_port or (data.port + 1 if data.port else 0);
                    previewStatus = "running";
                    previewStatusRef.current = "running";
                    previewRetryRef.current = 0;
                    screenshotPid = pid;
                    console.log("[screenshot] Preview running, will capture in 8s for project:", screenshotPid);
                    setTimeout(lambda {
                        console.log("[screenshot] Firing auto-capture now for:", screenshotPid);
                        idePreviewScreenshot(screenshotPid).then(lambda(res: Any) {
                            console.log("[screenshot] Auto-capture result:", res);
                        });
                    }, 8000);
                } elif data.status == "none" or (not data.status and not data.success) {
                    previewRetryRef.current = previewRetryRef.current + 1;
                    if previewRetryRef.current <= 3 {
                        console.log("[preview] Sandbox gone, retry " + String(previewRetryRef.current) + "/3...");
                        sendWsRequest("start", uid, pid, 0, lambda(_: Any) {});
                    } else {
                        console.log("[preview] Max retries reached, stopping.");
                        previewStatus = "error";
                        previewStatusRef.current = "error";
                    }
                } elif data.status == "error" or data.status == "stopped" {
                    previewStatus = data.status;
                    previewStatusRef.current = data.status;
                }
            });
            setTimeout(lambda {
                if previewStatusRef.current == "starting" {
                    pollStatus();
                }
            }, 2000);
        }

        def pollLog() -> None {
            status = previewStatusRef.current;
            if status != "starting" and status != "running" { return; }
            sendWsRequest("log", uid, pid, logOffsetRef.current, lambda(msg: Any) {
                if not msg or not msg.data { return; }
                data = msg.data;
                if data.success and data.content {
                    terminalContent = lambda prev: Any -> Any { return prev + data.content; };
                    logOffsetRef.current = data.offset or logOffsetRef.current;
                    idleCountRef.current = 0;
                    isHmrSuccess = data.content.includes("✔ Recompiled:") or
                                  data.content.includes("[vite] hmr update");
                    if isHmrSuccess {
                        previewErrors = [];
                    } else {
                        newErrors = _parsePreviewErrors(data.content);
                        if newErrors.length > 0 {
                            previewErrors = lambda prev: Any -> Any {
                                merged = prev.concat(newErrors);
                                return merged.filter(lambda(item: Any, idx: Any, arr: Any) -> bool {
                                    return arr.indexOf(item) == idx;
                                });
                            };
                        }
                    }
                } elif not data.success and previewStatusRef.current == "running" {
                    previewRetryRef.current = previewRetryRef.current + 1;
                    if previewRetryRef.current <= 3 {
                        console.log("[preview] Sandbox lost while running, retry " + String(previewRetryRef.current) + "/3...");
                        previewStatus = "starting";
                        previewStatusRef.current = "starting";
                        terminalContent = "";
                        logOffsetRef.current = 0;
                        sendWsRequest("start", uid, pid, 0, lambda(startMsg: Any) {
                            if startMsg and startMsg.data and startMsg.data.success {
                                previewUrl = startMsg.data.url or "";
                                previewPort = startMsg.data.port or 0;
                            }
                        });
                        pollStatus();
                    } else {
                        console.log("[preview] Max retries reached, stopping.");
                        previewStatus = "error";
                        previewStatusRef.current = "error";
                    }
                } else {
                    idleCountRef.current = idleCountRef.current + 1;
                }
            });
            setTimeout(lambda {
                s = previewStatusRef.current;
                if s != "starting" and s != "running" { return; }
                pollLog();
            }, (1500 if previewStatusRef.current == "starting" else (Math.min(1500 + idleCountRef.current * 500, 10000) if idleCountRef.current > 5 else 2000)));
        }

        idleCountRef.current = 0;
        setTimeout(pollStatus, 1000);
        setTimeout(pollLog, 1000);
    }

    def startPreview() -> None {
        if not projectId { return; }
        terminalContent = "";
        logOffsetRef.current = 0;
        previewRetryRef.current = 0;
        previewErrors = [];
        previewStatus = "starting";
        previewStatusRef.current = "starting";

        sendWsRequest("start", userId, projectId, 0, lambda(msg: Any) {
            if msg and msg.data {
                if msg.data.success {
                    previewUrl = msg.data.url or "";
                    previewPort = msg.data.port or 0;
                    apiPort = msg.data.api_port or 0;
                } else {
                    previewStatus = "error";
                    previewStatusRef.current = "error";
                }
            }
        });
        startWsPolling(userId, projectId);
    }

    def stopPreview() -> None {
        if not projectId { return; }
        previewStatus = "stopped";
        previewStatusRef.current = "stopped";
        previewUrl = "";
        previewPort = 0;
        previewErrors = [];
        sendWsRequest("stop", userId, projectId, 0, lambda(_: Any) {});
    }

    def openPreviewTab() -> None {
        if previewUrl {
            window.open(previewUrl, "_blank");
        }
    }

    def setActiveTabPath(path: str) -> None {
        activeTab = path;
    }

    def _startDeployPoll(pid: str) -> None {
        if deployPollRef.current {
            clearInterval(deployPollRef.current);
        }
        deployPollRef.current = setInterval(lambda {
            _checkDeployStatus(pid);
        }, 5000);
    }

    async def _checkDeployStatus(pid: str) -> None {
        result = await ideDeployStatus(pid);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success and rpt.deployment {
            newStatus = rpt.deployment.status or "";
            newUrl = rpt.deployment.url or "";
            deploymentStatus = newStatus;
            deploymentUrl = newUrl;
            if newStatus != "deploying" {
                if deployPollRef.current {
                    clearInterval(deployPollRef.current);
                    deployPollRef.current = None;
                }
            }
        }
    }

    async def deployProject() -> None {
        if not projectId { return; }
        deploymentStatus = "deploying";
        deploymentUrl = "";
        result = await ideDeployProject(projectId);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            _startDeployPoll(projectId);
        } else {
            deploymentStatus = "failed";
        }
    }

    async def destroyDeployment() -> None {
        if not projectId { return; }
        deploymentStatus = "destroying";
        result = await ideDestroyDeployment(projectId);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            deploymentStatus = "";
            deploymentUrl = "";
        } else {
            deploymentStatus = "failed";
        }
    }

    def _startSandboxPoll(pid: str) -> None {
        if sandboxPollRef.current {
            clearInterval(sandboxPollRef.current);
        }
        sandboxPollRef.current = setInterval(lambda {
            _checkSandboxStatus(pid);
        }, 5000);
    }

    async def _checkSandboxStatus(pid: str) -> None {
        result = await ideSandboxStatus(pid);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success and rpt.deployment {
            newStatus = rpt.deployment.status or "";
            newUrl = rpt.deployment.url or "";
            sandboxStatus = newStatus;
            sandboxUrl = newUrl;
            if newStatus != "deploying" {
                if sandboxPollRef.current {
                    clearInterval(sandboxPollRef.current);
                    sandboxPollRef.current = None;
                }
            }
        }
    }

    async def sandboxDeploy() -> None {
        if not projectId { return; }
        sandboxStatus = "deploying";
        sandboxUrl = "";
        result = await ideSandboxDeploy(projectId);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            _startSandboxPoll(projectId);
        } else {
            sandboxStatus = "failed";
        }
    }

    async def destroySandbox() -> None {
        if not projectId { return; }
        sandboxStatus = "destroying";
        result = await ideSandboxDestroy(projectId);
        rpt = result.reports[0] if result and result.reports and result.reports.length > 0 else None;
        if rpt and rpt.success {
            sandboxStatus = "";
            sandboxUrl = "";
        } else {
            sandboxStatus = "failed";
        }
    }

    useEffect(lambda {
        return lambda -> None {
            previewStatusRef.current = "stopped";
            closePreviewWs();
            if deployPollRef.current {
                clearInterval(deployPollRef.current);
            }
            if sandboxPollRef.current {
                clearInterval(sandboxPollRef.current);
            }
        };
    }, []);

    return {
        "userId": userId,
        "projectId": projectId,
        "project": project,
        "projectType": projectType,
        "templates": templates,
        "versions": versions,
        "isSetup": isSetup,
        "isLoading": isLoading,
        "files": fileList,
        "openTabs": openTabs,
        "activeTab": activeTab,
        "terminalContent": terminalContent,
        "previewUrl": previewUrl,
        "previewStatus": previewStatus,
        "previewPort": previewPort,
        "apiPort": apiPort,
        "openFile": openFile,
        "openDiffTab": openDiffTab,
        "closeTab": closeTab,
        "updateTabContent": updateTabContent,
        "saveFile": saveFile,
        "createFile": createFile,
        "deleteFile": deleteFile,
        "renameFile": renameFile,
        "createDir": createDir,
        "copyFile": copyFile,
        "duplicateFile": duplicateFile,
        "startPreview": startPreview,
        "stopPreview": stopPreview,
        "openPreview": openPreviewTab,
        "refreshFiles": doRefreshFiles,
        "setActiveTab": setActiveTabPath,
        "refreshVersions": lambda -> Any { return _refreshVersions(projectId); },
        "checkoutVersion": checkoutVersion,
        "exportVersion": exportVersion,
        "deploymentStatus": deploymentStatus,
        "deploymentUrl": deploymentUrl,
        "deployProject": deployProject,
        "destroyDeployment": destroyDeployment,
        "sandboxStatus": sandboxStatus,
        "sandboxUrl": sandboxUrl,
        "sandboxDeploy": sandboxDeploy,
        "destroySandbox": destroySandbox,
        "captureVersion": lambda -> Any { return ideCaptureVersion(projectId); },
        "previewRefreshKey": previewRefreshKey,
        "refreshPreview": lambda -> None { previewRefreshKey = previewRefreshKey + 1; },
        "previewErrors": previewErrors,
        "clearPreviewErrors": lambda -> None { previewErrors = []; }
    };
}
