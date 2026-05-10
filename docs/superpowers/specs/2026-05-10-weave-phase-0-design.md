# Weave Phase 0 Design

## Goal

Phase 0 turns Weave from a product direction into a runnable engineering skeleton. It proves the local desktop architecture works before adding real model calls, memory, writing workflows, or a full chat UI.

The deliverable is a desktop app that can render a minimal page, call Rust commands from React, reach a local Python agent service through Rust, initialize local data directories, and document how to run the system.

## Product Scope

Weave is a local-first writing agent for personal knowledge. The long-term product helps the user turn personal thoughts, memories, and prior writing into articles through conversation, active questioning, memory recall, and staged writing workflows.

Phase 0 does not implement that product experience. It creates the foundation for it.

In scope:
- Project skeleton and monorepo structure.
- React/TypeScript desktop UI inside Tauri.
- Rust bridge commands for app status, agent service checks, writing discovery, and local paths.
- Python FastAPI service with mock endpoints.
- Local data directory initialization.
- README and architecture documentation.

Out of scope:
- Real model providers or API keys.
- Multi-turn chat behavior.
- Session persistence beyond directory and starter object creation.
- Memory retrieval, indexing, embeddings, or knowledge ingestion.
- Agent workflow stages beyond a mocked `discover` response.
- LangChain, LangGraph, or other heavy orchestration frameworks.
- Complex editor, sidebar, profile management UI, or production packaging.

## Recommended Approach

Use Vite+ as the JavaScript and workspace toolchain, not as the whole application architecture.

Vite+ should manage Node, pnpm, workspace scripts, and frontend checks/builds. Tauri remains the desktop runtime, Rust remains the local bridge, and Python/FastAPI remains the agent runtime. This keeps Weave's long-term local-first boundary clear while still benefiting from Vite+'s unified JS workflow.

The first implementation should prefer a working skeleton over a polished app. The UI can be a single screen with runtime status, agent health, local paths, an input field, a discover button, and a structured result view.

## Architecture

```text
React/TypeScript UI
  -> Tauri invoke()
    -> Rust commands
      -> local filesystem for data paths
      -> localhost HTTP for Python agent service
        -> FastAPI mock writing endpoints
```

The front end must not directly know the Python service URL, port, process details, or HTTP routes. It calls typed Tauri commands and displays returned data.

Rust owns local desktop concerns:
- Tauri command surface.
- Local data path initialization.
- Agent service health and request forwarding.
- Future Python process lifecycle.

Python owns agent concerns:
- HTTP API shape for agent operations.
- Mock discovery behavior.
- Future model calls, memory, and workflows.

## Repository Structure

```text
weave/
  README.md
  .editorconfig
  .env.example
  .gitignore
  package.json
  pnpm-workspace.yaml
  Makefile

  apps/
    desktop/
      src/
      src-tauri/
      public/
      package.json
      tsconfig.json
      vite.config.ts

  services/
    agent/
      pyproject.toml
      app/
        __init__.py
        main.py
        api/
        schemas/
      tests/

  data/
    .gitkeep
    profiles/
    sessions/
    drafts/
    memory/
    indexes/
    logs/

  docs/
    architecture/
    decisions/
    superpowers/
      specs/
      plans/
```

`packages/shared-schemas` is intentionally deferred. Phase 0 can keep schemas small and duplicated at the Rust/Python/TypeScript edges until there is real shared complexity.

## Runtime Commands

Use top-level commands as the developer entry point:

```bash
make install
make agent-dev
make desktop-dev
make dev
make test
make check
```

Vite+ should back the JavaScript side:

```bash
vp install
vp run desktop-dev
vp check
vp build
```

Python should remain independently runnable:

```bash
cd services/agent
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e ".[dev]"
uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

Tauri requires Rust. The current machine has Vite+, Node, pnpm, and Python, but no `cargo`; implementation must install Rust before the Tauri step.

## API Boundaries

### Rust Commands

Phase 0 should expose a small command surface:

- `get_app_info`
- `get_runtime_status`
- `agent_health_check`
- `agent_discover`
- `get_local_paths`

`start_agent_service` can be added as a simple wrapper only after the manual service path works. The first stable implementation may require `make agent-dev` in one terminal and `make desktop-dev` in another. This reduces process-management risk while still proving the UI -> Rust -> Python chain.

### Python HTTP API

```text
GET  /health
POST /echo
POST /writing/discover
```

`/health` returns service identity and status.

`/echo` returns the submitted message.

`/writing/discover` accepts a user idea and returns:
- `stage`
- `summary`
- `questions`

The discover implementation should be deterministic mock logic. It should not call a model.

## Data Directories

Phase 0 initializes development data under repository-local `data/`:

```text
data/
  profiles/
  sessions/
  drafts/
  memory/
  indexes/
  logs/
```

It should create a default profile file if missing:

```json
{
  "id": "default",
  "name": "Default",
  "description": "Default writing profile",
  "style_preferences": [],
  "memory_namespace": "default",
  "knowledge_sources": []
}
```

Future production builds can move the root to the platform application data directory, such as `~/Library/Application Support/Weave/` on macOS.

## UI Design

The Phase 0 UI is a utilitarian developer verification screen, not the final writing product.

It should show:
- App name: Weave.
- Runtime status.
- Agent health status.
- Local data root.
- A small input for a writing idea.
- A discover button.
- Returned summary and questions.
- Basic error state when the agent service is unavailable.

Do not add a full chat transcript, session sidebar, profile editor, article editor, or decorative landing page.

## Error Handling

Expected Phase 0 errors should be explicit and recoverable:

- If the Python service is not running, Rust returns a clear unavailable error.
- The UI displays that error near the status/discover area.
- Invalid or empty discover input is rejected before calling Python.
- Python returns structured errors for invalid request bodies through FastAPI/Pydantic.

Process lifecycle errors are deferred unless `start_agent_service` is implemented. If it is implemented, repeated starts must not spawn uncontrolled duplicate processes.

## Testing And Verification

Automated tests:
- Python tests for `/health`.
- Python tests for `/echo`.
- Python tests for `/writing/discover` response shape.
- Frontend test for rendering a discover result if the app test setup is lightweight.

Manual verification:
1. Run the Python service.
2. Confirm `GET /health` returns 200.
3. Run the desktop app.
4. Confirm the UI renders.
5. Confirm the UI can call a Rust command.
6. Confirm the UI can trigger discover through Rust and display summary/questions.
7. Confirm local data directories and default profile are created.

## Documentation Deliverables

Phase 0 implementation must update:

- `README.md`: project overview, prerequisites, install commands, dev commands, verification steps.
- `AGENTS.md`: root navigation for future coding agents, with links to the knowledge base.
- `docs/project-structure.md`: repository layout, ownership boundaries, and startup path.
- `docs/phase-0-runtime-boundaries.md`: UI/Rust/Python/data ownership and cross-runtime rules.
- `docs/.state.md` and `docs/.todo.md`: knowledge-base state and open learning items.
- `docs/architecture/phase-0.md`: runtime boundaries and data flow.
- `docs/decisions/0001-runtime-split.md`: why Weave uses Vite+ + Tauri/Rust + Python/FastAPI.

## Acceptance Criteria

Phase 0 is complete when:

- The repository has the planned skeleton.
- The desktop UI starts and renders the Phase 0 verification screen.
- React can call at least one Rust command.
- Python FastAPI service starts independently.
- Rust can call Python `/health` and `/writing/discover`.
- The UI displays discover results returned through Rust.
- Local data directories and default profile are initialized.
- README, AGENTS.md, knowledge docs, and architecture docs match the implemented commands and structure.
