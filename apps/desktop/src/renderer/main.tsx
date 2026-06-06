import React from "react";
import { createRoot } from "react-dom/client";
import { AppShell } from "./app-shell";
import { createStarterWorkspace } from "./starter-workspace";
import "./styles.css";

const rootElement = document.getElementById("root");

if (!rootElement) {
  throw new Error("Renderer root element was not found.");
}

const workspace = createStarterWorkspace();
const appInfo = window.weave?.getAppInfo();

createRoot(rootElement).render(
  <React.StrictMode>
    <AppShell workspace={workspace} runtimeName={appInfo?.runtime ?? "browser"} />
  </React.StrictMode>
);
