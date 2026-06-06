import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import type { WorkspaceStatus } from "../shared/desktop-api";
import { AppShell } from "./app-shell";
import { createStarterWorkspace } from "./starter-workspace";
import "./styles.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("Renderer root element was not found.");
}

const workspace = createStarterWorkspace();
const appInfo = window.weave?.getAppInfo();

const fallbackStatus: WorkspaceStatus = {
  kind: "unconfigured",
  path: null,
  message: "Desktop workspace APIs are unavailable."
};

function RootApp() {
  const [status, setStatus] = useState<WorkspaceStatus | null>(null);
  const [isChoosingWorkspace, setIsChoosingWorkspace] = useState(false);

  useEffect(() => {
    let isMounted = true;

    async function loadStatus() {
      const nextStatus = window.weave ? await window.weave.getWorkspaceStatus() : fallbackStatus;
      if (isMounted) {
        setStatus(nextStatus);
      }
    }

    void loadStatus();

    return () => {
      isMounted = false;
    };
  }, []);

  async function chooseWorkspace() {
    if (!window.weave) {
      setStatus(fallbackStatus);
      return;
    }

    setIsChoosingWorkspace(true);
    try {
      const result = await window.weave.chooseWorkspace();
      setStatus(result.status);
    } finally {
      setIsChoosingWorkspace(false);
    }
  }

  if (!status) {
    return (
      <main className="setup-shell">
        <section className="setup-panel" aria-label="Loading workspace">
          <p className="eyebrow">local-first setup</p>
          <h1>正在加载 Weave</h1>
        </section>
      </main>
    );
  }

  return (
    <AppShell
      workspace={workspace}
      runtimeName={appInfo?.runtime ?? "browser"}
      status={status}
      isChoosingWorkspace={isChoosingWorkspace}
      onChooseWorkspace={chooseWorkspace}
    />
  );
}

createRoot(rootElement).render(
  <React.StrictMode>
    <RootApp />
  </React.StrictMode>
);
