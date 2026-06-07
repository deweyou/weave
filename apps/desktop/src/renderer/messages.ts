import type { AppLanguage } from "./language";

export const messages = {
  "zh-CN": {
    firstRun: {
      languageSummary: "选择界面语言",
      chinese: "中文",
      english: "English",
      themeSummary: "主题颜色",
      themeLight: "浅色",
      themeDark: "深色",
      themeSystem: "对齐系统",
      workspaceSummary: "选择本地文件夹",
      missingTitle: "重新选择 Weave 文件夹",
      missingMessage: "之前配置的文件夹不可用。请选择一个有效的本地文件夹。",
      noFolderSelected: "未选择文件夹",
      choosingFolder: "正在打开...",
      cancel: "取消",
      finish: "完成"
    },
    loading: {
      eyebrow: "本地优先设置",
      title: "正在加载 Weave"
    },
    shell: {
      workspaceReady: "本地资料根目录已就绪。这里会逐步成为写作、备忘录和待办的工作台。",
      workspaceLabel: "WORKSPACE",
      workspaceTitle: "工作区",
      changeFolder: "更改文件夹",
      choosingFolder: "正在打开..."
    }
  },
  "en-US": {
    firstRun: {
      languageSummary: "Choose interface language",
      chinese: "中文",
      english: "English",
      themeSummary: "Theme",
      themeLight: "Light",
      themeDark: "Dark",
      themeSystem: "System",
      workspaceSummary: "Choose local folder",
      missingTitle: "Choose a new Weave folder",
      missingMessage: "The configured folder is unavailable. Choose a valid local folder.",
      noFolderSelected: "No folder selected",
      choosingFolder: "Opening...",
      cancel: "Cancel",
      finish: "Done"
    },
    loading: {
      eyebrow: "Local-first setup",
      title: "Loading Weave"
    },
    shell: {
      workspaceReady: "Your local data root is ready. This will become the workspace for writing, memos, and todos.",
      workspaceLabel: "WORKSPACE",
      workspaceTitle: "Workspace",
      changeFolder: "Change folder",
      choosingFolder: "Opening..."
    }
  }
} as const satisfies Record<AppLanguage, object>;

export type AppMessages = (typeof messages)[AppLanguage];
