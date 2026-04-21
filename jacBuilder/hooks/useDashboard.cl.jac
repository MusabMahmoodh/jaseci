"""Dashboard state hook — user info, project list, create project, import jacpack."""
import from react { useState, useEffect }
import from "@jac/runtime" { useNavigate }
import from ..services.ideService {
    ideListProjects,
    ideCreateProject,
    ideImportProject,
    ideDeleteProject,
    ideRenameProject,
    ideGetMe,
    ideListTemplates,
    ideListVersions,
    ideExportVersionDownload,
    communitySubmit,
    ideGetProjectThumbnail,
    ideBatchWrite,
    githubOps
}
import from ..utils.toast { notify }

"""Hook for dashboard: user info, projects, create/delete/import actions."""
def:pub useDashboard(onShareSuccess: Any = None) -> Any {
    has user: Any = None;
    has projects: list = [];
    has templates: list = [];
    has isLoading: bool = True;
    has createModalOpen: bool = False;
    has createMode: str = "template";
    has newProjectName: str = "";
    has selectedTemplate: str = "";
    has createError: str = "";
    has isCreating: bool = False;
    has jacpackUrl: str = "";
    has jacpackFile: Any = None;
    has shareModalOpen: bool = False;
    has shareTarget: Any = None;
    has shareName: str = "";
    has shareDescription: str = "";
    has shareTags: str = "";
    has shareAgreed: bool = False;
    has isSharing: bool = False;
    has shareError: str = "";
    has shareSuccess: bool = False;
    has thumbnails: Any = {};
    has renameModalOpen: bool = False;
    has renameTarget: Any = None;
    has renameName: str = "";
    has isRenaming: bool = False;
    has renameError: str = "";
    has deleteConfirmOpen: bool = False;
    has deleteConfirmTarget: Any = None;
    has isDeleting: bool = False;
    has folderFiles: list = [];
    has folderName: str = "";

    navigate = useNavigate();

    async def loadData() -> None {
        isLoading = True;
        meRaw = await ideGetMe();
        meResult = meRaw.reports[0] if meRaw and meRaw.reports and meRaw.reports.length > 0 else None;
        if meResult and meResult.success {
            user = meResult.user;
        }
        projectsList = [];
        projectsRaw = await ideListProjects();
        projectsResult = projectsRaw.reports[0] if projectsRaw and projectsRaw.reports and projectsRaw.reports.length > 0 else None;
        if projectsResult and projectsResult.success {
            projectsList = projectsResult.projects or [];
            projects = projectsList;
        }
        templatesRaw = await ideListTemplates();
        templatesResult = templatesRaw.reports[0] if templatesRaw and templatesRaw.reports and templatesRaw.reports.length > 0 else None;
        if templatesResult and templatesResult.success {
            templates = templatesResult.templates or [];
        }
        isLoading = False;
        loadThumbnails(projectsList);
    }

    async def loadThumbnails(projectList: list) -> None {
        for p in projectList {
            if p.has_thumbnail {
                thumbRaw = await ideGetProjectThumbnail(p.id);
                result = thumbRaw.reports[0] if thumbRaw and thumbRaw.reports and thumbRaw.reports.length > 0 else None;
                if result and result.success and result.image {
                    dataUri = "data:" + (result.mime_type or "image/jpeg") + ";base64," + result.image;
                    thumbnails = lambda prev: Any -> Any {
                        updated = Object.assign({}, prev);
                        updated[p.id] = dataUri;
                        return updated;
                    };
                }
            }
        }
    }

    useEffect(lambda {
        loadData();
    }, []);

    async def quickCreate(prompt: str) -> None {
        projectName = prompt.trim().slice(0, 40) or "My Project";
        isCreating = True;
        createError = "";
        raw = await ideCreateProject(projectName, "client");
        result = raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
        if result and result.success and result.project {
            navigate("/project/" + result.project.id + "?prompt=" + encodeURIComponent(prompt.trim()));
        } else {
            createError = (result.error if result and result.error else "Failed to create project");
        }
        isCreating = False;
    }

    async def createProject(name: str, templateId: str) -> None {
        if not name.trim() or not templateId {
            createError = "Name and template are required";
            return;
        }
        isCreating = True;
        createError = "";
        raw = await ideCreateProject(name.trim(), templateId);
        result = raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
        if result and result.success and result.project {
            createModalOpen = False;
            newProjectName = "";
            selectedTemplate = "";
            navigate("/project/" + result.project.id);
        } else {
            createError = (result.error if result and result.error else "Failed to create project");
        }
        isCreating = False;
    }

    async def importProject(name: str, url: str, file: Any) -> None {
        if not name.trim() {
            createError = "Project name is required";
            return;
        }
        if not url and not file {
            createError = "Provide a JacPack URL or upload a file";
            return;
        }
        isCreating = True;
        createError = "";
        base64Content = "";
        if file {
            try {
                arrayBuffer = await file.arrayBuffer();
                uint8 = Reflect.construct(Uint8Array, [arrayBuffer]);
                binaryString = Array.from(uint8).map(lambda b: Any -> Any { return String.fromCharCode(b); }).join("");
                base64Content = btoa(binaryString);
            } except Exception as e {
                createError = "Failed to read file: " + String(e);
                isCreating = False;
                return;
            }
        }
        raw = await ideImportProject(name.trim(), url.trim(), base64Content);
        result = raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
        if result and result.success and result.project {
            createModalOpen = False;
            newProjectName = "";
            jacpackUrl = "";
            jacpackFile = None;
            navigate("/project/" + result.project.id);
        } else {
            createError = (result.error if result and result.error else "Failed to import project");
        }
        isCreating = False;
    }

    def openShareModal(project: Any) -> None {
        shareTarget = project;
        shareName = project.name or "";
        shareDescription = "";
        shareTags = "";
        shareAgreed = False;
        shareError = "";
        shareSuccess = False;
        shareModalOpen = True;
    }

    def closeShareModal() -> None {
        shareModalOpen = False;
        shareTarget = None;
        shareError = "";
        shareSuccess = False;
    }

    async def shareProject(projectId: str, name: str, description: str, tagsStr: str) -> None {
        if not name.trim() {
            shareError = "Name is required";
            return;
        }
        isSharing = True;
        shareError = "";
        shareSuccess = False;
        versionsRaw = await ideListVersions(projectId);
        versionsResult = versionsRaw.reports[0] if versionsRaw and versionsRaw.reports and versionsRaw.reports.length > 0 else None;
        versions = (versionsResult.versions if versionsResult and versionsResult.success else []);
        versionId = "";
        if versions and versions.length > 0 {
            versionId = versions[0].id or "";
        }
        if not versionId {
            shareError = "No saved versions found. Save your project before sharing.";
            isSharing = False;
            return;
        }
        exportRaw = await ideExportVersionDownload(projectId, versionId);
        exportResult = exportRaw.reports[0] if exportRaw and exportRaw.reports and exportRaw.reports.length > 0 else None;
        if not exportResult or not exportResult.success {
            shareError = (exportResult.error if exportResult and exportResult.error else "Failed to export project");
            isSharing = False;
            return;
        }
        tags: list = [];
        if tagsStr.trim() {
            rawTags = tagsStr.split(",");
            for rawTag in rawTags {
                t = rawTag.trim();
                if t { tags.push(t); }
            }
        }
        submitRaw = await communitySubmit(name.trim(), description.trim(), tags, exportResult.content_base64 or "");
        result = submitRaw.reports[0] if submitRaw and submitRaw.reports and submitRaw.reports.length > 0 else None;
        if result and result.success {
            shareSuccess = True;
            shareModalOpen = False;
            notify("Shared", "Project shared to community", "success");
            if onShareSuccess { refreshFn = onShareSuccess; refreshFn.call(None); }
        } else {
            shareError = (result.error if result and result.error else "Failed to share project");
        }
        isSharing = False;
    }

    def openRenameModal(project: Any) -> None {
        renameTarget = project;
        renameName = project.name or "";
        renameError = "";
        renameModalOpen = True;
    }

    def closeRenameModal() -> None {
        renameModalOpen = False;
        renameTarget = None;
        renameError = "";
    }

    async def renameProject(projectId: str, newName: str) -> None {
        if not newName.trim() {
            renameError = "Name is required";
            return;
        }
        isRenaming = True;
        renameError = "";
        renameRaw = await ideRenameProject(projectId, newName.trim());
        result = renameRaw.reports[0] if renameRaw and renameRaw.reports and renameRaw.reports.length > 0 else None;
        if result and result.success {
            renameModalOpen = False;
            renameTarget = None;
            projectsRaw = await ideListProjects();
            projectsResult = projectsRaw.reports[0] if projectsRaw and projectsRaw.reports and projectsRaw.reports.length > 0 else None;
            if projectsResult and projectsResult.success {
                projects = projectsResult.projects or [];
            }
        } else {
            renameError = (result.error if result and result.error else "Failed to rename project");
        }
        isRenaming = False;
    }

    def openDeleteConfirm(project: Any) -> None {
        deleteConfirmTarget = project;
        deleteConfirmOpen = True;
    }

    def closeDeleteConfirm() -> None {
        deleteConfirmOpen = False;
        deleteConfirmTarget = None;
    }

    async def createFromFolder(name: str, files: list) -> None {
        if not name.trim() {
            createError = "Project name is required";
            return;
        }
        if not files or files.length == 0 {
            createError = "No files to upload";
            return;
        }
        isCreating = True;
        createError = "";
        createRaw = await ideCreateProject(name.trim(), "empty");
        result = createRaw.reports[0] if createRaw and createRaw.reports and createRaw.reports.length > 0 else None;
        if not result or not result.success or not result.project {
            createError = (result.error if result and result.error else "Failed to create project");
            isCreating = False;
            return;
        }
        projectId = result.project.id;
        batchRaw = await ideBatchWrite(projectId, files);
        batchResult = batchRaw.reports[0] if batchRaw and batchRaw.reports and batchRaw.reports.length > 0 else None;
        if not batchResult or not batchResult.success {
            createError = "Project created but file upload failed: " + (batchResult.error if batchResult and batchResult.error else "unknown error");
            isCreating = False;
            navigate("/project/" + projectId);
            return;
        }
        createModalOpen = False;
        newProjectName = "";
        folderFiles = [];
        folderName = "";
        isCreating = False;
        navigate("/project/" + projectId);
    }

    async def confirmDelete() -> None {
        if not deleteConfirmTarget { return; }
        pId = deleteConfirmTarget.id;
        deleteConfirmOpen = False;
        deleteConfirmTarget = None;
        await deleteProject(pId);
    }

    async def deleteProject(projectId: str) -> None {
        isDeleting = True;
        deleteRaw = await ideDeleteProject(projectId);
        result = deleteRaw.reports[0] if deleteRaw and deleteRaw.reports and deleteRaw.reports.length > 0 else None;
        if result and result.success {
            # Remove deleted project from local state immediately
            projects = projects.filter(lambda p: Any -> Any { return p.id != projectId; });
            # Remove thumbnail for deleted project
            thumbnails = lambda prev: Any -> Any {
                updated = {};
                Object.keys(prev).forEach(lambda(k: Any) -> None {
                    if k != projectId {
                        updated[k] = prev[k];
                    }
                });
                return updated;
            };
            notify("Deleted", "Project deleted successfully", "success");
        } else {
            notify("Error", (result.error if result else "Failed to delete project"), "destructive");
        }
        isDeleting = False;
    }

    async def importFromGithub(repoName: str, cloneUrl: str) -> Any {
        isCreating = True;
        createError = "";
        raw = await githubOps("import_repo", {
            "repo_name": repoName,
            "clone_url": cloneUrl
        });
        result = raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
        isCreating = False;
        if result and result.success {
            createModalOpen = False;
            navigate("/project/" + result.project.id);
        } else {
            createError = (result.error if result else "Import failed");
        }
        return result;
    }

    async def listGithubRepos(page: int = 1) -> Any {
        raw = await githubOps("list_repos", {"page": page, "per_page": 30});
        return raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
    }

    async def getGithubStatus() -> Any {
        raw = await githubOps("status", {});
        return raw.reports[0] if raw and raw.reports and raw.reports.length > 0 else None;
    }

    return {
        "user": user,
        "projects": projects,
        "templates": templates,
        "isLoading": isLoading,
        "createModalOpen": createModalOpen,
        "setCreateModalOpen": lambda v: bool { createModalOpen = v; },
        "createMode": createMode,
        "setCreateMode": lambda v: str { createMode = v; createError = ""; },
        "newProjectName": newProjectName,
        "setNewProjectName": lambda v: str { newProjectName = v; },
        "selectedTemplate": selectedTemplate,
        "setSelectedTemplate": lambda v: str { selectedTemplate = v; },
        "jacpackUrl": jacpackUrl,
        "setJacpackUrl": lambda v: str { jacpackUrl = v; },
        "jacpackFile": jacpackFile,
        "setJacpackFile": lambda v: Any { jacpackFile = v; },
        "createError": createError,
        "isCreating": isCreating,
        "quickCreate": quickCreate,
        "createProject": createProject,
        "importProject": importProject,
        "createFromFolder": createFromFolder,
        "folderFiles": folderFiles,
        "setFolderFiles": lambda v: list { folderFiles = v; },
        "folderName": folderName,
        "setFolderName": lambda v: str { folderName = v; },
        "deleteProject": deleteProject,
        "importFromGithub": importFromGithub,
        "listGithubRepos": listGithubRepos,
        "getGithubStatus": getGithubStatus,
        "shareModalOpen": shareModalOpen,
        "shareTarget": shareTarget,
        "shareName": shareName,
        "setShareName": lambda v: str { shareName = v; },
        "shareDescription": shareDescription,
        "setShareDescription": lambda v: str { shareDescription = v; },
        "shareTags": shareTags,
        "setShareTags": lambda v: str { shareTags = v; },
        "shareAgreed": shareAgreed,
        "setShareAgreed": lambda v: bool { shareAgreed = v; },
        "isSharing": isSharing,
        "shareError": shareError,
        "shareSuccess": shareSuccess,
        "openShareModal": openShareModal,
        "closeShareModal": closeShareModal,
        "shareProject": shareProject,
        "thumbnails": thumbnails,
        "renameModalOpen": renameModalOpen,
        "renameTarget": renameTarget,
        "renameName": renameName,
        "setRenameName": lambda v: str { renameName = v; },
        "isRenaming": isRenaming,
        "renameError": renameError,
        "openRenameModal": openRenameModal,
        "closeRenameModal": closeRenameModal,
        "renameProject": renameProject,
        "deleteConfirmOpen": deleteConfirmOpen,
        "deleteConfirmTarget": deleteConfirmTarget,
        "isDeleting": isDeleting,
        "openDeleteConfirm": openDeleteConfirm,
        "closeDeleteConfirm": closeDeleteConfirm,
        "confirmDelete": confirmDelete
    };
}
