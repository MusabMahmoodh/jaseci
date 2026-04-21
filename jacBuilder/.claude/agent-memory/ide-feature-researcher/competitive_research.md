---
name: Competitive Research — AI IDEs and Builder Platforms
description: Lovable, Bolt, Replit, v0, Cursor analysis for Jac Builder productization
type: project
---

# Competitive Research (2026-04-08)

## Lovable
- Hides file tree by default — chat + preview is the default UI
- Every AI edit is atomic (works or auto-reverts)
- Visual edit: click element in preview → AI updates just that component
- Meters AI messages (not compute). Free = 50/month, Pro = $25/month
- Deploy = single "Publish" button → lovable.app subdomain
- Git is hidden, surfaced as "restore to previous version" with timestamps

## Bolt.new (StackBlitz)
- WebContainers = entire Node.js runtime in WASM in browser. Zero cold start.
- "Enhance prompt" button — AI refines vague prompt before generating
- "Fix errors" button appears automatically when terminal shows errors
- Deploys to Netlify/Vercel/Cloudflare with one button
- Enterprise: Azure DevOps + Jira integration

## Replit
- Replit Agent generates full projects from prompt
- Multiplayer via Yjs CRDT — anyone with link can co-edit
- "Always-on" = promoted deployment (not just preview)
- Architecture: nsjail containers + GCS FUSE-mounted filesystem. API server is stateless — any pod can serve any request because the container IS the state.
- Mobile: native iOS/Android app

## v0 (Vercel)
- Component generation (not full apps). Unit = shadcn component tree.
- Fork + iterate model. Public gallery of generated components.
- Direct Vercel deploy integration

## Cursor
- Electron app (VS Code fork)
- "Composer" mode: multi-file batch edit with unified diff review before apply
- `.cursorrules` per-project AI persona (similar to our CLAUDE.md)
- $20/month flat, not usage-metered — appeals to professionals

## Desktop App Frameworks
- **Tauri**: ~8MB binary, Rust + system WebView, best for bundling a webserver sidecar
- **Electron**: ~150MB, bundles Chromium, consistent rendering, VS Code/Cursor use this
- For Jac Builder: Tauri sidecar pattern — bundle `jac` binary, launch `jac start main.jac --port 0` as child process, WebView points to localhost

## Mobile Strategy
- **PWA** is the right first step — add manifest.webmanifest + service worker
- jac.toml already has theme_color + apple_touch_icon set
- Capacitor/Expo not feasible (need Jac runtime on device)
- iPad support: collapse 3-panel to 2-panel at < 1024px

## Stateless Architecture Patterns
- **Gitpod**: ws-manager service separate from API; events via nats.io message bus
- **Codespaces**: devcontainer snapshots; devtunnel proxies WebSocket to container
- **Replit**: GCS FUSE + nsjail; OT server with Redis for multiplayer

## Billing Model Recommendation
- Free: 3→10 projects, 50 AI messages/month
- Builder $20/month: 10 projects, 500 AI messages
- Pro $49/month: unlimited projects + deployments, 2000 AI messages, custom domain
- Team $99/seat/month: 5000 AI messages, team sharing
- Meter: AI message count (maps to API cost, predictable to users)
- Integration: Stripe Checkout hosted page → webhook → `Subscription` graph node on UserProfile
- Add `check_quota(user_id, action)` before ai_chat, project_ops create, deploy_ops
