import type { WorkspaceStatus } from "../shared/desktop-api";
import type { AppMessages } from "./messages";
import type { WorkspaceSummary } from "./starter-workspace";
import { WorkspaceSidebar } from "./workspace-sidebar";

interface WorkspaceHomeViewProps {
  readonly workspace: WorkspaceSummary;
  readonly runtimeName: string;
  readonly status: Extract<WorkspaceStatus, { kind: "ready" }>;
  readonly labels: AppMessages["shell"];
  readonly isChoosingWorkspace: boolean;
  readonly onChooseWorkspace: () => void;
}

export function WorkspaceHomeView({
  workspace,
  runtimeName,
  status,
  labels,
  isChoosingWorkspace,
  onChooseWorkspace
}: WorkspaceHomeViewProps) {
  return (
    <div className="app-shell">
      <WorkspaceSidebar
        workspacePath={status.path}
        labels={labels}
        isChoosingWorkspace={isChoosingWorkspace}
        onChooseWorkspace={onChooseWorkspace}
      />

      <main className="workspace-main">
        <header className="workspace-header">
          <div>
            <p className="eyebrow">
              {runtimeName} / <span className="workspace-path-inline">{status.path}</span>
            </p>
            <h1>Weave</h1>
          </div>
          <p className="workspace-summary">{labels.workspaceReady}</p>
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
      </main>
    </div>
  );
}
