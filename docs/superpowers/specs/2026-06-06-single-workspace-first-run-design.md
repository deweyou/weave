# Single Workspace First-run Setup Design

## Context

Weave is a local-first desktop product. Before writing, memo, todo, indexing, or agent workflows can behave predictably, the app needs one user-owned local root folder.

The current product direction is intentionally narrower than Obsidian's multi-vault model:

- Weave manages one active workspace.
- First launch binds that workspace to a local folder.
- Later path changes happen from Settings.
- Workspace switching, recent workspace lists, and multi-workspace management are out of scope.

## Decision

Build a first-run setup page, not a marketing landing page.

When no workspace path has been configured, Weave shows a setup screen that asks the user to choose or create a local workspace folder. After the folder is accepted, Weave initializes a fixed directory structure in that folder and stores the selected path in desktop-local app configuration. Future launches open the configured workspace directly.

## Workspace Structure

Weave initializes this structure inside the selected folder:

```text
MyWeave/
  .weave/
    config.json
    indexes/
    logs/
  notes/
  memos/
  todos/
```

Directory ownership:

- `.weave/` stores Weave internal metadata, settings tied to the workspace, logs, and future index data.
- `notes/` stores long-form writing and note-like content.
- `memos/` stores lightweight memo content.
- `todos/` stores task-oriented content.

The visible content folders are part of the user's local-first data. They should remain understandable, backup-friendly, and sync-friendly. `.weave/` is internal and should not be treated as a normal editing surface.

## First-run Flow

1. App starts.
2. Desktop main process checks for a configured workspace path in app-local configuration.
3. If no path exists, renderer shows the first-run setup page.
4. User chooses an existing folder or creates a new folder through the desktop folder picker.
5. Desktop main process validates the folder and initializes the workspace structure.
6. Desktop main process persists the selected workspace path.
7. Renderer enters the main app shell for that workspace.

## Normal Startup Flow

1. App starts.
2. Desktop main process reads the configured workspace path.
3. If the path exists and is accessible, renderer opens the main app shell.
4. If the path is missing or inaccessible, renderer shows a recoverable setup/error state asking the user to choose a valid folder.

## Settings Flow

Settings should expose the current workspace path and allow the user to change it.

Changing the path should reuse the same folder validation and initialization behavior as first-run setup. Short-term behavior can simply switch to the new path after confirmation. Migration of existing content between workspaces is out of scope.

## Desktop Boundary

The renderer must not read or write arbitrary filesystem paths directly.

Electron main owns:

- Opening the native folder picker.
- Reading and writing desktop-local app configuration.
- Validating workspace paths.
- Creating the workspace directory structure.
- Returning workspace status to the renderer through the preload bridge.

The renderer owns:

- First-run setup UI.
- Normal app shell UI.
- Settings UI for displaying and changing the workspace path.
- User-facing error and recovery states.

## iCloud Scope

Users may choose a folder inside iCloud Drive on macOS, but Weave should treat it as a normal local filesystem path for this feature.

This feature does not promise iOS/iCloud sync support. Future iOS support needs a separate path and container design because iOS access rules differ from macOS. In particular, apps like Obsidian rely on a mobile-accessible iCloud app folder convention for cross-device iCloud use.

## Out of Scope

- Multiple workspaces.
- Recent workspace lists.
- Workspace switcher UI.
- Content migration between workspace paths.
- iOS sync behavior.
- iCloud app container setup.
- Cloud sync conflict handling.
- Final note, memo, or todo file formats.

## Acceptance Criteria

- A fresh install with no workspace path shows first-run setup instead of the main app shell.
- The user can choose or create one local folder as the Weave workspace.
- Weave initializes `.weave/`, `.weave/indexes/`, `.weave/logs/`, `notes/`, `memos/`, and `todos/`.
- The selected path persists across app restarts.
- A subsequent launch with an accessible configured path goes straight to the main app shell.
- If the configured path is missing or inaccessible, the app shows a recovery state rather than failing silently.
- Settings can display the current workspace path and trigger choosing a replacement path.

## Verification

- Unit-test the workspace path validation and initialization logic.
- Typecheck the preload and renderer API boundary.
- Manually verify first-run setup, restart behavior, inaccessible-path recovery, and Settings path change in Electron.
