import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import type { WorkspaceStatus } from "../shared/desktop-api";
import { FirstRunView } from "./first-run-view";
import type { AppLanguage } from "./language";
import { messages } from "./messages";
import type { AppTheme } from "./theme";

const onChooseLanguage = vi.fn();
const onChooseTheme = vi.fn();
const onSelectWorkspace = vi.fn();
const onComplete = vi.fn();
const onCancel = vi.fn();

function renderFirstRunView(
  status: WorkspaceStatus,
  language: AppLanguage | null = "zh-CN",
  selectedWorkspacePath: string | null = null,
  theme: AppTheme = "system",
) {
  return renderToStaticMarkup(
    <FirstRunView
      status={status}
      language={language}
      theme={theme}
      labels={messages[language ?? "zh-CN"].firstRun}
      isSelectingWorkspace={false}
      isCompleting={false}
      selectedWorkspacePath={selectedWorkspacePath}
      previewNotice={null}
      onChooseLanguage={onChooseLanguage}
      onChooseTheme={onChooseTheme}
      onSelectWorkspace={onSelectWorkspace}
      onComplete={onComplete}
      onCancel={onCancel}
    />
  );
}

describe("FirstRunView", () => {
  it("shows first-run setup in one page", () => {
    const html = renderFirstRunView(
      {
        kind: "unconfigured",
        path: null,
        message: null,
      },
      null,
    );

    expect(html).toContain("选择界面语言");
    expect(html).toContain("中文");
    expect(html).toContain("English");
    expect(html).toContain("主题颜色");
    expect(html).toContain("浅色");
    expect(html).toContain("深色");
    expect(html).toContain("对齐系统");
    expect(html).toContain("选择本地文件夹");
    expect(html).toContain("未选择文件夹");
    expect(html).toContain("取消");
    expect(html).toContain("完成");
    expect(html).toContain("disabled");
    expect(html).not.toContain("步骤");
  });

  it("does not render unconfigured workspace status messages in first-run setup", () => {
    const html = renderFirstRunView({
      kind: "unconfigured",
      path: null,
      message: "Choose a local folder to start using Weave.",
    });

    expect(html).not.toContain("Choose a local folder to start using Weave.");
  });

  it("shows English first-run setup when English is selected", () => {
    const html = renderFirstRunView(
      {
        kind: "unconfigured",
        path: null,
        message: null,
      },
      "en-US",
    );

    expect(html).toContain("Choose interface language");
    expect(html).toContain("Theme");
    expect(html).toContain("Light");
    expect(html).toContain("Dark");
    expect(html).toContain("System");
    expect(html).toContain("Choose local folder");
    expect(html).toContain("No folder selected");
    expect(html).toContain("Cancel");
    expect(html).toContain("Done");
    expect(html).not.toContain("Step");
    expect(html).not.toContain("选择一个本地文件夹");
  });

  it("enables first-run completion after a workspace folder is selected", () => {
    const html = renderFirstRunView(
      {
        kind: "unconfigured",
        path: null,
        message: null,
      },
      "zh-CN",
      "/Users/deweyou/Weave",
    );

    expect(html).toContain("/Users/deweyou/Weave");
    expect(html).not.toContain("disabled=\"\"");
  });

  it("shows recovery setup when the configured workspace is missing", () => {
    const html = renderFirstRunView({
      kind: "missing",
      path: "/missing/weave",
      message: "The configured workspace folder is unavailable.",
    });

    expect(html).toContain("重新选择 Weave 文件夹");
    expect(html).toContain("之前配置的文件夹不可用。");
    expect(html).toContain("/missing/weave");
  });
});
