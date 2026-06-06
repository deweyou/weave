import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  getWorkspaceStatus,
  initializeWorkspace,
  setWorkspacePath,
  workspaceConfigFileName,
  workspaceDirectories,
} from "./workspace.js";

const tempRoots: string[] = [];
const expectedWorkspaceDirectories = [
  ".weave",
  ".weave/indexes",
  ".weave/logs",
  "notes",
  "memos",
  "todos",
] as const;

async function makeTempDir(prefix: string): Promise<string> {
  const dir = await mkdtemp(path.join(os.tmpdir(), prefix));
  tempRoots.push(dir);
  return dir;
}

afterEach(async () => {
  await Promise.all(tempRoots.splice(0).map((dir) => rm(dir, { force: true, recursive: true })));
});

describe("workspace", () => {
  it("initializes the fixed workspace directory structure", async () => {
    const workspacePath = await makeTempDir("weave-workspace-");

    await initializeWorkspace(workspacePath);

    expect(workspaceDirectories).toEqual(expectedWorkspaceDirectories);

    await Promise.all(
      expectedWorkspaceDirectories.map(async (relativePath) => {
        const directory = await stat(path.join(workspacePath, relativePath));
        expect(directory.isDirectory()).toBe(true);
      }),
    );
  });

  it("writes workspace metadata config inside .weave", async () => {
    const workspacePath = await makeTempDir("weave-workspace-");

    await initializeWorkspace(workspacePath);

    const configPath = path.join(workspacePath, ".weave", workspaceConfigFileName);
    const config = JSON.parse(await readFile(configPath, "utf8")) as { version: number };
    expect(config).toEqual({ version: 1 });
  });

  it("returns unconfigured when no app config exists", async () => {
    const appDataPath = await makeTempDir("weave-appdata-");

    await expect(getWorkspaceStatus(appDataPath)).resolves.toEqual({
      kind: "unconfigured",
      path: null,
      message: "Choose a local folder to start using Weave.",
    });
  });

  it("rejects damaged app workspace config", async () => {
    const appDataPath = await makeTempDir("weave-appdata-");
    await writeFile(path.join(appDataPath, "workspace.json"), "{", "utf8");

    await expect(getWorkspaceStatus(appDataPath)).rejects.toThrow(SyntaxError);
  });

  it("persists a configured workspace path and reports ready", async () => {
    const appDataPath = await makeTempDir("weave-appdata-");
    const workspacePath = await makeTempDir("weave-workspace-");

    await setWorkspacePath(appDataPath, workspacePath);

    await expect(getWorkspaceStatus(appDataPath)).resolves.toEqual({
      kind: "ready",
      path: workspacePath,
      message: null,
    });
  });

  it("reports missing when the configured workspace path is not a folder", async () => {
    const appDataPath = await makeTempDir("weave-appdata-");
    const workspacePath = path.join(await makeTempDir("weave-workspace-"), "workspace-file");

    await writeFile(workspacePath, "", "utf8");
    await writeFile(
      path.join(appDataPath, "workspace.json"),
      `${JSON.stringify({ workspacePath }, null, 2)}\n`,
      "utf8",
    );

    await expect(getWorkspaceStatus(appDataPath)).resolves.toEqual({
      kind: "missing",
      path: workspacePath,
      message: "The configured workspace folder is unavailable. Choose a valid local folder.",
    });
  });

  it("reports missing when the configured workspace path is unavailable", async () => {
    const appDataPath = await makeTempDir("weave-appdata-");
    const workspacePath = await makeTempDir("weave-workspace-");

    await setWorkspacePath(appDataPath, workspacePath);
    await rm(workspacePath, { force: true, recursive: true });

    await expect(getWorkspaceStatus(appDataPath)).resolves.toEqual({
      kind: "missing",
      path: workspacePath,
      message: "The configured workspace folder is unavailable. Choose a valid local folder.",
    });
  });
});
