import { contextBridge, ipcRenderer } from "electron";
import {
  workspaceIpcChannels,
  type ChooseWorkspaceResult,
  type DesktopApi,
  type WorkspaceStatus,
} from "../shared/desktop-api.js";

function invokeWorkspaceChannel<Result>(channel: string): Promise<Result> {
  return ipcRenderer.invoke(channel) as Promise<Result>;
}

const desktopApi: DesktopApi = {
  getAppInfo: () => ({
    name: "Weave",
    runtime: "electron",
  }),
  getWorkspaceStatus: (): Promise<WorkspaceStatus> =>
    invokeWorkspaceChannel<WorkspaceStatus>(workspaceIpcChannels.getStatus),
  chooseWorkspace: (): Promise<ChooseWorkspaceResult> =>
    invokeWorkspaceChannel<ChooseWorkspaceResult>(workspaceIpcChannels.choose),
};

contextBridge.exposeInMainWorld("weave", desktopApi);
