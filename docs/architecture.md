# 当前架构

第一期使用 SwiftUI 原生控件，macOS / iOS 26 为基线。`Weave.xcodeproj` 共享同一套 Swift 源码；`Package.swift` 用于本地存储测试。

## 实现边界

- `Sources/Weave/WeaveApp.swift`：应用生命周期、共享存储实例和 Mac 新建命令。
- `Sources/Weave/WorkspaceView.swift`：NavigationSplitView、List、搜索、富文本原生编辑区 和错误状态。系统导航与工具栏负责 Liquid Glass 外观。
- `Sources/Weave/NoteStore.swift`：记录身份、首行标题、选择状态、本地 JSON 读取和原子写入。
- `Tests/WeaveTests/NoteStoreTests.swift`：重启恢复、文件损坏保护、保存失败保留与重试。

`Note.richText` 是 AttributedString 主数据，使用 SwiftUI 属性范围显式编解码；`text` 是派生的纯文本投影。旧数据缺少 richText 时迁移为无格式文本；已有富文本损坏、为空值或与投影不一致时禁止写回。自定义格式命令通过 UndoManager 注册可逆修改。
`MarkdownFormatting.swift` 负责有限语法转换：按行识别块标记、使用 Foundation 解析行内语法并映射为 SwiftUI 字体/链接。不是 Markdown 往返编解码器，`MarkdownShortcut.swift` 提供局部输入转换规则，`NativeRichTextEditor.swift` 使用 NSTextView / UITextView 接入规则，跳过输入法组合态并注册撤销。

记录在创建时生成稳定 UUID。编辑直接更新当前记录，使用第一条非空行作为标题。列表保持创建顺序，输入时不跳动重排。
存储由应用实例拥有，UI 通过 Observation 更新；每次修改同步原子保存。读取失败后禁止写回覆盖源文件；保存失败后保留内存状态。

## 后续边界

CloudKit 已确认为后续方向，但没有容器、账号或同步代码。当前 JSON 不承诺跨设备合并，不能放入云盘来代替同步。
大规模内容需要评估写入调度、数据库和迁移；当前同步写入不是长期性能方案。
UITextView/NSTextView 深度扩展和 TextKit 2 自定义未实现。
画板与导图后续使用独立可编辑内容对象，正文显示引用预览。附件下载、缓存与冲突处理需要另行实现。

验证方法与命令见 [README](../README.md)。编译与存储测试不替代真实输入法、辅助功能、移动设备交互或 CloudKit 验证。

_Last updated: 2026-09-10 — 记录第一期实际源代码与存储边界。_

Markdown 快捷输入：行首 `#` 至 `######`、`-` / `*` / `+`、`>` 加空格；行内 `**加粗**`、`*斜体*`、反引号代码闭合后自动转换。支持有序列表和待办快捷输入，以及三个反引号加回车进入代码块。标题回车恢复正文，列表回车续写、空行退出；macOS 列表支持 Tab / Shift-Tab 缩进。代码块空行回车退出。选中文字粘贴 URL 添加链接，Cmd-K 打开链接编辑。待办标记可点击切换并撤销。多字符 Markdown 粘贴仍需手动转换。

代码样式通过 `CodeStyleAttribute` 区分行内代码和带标识的代码块，包含代码内部换行；`NoteAttributeScope` 同时保存原 SwiftUI 属性与代码角色。`CodeLayoutManager` 在原生文字背景阶段绘制表面，保留原生选区和插入点。旧版等宽代码及其高亮在展示桥接时兼容，正文字符不变。
