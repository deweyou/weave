import { contextBridge, ipcRenderer } from "electron";
import { workspaceIpcChannels, type DesktopApi } from "../shared/desktop-api.js";

const desktopApi: DesktopApi = {
  getAppInfo: () => ({
    name: "Weave",
    runtime: "electron",
  }),
  getWorkspaceStatus: () => ipcRenderer.invoke(workspaceIpcChannels.getStatus),
  chooseWorkspace: () => ipcRenderer.invoke(workspaceIpcChannels.choose),
};

contextBridge.exposeInMainWorld("weave", desktopApi);
