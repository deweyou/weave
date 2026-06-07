import { contextBridge, ipcRenderer } from "electron";
import {
  appIpcChannels,
  workspaceIpcChannels,
  type ChooseWorkspaceResult,
  type DesktopApi,
  type SelectWorkspaceFolderResult,
  type WorkspaceStatus,
} from "../shared/desktop-api.js";

function invokeWorkspaceChannel<Result>(channel: string, ...args: unknown[]): Promise<Result> {
  return ipcRenderer.invoke(channel, ...args) as Promise<Result>;
}

const desktopApi: DesktopApi = {
  getAppInfo: () => ({
    name: "Weave",
    runtime: "electron",
  }),
  getWorkspaceStatus: (): Promise<WorkspaceStatus> =>
    invokeWorkspaceChannel<WorkspaceStatus>(workspaceIpcChannels.getStatus),
  chooseWorkspace: (language): Promise<ChooseWorkspaceResult> =>
    invokeWorkspaceChannel<ChooseWorkspaceResult>(workspaceIpcChannels.choose, language),
  selectWorkspaceFolder: (language): Promise<SelectWorkspaceFolderResult> =>
    invokeWorkspaceChannel<SelectWorkspaceFolderResult>(workspaceIpcChannels.select, language),
  initializeWorkspace: (workspacePath): Promise<WorkspaceStatus> =>
    invokeWorkspaceChannel<WorkspaceStatus>(workspaceIpcChannels.initialize, workspacePath),
  setThemePreference: (theme): Promise<void> => invokeWorkspaceChannel<void>(appIpcChannels.setThemePreference, theme),
  quitApp: (): Promise<void> => invokeWorkspaceChannel<void>(appIpcChannels.quit),
};

contextBridge.exposeInMainWorld("weave", desktopApi);
