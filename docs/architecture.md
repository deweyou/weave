# 当前架构

## 工程与输入

现状：SwiftUI 组织界面，macOS / iOS 26 为基线；Swift Package 使用 Swift 6.2。共享 App target 位于 `Weave.xcodeproj`，Package 用于本地测试。

| 文件 | 职责 |
| --- | --- |
| `Sources/Weave/WeaveApp.swift` | 生命周期、存储实例、Mac 新建命令 |
| `Sources/Weave/WorkspaceView.swift` | 分栏、列表与搜索、格式菜单、链接表单、错误状态 |
| `Sources/Weave/NativeRichTextEditor.swift` | NSTextView / UITextView 桥接、字体映射、选区与输入属性、快捷输入接入、原生背景绘制 |
| `Sources/Weave/ParagraphEditing.swift` | 整段格式操作、段落角色、待办标记切换 |
| `Sources/Weave/MarkdownShortcut.swift` | 单次输入触发的局部转换规则，UTF-16 范围 |
| `Sources/Weave/MarkdownFormatting.swift` | 选区 / 全文 Markdown 转换，非无损编解码器 |
| `Sources/Weave/NoteStore.swift` | 身份、标题、搜索投影、JSON 读写和失败恢复 |

当前自定义 `CodeLayoutManager: NSLayoutManager` 绘制行内代码、代码块背景和引用竖线，走 TextKit 1 布局路径；不能称作 TextKit 2 编辑器。macOS 以滚动容器内边距限制正文宽度，滚动条留在编辑区右边。

输入事件经过平台 delegate、`Coordinator.intercept` 与局部转换规则，再发布富文本和选区。组合输入期间跳过转换；格式操作和快捷转换注册撤销。显示字体通过平台倍率放大，写回时还原，避免反复桥接导致字号增长。

## 数据与恢复

`Note.richText` 是主数据，`text` 为标题和搜索使用的纯文本投影。`NoteAttributeScope` 保存 SwiftUI 属性、`CodeStyleAttribute` 与 `ParagraphStyleAttribute`。代码属性区分 inline 与带 ID 的 block；段落属性保存标题、引用等角色。列表仍包含文本前缀，不是完整结构化列表树。

稳定 UUID 在创建时生成；列表保持创建顺序，输入不触发重新排序。存储由应用实例持有，Observation 驱动 UI。每次修改同步原子写入 Application Support 下 `Weave/notes.json`，实际目录受沙箱和启动方式影响。

旧数据缺少 richText 时读取为普通文本；已有富文本损坏、为空值或与投影不一致时禁止覆盖。读取失败保留原文件并禁写；保存失败保留当前进程的内存修改，可重试。持久化测试使用隔离临时目录，不能用用户真实笔记进行破坏性验证。

## 未实现与限制

- CloudKit 是确认的后续方向，没有账号、容器或同步实现。当前 JSON 不支持跨设备合并。
- 同步全量写入用于小规模起步，长文档与大笔记库性能待评估。
- 列表缩进和勾选属于文本编辑能力，没有独立待办模型、自动重编号或完整嵌套语义。
- 无删除 / 回收站、画板、导图、附件缓存；导入导出与冲突策略需另行设计。
- 多平台编译不能证明触控、输入法、辅助功能或多设备同步通过。

现状依据上述源码；验证方法见[验证清单](verification.md)。
