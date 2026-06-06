import type { WorkspaceStatus } from "../shared/desktop-api";
import type { WorkspaceSummary } from "./starter-workspace";

export interface AppShellProps {
  readonly workspace: WorkspaceSummary;
  readonly runtimeName: string;
  readonly status: WorkspaceStatus;
  readonly isChoosingWorkspace: boolean;
  readonly onChooseWorkspace: () => void;
}

function WorkspaceSetup({
  status,
  isChoosingWorkspace,
  onChooseWorkspace
}: Pick<AppShellProps, "status" | "isChoosingWorkspace" | "onChooseWorkspace">) {
  const isMissing = status.kind === "missing";

  return (
    <main className="setup-shell">
      <section className="setup-panel" aria-labelledby="setup-title">
        <p className="eyebrow">local-first setup</p>
        <h1 id="setup-title">{isMissing ? "重新选择 Weave 文件夹" : "选择你的 Weave 文件夹"}</h1>
        <p className="setup-copy">
          Weave 会在这个文件夹里创建 <code>.weave/</code>, <code>notes/</code>,{" "}
          <code>memos/</code>, 和 <code>todos/</code>。这个文件夹就是你的本地资料根目录。
        </p>
        {status.message ? <p className="setup-message">{status.message}</p> : null}
        {status.path ? (
          <p className="setup-path">
            当前路径：<span className="workspace-path-inline">{status.path}</span>
          </p>
        ) : null}
        <button
          className="primary-action"
          type="button"
          onClick={onChooseWorkspace}
          disabled={isChoosingWorkspace}
        >
          {isChoosingWorkspace ? "正在打开..." : "选择文件夹"}
        </button>
      </section>
    </main>
  );
}

export function AppShell({
  workspace,
  runtimeName,
  status,
  isChoosingWorkspace,
  onChooseWorkspace
}: AppShellProps) {
  if (status.kind !== "ready") {
    return (
      <WorkspaceSetup
        status={status}
        isChoosingWorkspace={isChoosingWorkspace}
        onChooseWorkspace={onChooseWorkspace}
      />
    );
  }

  return (
    <main className="app-shell">
      <header className="hero">
        <p className="eyebrow">
          {runtimeName} / <span className="workspace-path-inline">{status.path}</span>
        </p>
        <h1>Weave</h1>
      </header>

      <section className="entry-grid" aria-label={workspace.name}>
        {workspace.entries.map((entry) => (
          <article className="entry-card" key={entry.id}>
            <p className="entry-meta">
              {entry.kind.toUpperCase()} · {entry.updatedAt}
            </p>
            <h2>{entry.title}</h2>
            <p>{entry.summary}</p>
          </article>
        ))}
      </section>

      <section className="settings-strip" aria-label="Workspace settings">
        <div>
          <p className="entry-meta">WORKSPACE</p>
          <p className="settings-path">{status.path}</p>
        </div>
        <button
          className="secondary-action"
          type="button"
          onClick={onChooseWorkspace}
          disabled={isChoosingWorkspace}
        >
          {isChoosingWorkspace ? "正在打开..." : "更改文件夹"}
        </button>
      </section>
    </main>
  );
}
