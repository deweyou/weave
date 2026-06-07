export type WorkspaceStatusKind = "unconfigured" | "ready" | "missing";

export interface AppInfo {
  readonly name: string;
  readonly runtime: string;
}

export interface UnconfiguredWorkspaceStatus {
  readonly kind: "unconfigured";
  readonly path: null;
  readonly message: string | null;
}

export interface ReadyWorkspaceStatus {
  readonly kind: "ready";
  readonly path: string;
  readonly message: null;
}

export interface MissingWorkspaceStatus {
  readonly kind: "missing";
  readonly path: string | null;
  readonly message: string | null;
}

export type WorkspaceStatus =
  | UnconfiguredWorkspaceStatus
  | ReadyWorkspaceStatus
  | MissingWorkspaceStatus;

export interface ChooseWorkspaceResult {
  readonly canceled: boolean;
  readonly status: WorkspaceStatus;
}

export interface SelectWorkspaceFolderResult {
  readonly canceled: boolean;
  readonly path: string | null;
}

export type WorkspaceDialogLanguage = "zh-CN" | "en-US";
export type AppThemePreference = "light" | "dark" | "system";

export const workspaceIpcChannels = {
  getStatus: "workspace:getStatus",
  choose: "workspace:choose",
  select: "workspace:select",
  initialize: "workspace:initialize",
} as const;

export const appIpcChannels = {
  quit: "app:quit",
  setThemePreference: "app:setThemePreference",
} as const;

export interface DesktopApi {
  getAppInfo(): AppInfo;
  getWorkspaceStatus(): Promise<WorkspaceStatus>;
  chooseWorkspace(language: WorkspaceDialogLanguage): Promise<ChooseWorkspaceResult>;
  selectWorkspaceFolder(language: WorkspaceDialogLanguage): Promise<SelectWorkspaceFolderResult>;
  initializeWorkspace(path: string): Promise<WorkspaceStatus>;
  setThemePreference(theme: AppThemePreference): Promise<void>;
  quitApp(): Promise<void>;
}
