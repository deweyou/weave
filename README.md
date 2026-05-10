# Weave

Weave is a local-first writing agent for personal knowledge. Phase 0 builds the runnable project skeleton: Vite+ workspace, Tauri/React desktop UI, Rust bridge commands, Python FastAPI mock agent service, and development-local data directories.

## Prerequisites

- Vite+ (`vp`)
- Node managed by Vite+
- pnpm managed by Vite+
- Rust toolchain with `cargo`
- Python 3.11+

## Install

```bash
make install
```

## Run The Agent Service

```bash
make agent-dev
```

The service runs at `http://127.0.0.1:8765`.

## Run The Desktop App

In a second terminal:

```bash
make desktop-dev
```

## Test

```bash
make test
```

## Check

```bash
make check
```

## Phase 0 Scope

Included:

- Minimal desktop UI
- React to Rust command calls
- Rust to Python health/discover calls
- Mock `/writing/discover` response
- Development data directory initialization

Not included:

- Real model providers
- Multi-turn chat
- Memory retrieval
- Writing workflows
- LangChain or LangGraph

## Repository Map

- `apps/desktop/` - Tauri + React desktop app
- `services/agent/` - Python FastAPI agent service
- `data/` - development-local runtime data
- `docs/` - architecture, decisions, knowledge base, specs, and plans
