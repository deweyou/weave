import { app, BrowserWindow, dialog, ipcMain, type OpenDialogOptions } from "electron";
import {
  appIpcChannels,
  workspaceIpcChannels,
  type ChooseWorkspaceResult,
  type SelectWorkspaceFolderResult,
  type WorkspaceDialogLanguage,
  type WorkspaceStatus,
} from "../shared/desktop-api.js";
import { getWorkspaceStatus, setWorkspacePath } from "./workspace.js";

interface WorkspaceIpcOptions {
  readonly openMainWindow: (sourceWindow: BrowserWindow) => BrowserWindow;
}

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

function getWorkspaceDialogLabels(language: WorkspaceDialogLanguage): Pick<OpenDialogOptions, "buttonLabel" | "message"> {
  if (language === "en-US") {
    return {
      buttonLabel: "Use this folder",
      message: "Choose your Weave workspace folder",
    };
  }

  return {
    buttonLabel: "使用此文件夹",
    message: "选择 Weave 本地文件夹",
  };
}

async function showWorkspaceFolderDialog(
  parentWindow: BrowserWindow | undefined,
  language: WorkspaceDialogLanguage,
): Promise<SelectWorkspaceFolderResult> {
  const dialogLabels = getWorkspaceDialogLabels(language);
  const dialogOptions: OpenDialogOptions = {
    buttonLabel: dialogLabels.buttonLabel,
    message: dialogLabels.message,
    properties: ["openDirectory", "createDirectory"],
  };
  const result =
    parentWindow === undefined
      ? await dialog.showOpenDialog(dialogOptions)
      : await dialog.showOpenDialog(parentWindow, dialogOptions);

  const workspacePath = result.filePaths[0];

  return {
    canceled: result.canceled || workspacePath === undefined,
    path: workspacePath ?? null,
  };
}

export function registerWorkspaceIpc(options: WorkspaceIpcOptions): void {
  ipcMain.handle(workspaceIpcChannels.getStatus, async () => {
    return getRecoverableWorkspaceStatus(app.getPath("userData"));
  });

  ipcMain.handle(workspaceIpcChannels.choose, async (event, language: WorkspaceDialogLanguage): Promise<ChooseWorkspaceResult> => {
    const parentWindow = BrowserWindow.fromWebContents(event.sender) ?? undefined;
    const result = await showWorkspaceFolderDialog(parentWindow, language);
    const workspacePath = result.path;

    if (result.canceled || workspacePath === null) {
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

  ipcMain.handle(
    workspaceIpcChannels.select,
    async (event, language: WorkspaceDialogLanguage): Promise<SelectWorkspaceFolderResult> => {
      const parentWindow = BrowserWindow.fromWebContents(event.sender) ?? undefined;
      return showWorkspaceFolderDialog(parentWindow, language);
    },
  );

  ipcMain.handle(workspaceIpcChannels.initialize, async (event, workspacePath: string): Promise<WorkspaceStatus> => {
    try {
      const status = await setWorkspacePath(app.getPath("userData"), workspacePath);
      const sourceWindow = BrowserWindow.fromWebContents(event.sender);

      if (status.kind === "ready" && sourceWindow) {
        setTimeout(() => {
          options.openMainWindow(sourceWindow);
        }, 0);
      }

      return status;
    } catch {
      return internalWorkspaceInitializationErrorStatus(workspacePath);
    }
  });

  ipcMain.handle(appIpcChannels.quit, () => {
    app.quit();
  });
}
