# Weave

Weave is an early-stage local-first writing agent for personal knowledge. The current repository goal is Phase 0: prove a runnable desktop skeleton with Vite+ tooling, Tauri/React, Rust bridge commands, a Python FastAPI agent service, and local data directories.

## Knowledge Base

| Document | What it answers |
|----------|-----------------|
| [docs/project-structure.md](docs/project-structure.md) | How the repository is organized, where code should live, and how the app boots |
| [docs/phase-0-runtime-boundaries.md](docs/phase-0-runtime-boundaries.md) | Which runtime owns UI, desktop bridge, agent service, and data responsibilities |
| [docs/superpowers/specs/2026-05-10-weave-phase-0-design.md](docs/superpowers/specs/2026-05-10-weave-phase-0-design.md) | The approved Phase 0 product and architecture scope |
| [docs/.state.md](docs/.state.md) | Current knowledge-base state and coverage |
| [docs/.todo.md](docs/.todo.md) | Open learning items and unresolved product/architecture questions |

## Hard Constraints

- Keep Phase 0 scoped to project initialization, Hello World UI, Rust bridge checks, Python mock endpoints, local data directory initialization, and docs.
- Do not add real model providers, API key handling, memory retrieval, embeddings, multi-turn chat, writing workflow automation, or LangChain/LangGraph in Phase 0.
- Use Vite+ for JavaScript workspace/tooling only; keep Tauri/Rust and Python/FastAPI as explicit runtime boundaries.
- The React UI must call Python only through Rust/Tauri commands, never directly through a hardcoded localhost URL.
- Treat `data/` as development-local runtime state. Do not commit generated profile/session/draft content beyond intentional starter fixtures.

## Task Routing

- If changing repository layout, startup commands, or boot flow, read [docs/project-structure.md](docs/project-structure.md) first.
- If touching React/Tauri/Rust/Python boundaries, read [docs/phase-0-runtime-boundaries.md](docs/phase-0-runtime-boundaries.md) first.
- If changing Phase 0 scope, update [docs/superpowers/specs/2026-05-10-weave-phase-0-design.md](docs/superpowers/specs/2026-05-10-weave-phase-0-design.md) before implementation.
- If completing meaningful architecture or product work, update the knowledge base under `docs/` and refresh [docs/.state.md](docs/.state.md).

## Current Prerequisites

- Vite+ (`vp`) is expected for Node/pnpm workspace commands.
- Rust toolchain is required before Tauri work because `cargo` is needed.
- Python 3.11+ is expected for the FastAPI agent service.

