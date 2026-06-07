import type { AppMessages } from "./messages";

interface WorkspaceSidebarProps {
  readonly workspacePath: string;
  readonly labels: AppMessages["shell"];
  readonly isChoosingWorkspace: boolean;
  readonly onChooseWorkspace: () => void;
}

export function WorkspaceSidebar({
  workspacePath,
  labels,
  isChoosingWorkspace,
  onChooseWorkspace
}: WorkspaceSidebarProps) {
  const primaryNavigation = [
    { id: "home", label: labels.home, isCurrent: true },
    { id: "todos", label: labels.todos, isCurrent: false },
    { id: "memos", label: labels.memos, isCurrent: false },
    { id: "documents", label: labels.documents, isCurrent: false },
    { id: "chat", label: labels.chat, isCurrent: false },
  ] as const;

  return (
    <aside className="workspace-sidebar">
      <div className="sidebar-brand">
        <p className="sidebar-kicker">Weave</p>
        <p className="sidebar-workspace-path">{workspacePath}</p>
      </div>

      <nav className="sidebar-nav" aria-label="Weave navigation">
        {primaryNavigation.map((destination) => (
          <button
            className="sidebar-nav-button"
            type="button"
            key={destination.id}
            aria-current={destination.isCurrent ? "page" : undefined}
          >
            {destination.label}
          </button>
        ))}
      </nav>

      <div className="sidebar-footer">
        <button className="sidebar-nav-button" type="button">
          {labels.settings}
        </button>
        <section className="sidebar-workspace" aria-label={labels.workspaceTitle}>
          <p className="sidebar-section-label">{labels.workspaceLabel}</p>
          <p className="sidebar-section-title">{labels.workspaceTitle}</p>
          <p className="sidebar-workspace-path">{workspacePath}</p>
          <button
            className="secondary-action sidebar-folder-action"
            type="button"
            onClick={onChooseWorkspace}
            disabled={isChoosingWorkspace}
          >
            {isChoosingWorkspace ? labels.choosingFolder : labels.changeFolder}
          </button>
        </section>
      </div>
    </aside>
  );
}
