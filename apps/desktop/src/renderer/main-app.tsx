import { useEffect, useRef, useState } from "react";
import type { WorkspaceStatus } from "../shared/desktop-api";
import type { AppLanguage } from "./language";
import { readStoredLanguage } from "./language";
import { messages } from "./messages";
import { renderRoot } from "./render-root";
import { createStarterWorkspace } from "./starter-workspace";
import { applyTheme, readStoredTheme, syncSystemIconTheme } from "./theme";
import { WorkspaceHomeView } from "./workspace-home-view";
import "./design-theme.css";
import "./styles.css";

const browserPreviewStatus: WorkspaceStatus = {
  kind: "ready",
  path: "Browser Preview",
  message: null,
};

const workspaceStatusError: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: "Weave could not load workspace status.",
};

const folderPickerError: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: "Weave could not open the folder picker. Try again.",
};

function MainApp() {
  const isMountedRef = useRef(true);
  const [status, setStatus] = useState<WorkspaceStatus | null>(null);
  const [isChoosingWorkspace, setIsChoosingWorkspace] = useState(false);
  const language: AppLanguage = readStoredLanguage() ?? "zh-CN";
  const labels = messages[language];
  const workspace = createStarterWorkspace();
  const appInfo = window.weave?.getAppInfo();

  useEffect(() => {
    isMountedRef.current = true;
    const theme = readStoredTheme();
    applyTheme(theme);
    syncSystemIconTheme(theme);

    async function loadStatus() {
      try {
        const nextStatus = window.weave ? await window.weave.getWorkspaceStatus() : browserPreviewStatus;
        if (isMountedRef.current) {
          setStatus(nextStatus);
        }
      } catch {
        if (isMountedRef.current) {
          setStatus(workspaceStatusError);
        }
      }
    }

    void loadStatus();

    return () => {
      isMountedRef.current = false;
    };
  }, []);

  async function chooseWorkspace() {
    if (!window.weave) {
      return;
    }

    setIsChoosingWorkspace(true);
    try {
      const result = await window.weave.chooseWorkspace(language);
      if (isMountedRef.current) {
        setStatus(result.status);
      }
    } catch {
      if (isMountedRef.current) {
        setStatus(folderPickerError);
      }
    } finally {
      if (isMountedRef.current) {
        setIsChoosingWorkspace(false);
      }
    }
  }

  if (!status) {
    return (
      <main className="status-shell">
        <header className="workspace-header">
          <p className="eyebrow">{labels.loading.eyebrow}</p>
          <h1>{labels.loading.title}</h1>
        </header>
      </main>
    );
  }

  if (status.kind !== "ready") {
    return (
      <main className="status-shell">
        <header className="workspace-header">
          <p className="eyebrow">Weave</p>
          <h1>{status.message ?? labels.firstRun.missingTitle}</h1>
        </header>
        <button
          className="secondary-action"
          type="button"
          onClick={chooseWorkspace}
          disabled={isChoosingWorkspace}
        >
          {isChoosingWorkspace ? labels.shell.choosingFolder : labels.shell.changeFolder}
        </button>
      </main>
    );
  }

  return (
    <WorkspaceHomeView
      workspace={workspace}
      runtimeName={appInfo?.runtime ?? "browser"}
      status={status}
      labels={labels.shell}
      isChoosingWorkspace={isChoosingWorkspace}
      onChooseWorkspace={chooseWorkspace}
    />
  );
}

renderRoot(<MainApp />);
