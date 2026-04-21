"""Git panel — VS Code Source Control style: repo header, commit area, changes list, overflow menu."""

import from react { useState, useRef, useEffect }
import from "..ui.scroll-area" { ScrollArea }
import from ..ui.input { Input }
import from ..ui.button { Button }
import from ..ui.badge { Badge }
import from ..ui.spinner { Spinner }
import from ..ui.tooltip { Tooltip, TooltipTrigger, TooltipContent }
import from "..ui.alert-dialog" {
    AlertDialog, AlertDialogContent, AlertDialogHeader,
    AlertDialogTitle, AlertDialogDescription,
    AlertDialogFooter, AlertDialogCancel, AlertDialogAction
}
import from "..ui.dropdown-menu" {
    DropdownMenu, DropdownMenuTrigger, DropdownMenuContent,
    DropdownMenuItem, DropdownMenuSeparator, DropdownMenuSub,
    DropdownMenuSubTrigger, DropdownMenuSubContent, DropdownMenuPortal,
    DropdownMenuLabel
}
import from ..ui.dialog { Dialog, DialogContent, DialogHeader, DialogTitle }
import from ..ui.select { Select, SelectTrigger, SelectValue, SelectContent, SelectItem }
import from ..ui.switch { Switch }
import from ..ui.label { Label }
import from ..ui.textarea { Textarea }
import from ..ui.alert { Alert }
import from "...utils.toast" { notify }
import from "@hugeicons/react" { HugeiconsIcon }
import from "@hugeicons/core-free-icons" {
    GitBranchIcon, GitCommitIcon, GitMergeIcon,
    ArrowUp01Icon, ArrowDown01Icon, Refresh01Icon, PlusSignIcon, Tick02Icon,
    AlertCircleIcon, MinusSignIcon, Delete02Icon, Clock01Icon, ArrowTurnBackwardIcon,
    InternetIcon, Cancel01Icon, MoreHorizontalCircle01Icon, Copy01Icon,
    Link01Icon, GitPullRequestIcon, ArrowDown02Icon, Download04Icon,
    Upload04Icon, ArrowRight01Icon, FolderOpenIcon
}
import from "...lib.utils" { cn }

def _notify(title: str, message: str, color: str) -> None {
    notify(title, message, color);
}

def _relativeTime(dateStr: str) -> str {
    if not dateStr { return ""; }
    try {
        now = Date.now();
        then = Reflect.construct(Date, [dateStr]).getTime();
        diffSec = Math.floor((now - then) / 1000);
        if diffSec < 60 { return String(diffSec) + "s ago"; }
        diffMin = Math.floor(diffSec / 60);
        if diffMin < 60 { return String(diffMin) + "m ago"; }
        diffHr = Math.floor(diffMin / 60);
        if diffHr < 24 { return String(diffHr) + "h ago"; }
        diffDay = Math.floor(diffHr / 24);
        if diffDay < 30 { return String(diffDay) + "d ago"; }
        diffMo = Math.floor(diffDay / 30);
        return String(diffMo) + "mo ago";
    } except Exception {
        return "";
    }
}

def _isGithubRemote(url: str) -> bool {
    if not url { return False; }
    lower = url.toLowerCase();
    return lower.indexOf("github.com") >= 0;
}

def _statusColor(code: str) -> str {
    if code == "M" or code == "MM" { return "text-warning"; }
    if code == "A" or code == "??" { return "text-success"; }
    if code == "D" { return "text-destructive"; }
    if code == "R" { return "text-info"; }
    return "text-muted-foreground";
}

def _statusDotColor(code: str) -> str {
    if code == "M" or code == "MM" { return "bg-warning"; }
    if code == "A" or code == "??" { return "bg-success"; }
    if code == "D" { return "bg-destructive"; }
    if code == "R" { return "bg-info"; }
    return "bg-muted-foreground";
}

def:pub GitPanel(props: Any) -> Any {
    git = props.git;
    onOpenDiffProp = props.onOpenDiff or None;
    has commitMsg: str = "";
    has newBranchName: str = "";
    has showNewBranch: bool = False;
    has commitMode: str = "all";
    has checkpoints: list = [];
    has changesOpen: bool = True;
    has selectedFile: str = "";

    has confirmOpen: bool = False;
    has confirmTitle: str = "";
    has confirmMessage: str = "";
    has confirmAction: str = "";
    has confirmTarget: str = "";
    has confirmColor: str = "red";

    has remoteUrl: str = "";
    has logLoaded: bool = False;
    has remotesLoaded: bool = False;
    has logLimit: int = 20;
    has historyOpen: bool = False;

    has pushDialogOpen: bool = False;
    has pushRepoName: str = "";
    has pushRepoPrivate: bool = True;
    has pushLoading: bool = False;
    has pushError: str = "";

    has repoNotFound: bool = False;

    has prDialogOpen: bool = False;
    has prTitle: str = "";
    has prBase: str = "main";
    has prBody: str = "";
    has prLoading: bool = False;
    has prError: str = "";
    has prStatus: str = "";
    has prResultUrl: str = "";

    has remoteDialogOpen: bool = False;
    has branchDialogOpen: bool = False;
    has checkpointDialogOpen: bool = False;

    status = git.status;
    branches = git.branches or [];
    currentBranch = git.currentBranch or "";

    if not remotesLoaded and git.remoteList and git.remoteList.length > 0 {
        remotesLoaded = True;
    }

    hasStagedFiles = False;
    stagedCount = 0;
    if status and status.files {
        for f in (status.files or []) {
            if f.staged {
                hasStagedFiles = True;
                stagedCount = stagedCount + 1;
            }
        }
    }

    fileCount = 0;
    if status and status.files {
        fileCount = (status.files or []).length;
    }

    hasRemote = status and status.has_remote or False;
    originUrl = _getOriginUrl();
    isGithubOrigin = _isGithubRemote(originUrl);

    def openConfirm(title: str, msg: str, action: str, target: str, color: str) -> None {
        confirmTitle = title;
        confirmMessage = msg;
        confirmAction = action;
        confirmTarget = target;
        confirmColor = color;
        confirmOpen = True;
    }

    def handleConfirmAction() -> None {
        action = confirmAction;
        target = confirmTarget;
        confirmOpen = False;

        if action == "delete_branch" {
            git.deleteBranch(target).then(lambda(r: Any) -> None {
                if r and r.success { _notify("Branch Deleted", "Deleted " + target, "green"); }
                else { _notify("Delete Failed", (r.error if r else "Unknown error"), "red"); }
            });
        } elif action == "restore_checkpoint" {
            git.restoreCheckpoint(target).then(lambda(r: Any) -> None {
                if r and r.success { _notify("Checkpoint Restored", "Restored to " + target.slice(0, 7), "green"); }
                else { _notify("Restore Failed", (r.error if r else "Unknown error"), "red"); }
            });
        } elif action == "remove_remote" {
            git.removeRemote(target).then(lambda(r: Any) -> None {
                if r and r.success { _notify("Remote Removed", "Removed " + target, "green"); }
                else { _notify("Remove Failed", (r.error if r else "Unknown error"), "red"); }
            });
        } elif action == "merge_branch" {
            git.mergeBranch(target).then(lambda(r: Any) -> None {
                if r and r.success { _notify("Merged", "Merged " + target + " into " + currentBranch, "green"); }
                elif r and r.conflicts { _notify("Merge Conflict", "Merge conflict with " + target + " — aborted", "red"); }
                else { _notify("Merge Failed", (r.error if r else "Unknown error"), "red"); }
            });
        }
    }

    def handleCommit() -> None {
        if not commitMsg.trim() { return; }
        msg = commitMsg;
        commitMsg = "";
        commitFn = None;
        if commitMode == "staged" and hasStagedFiles { commitFn = git.doCommitStaged; }
        else { commitFn = git.doCommit; }
        commitFn.call(None, msg).then(lambda(r: Any) -> None {
            if r and r.success {
                sha = r.sha or "";
                shortSha = sha.slice(0, 7) if sha else "";
                _notify("Committed", shortSha + " - " + msg, "green");
            } else { _notify("Commit Failed", (r.error if r else "Unknown error"), "red"); }
        });
    }

    def handleCreateBranch() -> None {
        if not newBranchName.trim() { return; }
        name = newBranchName;
        newBranchName = "";
        showNewBranch = False;
        branchDialogOpen = False;
        git.createBranch(name).then(lambda(r: Any) -> None {
            if r and r.success { _notify("Branch Created", "Created and switched to " + name, "green"); }
            else { _notify("Branch Failed", (r.error if r else "Unknown error"), "red"); }
        });
    }

    def _handleSyncPush() -> None {
        if isGithubOrigin and git.githubConnected {
            _handleGithubPush();
        } else {
            git.doPush().then(lambda(r: Any) -> None {
                if r and r.success { _notify("Pushed", "Changes pushed to remote", "green"); }
                else { _notify("Push Failed", (r.error if r else "Unknown error"), "red"); }
            });
        }
    }

    def _handleSyncPull() -> None {
        if isGithubOrigin and git.githubConnected {
            _handleGithubPull();
        } else {
            git.doPull().then(lambda(r: Any) -> None {
                if r and r.success {
                    if props.ide and props.ide.refreshFiles { props.ide.refreshFiles(); }
                    _notify("Pulled", "Changes pulled from remote", "green");
                } else { _notify("Pull Failed", (r.error if r else "Unknown error"), "red"); }
            });
        }
    }

    def _handleGithubPush() -> None {
        git.githubPushProject().then(lambda(r: Any) -> None {
            if r and r.success {
                repoNotFound = False;
                _notify("Pushed", "Changes pushed successfully", "green");
            } else {
                errMsg = (r.error if r else "Unknown error");
                if _isRepoNotFound(errMsg) { repoNotFound = True; }
                _notify("Push Failed", errMsg, "red");
            }
        });
    }

    def _handleGithubPull() -> None {
        git.githubPullProject().then(lambda(r: Any) -> None {
            if r and r.success {
                repoNotFound = False;
                if props.ide and props.ide.refreshFiles { props.ide.refreshFiles(); }
                _notify("Pulled", "Changes pulled successfully", "green");
            } else {
                errMsg = (r.error if r else "Unknown error");
                if _isRepoNotFound(errMsg) { repoNotFound = True; }
                _notify("Pull Failed", errMsg, "red");
            }
        });
    }

    def _openPublishDialog() -> None {
        projectName = "";
        if props.ide and props.ide.project { projectName = props.ide.project.name or ""; }
        pushRepoName = projectName;
        pushRepoPrivate = True;
        pushError = "";
        pushLoading = False;
        pushDialogOpen = True;
    }

    def _handlePublish() -> None {
        if not pushRepoName.trim() { pushError = "Repository name is required"; return; }
        pushLoading = True;
        pushError = "";
        git.githubPushNew(pushRepoName.trim(), pushRepoPrivate).then(lambda(r: Any) -> None {
            pushLoading = False;
            if r and r.success {
                pushDialogOpen = False;
                _notify("Published", "Repository created and code pushed", "green");
            } else { pushError = (r.error if r else "Failed to publish"); }
        });
    }

    def _openPRDialog() -> None {
        prTitle = "";
        prBody = "";
        prError = "";
        prStatus = "";
        prResultUrl = "";
        prLoading = False;
        git.refresh().then(lambda (_: Any) -> None {
            freshBranches = git.branches or [];
            defaultBase = "main";
            i = 0;
            while i < freshBranches.length {
                bName = freshBranches[i].name or "";
                hasRemoteBranch = freshBranches[i].has_remote or False;
                if bName == "main" and hasRemoteBranch { defaultBase = "main"; break; }
                if bName == "master" and hasRemoteBranch { defaultBase = "master"; }
                i += 1;
            }
            prBase = defaultBase;
        });
        prBase = "main";
        prDialogOpen = True;
    }

    def _submitPR(head: str) -> None {
        prStatus = "Creating pull request...";
        git.githubCreatePR(prTitle.trim(), head, prBase or "main", prBody).then(lambda(r: Any) -> None {
            prLoading = False;
            prStatus = "";
            if r and r.success and r.pr {
                prResultUrl = r.pr.html_url or "";
                _notify("PR Created", prTitle, "green");
            } else {
                errMsg = (r.error if r else "Failed to create PR");
                if errMsg == "Validation Failed" { errMsg = "Invalid base branch '" + prBase + "'"; }
                prError = errMsg;
            }
        });
    }

    def _autoPushThenPR(head: str) -> None {
        prStatus = "Pushing '" + head + "' to remote...";
        git.githubPushProject().then(lambda(pushR: Any) -> None {
            if pushR and pushR.success { _submitPR(head); }
            else {
                prLoading = False;
                prStatus = "";
                prError = "Failed to push: " + (pushR.error if pushR else "Unknown error");
            }
        });
    }

    def _handleCreatePR() -> None {
        if not prTitle.trim() { prError = "PR title is required"; return; }
        head = currentBranch or "main";
        if head == prBase { prError = "Head and base branches must be different"; return; }
        headHasRemote = False;
        baseHasRemote = False;
        i = 0;
        while i < branches.length {
            bName = branches[i].name or "";
            bRemote = branches[i].has_remote or False;
            if bName == head { headHasRemote = bRemote; }
            if bName == prBase { baseHasRemote = bRemote; }
            i += 1;
        }
        if not baseHasRemote { prError = "Base branch '" + prBase + "' not on remote."; return; }
        prLoading = True;
        prError = "";
        prStatus = "";
        prResultUrl = "";
        if not headHasRemote or (status and (status.ahead or 0) > 0) { _autoPushThenPR(head); return; }
        _submitPR(head);
    }

    def _getOriginUrl() -> str {
        if not git.remoteList or git.remoteList.length == 0 { return ""; }
        i = 0;
        while i < git.remoteList.length {
            r = git.remoteList[i];
            if r.name == "origin" { return r.url or ""; }
            i = i + 1;
        }
        return "";
    }

    def _copyToClipboard(text: str) -> None {
        navigator.clipboard.writeText(text);
        _notify("Copied", "Copied to clipboard", "green");
    }

    def _isRepoNotFound(error: str) -> bool {
        if not error { return False; }
        lower = error.toLowerCase();
        return lower.indexOf("repository not found") >= 0 or (lower.indexOf("not found") >= 0 and lower.indexOf("remote") >= 0);
    }

    def _handleRemoveStaleRemote() -> None {
        git.removeRemote("origin").then(lambda(r: Any) -> None {
            if r and r.success { repoNotFound = False; git.refresh(); _notify("Remote Removed", "Stale remote removed", "green"); }
            else { _notify("Failed", (r.error if r else "Could not remove remote"), "red"); }
        });
    }

    def handleCreateCheckpoint() -> None {
        git.createCheckpoint().then(lambda(result: Any) -> None {
            if result and result.success and result.checkpoint_ref {
                checkpoints = [{"ref": result.checkpoint_ref, "timestamp": Date.now()}].concat(checkpoints.slice(0, 9));
                _notify("Checkpoint Saved", "Checkpoint " + result.checkpoint_ref.slice(0, 7), "green");
            } else { _notify("Checkpoint Failed", (result.error if result else "Unknown error"), "red"); }
        });
    }

    def handleAddRemote() -> None {
        if not remoteUrl.trim() { return; }
        url = remoteUrl;
        remoteUrl = "";
        remoteDialogOpen = False;
        git.addRemote(url).then(lambda(r: Any) -> None {
            if r and r.success { _notify("Remote Added", "Added remote origin", "green"); }
            else { _notify("Add Remote Failed", (r.error if r else "Unknown error"), "red"); }
        });
    }

    useEffect(lambda {
        if not remotesLoaded {
            remotesLoaded = True;
            git.fetchRemotes();
        }
    }, []);

    def openDiffFile(filePath: str, mode: str) -> None {
        if onOpenDiffProp {
            diffFn = onOpenDiffProp;
            diffFn.call(None, filePath, mode);
        }
    }

    def _stageAll() -> None {
        if not status or not status.files { return; }
        for f in (status.files or []) {
            if f.unstaged {
                stageFn = git.stageFile;
                stageFn.call(None, f.path);
            }
        }
    }

    def _unstageAll() -> None {
        if not status or not status.files { return; }
        for f in (status.files or []) {
            if f.staged {
                unstageFn = git.unstageFile;
                unstageFn.call(None, f.path);
            }
        }
    }

    isDirty = status and status.dirty or False;
    ahead = status and status.ahead or 0;
    behind = status and status.behind or 0;
    branchLabel = currentBranch + (isDirty and "*" or "");

    return <div className="flex flex-col h-full bg-card text-foreground">

        <div className="flex items-center justify-between px-3 h-9 flex-shrink-0 border-b border-border">
            <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">{"Source Control"}</span>
            <DropdownMenu>
                <DropdownMenuTrigger>
                    <Button variant="ghost" size="icon-xs" className="size-6 text-muted-foreground hover:bg-accent">
                        <HugeiconsIcon icon={MoreHorizontalCircle01Icon} strokeWidth={2} className="size-3.5" />
                    </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end" className="w-52">
                    {hasRemote and <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={ArrowUp01Icon} strokeWidth={2} className="size-3.5" />
                            {"Pull, Push"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { _handleSyncPull(); }}>{"Pull"}</DropdownMenuItem>
                            <DropdownMenuItem onClick={lambda -> None { _handleSyncPush(); }}>{"Push"}</DropdownMenuItem>
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub> or None}
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={GitCommitIcon} strokeWidth={2} className="size-3.5" />
                            {"Commit"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { commitMode = "all"; }}>
                                {"Commit All"}
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={lambda -> None { commitMode = "staged"; }}
                                disabled={not hasStagedFiles}>
                                {"Commit Staged"}
                            </DropdownMenuItem>
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={FolderOpenIcon} strokeWidth={2} className="size-3.5" />
                            {"Changes"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { _stageAll(); }} disabled={not isDirty}>
                                {"Stage All Changes"}
                            </DropdownMenuItem>
                            <DropdownMenuItem onClick={lambda -> None { _unstageAll(); }} disabled={not hasStagedFiles}>
                                {"Unstage All Changes"}
                            </DropdownMenuItem>
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={GitBranchIcon} strokeWidth={2} className="size-3.5" />
                            {"Branch"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { branchDialogOpen = True; showNewBranch = True; }}>
                                {"Create Branch..."}
                            </DropdownMenuItem>
                            {branches.length > 1 and <DropdownMenuSeparator /> or None}
                            {branches.map(lambda (b: Any) -> Any {
                                isCurrent = b.name == currentBranch;
                                return not isCurrent and <DropdownMenuSub key={b.name}>
                                    <DropdownMenuSubTrigger>{b.name}</DropdownMenuSubTrigger>
                                    <DropdownMenuPortal><DropdownMenuSubContent>
                                        <DropdownMenuItem onClick={lambda -> None { git.switchBranch(b.name); }}>{"Checkout"}</DropdownMenuItem>
                                        <DropdownMenuItem onClick={lambda -> None { openConfirm("Merge Branch", "Merge " + b.name + " into " + currentBranch + "?", "merge_branch", b.name, "blue"); }}>{"Merge into " + currentBranch}</DropdownMenuItem>
                                        <DropdownMenuSeparator />
                                        <DropdownMenuItem variant="destructive" onClick={lambda -> None { openConfirm("Delete Branch", "Delete " + b.name + "?", "delete_branch", b.name, "red"); }}>{"Delete"}</DropdownMenuItem>
                                    </DropdownMenuSubContent></DropdownMenuPortal>
                                </DropdownMenuSub> or None;
                            })}
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={InternetIcon} strokeWidth={2} className="size-3.5" />
                            {"Remote"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { remoteDialogOpen = True; }}>
                                {"Add Remote..."}
                            </DropdownMenuItem>
                            {git.remoteList and git.remoteList.length > 0 and <DropdownMenuSeparator /> or None}
                            {(git.remoteList or []).map(lambda (r: Any) -> Any {
                                return <DropdownMenuItem key={r.name} onClick={lambda -> None {
                                    openConfirm("Remove Remote", "Remove " + r.name + " (" + r.url + ")?", "remove_remote", r.name, "red");
                                }}>
                                    <span className="text-destructive">{"Remove " + r.name}</span>
                                </DropdownMenuItem>;
                            })}
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={ArrowTurnBackwardIcon} strokeWidth={2} className="size-3.5" />
                            {"Checkpoints"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            <DropdownMenuItem onClick={lambda -> None { handleCreateCheckpoint(); }}>
                                {"Save Checkpoint"}
                            </DropdownMenuItem>
                            {checkpoints.length > 0 and <DropdownMenuSeparator /> or None}
                            {checkpoints.map(lambda (cp: Any, i: int) -> Any {
                                shortRef = cp.ref.slice(0, 7);
                                return <DropdownMenuItem key={String(i)} onClick={lambda -> None {
                                    openConfirm("Restore", "Restore to " + shortRef + "?", "restore_checkpoint", cp.ref, "yellow");
                                }}>
                                    {"Restore " + shortRef}
                                </DropdownMenuItem>;
                            })}
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSeparator />
                    <DropdownMenuSub>
                        <DropdownMenuSubTrigger>
                            <HugeiconsIcon icon={InternetIcon} strokeWidth={2} className="size-3.5" />
                            {"GitHub"}
                        </DropdownMenuSubTrigger>
                        <DropdownMenuPortal><DropdownMenuSubContent>
                            {not git.githubConnected and <DropdownMenuItem onClick={lambda -> None {
                                git.connectGithub().then(lambda(r: Any) -> None {
                                    if not r or not r.success { _notify("Connect Failed", (r.error if r else ""), "red"); }
                                });
                            }}>{"Connect GitHub"}</DropdownMenuItem> or None}
                            {git.githubConnected and <DropdownMenuItem disabled={True}>
                                <HugeiconsIcon icon={Tick02Icon} strokeWidth={2} className="size-3 text-success" />
                                {"@" + git.githubUsername}
                            </DropdownMenuItem> or None}
                            {git.githubConnected and not hasRemote and <DropdownMenuItem onClick={lambda -> None { _openPublishDialog(); }}>{"Publish to GitHub..."}</DropdownMenuItem> or None}
                            {git.githubConnected and hasRemote and isGithubOrigin and <DropdownMenuItem onClick={lambda -> None { _openPRDialog(); }} disabled={branches.length < 2}>{"Create Pull Request..."}</DropdownMenuItem> or None}
                            {git.githubConnected and <DropdownMenuSeparator /> or None}
                            {git.githubConnected and <DropdownMenuItem variant="destructive" onClick={lambda -> None {
                                git.disconnectGithub().then(lambda(r: Any) -> None {
                                    if r and r.success { _notify("Disconnected", "GitHub disconnected", "green"); }
                                    else { _notify("Failed", (r.error if r else ""), "red"); }
                                });
                            }}>{"Disconnect GitHub"}</DropdownMenuItem> or None}
                        </DropdownMenuSubContent></DropdownMenuPortal>
                    </DropdownMenuSub>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={lambda -> None {
                        historyOpen = not historyOpen;
                        if not logLoaded { logLoaded = True; fetchFn = git.fetchLog; fetchFn.call(None, logLimit); }
                    }}>
                        <HugeiconsIcon icon={Clock01Icon} strokeWidth={2} className="size-3.5" />
                        {"Show History"}
                    </DropdownMenuItem>
                </DropdownMenuContent>
            </DropdownMenu>
        </div>

        <ScrollArea className="flex-1">
            <div className="flex flex-col">

                <div className="px-3 pt-2 pb-1">
                    <div className="flex items-center justify-between">
                        <div className="flex items-center gap-1.5">
                            <HugeiconsIcon icon={GitBranchIcon} strokeWidth={2} className="size-3 text-primary" />
                            <span className="text-[11px] font-medium text-foreground">{props.ide and props.ide.project and props.ide.project.name or "Project"}</span>
                        </div>
                        <div className="flex items-center gap-0.5">
                            <Tooltip>
                                <TooltipTrigger asChild={True}>
                                    <Button variant="ghost" size="icon-xs" className="h-5 px-1.5 text-muted-foreground hover:bg-accent gap-0.5"
                                        onClick={lambda -> None { branchDialogOpen = True; showNewBranch = False; }}>
                                        <HugeiconsIcon icon={GitBranchIcon} strokeWidth={2} className="size-2.5" />
                                        <span className="text-[10px]">{branchLabel}</span>
                                    </Button>
                                </TooltipTrigger>
                                <TooltipContent>{"Switch branch"}</TooltipContent>
                            </Tooltip>
                            {hasRemote and <Tooltip>
                                <TooltipTrigger asChild={True}>
                                    <Button variant="ghost" size="icon-xs" className="size-5 text-muted-foreground hover:bg-accent"
                                        onClick={lambda -> None { _handleSyncPush(); _handleSyncPull(); }}
                                        disabled={git.isLoading or git.githubLoading}>
                                        {(git.isLoading or git.githubLoading) and <Spinner className="size-2.5" /> or <HugeiconsIcon icon={Refresh01Icon} strokeWidth={2} className="size-2.5" />}
                                    </Button>
                                </TooltipTrigger>
                                <TooltipContent>{"Sync" + (ahead > 0 and " " + String.fromCharCode(8593) + String(ahead) or "") + (behind > 0 and " " + String.fromCharCode(8595) + String(behind) or "")}</TooltipContent>
                            </Tooltip> or None}
                        </div>
                    </div>
                </div>

                <div className="border-t border-border">
                    <div className="flex items-center justify-between px-3 py-1.5 group">
                        <div className="flex items-center gap-1.5">
                            <span className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">{"Changes"}</span>
                        </div>
                        <div className="flex items-center gap-0.5">
                            <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                                {isDirty and <Tooltip>
                                    <TooltipTrigger asChild={True}>
                                        <Button variant="ghost" size="icon-xs" className="size-5 text-muted-foreground hover:bg-accent"
                                            onClick={lambda -> None { _stageAll(); }}>
                                            <HugeiconsIcon icon={PlusSignIcon} strokeWidth={2} className="size-2.5" />
                                        </Button>
                                    </TooltipTrigger>
                                    <TooltipContent>{"Stage All"}</TooltipContent>
                                </Tooltip> or None}
                                {hasStagedFiles and <Tooltip>
                                    <TooltipTrigger asChild={True}>
                                        <Button variant="ghost" size="icon-xs" className="size-5 text-muted-foreground hover:bg-accent"
                                            onClick={lambda -> None { _unstageAll(); }}>
                                            <HugeiconsIcon icon={MinusSignIcon} strokeWidth={2} className="size-2.5" />
                                        </Button>
                                    </TooltipTrigger>
                                    <TooltipContent>{"Unstage All"}</TooltipContent>
                                </Tooltip> or None}
                                <Tooltip>
                                    <TooltipTrigger asChild={True}>
                                        <Button variant="ghost" size="icon-xs" className="size-5 text-muted-foreground hover:bg-accent"
                                            onClick={lambda -> None { git.refresh(); }}
                                            disabled={git.isLoading}>
                                            {git.isLoading and <Spinner className="size-2.5" /> or <HugeiconsIcon icon={Refresh01Icon} strokeWidth={2} className="size-2.5" />}
                                        </Button>
                                    </TooltipTrigger>
                                    <TooltipContent>{"Refresh"}</TooltipContent>
                                </Tooltip>
                            </div>
                        </div>
                    </div>

                    <div className="px-3 pb-2">
                        <div className="flex flex-col gap-1.5">
                            <Input className="h-7 text-xs"
                                value={commitMsg}
                                onChange={lambda (e: Any) { commitMsg = e.currentTarget.value; }}
                                placeholder={"Message (Ctrl+Enter to commit on '" + currentBranch + "')"}
                                onKeyDown={lambda (e: Any) -> None {
                                    if (e.key == "Enter" and e.ctrlKey) or (e.key == "Enter" and not e.shiftKey) { handleCommit(); }
                                }}
                            />
                            <div className="flex items-center gap-0">
                                <Button size="sm" className="flex-1 rounded-r-none text-xs bg-primary text-primary-foreground hover:bg-primary/90"
                                    onClick={lambda -> None { handleCommit(); }}
                                    disabled={not commitMsg.trim() or git.isLoading}>
                                    <HugeiconsIcon icon={Tick02Icon} strokeWidth={2} className="size-3" />
                                    {commitMode == "staged" and hasStagedFiles and "Commit Staged" or "Commit"}
                                </Button>
                                <DropdownMenu>
                                    <DropdownMenuTrigger>
                                        <Button size="sm" className="rounded-l-none border-l border-primary-foreground/20 px-1.5 bg-primary text-primary-foreground hover:bg-primary/90">
                                            <HugeiconsIcon icon={ArrowDown02Icon} strokeWidth={2} className="size-3" />
                                        </Button>
                                    </DropdownMenuTrigger>
                                    <DropdownMenuContent align="end">
                                        <DropdownMenuItem onClick={lambda -> None { commitMode = "all"; }}>
                                            {commitMode == "all" and <HugeiconsIcon icon={Tick02Icon} strokeWidth={2} className="size-3" /> or <span className="size-3" />}
                                            {"Commit All"}
                                        </DropdownMenuItem>
                                        <DropdownMenuItem onClick={lambda -> None { commitMode = "staged"; }} disabled={not hasStagedFiles}>
                                            {commitMode == "staged" and <HugeiconsIcon icon={Tick02Icon} strokeWidth={2} className="size-3" /> or <span className="size-3" />}
                                            {"Commit Staged"}
                                        </DropdownMenuItem>
                                    </DropdownMenuContent>
                                </DropdownMenu>
                            </div>
                        </div>
                    </div>

                    <div className="border-t border-border">
                        <button
                            className="flex items-center justify-between w-full px-3 py-1.5 text-left bg-transparent border-0 cursor-pointer hover:bg-accent/50 transition-colors group"
                            onClick={lambda -> None { changesOpen = not changesOpen; }}>
                            <div className="flex items-center gap-1">
                                <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className={cn("size-3 text-muted-foreground transition-transform", (changesOpen and "rotate-90" or ""))} />
                                <span className="text-[11px] font-medium text-foreground">{"Changes"}</span>
                            </div>
                            {fileCount > 0 and <Badge className="text-[9px] h-4 min-w-4 px-1 rounded-full bg-muted text-muted-foreground">{String(fileCount)}</Badge> or None}
                        </button>
                        {changesOpen and <div className="flex flex-col">
                            {(status and status.files or []).map(lambda (f: Any, i: int) -> Any {
                                statusCode = f.status or "";
                                filePath = f.path or "";
                                pathParts = filePath.split("/");
                                fileName = pathParts[pathParts.length - 1];
                                dirPath = pathParts.slice(0, -1).join("/");
                                isStagedFile = f.staged or False;
                                isUnstagedFile = f.unstaged or False;
                                dotColor = _statusDotColor(statusCode);
                                letterColor = _statusColor(statusCode);
                                openDiffFn = onOpenDiffProp;

                                isSelected = selectedFile == filePath;

                                return <div key={String(i)} className={cn("flex items-center gap-1.5 px-3 pl-6 py-0.5 group/file cursor-pointer", (isSelected and "bg-accent" or "hover:bg-accent/50"))}
                                    onClick={lambda -> None { selectedFile = filePath; if openDiffFn { openDiffFn.call(None, filePath, "working"); } }}>
                                    <span className={cn("size-2 rounded-full flex-shrink-0", dotColor)} />
                                    <span className="text-[11px] text-foreground font-medium truncate">{fileName}</span>
                                    <span className="text-[10px] text-muted-foreground truncate flex-1">{dirPath}</span>
                                    <div className="flex items-center gap-0.5 opacity-0 group-hover/file:opacity-100 transition-opacity flex-shrink-0">
                                        {isUnstagedFile and <Tooltip>
                                            <TooltipTrigger asChild={True}>
                                                <Button variant="ghost" size="icon-xs" className="size-4 text-success hover:bg-success/20"
                                                    onClick={lambda (e: Any) -> None {
                                                        e.stopPropagation();
                                                        stageFn = git.stageFile;
                                                        stageFn.call(None, filePath);
                                                    }}>
                                                    <HugeiconsIcon icon={PlusSignIcon} strokeWidth={2} className="size-2.5" />
                                                </Button>
                                            </TooltipTrigger>
                                            <TooltipContent side="left">{"Stage"}</TooltipContent>
                                        </Tooltip> or None}
                                        {isStagedFile and <Tooltip>
                                            <TooltipTrigger asChild={True}>
                                                <Button variant="ghost" size="icon-xs" className="size-4 text-destructive hover:bg-destructive/20"
                                                    onClick={lambda (e: Any) -> None {
                                                        e.stopPropagation();
                                                        unstageFn = git.unstageFile;
                                                        unstageFn.call(None, filePath);
                                                    }}>
                                                    <HugeiconsIcon icon={MinusSignIcon} strokeWidth={2} className="size-2.5" />
                                                </Button>
                                            </TooltipTrigger>
                                            <TooltipContent side="left">{"Unstage"}</TooltipContent>
                                        </Tooltip> or None}
                                    </div>
                                    <span className={cn("text-[10px] font-mono flex-shrink-0 w-4 text-right", letterColor)}>{statusCode == "??" and "U" or statusCode.charAt(0)}</span>
                                </div>;
                            })}
                            {fileCount == 0 and not isDirty and <div className="px-6 py-3">
                                <span className="text-[10px] text-muted-foreground italic">{"No changes"}</span>
                            </div> or None}
                        </div> or None}
                    </div>

                    {hasStagedFiles and <div className="border-t border-border">
                        <button
                            className="flex items-center justify-between w-full px-3 py-1.5 text-left bg-transparent border-0 cursor-pointer hover:bg-accent/50 transition-colors"
                            onClick={lambda -> None {}}>
                            <div className="flex items-center gap-1">
                                <HugeiconsIcon icon={ArrowRight01Icon} strokeWidth={2} className="size-3 text-muted-foreground rotate-90" />
                                <span className="text-[11px] font-medium text-foreground">{"Staged Changes"}</span>
                            </div>
                            <Badge className="text-[9px] h-4 min-w-4 px-1 rounded-full bg-muted text-muted-foreground">{String(stagedCount)}</Badge>
                        </button>
                        <div className="flex flex-col">
                            {(status and status.files or []).map(lambda (f: Any, i: int) -> Any {
                                isStagedFile = f.staged or False;
                                if not isStagedFile { return None; }
                                statusCode = f.status or "";
                                filePath = f.path or "";
                                pathParts = filePath.split("/");
                                fileName = pathParts[pathParts.length - 1];
                                dirPath = pathParts.slice(0, -1).join("/");
                                dotColor = _statusDotColor(statusCode);
                                letterColor = _statusColor(statusCode);

                                isStagedSelected = selectedFile == filePath;

                                return <div key={"staged-" + String(i)} className={cn("flex items-center gap-1.5 px-3 pl-6 py-0.5 group/file cursor-pointer", (isStagedSelected and "bg-accent" or "hover:bg-accent/50"))}>
                                    <span className={cn("size-2 rounded-full flex-shrink-0", dotColor)} />
                                    <span className="text-[11px] text-foreground font-medium truncate">{fileName}</span>
                                    <span className="text-[10px] text-muted-foreground truncate flex-1">{dirPath}</span>
                                    <div className="flex items-center gap-0.5 opacity-0 group-hover/file:opacity-100 transition-opacity flex-shrink-0">
                                        <Tooltip>
                                            <TooltipTrigger asChild={True}>
                                                <Button variant="ghost" size="icon-xs" className="size-4 text-destructive hover:bg-destructive/20"
                                                    onClick={lambda (e: Any) -> None {
                                                        e.stopPropagation();
                                                        unstageFn = git.unstageFile;
                                                        unstageFn.call(None, filePath);
                                                    }}>
                                                    <HugeiconsIcon icon={MinusSignIcon} strokeWidth={2} className="size-2.5" />
                                                </Button>
                                            </TooltipTrigger>
                                            <TooltipContent side="left">{"Unstage"}</TooltipContent>
                                        </Tooltip>
                                    </div>
                                    <span className={cn("text-[10px] font-mono flex-shrink-0 w-4 text-right", letterColor)}>{statusCode == "??" and "U" or statusCode.charAt(0)}</span>
                                </div>;
                            })}
                        </div>
                    </div> or None}
                </div>

                {repoNotFound and <div className="px-3 py-2">
                    <div className="flex flex-col gap-1.5 p-2 rounded bg-destructive/10 border border-destructive/20">
                        <div className="flex items-center gap-1.5">
                            <HugeiconsIcon icon={AlertCircleIcon} strokeWidth={2} className="size-3 text-destructive flex-shrink-0" />
                            <span className="text-[10px] text-destructive font-medium">{"Remote not found"}</span>
                        </div>
                        <Button variant="destructive" size="xs" className="w-full text-[10px]"
                            onClick={lambda -> None { _handleRemoveStaleRemote(); }}>
                            {"Remove Stale Remote"}
                        </Button>
                    </div>
                </div> or None}

                {historyOpen and <div className="border-t border-border px-3 pt-2 pb-2">
                    <div className="flex items-center justify-between mb-1.5">
                        <span className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground">{"History"}</span>
                        <Button variant="ghost" size="icon-xs" className="size-5 text-muted-foreground hover:bg-accent"
                            onClick={lambda -> None { historyOpen = False; }}>
                            <HugeiconsIcon icon={Cancel01Icon} strokeWidth={2} className="size-2.5" />
                        </Button>
                    </div>
                    {logLoaded and git.commits.length == 0 and <span className="text-[10px] text-muted-foreground italic">{"No commits"}</span> or None}
                    {logLoaded and git.commits.length > 0 and <div className="flex flex-col gap-0.5">
                        {git.commits.map(lambda (c: Any, i: int) -> Any {
                            sha = c.sha or "";
                            shortSha = sha.slice(0, 7);
                            msg = c.message or "";
                            truncMsg = msg.slice(0, 40) + ("..." if msg.length > 40 else "");
                            relTime = _relativeTime(c.date or "");
                            return <div key={String(i)} className="flex flex-col gap-0.5 py-1 px-1.5 rounded hover:bg-accent/50 border-b border-border/50 last:border-0">
                                <div className="flex items-center justify-between">
                                    <span className="text-[10px] font-mono text-primary font-medium">{shortSha}</span>
                                    <span className="text-[9px] text-muted-foreground">{relTime}</span>
                                </div>
                                <span className="text-[11px] text-foreground leading-tight" title={msg}>{truncMsg}</span>
                            </div>;
                        })}
                        {git.commits.length >= logLimit and <Button size="xs" variant="ghost" className="w-full mt-1 text-[10px] text-muted-foreground"
                            onClick={lambda {
                                newLimit = logLimit + 30;
                                logLimit = newLimit;
                                fetchFn = git.fetchLog;
                                fetchFn.call(None, newLimit);
                            }}>
                            {"Load more..."}
                        </Button> or None}
                    </div> or None}
                </div> or None}

                {git.gitError and <div className="flex items-center gap-1.5 p-2 mx-3 my-2 rounded bg-destructive/10 border border-destructive/20">
                    <HugeiconsIcon icon={AlertCircleIcon} strokeWidth={2} className="size-3 text-destructive" />
                    <span className="text-[11px] text-destructive/70">{git.gitError}</span>
                </div> or None}
            </div>
        </ScrollArea>

        <AlertDialog open={confirmOpen} onOpenChange={lambda v: Any { if not v { confirmOpen = False; } }}>
            <AlertDialogContent>
                <AlertDialogHeader>
                    <AlertDialogTitle>{confirmTitle}</AlertDialogTitle>
                    <AlertDialogDescription>{confirmMessage}</AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                    <AlertDialogCancel onClick={lambda -> None { confirmOpen = False; }}>{"Cancel"}</AlertDialogCancel>
                    <AlertDialogAction variant={confirmColor == "red" and "destructive" or "default"} onClick={lambda -> None { handleConfirmAction(); }}>{"Confirm"}</AlertDialogAction>
                </AlertDialogFooter>
            </AlertDialogContent>
        </AlertDialog>

        <Dialog open={branchDialogOpen} onOpenChange={lambda v: Any { if not v { branchDialogOpen = False; } }}>
            <DialogContent className="sm:max-w-sm" aria-describedby={undefined}>
                <DialogHeader>
                    <DialogTitle>{showNewBranch and "Create Branch" or "Switch Branch"}</DialogTitle>
                </DialogHeader>
                <div className="flex flex-col gap-3">
                    {showNewBranch and <div className="flex flex-col gap-2">
                        <Input className="text-xs"
                            value={newBranchName}
                            onChange={lambda (e: Any) { newBranchName = e.currentTarget.value; }}
                            placeholder="new-branch-name"
                            onKeyDown={lambda (e: Any) -> None { if e.key == "Enter" { handleCreateBranch(); } }}
                            autoFocus={True}
                        />
                        <Button size="sm" className="text-xs" onClick={lambda -> None { handleCreateBranch(); }} disabled={not newBranchName.trim()}>
                            <HugeiconsIcon icon={PlusSignIcon} strokeWidth={2} className="size-3" />
                            {"Create & Checkout"}
                        </Button>
                    </div> or None}
                    {not showNewBranch and <div className="flex flex-col gap-1">
                        <Button variant="ghost" size="sm" className="justify-start text-xs text-primary"
                            onClick={lambda -> None { showNewBranch = True; }}>
                            <HugeiconsIcon icon={PlusSignIcon} strokeWidth={2} className="size-3" />
                            {"Create new branch..."}
                        </Button>
                        {branches.map(lambda (b: Any) -> Any {
                            isCurrent = b.name == currentBranch;
                            return <Button key={b.name} variant="ghost" size="sm"
                                className={cn("justify-start text-xs", (isCurrent and "text-primary font-medium" or "text-foreground"))}
                                onClick={lambda -> None { if not isCurrent { git.switchBranch(b.name); branchDialogOpen = False; } }}>
                                <HugeiconsIcon icon={GitBranchIcon} strokeWidth={2} className="size-3" />
                                {b.name}
                                {isCurrent and <Badge variant="secondary" className="text-[8px] px-1 ml-auto">{"current"}</Badge> or None}
                            </Button>;
                        })}
                    </div> or None}
                </div>
            </DialogContent>
        </Dialog>

        <Dialog open={remoteDialogOpen} onOpenChange={lambda v: Any { if not v { remoteDialogOpen = False; } }}>
            <DialogContent className="sm:max-w-sm" aria-describedby={undefined}>
                <DialogHeader>
                    <DialogTitle>{"Add Remote"}</DialogTitle>
                </DialogHeader>
                <div className="flex flex-col gap-3">
                    <Input className="text-xs"
                        value={remoteUrl}
                        onChange={lambda (e: Any) { remoteUrl = e.currentTarget.value; }}
                        placeholder="https://github.com/user/repo.git or any git URL"
                        onKeyDown={lambda (e: Any) -> None { if e.key == "Enter" { handleAddRemote(); } }}
                        autoFocus={True}
                    />
                    <Button size="sm" className="text-xs" onClick={lambda -> None { handleAddRemote(); }} disabled={not remoteUrl.trim()}>
                        {"Add Remote"}
                    </Button>
                </div>
            </DialogContent>
        </Dialog>

        <Dialog open={pushDialogOpen} onOpenChange={lambda v: Any { if not v { pushDialogOpen = False; } }}>
            <DialogContent className="sm:max-w-md">
                <DialogHeader>
                    <DialogTitle>{"Publish to GitHub"}</DialogTitle>
                </DialogHeader>
                <div className="flex flex-col gap-4">
                    <div className="flex flex-col gap-2">
                        <Label className="text-xs">{"Repository name"}</Label>
                        <Input className="text-xs"
                            value={pushRepoName}
                            onChange={lambda (e: Any) { pushRepoName = e.currentTarget.value; }}
                            placeholder="my-project"
                            disabled={pushLoading}
                            onKeyDown={lambda (e: Any) -> None { if e.key == "Enter" { _handlePublish(); } }}
                        />
                    </div>
                    <div className="flex items-center justify-between">
                        <Label className="text-xs">{"Private repository"}</Label>
                        <Switch checked={pushRepoPrivate} onCheckedChange={lambda (v: Any) { pushRepoPrivate = v; }} disabled={pushLoading} />
                    </div>
                    {pushError and <Alert variant="destructive" className="text-xs py-2">{pushError}</Alert> or None}
                    <div className="flex items-center gap-2 justify-end">
                        <Button variant="ghost" size="sm" className="text-xs" onClick={lambda -> None { pushDialogOpen = False; }} disabled={pushLoading}>{"Cancel"}</Button>
                        <Button size="sm" className="text-xs" onClick={lambda -> None { _handlePublish(); }} disabled={not pushRepoName.trim() or pushLoading}>
                            {pushLoading and <Spinner className="size-3" /> or <HugeiconsIcon icon={ArrowUp01Icon} strokeWidth={2} className="size-3" />}
                            {"Create & Push"}
                        </Button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>

        <Dialog open={prDialogOpen} onOpenChange={lambda v: Any { if not v { prDialogOpen = False; } }}>
            <DialogContent className="sm:max-w-md" aria-describedby={undefined}>
                <DialogHeader>
                    <DialogTitle>{"Create Pull Request"}</DialogTitle>
                </DialogHeader>
                <div className="flex flex-col gap-4">
                    {branches.length < 2 and <div className="flex flex-col gap-2 p-3 rounded bg-muted border border-border">
                        <p className="text-xs text-muted-foreground">{"You need at least two branches to create a PR."}</p>
                        <Button variant="ghost" size="sm" className="text-xs w-fit" onClick={lambda -> None { prDialogOpen = False; }}>{"Close"}</Button>
                    </div> or None}
                    {branches.length >= 2 and <div className="flex flex-col gap-4">
                        <div className="flex items-center gap-2">
                            <Badge variant="secondary" className="text-[10px] px-2">{currentBranch or "main"}</Badge>
                            <span className="text-xs text-muted-foreground">{String.fromCharCode(8594)}</span>
                            <select
                                value={prBase}
                                onChange={lambda (e: Any) { prBase = e.currentTarget.value; }}
                                disabled={prLoading}
                                className="flex-1 text-xs h-8 rounded-lg border border-input bg-transparent px-2.5 outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
                            >
                                {branches.map(lambda (b: Any) -> Any {
                                    bName = b.name or "";
                                    hasRemoteBranch = b.has_remote or False;
                                    label = bName + ("" if hasRemoteBranch else " (local only)");
                                    return <option key={bName} value={bName} disabled={not hasRemoteBranch}>{label}</option>;
                                })}
                            </select>
                        </div>
                        <div className="flex flex-col gap-2">
                            <Label className="text-xs">{"Title"}</Label>
                            <Input className="text-xs" value={prTitle} onChange={lambda (e: Any) { prTitle = e.currentTarget.value; }}
                                placeholder="What does this PR do?" disabled={prLoading}
                                onKeyDown={lambda (e: Any) -> None { if e.key == "Enter" { _handleCreatePR(); } }} />
                        </div>
                        <div className="flex flex-col gap-2">
                            <Label className="text-xs">{"Description"}</Label>
                            <Textarea className="text-xs resize-none" value={prBody} onChange={lambda (e: Any) { prBody = e.currentTarget.value; }}
                                placeholder="Optional description..." disabled={prLoading} rows={3} />
                        </div>
                        {prStatus and <div className="flex items-center gap-1.5 p-2 rounded bg-info/10 border border-info/20">
                            <Spinner className="size-3 text-info" />
                            <span className="text-[11px] text-info">{prStatus}</span>
                        </div> or None}
                        {prError and <Alert variant="destructive" className="text-xs py-2">{prError}</Alert> or None}
                        {prResultUrl and <div className="flex items-center gap-1.5 p-2 rounded bg-success/10 border border-success/20">
                            <HugeiconsIcon icon={Tick02Icon} strokeWidth={2} className="size-3 text-success flex-shrink-0" />
                            <a href={prResultUrl} target="_blank" rel="noopener noreferrer" className="text-[11px] text-primary underline truncate">{prResultUrl}</a>
                        </div> or None}
                        <div className="flex items-center gap-2 justify-end">
                            <Button variant="ghost" size="sm" className="text-xs" onClick={lambda -> None { prDialogOpen = False; }} disabled={prLoading}>
                                {prResultUrl and "Close" or "Cancel"}
                            </Button>
                            {not prResultUrl and <Button size="sm" className="text-xs" onClick={lambda -> None { _handleCreatePR(); }} disabled={not prTitle.trim() or prLoading}>
                                {prLoading and <Spinner className="size-3" /> or <HugeiconsIcon icon={GitPullRequestIcon} strokeWidth={2} className="size-3" />}
                                {"Create PR"}
                            </Button> or None}
                        </div>
                    </div> or None}
                </div>
            </DialogContent>
        </Dialog>

    </div>;
}
