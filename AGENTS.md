# Weave

请跟我中文对话。

Weave is a local-first writing, memo, and todo app. The repository is a single
Vite+ pnpm workspace. The first runnable target is an Electron desktop app;
future iOS work should stay in this repository, but no mobile directory should be
created before implementation starts.

## Knowledge Base

| Document | What it covers |
|----------|----------------|
| [docs/project-structure.md](docs/project-structure.md) | Current structure, startup path, and ownership map |
| [docs/repository-rules.md](docs/repository-rules.md) | Rules for packages, mobile, and future extraction |
| [DESIGN.md](DESIGN.md) | Durable UI design contract |

## Current Architecture

- `apps/desktop` owns Electron main/preload code and the React renderer.
- Keep all application code in `apps/desktop` until a real second consumer exists.
- Do not create `packages/*` preemptively. Extract a package only after repeated
  code or a second app proves the boundary.

## Commands

- Install dependencies with `vp install`.
- Run the desktop app with `vp run desktop:dev`.
- Run baseline checks with `vp run check`.

## Development Workflow

- Use DDev as the default workflow for non-trivial development tasks.
- Keep only the `ddev` entry skill in the repository. DDev loads product,
  UI, coding, delivery, and repository-memory modules from the global Dewey
  asset cache when they are needed.
- Use `$DDev <task>` for implementation, `$DDev inspect <question>` for
  investigation, `$DDev brainstorm <topic>` for exploration, and `$DDev ship`
  only when delivery is explicitly requested.
- Keep DDev session state under `~/.deweyou/dev/`; do not commit repository-local
  `.deweyou/dev/` state.

## Constraints

- Keep this as one repository.
- Do not over-design iOS before the stack is chosen.
- Do not create `apps/mobile` until iOS work actually starts.
- Do not create shared packages until extraction has a concrete consumer.
- Prefer explicit domain names over generic utility modules.

## Task Routing

- If changing repository layout, read [docs/project-structure.md](docs/project-structure.md) first.
- If adding `packages/*`, `apps/mobile`, sync, or persistence boundaries, read [docs/repository-rules.md](docs/repository-rules.md) first.
- If making UI, UX, or visual design changes, read [DESIGN.md](DESIGN.md) first.
