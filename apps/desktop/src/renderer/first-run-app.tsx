import { useEffect, useRef, useState } from "react";
import type { WorkspaceStatus } from "../shared/desktop-api";
import { FirstRunView } from "./first-run-view";
import type { AppLanguage } from "./language";
import { readStoredLanguage, storeLanguage } from "./language";
import { messages } from "./messages";
import { renderRoot } from "./render-root";
import type { AppTheme } from "./theme";
import { applyTheme, readStoredTheme, storeTheme, syncSystemIconTheme } from "./theme";
import "./design-theme.css";
import "./styles.css";

const browserPreviewNotice = "当前浏览器预览不能打开系统文件夹选择器，请在桌面应用窗口中完成设置。";

const fallbackStatus: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: null,
};

const workspaceStatusError: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: "Weave could not load workspace status. Choose a local folder to continue.",
};

const folderPickerError: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: "Weave could not open the folder picker. Try again.",
};

function FirstRunApp() {
  const isMountedRef = useRef(true);
  const [status, setStatus] = useState<WorkspaceStatus | null>(null);
  const [language, setLanguage] = useState<AppLanguage | null>(() => readStoredLanguage());
  const [theme, setTheme] = useState<AppTheme>(() => readStoredTheme());
  const [selectedWorkspacePath, setSelectedWorkspacePath] = useState<string | null>(null);
  const [previewNotice, setPreviewNotice] = useState<string | null>(window.weave ? null : browserPreviewNotice);
  const [isSelectingWorkspace, setIsSelectingWorkspace] = useState(false);
  const [isCompleting, setIsCompleting] = useState(false);
  const labels = messages[language ?? "zh-CN"];

  useEffect(() => {
    isMountedRef.current = true;

    async function loadStatus() {
      try {
        const nextStatus = window.weave ? await window.weave.getWorkspaceStatus() : fallbackStatus;
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

  useEffect(() => {
    applyTheme(theme);
    syncSystemIconTheme(theme);
  }, [theme]);

  function chooseLanguage(nextLanguage: AppLanguage) {
    storeLanguage(nextLanguage);
    setLanguage(nextLanguage);
  }

  function chooseTheme(nextTheme: AppTheme) {
    storeTheme(nextTheme);
    setTheme(nextTheme);
  }

  async function selectWorkspace() {
    if (!window.weave) {
      if (isMountedRef.current) {
        setStatus(fallbackStatus);
        setPreviewNotice(browserPreviewNotice);
      }
      return;
    }

    setIsSelectingWorkspace(true);
    try {
      const result = await window.weave.selectWorkspaceFolder(language ?? "zh-CN");
      if (isMountedRef.current && !result.canceled) {
        setSelectedWorkspacePath(result.path);
      }
    } catch {
      if (isMountedRef.current) {
        setStatus(folderPickerError);
      }
    } finally {
      if (isMountedRef.current) {
        setIsSelectingWorkspace(false);
      }
    }
  }

  async function completeFirstRun() {
    if (!window.weave || selectedWorkspacePath === null) {
      return;
    }

    setIsCompleting(true);
    try {
      const nextStatus = await window.weave.initializeWorkspace(selectedWorkspacePath);
      if (isMountedRef.current) {
        setStatus(nextStatus);
      }
    } catch {
      if (isMountedRef.current) {
        setStatus(folderPickerError);
      }
    } finally {
      if (isMountedRef.current) {
        setIsCompleting(false);
      }
    }
  }

  function cancelFirstRun() {
    if (window.weave) {
      void window.weave.quitApp();
      return;
    }

    window.close();
  }

  if (!status) {
    return (
      <main className="first-run-shell">
        <section className="first-run-panel" aria-label="Loading workspace">
          <p className="eyebrow">{labels.loading.eyebrow}</p>
          <h1>{labels.loading.title}</h1>
        </section>
      </main>
    );
  }

  return (
    <FirstRunView
      status={status}
      language={language}
      theme={theme}
      labels={labels.firstRun}
      isSelectingWorkspace={isSelectingWorkspace}
      isCompleting={isCompleting}
      selectedWorkspacePath={selectedWorkspacePath}
      previewNotice={previewNotice}
      onChooseLanguage={chooseLanguage}
      onChooseTheme={chooseTheme}
      onSelectWorkspace={selectWorkspace}
      onComplete={completeFirstRun}
      onCancel={cancelFirstRun}
    />
  );
}

renderRoot(<FirstRunApp />);
