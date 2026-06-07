import type { AppMessages } from "./messages";

interface WorkspaceSettingsPanelProps {
  readonly workspacePath: string;
  readonly labels: AppMessages["shell"];
  readonly isChoosingWorkspace: boolean;
  readonly onChooseWorkspace: () => void;
}

export function WorkspaceSettingsPanel({
  workspacePath,
  labels,
  isChoosingWorkspace,
  onChooseWorkspace
}: WorkspaceSettingsPanelProps) {
  return (
    <section className="settings-strip" aria-label="工作区设置">
      <div>
        <p className="entry-meta">{labels.workspaceLabel}</p>
        <h2>{labels.workspaceTitle}</h2>
        <p className="settings-path">{workspacePath}</p>
      </div>
      <button
        className="secondary-action"
        type="button"
        onClick={onChooseWorkspace}
        disabled={isChoosingWorkspace}
      >
        {isChoosingWorkspace ? labels.choosingFolder : labels.changeFolder}
      </button>
    </section>
  );
}
