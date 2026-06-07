import { useState } from "react";
import type { WorkspaceStatus } from "../shared/desktop-api";
import weaveMarkUrl from "./assets/weave-mark-1024.png";
import weaveMarkReversedUrl from "./assets/weave-mark-reversed-1024.png";
import type { AppLanguage } from "./language";
import type { AppMessages } from "./messages";
import type { AppTheme } from "./theme";

interface FirstRunViewProps {
  readonly status: WorkspaceStatus;
  readonly language: AppLanguage | null;
  readonly theme: AppTheme;
  readonly labels: AppMessages["firstRun"];
  readonly isSelectingWorkspace: boolean;
  readonly isCompleting: boolean;
  readonly selectedWorkspacePath: string | null;
  readonly previewNotice: string | null;
  readonly onChooseLanguage: (language: AppLanguage) => void;
  readonly onChooseTheme: (theme: AppTheme) => void;
  readonly onSelectWorkspace: () => void;
  readonly onComplete: () => void;
  readonly onCancel: () => void;
}

export function FirstRunView({
  status,
  language,
  theme,
  labels,
  isSelectingWorkspace,
  isCompleting,
  selectedWorkspacePath,
  previewNotice,
  onChooseLanguage,
  onChooseTheme,
  onSelectWorkspace,
  onComplete,
  onCancel,
}: FirstRunViewProps) {
  const isMissing = status.kind === "missing";
  const [selectedLanguage, setSelectedLanguage] = useState<AppLanguage>(language ?? "zh-CN");
  const [selectedTheme, setSelectedTheme] = useState<AppTheme>(theme);
  const displayPath = selectedWorkspacePath ?? (status.kind === "missing" ? status.path : null);
  const canComplete = selectedWorkspacePath !== null && !isSelectingWorkspace && !isCompleting;

  function chooseLanguage(nextLanguage: AppLanguage) {
    setSelectedLanguage(nextLanguage);
    onChooseLanguage(nextLanguage);
  }

  function chooseTheme(nextTheme: AppTheme) {
    setSelectedTheme(nextTheme);
    onChooseTheme(nextTheme);
  }

  return (
    <main className="first-run-shell">
      <section className="first-run-panel" aria-label="Weave">
        <header className="setup-brand">
          <picture>
            {selectedTheme === "dark" ? <source srcSet={weaveMarkReversedUrl} /> : null}
            {selectedTheme === "system" ? (
              <source srcSet={weaveMarkReversedUrl} media="(prefers-color-scheme: dark)" />
            ) : null}
            <img className="setup-logo" src={weaveMarkUrl} alt="" aria-hidden="true" />
          </picture>
        </header>

        <div className="setup-content">
          <div className="setup-field">
            <p className="setup-label">{labels.languageSummary}</p>
            <div className="language-options" role="group" aria-label={labels.languageSummary}>
              <button
                className="language-option"
                type="button"
                aria-pressed={selectedLanguage === "zh-CN"}
                onClick={() => chooseLanguage("zh-CN")}
              >
                <span>{labels.chinese}</span>
              </button>
              <button
                className="language-option"
                type="button"
                aria-pressed={selectedLanguage === "en-US"}
                onClick={() => chooseLanguage("en-US")}
              >
                <span>{labels.english}</span>
              </button>
            </div>
          </div>

          <div className="setup-field">
            <p className="setup-label">{labels.themeSummary}</p>
            <div className="theme-options" role="group" aria-label={labels.themeSummary}>
              <button
                className="theme-option"
                type="button"
                aria-pressed={selectedTheme === "system"}
                onClick={() => chooseTheme("system")}
              >
                <span>{labels.themeSystem}</span>
              </button>
              <button
                className="theme-option"
                type="button"
                aria-pressed={selectedTheme === "light"}
                onClick={() => chooseTheme("light")}
              >
                <span>{labels.themeLight}</span>
              </button>
              <button
                className="theme-option"
                type="button"
                aria-pressed={selectedTheme === "dark"}
                onClick={() => chooseTheme("dark")}
              >
                <span>{labels.themeDark}</span>
              </button>
            </div>
          </div>

          <div className="setup-field">
            <p className="setup-label">{isMissing ? labels.missingTitle : labels.workspaceSummary}</p>
            {status.kind === "missing" ? <p className="setup-message">{labels.missingMessage}</p> : null}
            {previewNotice ? <p className="setup-message">{previewNotice}</p> : null}
            <button
              className="folder-field"
              type="button"
              onClick={onSelectWorkspace}
              disabled={isSelectingWorkspace || isCompleting}
            >
              {isSelectingWorkspace ? labels.choosingFolder : null}
              {!isSelectingWorkspace && displayPath ? (
                <span className="workspace-path-inline">{displayPath}</span>
              ) : null}
              {!isSelectingWorkspace && !displayPath ? labels.noFolderSelected : null}
            </button>
          </div>
        </div>

        <footer className="setup-actions">
          <button
            className="setup-text-button"
            type="button"
            onClick={onCancel}
            disabled={isCompleting}
          >
            {labels.cancel}
          </button>
          <button
            className="setup-text-button"
            type="button"
            onClick={onComplete}
            disabled={!canComplete}
          >
            {isCompleting ? labels.choosingFolder : labels.finish}
          </button>
        </footer>
      </section>
    </main>
  );
}
