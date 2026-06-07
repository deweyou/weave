import { app, BrowserWindow, ipcMain, nativeImage, nativeTheme } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { appIpcChannels, type AppThemePreference } from "../shared/desktop-api.js";
import { registerWorkspaceIpc } from "./workspace-ipc.js";
import { getWorkspaceStatus } from "./workspace.js";

const currentFile = fileURLToPath(import.meta.url);
const currentDir = path.dirname(currentFile);
let themePreference: AppThemePreference = "system";

type RendererEntry = "first-run" | "main";

function getRendererHtmlFile(entry: RendererEntry): string {
  return entry === "first-run" ? "first-run.html" : "main.html";
}

function getAppIconPath(theme: "light" | "dark"): string {
  const fileName = theme === "dark" ? "weave-icon-ink-1024.png" : "weave-icon-paper-1024.png";
  return path.join(currentDir, "../../build", fileName);
}

function getResolvedIconTheme(): "light" | "dark" {
  if (themePreference !== "system") {
    return themePreference;
  }

  return nativeTheme.shouldUseDarkColors ? "dark" : "light";
}

function updateDockIcon(): void {
  if (process.platform !== "darwin" || !app.dock) {
    return;
  }

  const icon = nativeImage.createFromPath(getAppIconPath(getResolvedIconTheme()));
  if (!icon.isEmpty()) {
    app.dock.setIcon(icon);
  }
}

function registerAppIpc(): void {
  ipcMain.handle(appIpcChannels.setThemePreference, (_event, nextTheme: AppThemePreference) => {
    themePreference = nextTheme;
    updateDockIcon();
  });
}

function loadRenderer(window: BrowserWindow, entry: RendererEntry): void {
  const htmlFile = getRendererHtmlFile(entry);

  if (app.isPackaged) {
    void window.loadFile(path.join(currentDir, "../renderer", htmlFile));
  } else {
    const rendererUrl = new URL(htmlFile, process.env.WEAVE_RENDERER_URL ?? "http://127.0.0.1:5173");
    void window.loadURL(rendererUrl.toString());
    window.webContents.openDevTools({ mode: "detach" });
  }
}

function createFirstRunWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 440,
    height: 420,
    center: true,
    resizable: false,
    maximizable: false,
    fullscreenable: false,
    frame: false,
    icon: path.join(currentDir, "../../build/weave-icon.png"),
    title: "Weave",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      // The preload bundle is ESM, so it must run outside Electron's sandboxed preload context.
      sandbox: false,
      preload: path.join(currentDir, "../preload/preload.js")
    }
  });

  loadRenderer(window, "first-run");

  return window;
}

function createMainWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1180,
    height: 820,
    minWidth: 900,
    minHeight: 640,
    center: true,
    resizable: true,
    maximizable: true,
    fullscreenable: true,
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 16, y: 18 },
    icon: path.join(currentDir, "../../build/weave-icon.png"),
    title: "Weave",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      // The preload bundle is ESM, so it must run outside Electron's sandboxed preload context.
      sandbox: false,
      preload: path.join(currentDir, "../preload/preload.js")
    }
  });

  loadRenderer(window, "main");

  return window;
}

async function createStartupWindow(): Promise<BrowserWindow> {
  try {
    const status = await getWorkspaceStatus(app.getPath("userData"));
    return status.kind === "ready" ? createMainWindow() : createFirstRunWindow();
  } catch {
    return createFirstRunWindow();
  }
}

void app.whenReady().then(() => {
  updateDockIcon();
  nativeTheme.on("updated", updateDockIcon);
  registerAppIpc();
  registerWorkspaceIpc({
    openMainWindow(sourceWindow) {
      const mainWindow = createMainWindow();
      sourceWindow.close();
      return mainWindow;
    }
  });
  void createStartupWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      void createStartupWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
