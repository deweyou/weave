import { app, BrowserWindow, dialog, ipcMain, type OpenDialogOptions } from "electron";
import { workspaceIpcChannels, type ChooseWorkspaceResult } from "../shared/desktop-api.js";
import { getWorkspaceStatus, setWorkspacePath } from "./workspace.js";

export function registerWorkspaceIpc(): void {
  ipcMain.handle(workspaceIpcChannels.getStatus, async () => {
    return getWorkspaceStatus(app.getPath("userData"));
  });

  ipcMain.handle(workspaceIpcChannels.choose, async (event): Promise<ChooseWorkspaceResult> => {
    const parentWindow = BrowserWindow.fromWebContents(event.sender) ?? undefined;
    const dialogOptions: OpenDialogOptions = {
      buttonLabel: "Use this folder",
      message: "Choose your Weave workspace folder",
      properties: ["openDirectory", "createDirectory"],
    };
    const result =
      parentWindow === undefined
        ? await dialog.showOpenDialog(dialogOptions)
        : await dialog.showOpenDialog(parentWindow, dialogOptions);

    const workspacePath = result.filePaths[0];

    if (result.canceled || workspacePath === undefined) {
      return {
        canceled: true,
        status: await getWorkspaceStatus(app.getPath("userData")),
      };
    }

    return {
      canceled: false,
      status: await setWorkspacePath(app.getPath("userData"), workspacePath),
    };
  });
}
