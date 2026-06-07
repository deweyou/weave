# Project Structure

```mermaid
flowchart TD
    Repo["weave repo"] --> Tools["Vite+ / pnpm workspace"]
    Repo --> Desktop["apps/desktop"]
    Repo --> Docs["docs knowledge base"]
    Desktop --> Main["Electron main"]
    Desktop --> Preload["Electron preload bridge"]
    Desktop --> FirstRunWindow["first-run BrowserWindow"]
    Desktop --> MainWindow["main BrowserWindow"]
    FirstRunWindow --> FirstRunRenderer["first-run React app"]
    MainWindow --> MainRenderer["main React app"]
```

Weave is currently a desktop-first local app in a single repository. The
workspace is intentionally shallow: one runnable Electron app plus docs.

## Directory Layout

```text
weave/
  AGENTS.md
  DESIGN.md
  README.md
  package.json
  pnpm-workspace.yaml
  tsconfig.base.json

  apps/
    desktop/
      src/
        main/
        preload/
        shared/
        renderer/

  docs/
    project-structure.md
    repository-rules.md
    decisions/
```

## Startup Path

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant VP as Vite+ / pnpm
    participant Main as Electron main
    participant Preload as Preload bridge
    participant FirstRun as first-run React app
    participant MainUI as main React app

    Dev->>VP: vp run desktop:dev
    VP->>FirstRun: serve first-run.html
    VP->>MainUI: serve main.html
    VP->>Main: compile and launch Electron
    Main->>Main: read workspace status
    alt no usable workspace
        Main->>Preload: create first-run BrowserWindow
        Preload->>FirstRun: expose window.weave
    else workspace ready
        Main->>Preload: create main BrowserWindow
        Preload->>MainUI: expose window.weave
    end
```

## Ownership Rules

Desktop runtime ownership:

- `apps/desktop/src/renderer/first-run-app.tsx` owns the first-run setup React
  app and should only be loaded by the first-run BrowserWindow.
- `apps/desktop/src/renderer/main-app.tsx` owns the main workspace React app and
  should only be loaded by the main BrowserWindow.
- `apps/desktop/first-run.html` and `apps/desktop/main.html` are separate Vite
  HTML entries. Keep this one-window-to-one-renderer-app mapping unless a future
  architecture decision explicitly changes it.
- `apps/desktop/src/renderer/` owns shared React view components used by those
  entries; it should not reintroduce a single root app that branches between
  first-run and main window behavior.
- `apps/desktop/src/main/` owns Electron main-process behavior, native dialogs,
  app-local config, and filesystem setup.
- `apps/desktop/src/preload/` owns the safe renderer bridge.
- `apps/desktop/src/shared/` owns shared TypeScript API contracts.

- [apps/desktop/src/main/main.ts#L1](../apps/desktop/src/main/main.ts#L1) owns
  desktop process startup and window creation.
- [apps/desktop/src/preload/preload.ts#L1](../apps/desktop/src/preload/preload.ts#L1)
  owns the safe Electron-to-renderer bridge.
- [apps/desktop/src/renderer/first-run-app.tsx#L1](../apps/desktop/src/renderer/first-run-app.tsx#L1)
  owns first-run React bootstrapping.
- [apps/desktop/src/renderer/main-app.tsx#L1](../apps/desktop/src/renderer/main-app.tsx#L1)
  owns main workspace React bootstrapping.
- [apps/desktop/src/shared/desktop-api.ts#L1](../apps/desktop/src/shared/desktop-api.ts#L1)
  owns shared type contracts between preload and renderer.

## Initialized Workspace Structure

```text
SelectedFolder/
  .weave/
    config.json
    indexes/
    logs/
  notes/
  memos/
  todos/
```

## Non-Goals For Now

- No `packages/*` directory until extraction has a real consumer.
- No `apps/mobile` directory until iOS implementation starts.
- No sync, storage engine, or cross-device architecture before local workflows
  are useful.

---
*Last updated: 2026-06-07 | Reason: record the separate first-run and main renderer app boundary*
