# HMR Architecture and Implementation Plan

## 1. Goal

Integrate Hot Module Replacement (HMR) for the jac-client development workflow using the Vite Dev Server. The primary challenge is creating a high-speed feedback loop between the `.jac` source files and the `.js` files consumed by Vite.

**Key Outcome:** When a developer saves a `.jac` file, the corresponding component updates instantly in the browser without losing React state.

## 2. Architectural Overview

The HMR system introduces a new component, the **Jac Compiler Watcher**, which works in parallel with the Vite Dev Server.

### Dev Flow Diagram

```mermaid
graph TD
    subgraph Frontend (Browser)
        Browser[Client App]
        ViteClient[Vite HMR Client]
    end

    subgraph Backend (Dev Environment)
        JacWatcher[Jac Compiler Watcher]
        ViteServer[Vite Dev Server]
    end

    style JacWatcher fill:#ffdd99,stroke:#e8b937,stroke-width:2px;
    style ViteServer fill:#c7e8ff,stroke:#6aa2d7,stroke-width:2px;
    style ViteClient fill:#c7e8ff,stroke:#6aa2d7,stroke-width:2px;

    A[Edit app/MyComponent.jac] --> B{File Change Detected};
    
    subgraph Step 1: Pre-compilation and HMR Trigger
        B --> C[JacWatcher: Minimal Re-compile]
        C --> D(Update build/MyComponent.js)
    end
    
    subgraph Step 2: Vite HMR Propagation
        D --> E{ViteServer: Detects .js Change in build/}
        E --> F[ViteServer: Sends HMR Payload via WebSocket]
        F --> G(ViteClient: Receives Update)
        G --> H[ViteClient: Triggers React Fast Refresh]
        H --> Browser
    end

    ViteServer -- Serves build/ directory --> Browser;
    ViteServer -- Maintains WS connection --> ViteClient;
```

## 3. Core Component Changes

### 3.1. ViteClientBundleBuilder Enhancement

The builder's entry point must now be conditional based on the run mode (`--dev` or `--build`).

| Mode | Entry Point Method | Action |
|------|-------------------|--------|
| `--build` (Production) | `_bundle_with_vite()` | Executes the full pipeline (compilation, Babel, asset copy, `npm run build`), resulting in `client.[hash].js` and `main.css`. (Current functionality) |
| `--dev` (Development) | `_start_dev_workflow()` | New Method. Performs the initial compilation, starts the JacCompilerWatcher, and starts the Vite Dev Server. |

#### New Method: `_start_dev_workflow()`

1. **Initial Pre-Compilation (Bootstrap):** Run the existing Steps 1-4 (Module compilation, Recursive dependency resolution, Babel compilation, Asset copying) once. This populates the `build/` directory for the first server load.

2. **Start Watcher:** Start the JacCompilerWatcher process (see 3.2).

3. **Start Dev Server:** Start the Vite Dev Server (either programmatically or via `npm run dev`) pointing its root to the `build/` directory.

### 3.2. New Component: JacCompilerWatcher

This service is the core HMR enabler for Jac code. It is a persistent process in development mode.

| Responsibility | Detail | Implementation Strategy |
|----------------|--------|-------------------------|
| **File Watching** | Monitor all relevant source files (e.g., `**/*.jac`, `**/*.js`, `**/*.css`) within the project root. | Use a fast, reliable file-watching utility (e.g., `chokidar` in Node/JS, or platform-native watching in Python/Rust if used for the backend). |
| **Minimal Re-compilation** | When a change is detected, run the `jac → js` transpilation only for the affected file and its direct dependents. | This must reuse the logic from `_compile_dependencies_recursively` but in a targeted, incremental way. |
| **Output Update** | Write the newly generated `.js` file directly to the `build/` directory. | **Crucial:** The update must occur here. Vite's native watcher will pick up this change and initiate HMR. |
| **Asset Copying** | If the changed file is a CSS/image asset, immediately re-run Step 4 (`_copy_asset_files`) for that specific file. | Vite will detect the change in the `build/` asset and perform CSS HMR. |

### 3.3. Vite Dev Server Configuration

The server must be configured to watch the `build/` output directory, not the source directory.

The generated `vite.config.js` (`.jac-client.configs/vite.config.js`) must be updated:

```javascript
// vite.config.js (Simplified Dev Mode)
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react'; // Provides React Fast Refresh
// ... other imports

export default defineConfig({
  // 1. Point root to the *output* of the Jac compiler
  root: path.resolve(projectRoot, "build"), 
  
  // 2. Base configuration as defined by the user
  server: { 
    port: process.env.VITE_PORT || 3000, 
    // Additional user overrides from config.json
    // ...userServerOptions
  },
  
  plugins: [
    // Ensure Fast Refresh is always included in Dev mode
    react(), 
    // ...userPlugins
  ],
  
  // Existing resolve aliases must target the build output:
  resolve: {
    alias: {
      "@jac-client/utils": path.resolve(projectRoot, "build/client_runtime.js"),
      // Note: Use 'build/' here, as compiled/ is now a temporary step.
    },
    // ...
  }
});
```

## 4. Implementation Details: Fast Refresh

The `@vitejs/plugin-react` (React Fast Refresh) handles the actual component state preservation. This requires no changes to your existing Jac-to-JS transpiler.

As long as the transpiler output (`.js` files in `build/`) adheres to the standard React/JSX conventions, Vite's React plugin will automatically wrap components with the necessary HMR runtime code, enabling state preservation upon updates.

**Note:** No `import.meta.hot.accept()` is required for standard React components; the official plugin handles it.

## 5. CSS HMR

The existing CSS flow is already well-suited for HMR:

1. `app.jac` changes → JacCompilerWatcher detects change.
2. JacCompilerWatcher runs minimal compilation/asset copy: `source/styles.css` → `build/styles.css`.
3. Vite detects the change in `build/styles.css`.
4. Vite pushes the updated CSS via HMR to the browser without a page reload.

This process is automatically managed by Vite once it sees the updated file in its source root (`build/`).

## 6. Development Workflow (New)

The developer experience will change from running a single build command to running a persistent dev server.

### Start

Run `npm run dev` (or the equivalent command handled by JacAPIServer).

- This runs the `_start_dev_workflow()`.
- Browser automatically opens to `http://localhost:3000/`.

### Edit

Developer modifies `components/button.jac`.

### HMR

1. JacCompilerWatcher recompiles `components/button.jac` to `build/components/button.js` (e.g., in ≈50ms).
2. Vite detects the change in the `build/` file.
3. The button component updates in the browser instantly, preserving its state (e.g., if it was clicked).

### Stop

Developer terminates the JacCompilerWatcher / Vite Dev Server process.
