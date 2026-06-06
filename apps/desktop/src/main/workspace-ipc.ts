import { app, BrowserWindow, dialog, ipcMain, type OpenDialogOptions } from "electron";
import {
  workspaceIpcChannels,
  type ChooseWorkspaceResult,
  type WorkspaceStatus,
} from "../shared/desktop-api.js";
import { getWorkspaceStatus, setWorkspacePath } from "./workspace.js";

export function internalWorkspaceConfigReadErrorStatus(): WorkspaceStatus {
  return {
    kind: "unconfigured",
    path: null,
    message: "Workspace configuration could not be read. Choose a local folder to continue.",
  };
}

async function getRecoverableWorkspaceStatus(appDataPath: string): Promise<WorkspaceStatus> {
  try {
    return await getWorkspaceStatus(appDataPath);
  } catch {
    return internalWorkspaceConfigReadErrorStatus();
  }
}

export function internalWorkspaceInitializationErrorStatus(workspacePath: string): WorkspaceStatus {
  return {
    kind: "missing",
    path: workspacePath,
    message: "Weave could not initialize that folder. Choose a writable local folder.",
  };
}

export function registerWorkspaceIpc(): void {
  ipcMain.handle(workspaceIpcChannels.getStatus, async () => {
    return getRecoverableWorkspaceStatus(app.getPath("userData"));
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
        status: await getRecoverableWorkspaceStatus(app.getPath("userData")),
      };
    }

    let status: WorkspaceStatus;

    try {
      status = await setWorkspacePath(app.getPath("userData"), workspacePath);
    } catch {
      status = internalWorkspaceInitializationErrorStatus(workspacePath);
    }

    return {
      canceled: false,
      status,
    };
  });
}
