# Jac Builder Studio — 8-Week Roadmap (April–June 2026)

## Post-Hackathon Status Assessment

### What We Have
Jac Builder is a **full-featured web IDE** for the Jac language: Monaco editor with TextMate highlighting, LSP integration (`jac lsp`), file management, live preview via K8s sandboxes, output panel, git workflow (branches, commit, push/pull, diff, remotes — works locally without GitHub), JacPack + ZIP export with version history, community gallery, AI coding agent (JacCoder with model switching — GPT 5.2, GPT 5.4, Claude Sonnet, Claude Opus — users bring their own API keys via env vars), preview error auto-fix ("Fix with AI" button), SSO (Google/GitHub), and GitHub App integration.

**Production scale during hackathon**: 54 physical servers, 600 pods (150 Jac Builder pods + 450 warm sandbox pods), EFS-backed persistence.

### Hackathon Results
- **200 participants**, **70 submissions**
- Users started on Jac Builder but **migrated to VS Code + Claude + jac-mcp** mid-hackathon

### Why Users Left — Root Cause Analysis

| Pain Area | Weight | Root Cause |
|-----------|--------|------------|
| **AI coding quality/speed** | 80% | JacCoder works but users found VS Code + Claude with jac-mcp more responsive. The issue isn't the model (users had access to GPT 5.4 and Claude) — it's the **agent workflow**: jac-coder's context management, tool usage, and error recovery loop need improvement to match Claude Code CLI's capabilities. |
| **Git/code management friction** | 15% | .git configuration issues — some users had trouble with git setup even though local git works without GitHub. Moving code between Builder and VS Code was manual. Branch workflow confusing for non-technical users. |
| **UI/sandbox issues** | 5% | Sandbox slowness (K8s pod scheduling under 600-pod load), preview startup time, general UI polish gaps. "Is my sandbox broken?" uncertainty. |

### Target Audience
**Primary**: Low-tech people who want to build apps with natural language — Jac Builder as the **Lovable/Bolt equivalent** for Jac.

**Secondary**: Developers who also use VS Code — ensure consistent tooling experience across both.

---

## What Already Works (Not in Scope)

These features are **implemented and functional** — no work needed:

| Feature | Status | Evidence |
|---------|--------|---------|
| Download as ZIP | Working | `ideServer.jac:463-500`, ExportPanel UI |
| Download as JacPack | Working | `ideServer.jac:1170-1194`, ExportPanel UI |
| Version history with download | Working | ExportPanel lists versions with .jacpack + .zip buttons |
| Preview error auto-fix | Working | "Fix with AI" button in IDEPreviewPanel sends errors to chat |
| Open preview in new tab | Working | Button opens `previewUrl` in `_blank` |
| Model switching | Working | SettingsPanel dropdown: Claude Opus/Sonnet 4.5/4.6, GPT 5.2/5.4 |
| User API keys via env vars | Working | EnvVarPanel + global env vars for OPENAI_API_KEY, ANTHROPIC_API_KEY |
| Git without GitHub | Working | Local commit, branch, stash, diff — GitHub OAuth is optional |
| Loading skeletons | Partial | Skeleton component exists, used in CommunityGallery |
| Community gallery | Working | Search, tag filter, clone, submit |
| SSO (Google/GitHub) | Working | OAuth flows implemented |

---

## Architecture: Current State vs Target

### Subprocess Management (per user session)
Each active user can spawn up to 3 long-lived subprocesses:
- `jac start main.jac` (preview — runs in K8s sandbox pod, not on main pod)
- `jac lsp` (language server — runs on main pod)
- `jac install` (transient, 120s timeout)

These are tracked in **in-memory global dictionaries** (`glob` variables) across service files. Pod restart = session loss for LSP. Preview survives (separate sandbox pod) but loses connection.

### Key Global State That Blocks Stateless Migration

| Service | Glob Variables | What They Hold |
|---------|---------------|----------------|
| session_manager.jac | `_session_locks`, `_session_activity`, `_session_user_map` | Session lifecycle per user |
| lsp_manager.jac | `_lsp_registry` | LSP subprocess PID + stdio handles |
| jaccoder_adapter.jac | `_session_map`, `_event_queues`, `_ai_processing`, `_agent_threads` | JacCoder AI agent state per project |
| preview_manager.jac | `_staging_dirs`, `_preview_registry` | Preview workspace paths |
| file_watcher.jac | `_watcher_registry` | Filesystem watchers per session |
| ideServer.jac | `_ws_auth_tokens`, `_project_counts` | WebSocket auth, quota tracking |
| file_sync.jac | `_pending`, `_timers` | Debounced file sync queues |
| deploy_manager.jac | `_deploy_threads`, `_deploy_results` | Background deploy jobs |

### LSP Gaps vs VS Code JacLang Extension
Both use the same `jac lsp` server. The gap is purely in client-side feature consumption:

| Feature | VS Code | jac-ide | Gap |
|---------|---------|---------|-----|
| Completion | Yes | Yes | — |
| Hover | Yes | Yes | — |
| Go to Definition | Yes | Yes | — |
| References | Yes | Yes | — |
| Document Symbols | Yes | Yes | — |
| Workspace Symbols | — | Yes | jac-ide ahead |
| **Rename** | Yes | **No** | Missing |
| **Formatting** | Yes | **No** | Missing |
| **Semantic Tokens** | Yes | **No** | Missing |
| **Lintfix** | Yes | **No** | Missing |
| **File Ops Notifications** | Yes | **No** | LSP doesn't know about file tree creates/renames/deletes |
| `.cl.jac` support | N/A | Filtered out | Fundamental `jac lsp` limitation |

---

## 2-Month Roadmap

### Phase 1: UX for Low-Tech Users (Weeks 1–2)

#### 1.1 "Describe & Build" First Screen — ALREADY SHIPPED
The dashboard already has the Lovable-style prompt bar: "Ready to build, {username}?" + "Describe what you want to build..." + template grid below. **No work needed.**

#### 1.2 Git UX Improvements
**Why**: The git panel works but all sections are visible at once (Branch, Changes, GitHub, Remotes, Checkpoints, History) — overwhelming for non-technical users. During the hackathon, .git configuration caused confusion.

**What**:
- **Auto-set .git config**: ensure `user.name` and `user.email` are auto-set from the authenticated user's profile on project creation so commits never fail on unconfigured git identity
- **Default collapsed sections**: GitHub, Remotes, History sections collapsed by default — most users only need Branch, Changes, and Checkpoints
- **Auto-initialize .git** on project creation if not present
- **Prominent "Connect GitHub" CTA**: the current button is there but could be more discoverable for users who want push/pull

**Files**: `components/ide/GitPanel.cl.jac`, `services/project_manager.jac`, `services/git_service.jac`
**Effort**: 2–3 days

#### 1.3 Share Preview URL
**Why**: Preview URLs work via subdomain routing (`{sandbox_id}.jaseci.org`) and "Open in new tab" exists, but there's no copy-to-clipboard button for the URL. Users can't easily share their running app with others.

**What**:
- Add "Copy Link" button next to the URL display in `IDEPreviewPanel`
- Copy the public sandbox URL to clipboard with toast confirmation

**Files**: `components/ide/IDEPreviewPanel.cl.jac`
**Effort**: 0.5 day

#### 1.4 Onboarding Polish
**Why**: First-time users need guidance on what Jac Builder can do.

**What**:
- Welcome tooltip tour (3–4 steps: prompt bar → preview → file tree → deploy)
- Better empty states in file tree, terminal, preview panels (not just blank)
- Extend loading skeleton usage beyond CommunityGallery to file tree, preview, chat

**Files**: Various `components/ide/` files, `pages/JacIDE.cl.jac`
**Effort**: 2–3 days

---

### Phase 2: Performance & LSP Polish (Weeks 3–4)

#### 2.1 Preview/Sandbox Performance
**Why**: Under hackathon load (600 pods), sandbox scheduling was slow. Users reported "is my sandbox broken?" uncertainty.

**What**:
- **Progress UI**: Show sandbox startup phases in preview panel (provisioning → installing deps → starting app → ready) with real status from K8s pod events instead of generic spinner
- **Faster file sync**: Current `write_preview_file()` does full-file writes; add batch sync for multi-file AI edits (single rsync instead of N writes)
- **Warm pool tuning**: During the hackathon we had 450 warm pods. Analyze pod scheduling latency data to right-size warm pool for steady-state vs burst. Add env-configurable warm pool size per time-of-day.
- **Sandbox health check**: Visible indicator when sandbox is healthy vs degraded vs crashed. Auto-recovery with user notification ("Sandbox restarted") instead of silent failure.
- **Pod startup optimization**: Current readiness delay is 480s (8 min). Profile startup to identify slow phases — `jac install` and `jac check main.jac` pre-compilation are likely candidates.

**Files**: `services/preview_manager.jac`, `services/sandbox_store.jac`, `components/ide/IDEPreviewPanel.cl.jac`, `hooks/useIDE.cl.jac`
**Effort**: 5–6 days

#### 2.2 LSP Feature Parity with VS Code
**Why**: Both use the same `jac lsp` server. VS Code JacLang extension (3,834 installs) consumes more LSP capabilities than jac-ide. Users who tried VS Code got better code intelligence simply because the client-side consumed more of the protocol.

**What** (prioritized by impact):
1. **Formatting on save** — register `textDocument/formatting` in LSP capabilities, send on Ctrl+S, apply returned edits. (1 day)
2. **Workspace file notifications** — send `didCreateFiles`/`didRenameFiles`/`didDeleteFiles` from FileTree operations so LSP index stays in sync. Currently the LSP has stale references after file renames. (1 day)
3. **Rename symbol** — register Monaco `RenameProvider` + `textDocument/rename`. Show inline rename input, apply multi-file edits with preview. (2 days)
4. **Semantic tokens** — register `DocumentSemanticTokensProvider` + `textDocument/semanticTokens/full`. Map Jac-specific token types (walker, node, ability, edge) to Monaco classifications for richer highlighting than TextMate alone. (2 days)
5. **Lintfix command** — add "Format & Fix" to CommandPalette, sends custom `jac/lintfixFormat` request. (0.5 days)
6. **Sync tmLanguage grammar** — jac-ide has 4889 lines, jac-vscode has 4872. Copy canonical version from `jac-vscode/syntaxes/jac.tmLanguage.json`. (0.5 day)

**Files**: `hooks/useLSP.cl.jac`, `utils/lsp_client.cl.jac`, `hooks/useEditorSetup.cl.jac`, `components/ide/FileTree.cl.jac`, `components/ide/CommandPalette.cl.jac`
**Effort**: 7 days total

#### 2.3 JacCoder Agent Quality
**Why**: 80% of hackathon pain. The issue isn't the model (users had GPT 5.4 and Claude) — it's jac-coder's agent workflow: context management, tool usage, and error recovery.

**What**:
- **Better context injection**: Auto-include `jac://guide/pitfalls` and `jac://guide/patterns` from jac-mcp in every agent session — jac-coder should always know Jac syntax rules
- **Validation loop**: After jac-coder generates code, run `jac check` and feed errors back for auto-retry (up to 2 rounds) before presenting to user
- **Streaming latency**: Replace 500ms polling with true SSE for JacCoder events (reduce perceived latency from 2-5s to <1s for first token)
- **File context**: When user asks about a specific file, auto-attach all imported files (already have `resolve_jac_imports` in ai_service.jac — ensure jac-coder uses it)

**Files**: `services/jaccoder_adapter.jac`, `services/ai_service.jac`, `hooks/useChatMode.cl.jac`
**Effort**: 5–6 days

---

### Phase 3: Stateless Migration (Weeks 5–6)

#### 3.1 Externalize Session State to Redis
**Why**: In-memory `glob` dicts across 8+ service files mean pod restart = session loss. With 150 Builder pods in production, sticky sessions via ALB cookies work but limit horizontal scaling and make rolling deploys disruptive.

**What**:
- Deploy Redis (ElastiCache) alongside EKS cluster
- Create `services/state_store.jac` — thin wrapper over Redis with JSON serialization
- Migrate in priority order:
  1. `_ws_auth_tokens` → Redis with TTL (already has 24h TTL, natural fit)
  2. `_session_activity`, `_session_user_map` → Redis sorted sets (cross-pod session awareness)
  3. `_event_queues`, `_ai_processing` (jaccoder_adapter) → Redis Streams (event bus)
  4. `_project_counts` → Redis INCR/DECR (atomic, no race conditions)
  5. `_staging_dirs`, `_preview_registry` → Redis hash maps

**What stays in-memory** (subprocess PID handles cannot be externalized):
- `_lsp_registry` — LSP subprocess handles (must pin to pod)
- JacCoder thread pools — Python-native
- File watchers — OS-level inotify handles

**Files**: New `services/state_store.jac`, modifications to session_manager, jaccoder_adapter, preview_manager, ideServer, file_sync
**Effort**: 8–10 days

#### 3.2 Subprocess Affinity Strategy
**Why**: LSP is the only long-lived subprocess on main pods (preview runs in sandbox pods, JacCoder is thread-pool-based). LSP subprocess pins sessions to specific pods.

**What**:
- **Session affinity via Redis**: When LSP starts, record `(user_id::project_id → pod_hostname)` in Redis. Route subsequent LSP requests to same pod via custom header/cookie.
- **Graceful failover**: If pod dies, user sees "Reconnecting..." and LSP restarts on new pod (state is just the workspace — reopening files is fast).
- **Future**: Move LSP to dedicated sidecar pods (one `jac lsp` per user session, separate from API pods). Design the interface now, implement post-roadmap.

**Files**: `services/session_manager.jac`, `services/lsp_manager.jac`, deploy manifests
**Effort**: 4–5 days

---

### Phase 4: JacCoder Upgrade & Monetization (Weeks 7–8)

#### 4.1 JacCoder Feature Upgrade (Week 7)
**Why**: 80% of hackathon pain was AI quality. The VS Code JacCoder extension (`vscode-jac-coder-main/`) has 13 features our current integration doesn't. Build them directly into jac-builder — no plugin system needed.

**Reference**: VS Code extension source at `vscode-jac-coder-main/`. Key files: `JacCoderClient.ts` (JSON-RPC protocol), `ExtensionState.tsx` (streaming state machine), `ToolCallCard.tsx` (inline diffs), `InputBox.tsx` (slash commands).

**What** (prioritized by user impact):
1. **Subprocess mode**: Rewrite `jaccoder_adapter.jac` to spawn `jac-coder-server` subprocess + JSON-RPC over stdin/stdout (same protocol as VS Code extension), replacing direct Python library calls. Unlocks all features below.
2. **Permission/ask mode**: Agent asks before writing files, shows diff. User approves/denies.
3. **Plan mode**: Agent generates plan, user approves, then executes.
4. **Inline tool timeline**: Tool step cards mixed into streaming chat (not separate ActivityTimeline panel).
5. **LCS diff display**: File changes shown as `+`/`-` lines inside tool cards.
6. **Slash commands**: `/clear`, `/new`, `/attach`, `/explain`, `/jaccheck` in chat input.
7. **Model switching at runtime**: `model.get`/`model.set` RPC — no restart needed.
8. **Token usage tracking**: Per-session cost/token breakdown bar.

**Also**: Remove `claude_adapter.jac`, `useClaudeChat.cl.jac`, all Claude-specific walkers (jac-builder only uses jac-coder).

**Keep code self-contained**: All jac-coder integration stays in `services/jaccoder_adapter.jac` + `hooks/useChatMode.cl.jac` + `components/ide/ChatPanel.cl.jac`. Clean boundaries make future plugin extraction easy.

**Files**: `services/jaccoder_adapter.jac` (rewrite), `hooks/useChatMode.cl.jac` (upgrade), `components/ide/ChatPanel.cl.jac` (upgrade)
**Effort**: 6–7 days

#### 4.2 Stripe Integration
**Why**: Zero payment infrastructure. Product is live with users.

**What**:
- `Subscription` node on user graph (plan, status, stripe_customer_id, current_period_end)
- `billing_ops` walker: `create_checkout`, `webhook`, `portal`, `status`
- Stripe Checkout redirect flow (simplest integration)
- Stripe webhook walker (`walker:pub`) for subscription lifecycle events
- Quota enforcement in `project_ops` (project limits), `preview_control` (sandbox TTL/concurrency), JacCoder (message limits)

**Tier Structure** (suggested):
| | Free | Pro ($20/mo) | Team ($50/mo) |
|---|---|---|---|
| Projects | 5 | 25 | Unlimited |
| AI messages/day | 20 | 200 | 1000 |
| Deployments | 1 | 5 | 20 |
| Preview sandbox TTL | 30 min | 4 hours | 48 hours |

**Files**: New `services/billing_service.jac`, `services/ideServer.jac` (new walker), frontend billing page
**Effort**: 7–8 days

#### 4.3 User Project Export: Desktop & Mobile Apps
**Why**: Users build apps in Jac Builder — they should be able to export them as native desktop and mobile apps directly from the IDE.

**Current state of jac's build targets**:
- **Desktop (Tauri)**: Production-ready. `jac build main.jac --client desktop` works. Produces `.dmg`/`.exe`/`.AppImage`. Requires Rust/Tauri toolchain on build machine. Backend bundled as PyInstaller sidecar.
- **PWA**: Production-ready. `jac build main.jac --client pwa` works. Service workers, offline support, installable.
- **Mobile (Capacitor/React Native)**: **Not implemented** in jac-client. No mobile target exists yet. Target registry (`TargetType` enum) only has `WEB`, `DESKTOP`, `PWA`.

**What**:
- **Desktop export button**: Add to deploy panel. Triggers remote build via jac-scale pipeline (users don't need Rust locally). Download artifact when ready.
- **PWA export button**: Simpler — can run `jac build --client pwa` and deliver the output. No special toolchain needed.
- **Mobile**: Blocked on jac-client implementing a mobile target (Capacitor or similar). Track upstream. In the meantime, PWA covers mobile install via "Add to Home Screen".
- Build queue UI: show progress, deliver artifacts as downloads.
- Gate desktop/PWA export behind Pro tier.

**Files**: `services/deploy_manager.jac`, `components/ide/RunPanel.cl.jac`
**Effort**: 4–5 days for desktop + PWA export UI (mobile blocked on upstream)

#### 4.4 Jac Builder as Desktop App
**Why**: Jac Builder itself should be available as a native desktop app — not just the web IDE. This gives users a local development experience with the full Builder UI, faster performance (no network latency), and offline capability.

**Current state**: jac-ide already has a `[desktop]` section in `jac.toml`:
```toml
[desktop]
name = "jac-ide"
identifier = "jac.ide"
version = "1.0.0"
[desktop.window]
title = "jac-ide"
width = 1200
height = 800
```
The Tauri desktop target is production-ready in jac-client. `jac start main.jac --client desktop` should launch the IDE as a native window with the backend running as a local sidecar.

**What**:
- **Test and validate**: Run `jac start main.jac --client desktop` — verify the full IDE works (Monaco, LSP, preview, AI chat, file management). Fix any issues with local-mode assumptions (sandbox type=local, LSP on localhost, etc.)
- **Build pipeline**: Set up CI to produce `.dmg` (macOS), `.exe` (Windows), `.AppImage` (Linux) on each release via `jac build main.jac --client desktop`
- **Distribution**: GitHub Releases initially, auto-update via Tauri's built-in updater later
- **Local-first features**: When running as desktop app, sandboxes run locally (no K8s), LSP runs locally (no pod affinity needed), git uses system git config. This sidesteps most of the stateless migration complexity.
- **Offline mode**: JacCoder needs API keys (online), but editing, preview, git, and export should work offline.

**Files**: `jac.toml` (desktop config), CI workflow, potential Tauri-specific adjustments
**Effort**: 3–4 days to validate and fix issues, 2–3 days for CI pipeline

#### 4.5 Jac Builder as Mobile App
**Why**: Mobile IDE for quick edits, previewing, and sharing — not full development.

**Current state**: No mobile target in jac-client. PWA is the viable path for now.

**What**:
- **PWA-first**: Configure `jac build main.jac --client pwa` for Jac Builder itself. This makes it installable on iOS/Android via "Add to Home Screen" with offline support.
- **Mobile-optimized layout**: Dashboard and preview work on mobile, editor is read-only or simplified (Monaco doesn't work well on mobile — consider CodeMirror mobile or view-only mode).
- **Future**: When jac-client adds a Capacitor target, build a proper native mobile app. For now, PWA covers the use case.

**Files**: `jac.toml` (pwa config), responsive CSS in dashboard/preview components
**Effort**: 2–3 days for PWA config + mobile layout fixes

#### 4.6 UI Polish Pass
**Why**: Cumulative small improvements that compound into a polished product feel.

**What**:
- Consistent error states with recovery actions across all panels (not raw tracebacks)
- Keyboard shortcut discoverability (tooltip badges on ActivityBar icons)
- Mobile-responsive dashboard
- Dark mode contrast audit on all semantic color tokens
- Smoother transitions between chat-view and editor-view layouts

**Files**: Various `components/ide/` files
**Effort**: 3–4 days

---

## VS Code Extension Alignment

### Current Extensions
- **JacLang** (`jaseci-labs.jaclang-extension`) — 3,834 installs. Full LSP, TextMate grammar, debugging, graph visualization, env management.
- **JacCoder** (`jaseci-labs.jaccoder`) — 85 installs. AI chat agent in VS Code webview panel. Connects to jac-coder-server.

### Alignment Plan

| Action | Where | Effort |
|--------|-------|--------|
| Sync tmLanguage grammar (4872 vs 4889 lines diverged) | Both | 1 hour |
| jac-ide consumes formatting, rename, semantic tokens | jac-ide (Phase 2) | 7 days |
| Add workspace symbol search to VS Code extension | jac-vscode | 1 day |
| Share snippet definitions via LSP (remove 15 hardcoded snippets) | Both | 2 days |
| Ensure jac-mcp works identically in both environments | Already done | — |

### What Cannot Be Shared
- **Debugging** (VS Code has DebugPy — not feasible in web IDE without remote debug adapter)
- **Graph visualization** (VS Code webview vs React — different rendering tech)
- **Environment management** (irrelevant in jac-ide's server architecture)

### Experiment Needed
Can we make the exact VS Code JacLang plugin work inside jac-ide via Monaco's extension host? Monaco doesn't natively run VS Code extensions, but projects like `@codingame/monaco-vscode-api` bridge this gap. **Spike**: 2–3 days to evaluate feasibility. If it works, we get VS Code parity for free. If not, continue with manual LSP feature consumption.

---

## Subprocess Architecture (Current → Target)

### Current State
| Process | Where It Runs | State Location | Survives Pod Restart? |
|---------|--------------|----------------|----------------------|
| Preview (`jac start`) | K8s sandbox pod | `sandbox_store` (graph nodes) | **Yes** — separate pod |
| LSP (`jac lsp`) | Main Builder pod | `_lsp_registry` (in-memory) | **No** — PID lost |
| JacCoder agent | Main Builder pod (ThreadPoolExecutor) | `_session_map`, `_event_queues` | **No** — threads lost |
| `jac install` | Transient (120s) | None | N/A |

### Target (After Phase 3)
| Process | Where It Runs | State Location | Survives Pod Restart? |
|---------|--------------|----------------|----------------------|
| Preview | K8s sandbox pod (unchanged) | Graph nodes (unchanged) | **Yes** |
| LSP | Main pod with Redis affinity | `_lsp_registry` local + Redis routing | **Reconnects** in <5s |
| JacCoder agent | Main pod with Redis event bus | Redis Streams | **Recoverable** — events preserved |
| `jac install` | Transient (unchanged) | None | N/A |

### Future (Post-Roadmap): Full Sidecar Architecture
- LSP → dedicated lightweight pod per user session
- JacCoder → distributed task queue (Celery/RQ) with Redis broker
- Main Builder pods → pure stateless API servers
- Estimated: 4–6 weeks additional work

---

## Production Performance Targets

| Metric | Current (hackathon) | Target (2 months) |
|--------|-------------------|-------------------|
| Infrastructure | 54 servers, 600 pods | Right-sized based on steady-state load |
| Preview cold-start (warm pool hit) | 3–5s | < 2s (parallel init, pre-installed deps) |
| Preview cold-start (cold) | 10–15s | < 5s (faster pod scheduling) |
| AI first-token latency | 2–5s (500ms polling) | < 1s (SSE streaming) |
| Pod startup (readiness) | 480s (8 min) | < 180s (profile and optimize startup) |
| Session recovery on pod restart | Total loss | LSP reconnects in <5s, JacCoder events preserved |
| Warm pool size | 450 pods (hackathon) | Dynamic based on active user count |

---

## Local Development Issues

**Known**: jaclang changes by Thami in progress affect local setup. Until those land, local dev may have incompatibilities with production.

**Mitigation**:
- Pin `jaclang` version in Dockerfile and document required version in README
- Add setup script (`scripts/dev-setup.sh`) that creates venv, installs pinned deps, runs sanity check
- Track Thami's branch for merge readiness

---

## Weekly Sprint Plan

### Week 1–2: UX for Low-Tech Users
- [x] ~~"Describe & Build" prompt-first screen~~ (already shipped on dashboard)
- [ ] Git: auto-set user.name/email from auth profile on project creation
- [ ] Git: collapse GitHub/Remotes/History sections by default
- [ ] Git: auto-initialize .git if not present
- [ ] Share preview URL (copy to clipboard)
- [ ] Onboarding tooltip tour
- [ ] Loading skeletons for file tree, preview, chat

### Week 3–4: Performance & Intelligence
- [ ] Preview startup progress UI (phases, not spinner)
- [ ] Batch file sync for multi-file AI edits
- [ ] Warm pool tuning based on hackathon data
- [ ] LSP formatting on save
- [ ] LSP workspace file notifications
- [ ] LSP rename symbol
- [ ] LSP semantic tokens
- [ ] LSP lintfix in command palette
- [ ] tmLanguage grammar sync
- [ ] JacCoder: auto-inject pitfalls/patterns context
- [ ] JacCoder: validation loop (jac check → auto-retry)
- [ ] JacCoder: SSE streaming (replace 500ms polling)

### Week 5–6: Stateless Infrastructure
- [ ] Deploy Redis (ElastiCache)
- [ ] State store abstraction layer
- [ ] Migrate WS auth tokens to Redis
- [ ] Migrate session state to Redis
- [ ] Migrate JacCoder event queues to Redis Streams
- [ ] LSP session affinity via Redis
- [ ] Graceful reconnection UI
- [ ] Pod startup profiling and optimization

### Week 7: JacCoder Feature Upgrade
- [ ] Rewrite `jaccoder_adapter.jac` → subprocess + JSON-RPC (reference `JacCoderClient.ts`)
- [ ] Permission/ask mode (agent asks before writing, shows diff)
- [ ] Plan mode (generate plan → user approves → execute)
- [ ] Inline tool timeline with LCS diffs (replace separate ActivityTimeline)
- [ ] Slash commands in chat input (`/clear`, `/new`, `/attach`, `/explain`)
- [ ] Runtime model switching (`model.get`/`model.set` RPC)
- [ ] Token usage tracking bar
- [ ] Remove claude_adapter.jac and all Claude-specific code

### Week 8: Monetization & Platform
- [ ] Stripe Checkout integration
- [ ] Billing walker + webhook handler
- [ ] Tier enforcement (quotas)
- [ ] Desktop export button for user projects (Tauri build pipeline)
- [ ] PWA export button for user projects
- [ ] Jac Builder desktop app: validate + CI pipeline
- [ ] Jac Builder PWA: configure for mobile install
- [ ] UI polish pass (error states, shortcuts, responsive dashboard)

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| jaclang breaking changes from Thami's work | Blocks local dev + prod | Pin version, coordinate with Thami on merge timing |
| Redis adds ops complexity | Deployment issues | Use ElastiCache managed, start single-node, add later |
| Tauri build requires Rust toolchain in CI | CI setup complexity | Use pre-built Tauri GitHub Actions, test on one platform first |
| Mobile target not in jac-client | Can't ship native mobile export | PWA covers install use case; track upstream for Capacitor target |
| JacCoder quality improvements insufficient | Users still prefer VS Code + Claude | Measure before/after with same prompts, iterate on agent tools |
| Warm pool right-sizing wrong | Over-provisioning (cost) or under (latency) | Start conservative, auto-scale based on metrics |
| Graph persistence race condition (#5446) | Silent data loss | Track upstream fix, no app-level workaround |
| Desktop app local-mode issues | Monaco/LSP/preview broken locally | Spike early in week 8, budget 2 days for fixes |
| jac-coder-server subprocess instability | AI chat breaks during rewrite | Keep old `jaccoder_adapter.jac` as fallback behind feature flag until new approach is stable |
| jac-coder-server not installed in venv | Subprocess spawn fails | Add `jac-coder` to Dockerfile pip install, verify in CI |

---

## Success Metrics (End of 2 Months)

1. **"Describe & Build"** flow: >50% of new users start with the prompt bar (not file tree)
2. **Preview startup**: <2s warm, <5s cold (measured via pod event timestamps)
3. **AI first-token**: <1s with SSE streaming
4. **JacCoder quality**: validation loop catches >80% of syntax errors before user sees them
5. **LSP parity**: formatting, rename, semantic tokens all working in jac-ide
6. **Session resilience**: pod restart recovers LSP in <5s, JacCoder events preserved
7. **Stripe billing**: live with Free + Pro tiers, first paying customers
8. **No "is my sandbox broken?"**: clear status indicator + auto-recovery covers all failure modes
9. **Desktop app**: Jac Builder downloadable as .dmg/.exe/.AppImage from GitHub Releases
10. **Mobile access**: Jac Builder installable as PWA on iOS/Android
11. **JacCoder upgrade**: permission mode, plan mode, inline diffs, slash commands all working
12. **Claude code removed**: zero Claude-specific code remaining in codebase

---

## Future / Experimental: Plugin System & Marketplace

> Full architecture: [docs/PLUGIN_ARCHITECTURE.md](PLUGIN_ARCHITECTURE.md)
>
> **Status**: Architecture designed and documented. Implementation deferred until product is stable with paying customers and there is demand from third-party developers.

**When to build**: When Jac Builder has 1,000+ active users, Stripe revenue, and developers asking "can I add my own tools?" — not before.

**What's ready**: Complete architecture doc covering:
- Handler-based plugin API (Direction C) — plugins register functions, not walkers
- Two core dispatcher walkers (`plugin_dispatch` + `plugin_stream`) handle all plugin traffic
- `PluginRoot` graph isolation — enforced by core, not convention
- `PluginContext` API — event bus, subprocess management, file access, settings, inter-plugin calls
- No server restart on plugin install (runtime handler registration)
- Error isolation (try/except wrapping per handler)
- `plugin.json` manifest format with 7 contribution points
- Marketplace sidebar panel design
- `.jacplugin` distribution format
- jac-coder and jaclang as reference plugin implementations

**Prep work done now (free — just good code organization)**:
- Keep jac-coder integration self-contained in `services/jaccoder_adapter.jac` (clean boundaries)
- Keep LSP integration self-contained in `services/lsp_manager.jac`
- Don't scatter these features across `ideServer.jac`
- When the time comes, extracting into plugins is a 3-4 week project with the blueprint ready

**Estimated implementation**: 4-5 weeks when ready
- Week 1: Plugin API foundation (PluginContext, plugin_dispatch walker, plugin_loader)
- Week 2: Rebuild jaseci.jaclang as plugin (LSP, graph viz)
- Week 2-3: Rebuild jaseci.jac-coder as plugin (AI chat, all 13 features)
- Week 3-4: Frontend plugin framework (data-driven ActivityBar, sidebar registry, CommandPalette)
- Week 4-5: Marketplace UI + distribution (.jacplugin format, install/uninstall)
