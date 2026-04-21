"""Hook for managing project environment variables."""

import from ..services.ideService { ideEnvOps }

def _unwrap(result: Any) -> Any {
    return result.reports[0] if result and result.reports and result.reports.length > 0 else None;
}

def:pub useProjectSettings(projectId: str) -> Any {
    has projectVars: list = [];
    has projectVarsLoading: bool = False;
    has projectVarsSaving: bool = False;
    has projectVarsError: str = "";
    has aiModel: str = "default";

    async def loadProjectVars() -> None {
        if not projectId { return; }
        projectVarsLoading = True;
        result = _unwrap(await ideEnvOps(projectId, "list_project", []));
        projectVarsLoading = False;
        if result and result.success {
            projectVars = result.env_list or [];
            # Extract MODEL from env vars for the dropdown
            foundModel = "default";
            for v in projectVars {
                if v.key == "MODEL" {
                    foundModel = v.value;
                    break;
                }
            }
            aiModel = foundModel;
        }
    }

    def updateProjectVar(keyName: str, newVal: str) -> None {
        projectVars = projectVars.map(lambda (v: Any) -> Any {
            if v.key == keyName {
                return {"key": v.key, "value": newVal};
            }
            return v;
        });
    }

    def deleteProjectVar(keyName: str) -> None {
        projectVars = projectVars.filter(lambda (v: Any) -> bool { return v.key != keyName; });
    }

    def addProjectVar(keyName: str, val: str) -> None {
        trimmed = keyName.trim() if keyName else "";
        if not trimmed { return; }
        projectVars = projectVars.concat([{"key": trimmed, "value": val}]);
    }

    async def onAiModelChange(model: str) -> None {
        aiModel = model;
        # Reload current vars from backend to avoid overwriting user's API keys
        freshReport = _unwrap(await ideEnvOps(projectId, "list_project", []));
        freshVars: list = [];
        if freshReport and freshReport.success {
            freshVars = freshReport.env_list or [];
        }
        # Remove existing MODEL entry from fresh vars
        filtered = freshVars.filter(lambda (v: Any) -> bool { return v.key != "MODEL"; });
        # Add MODEL if not default
        if model and model != "default" {
            filtered = filtered.concat([{"key": "MODEL", "value": model}]);
        }
        projectVars = filtered;
        # Auto-save
        projectVarsSaving = True;
        saveReport = _unwrap(await ideEnvOps(projectId, "save_project", projectVars));
        projectVarsSaving = False;
        if not saveReport or not saveReport.success {
            projectVarsError = (saveReport.error if saveReport and saveReport.error else "Save failed");
        }
    }

    async def saveProjectVars() -> None {
        projectVarsSaving = True;
        result = _unwrap(await ideEnvOps(projectId, "save_project", projectVars));
        projectVarsSaving = False;
        if result and result.success {
            projectVarsError = "";
        } else {
            projectVarsError = (result.error if result and result.error else "Save failed");
        }
    }

    return {
        "projectVars": projectVars,
        "projectVarsLoading": projectVarsLoading,
        "projectVarsSaving": projectVarsSaving,
        "projectVarsError": projectVarsError,
        "loadProjectVars": loadProjectVars,
        "updateProjectVar": updateProjectVar,
        "deleteProjectVar": deleteProjectVar,
        "addProjectVar": addProjectVar,
        "saveProjectVars": saveProjectVars,
        "aiModel": aiModel,
        "onAiModelChange": onAiModelChange
    };
}
