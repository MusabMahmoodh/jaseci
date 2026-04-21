# Jac IDE - Agent Memory (ide-feature-researcher)

## Project Summary
Jac Builder Studio — full-stack web IDE written entirely in Jac. Production at jac-builder.jaseci.org.
Entry point: `main.jac`. Config: `jac.toml`. Deployed to EKS (us-east-2), 15-30 replicas.

## Current Production Feature Set (confirmed 2026-04-08)
- K8s sandbox backend (warm pool of 50, subdomain routing via ALB)
- Full git workflow (15+ ops, worktrees, checkpoints, diff, push/pull, remotes)
- Two AI agents: JacCoder (GPT-4o via byllm) + Claude Code CLI integration
- Community gallery (submit/clone/search)
- K8s deploy via `jac-scale` (`deploy_ops` walker)
- Google + GitHub SSO; GitHub repo integration with encrypted token storage
- LSP (`jac lsp` subprocess) with completions, hover, diagnostics, go-to-definition
- Version history (50 rolling snapshots, jacpack export/import)
- 3-project limit per user (hardcoded, NO billing system)
- Desktop app config in `jac.toml` `[desktop]` section (Tauri-style, NOT yet enabled)
- NO Stripe or payment code anywhere

## Architecture

### Backend services
- `services/ideServer.jac` — all walkers (see CLAUDE.md for full list)
- `services/sandbox_store.jac` — graph-backed sandbox state (MongoDB, pod-safe)
- `services/deploy_manager.jac` — jac-scale K8s deploy; `_deploy_results` is IN-MEMORY (gap)
- `services/jaccoder_adapter.jac` — in-memory event queues (gap for pod rotation)
- `services/claude_adapter.jac` — in-memory subprocess registry (requires sticky sessions)
- `services/github_service.jac` — GitHub OAuth + installation tokens (8h expiry)

### Known in-memory state gaps (stateless risk)
- `_deploy_results` dict in deploy_manager — should write to Project graph node
- JacCoder event queues — should move to Redis Pub/Sub
- Claude subprocess registry — requires ALB sticky sessions (not yet configured)

### Frontend
- `pages/JacIDE.cl.jac` — VS Code-style layout, ActivityBar + sidebars
- Default view is "chat" sidebar (`activeSidebarView = "chat"`)
- File tree is always visible as primary sidebar option
- `hooks/useIDE.cl.jac`, `useChatMode.cl.jac`, `useClaudeChat.cl.jac`

## Key Strategic Gaps
1. No billing (Stripe) — biggest gap for productization
2. No "describe and build" entry point — AI is in sidebar, not hero
3. 3-project limit too low vs competitors (Lovable/Bolt give unlimited projects, meter AI)
4. Community gallery not linked from landing page — missed growth lever
5. No error auto-fix loop (preview fails → user stuck, no path to AI fix)
6. No "Share preview URL" button in UI (subdomain routing works, just not exposed)
7. Desktop features disabled in jac.toml despite config being present

## Walker Pattern (unchanged)
```jac
walker my_walker {
    has param1: str;
    can handle with Root entry { report {...}; }
}
```

## Detailed Feature Analysis
See: `feature-analysis.md`

## Competitive Research (2026-04-08)
See: `competitive_research.md`
Key findings: Lovable hides file tree by default, meters AI messages not compute, visual-click-to-edit;
Bolt uses WebContainers (browser WASM) for zero cold start; Replit uses nsjail + GCS FUSE for stateless pods;
Cursor is Electron (VS Code fork); v0 is component-generation not full apps.
Billing model: seat + AI-message hybrid. Stripe Checkout hosted page is fastest integration.
