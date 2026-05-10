# Project Structure

```mermaid
flowchart TD
    Repo["weave repo"] --> Tools["Vite+ workspace tooling"]
    Repo --> Desktop["apps/desktop: Tauri + React"]
    Repo --> Agent["services/agent: Python FastAPI"]
    Repo --> Data["data: local dev runtime state"]
    Repo --> Docs["docs: knowledge and architecture"]
    Desktop --> Rust["src-tauri Rust bridge"]
    Rust --> Agent
    Rust --> Data
```

Weave is planned as a small monorepo where the desktop app, local agent service, runtime data, and knowledge base live together during early development.

## Directory Layout

```text
weave/
  AGENTS.md
  CLAUDE.md
  LICENSE
  Makefile
  package.json
  pnpm-workspace.yaml

  apps/
    desktop/
      index.html
      package.json
      src/
      src-tauri/

  services/
    agent/
      app/
      tests/

  data/
    profiles/
    sessions/
    drafts/
    memory/
    indexes/
    logs/

  docs/
    architecture.md
    project-structure.md
    runtime-boundaries.md
    superpowers/
```

The current implementation includes the Phase 0 desktop UI, Tauri bridge, Python agent service, local `data/` placeholders, and knowledge docs. [CLAUDE.md](../CLAUDE.md#L1) is a symlink to [AGENTS.md](../AGENTS.md#L1).

## Startup Path

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Vite as Vite+ / pnpm
    participant UI as React UI
    participant Rust as Tauri Rust bridge
    participant Py as Python FastAPI agent
    participant FS as data/

    Dev->>Vite: make desktop-dev / vp run desktop-dev
    Vite->>UI: start Vite dev server
    UI->>Rust: invoke Tauri command
    Rust->>FS: initialize local paths
    Rust->>Py: call health/discover over localhost
    Py-->>Rust: structured JSON
    Rust-->>UI: typed command result
```

Phase 0 may start the Python service manually with `make agent-dev` before launching the desktop app. Rust should still own the bridge between UI and Python so the frontend does not depend on Python port details.

## Ownership Boundaries

- `apps/desktop/src/` owns the minimal React verification UI.
- `apps/desktop/src-tauri/` owns Tauri commands, local data setup, and Python service forwarding.
- `services/agent/app/` owns agent HTTP endpoints and future writing-agent behavior.
- `data/` is development runtime state, not core source code.
- `docs/` owns repository knowledge, architecture notes, decisions, specs, and implementation plans.

## Scope Rules

- Keep Phase 0 changes small enough to verify manually.
- Add shared packages only after there is repeated schema or utility duplication.
- Keep product intent and runtime boundaries documented before adding implementation complexity.

## Key Files

- [AGENTS.md](../AGENTS.md#L1) - root navigation and task routing for agents.
- [apps/desktop/src/main.tsx](../apps/desktop/src/main.tsx#L1) - React entry point.
- [apps/desktop/src/App.tsx](../apps/desktop/src/App.tsx#L1) - Phase 0 verification UI.
- [apps/desktop/src/tauri.ts](../apps/desktop/src/tauri.ts#L1) - typed frontend wrappers around Tauri commands.
- [apps/desktop/src-tauri/src/lib.rs](../apps/desktop/src-tauri/src/lib.rs#L1) - Tauri command registration.
- [apps/desktop/src-tauri/src/commands.rs](../apps/desktop/src-tauri/src/commands.rs#L1) - Rust command handlers.
- [apps/desktop/src-tauri/src/agent.rs](../apps/desktop/src-tauri/src/agent.rs#L1) - Rust HTTP client for Python agent service.
- [apps/desktop/src-tauri/src/storage.rs](../apps/desktop/src-tauri/src/storage.rs#L1) - local data initialization.
- [services/agent/app/main.py](../services/agent/app/main.py#L1) - FastAPI app and Phase 0 routes.
- [docs/architecture.md](architecture.md#L1) - current architecture and startup flow.
- [docs/runtime-boundaries.md](runtime-boundaries.md#L1) - runtime ownership and cross-layer rules.
- [docs/superpowers/specs/2026-05-10-weave-phase-0-design.md](superpowers/specs/2026-05-10-weave-phase-0-design.md#L1) - Phase 0 design source of truth.

---
*Last updated: 2026-05-10 | Reason: Phase 0 implementation refresh*
