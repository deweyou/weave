import { app, BrowserWindow } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";

const currentFile = fileURLToPath(import.meta.url);
const currentDir = path.dirname(currentFile);

function createMainWindow(): BrowserWindow {
  const window = new BrowserWindow({
    width: 1180,
    height: 820,
    minWidth: 900,
    minHeight: 640,
    title: "Weave",
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      preload: path.join(currentDir, "../preload/preload.js")
    }
  });

  if (app.isPackaged) {
    void window.loadFile(path.join(currentDir, "../renderer/index.html"));
  } else {
    void window.loadURL(process.env.WEAVE_RENDERER_URL ?? "http://127.0.0.1:5173");
    window.webContents.openDevTools({ mode: "detach" });
  }

  return window;
}

void app.whenReady().then(() => {
  createMainWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
