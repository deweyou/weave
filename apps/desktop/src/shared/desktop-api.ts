export type WorkspaceStatusKind = "unconfigured" | "ready" | "missing";

export interface AppInfo {
  readonly name: string;
  readonly runtime: string;
}

export interface WorkspaceStatus {
  readonly kind: WorkspaceStatusKind;
  readonly path: string | null;
  readonly message: string | null;
}

export interface ChooseWorkspaceResult {
  readonly canceled: boolean;
  readonly status: WorkspaceStatus;
}

export const workspaceIpcChannels = {
  getStatus: "workspace:getStatus",
  choose: "workspace:choose",
} as const;

export interface DesktopApi {
  getAppInfo(): AppInfo;
  getWorkspaceStatus(): Promise<WorkspaceStatus>;
  chooseWorkspace(): Promise<ChooseWorkspaceResult>;
}
