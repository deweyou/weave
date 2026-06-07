import { constants } from "node:fs";
import { access, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import type { WorkspaceStatus } from "../shared/desktop-api.js";

export const workspaceConfigFileName = "config.json";

export const workspaceDirectories = [
  ".weave",
  ".weave/indexes",
  ".weave/logs",
  "notes",
  "memos",
  "todos",
] as const;

interface AppWorkspaceConfig {
  readonly workspacePath: string;
}

interface WorkspaceMetadata {
  readonly version: 1;
}

const appConfigFileName = "workspace.json";

function appConfigPath(appDataPath: string): string {
  return path.join(appDataPath, appConfigFileName);
}

function workspaceMetadataPath(workspacePath: string): string {
  return path.join(workspacePath, ".weave", workspaceConfigFileName);
}

async function isAccessibleDirectory(targetPath: string): Promise<boolean> {
  try {
    const target = await stat(targetPath);

    if (!target.isDirectory()) {
      return false;
    }

    await access(targetPath, constants.R_OK | constants.W_OK | constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

async function readAppWorkspaceConfig(appDataPath: string): Promise<AppWorkspaceConfig | null> {
  let rawConfig: string;

  try {
    rawConfig = await readFile(appConfigPath(appDataPath), "utf8");
  } catch (error) {
    if (isNodeError(error) && error.code === "ENOENT") {
      return null;
    }

    throw error;
  }

  const parsed = JSON.parse(rawConfig) as Partial<AppWorkspaceConfig>;
  return typeof parsed.workspacePath === "string" && parsed.workspacePath.length > 0
    ? { workspacePath: parsed.workspacePath }
    : null;
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

export async function initializeWorkspace(workspacePath: string): Promise<void> {
  const target = await stat(workspacePath);

  if (!target.isDirectory()) {
    throw new Error("Workspace path must be a folder.");
  }

  await Promise.all(
    workspaceDirectories.map((relativePath) =>
      mkdir(path.join(workspacePath, relativePath), { recursive: true }),
    ),
  );

  const metadata: WorkspaceMetadata = { version: 1 };
  await writeFile(workspaceMetadataPath(workspacePath), `${JSON.stringify(metadata, null, 2)}\n`, "utf8");
}

export async function setWorkspacePath(appDataPath: string, workspacePath: string): Promise<WorkspaceStatus> {
  await initializeWorkspace(workspacePath);
  await mkdir(appDataPath, { recursive: true });

  const config: AppWorkspaceConfig = { workspacePath };
  await writeFile(appConfigPath(appDataPath), `${JSON.stringify(config, null, 2)}\n`, "utf8");

  return {
    kind: "ready",
    path: workspacePath,
    message: null,
  };
}

export async function getWorkspaceStatus(appDataPath: string): Promise<WorkspaceStatus> {
  const config = await readAppWorkspaceConfig(appDataPath);

  if (!config) {
    return {
      kind: "unconfigured",
      path: null,
      message: null,
    };
  }

  if (!(await isAccessibleDirectory(config.workspacePath))) {
    return {
      kind: "missing",
      path: config.workspacePath,
      message: "The configured workspace folder is unavailable. Choose a valid local folder.",
    };
  }

  return {
    kind: "ready",
    path: config.workspacePath,
    message: null,
  };
}
