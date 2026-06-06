import { contextBridge } from "electron";
import type { DesktopApi } from "../shared/desktop-api.js";

const desktopApi: DesktopApi = {
  getAppInfo: () => ({
    name: "Weave",
    runtime: "electron"
  })
};

contextBridge.exposeInMainWorld("weave", desktopApi);
