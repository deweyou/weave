import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import { messages } from "./messages";
import { createStarterWorkspace } from "./starter-workspace";
import { WorkspaceHomeView } from "./workspace-home-view";

describe("WorkspaceHomeView", () => {
  it("shows the workspace home and settings", () => {
    const html = renderToStaticMarkup(
      <WorkspaceHomeView
        workspace={createStarterWorkspace()}
        runtimeName="electron"
        status={{
          kind: "ready",
          path: "/Users/deweyou/Weave",
          message: null,
        }}
        labels={messages["zh-CN"].shell}
        isChoosingWorkspace={false}
        onChooseWorkspace={vi.fn()}
      />,
    );

    expect(html).toContain("Weave");
    expect(html).toContain("写作");
    expect(html).toContain("工作区");
    expect(html).toContain("更改文件夹");
  });
});
