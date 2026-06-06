export type ContentKind = "writing" | "memo" | "todo";

export interface WorkspaceEntry {
  readonly id: string;
  readonly kind: ContentKind;
  readonly title: string;
  readonly summary: string;
  readonly updatedAt: string;
}

export interface WorkspaceSummary {
  readonly id: string;
  readonly name: string;
  readonly entries: readonly WorkspaceEntry[];
}

export function createStarterWorkspace(): WorkspaceSummary {
  return {
    id: "local",
    name: "Local Workspace",
    entries: [
      {
        id: "writing-inbox",
        kind: "writing",
        title: "写作",
        summary: "沉淀长文、草稿和可继续推进的想法。",
        updatedAt: "2026-06-06"
      },
      {
        id: "memo-inbox",
        kind: "memo",
        title: "备忘录",
        summary: "快速记录片段、灵感和稍后整理的内容。",
        updatedAt: "2026-06-06"
      },
      {
        id: "todo-inbox",
        kind: "todo",
        title: "待办",
        summary: "管理下一步行动，不让想法停在脑子里。",
        updatedAt: "2026-06-06"
      }
    ]
  };
}
