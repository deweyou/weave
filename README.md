# Weave

Weave is a local-first writing, memo, and todo app.

The current repository is initialized as a Vite+ pnpm workspace with an Electron
desktop app. iOS support is planned in the same repository, but the directory
should be created only when implementation starts.

## Commands

```bash
vp install
vp run desktop:dev
vp run check
```

## Structure

- `apps/desktop` - Electron main process, preload bridge, and Vite React renderer.
- `docs` - repository memory, architecture rules, and decisions.
