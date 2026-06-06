import { describe, expect, it } from "vitest";
import {
  internalWorkspaceConfigReadErrorStatus,
  internalWorkspaceInitializationErrorStatus,
} from "./workspace-ipc.js";

describe("workspace IPC status mapping", () => {
  it("maps workspace config read failures to unconfigured status", () => {
    expect(internalWorkspaceConfigReadErrorStatus()).toEqual({
      kind: "unconfigured",
      path: null,
      message: "Workspace configuration could not be read. Choose a local folder to continue.",
    });
  });

  it("maps selected folder initialization failures to missing status", () => {
    expect(internalWorkspaceInitializationErrorStatus("/tmp/weave-workspace")).toEqual({
      kind: "missing",
      path: "/tmp/weave-workspace",
      message: "Weave could not initialize that folder. Choose a writable local folder.",
    });
  });
});
