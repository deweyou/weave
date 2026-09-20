# 当前架构

## 工程与输入

现状：SwiftUI 组织界面，macOS / iOS 26 为基线；Swift Package 使用 Swift 6.2。共享 App target 位于 `Weave.xcodeproj`，Package 用于带覆盖率的单测；`UITests/WeaveUITests.swift` 通过 Xcode UI test target 在 Mac 和 iPhone 模拟器运行。

| 文件 | 职责 |
| --- | --- |
| `Sources/Weave/App/WeaveApp.swift` | 生命周期、存储实例、Mac 新建命令 |
| `Sources/Weave/App/WorkspaceView.swift` | 分栏、列表与搜索、格式工具条与菜单、链接表单、Markdown 文件面板、错误状态 |
| `Sources/Weave/Editor/Native/NativeRichTextEditor.swift` | NSTextView / UITextView 桥接、选区、输入事件和平台交互 |
| `Sources/Weave/Editor/Features/EditorFeatureRegistry.swift` | 不可变输入上下文、feature 协议、语义命令与优先级 registry |
| `Sources/Weave/Editor/Features/StandardEditorFeatures.swift` | quote、task/list、code block、inline 和 Markdown shortcut 等内置输入 feature |
| `Sources/Weave/Editor/Native/NativeTextAttributes.swift` | TextKit 绘制、字体映射、原生属性与持久化属性转换 |
| `Sources/Weave/Editor/ParagraphEditing.swift` | `DocumentTypography` 排版配置、独立行内强调、整段格式操作、旧语义字体迁移、待办标记切换 |
| `Sources/Weave/Editor/MarkdownShortcut.swift` | 单次输入触发的局部转换规则，UTF-16 范围 |
| `Sources/Weave/Markdown/MarkdownFormatting.swift` | 常用 Markdown 导入与语义导出，非全部富文本的无损编解码器 |
| `Sources/Weave/Markdown/MarkdownFile.swift` | Markdown 文件类型与 SwiftUI 文档读写适配 |
| `Sources/Weave/Model/Note.swift` | 笔记值模型、纯文本投影和兼容解码 |
| `Sources/Weave/Model/TableData.swift` | 表格 Codable 模型、行列操作、Markdown 表格交换与纯文本投影 |
| `Sources/Weave/Editor/Native/NativeTableView.swift` | 表格附件尺寸、原位单元格控件与行列菜单 |
| `Sources/Weave/Editor/Native/NativeTableOverlay.swift` | 表格控件与代码块工具栏随原生文本布局定位、复用与移除 |
| `Sources/Weave/Editor/RichTextClipboard.swift` | 结构化选区剪贴板编解码与粘贴时的块标识去重 |
| `Sources/Weave/Editor/CodeBlockEditing.swift` | 代码语言、块范围、缩进和基础词法高亮规则 |
| `Sources/Weave/Persistence/NoteStore.swift` | 身份、标题、搜索投影、JSON 读写和失败恢复 |

当前自定义 `CodeLayoutManager: NSLayoutManager` 绘制行内代码、代码块背景和引用竖线，走 TextKit 1 布局路径；不能称作 TextKit 2 编辑器。macOS 以滚动容器内边距限制正文宽度，滚动条留在编辑区右边。

原生输入先捕获为 `EditorInputContext`，再由 `EditorFeatureRegistry` 依次匹配 feature。feature 只返回 `EditorInputCommand`；
`NativeRichTextEditor.Coordinator` 统一执行文本修改、输入属性、选区、撤销和发布。新增 feature 必须显式确定优先级，并覆盖与 quote、task、list、code 等已有 feature 的组合行为。

输入事件经过平台 delegate、`Coordinator.intercept` 与局部转换规则，再发布富文本和选区。组合输入期间跳过转换；格式操作和快捷转换注册撤销。显示字体通过平台倍率放大，写回时还原，避免反复桥接导致字号增长。

原生正文用 LF 表示段落边界、U+2028 表示段内换行；正文段后距由 `DocumentTypography.bodyParagraphSpacing` 控制。Markdown 交换在导入时消费块间的一个分隔空行，保留多余空段和代码块内部空行；导出恢复分隔语法，连续列表或引用保持紧凑。已有富文本中的换行不自动迁移，存储与结构化剪贴板直接保留这些字符。

代码块的 `CodeHeaderOverlayController` 只承载语言和复制操作，代码文字继续留在同一 TextKit 文本存储中。布局委托在首行预留工具栏高度，避免文档开头忽略段前距时发生遮挡。语言编辑按块 ID 定位，通过原生编辑器的撤销路径修改，并保留正文选区。

## 数据与恢复

`Note.richText` 是主数据，`text` 为正文搜索和摘要使用的纯文本投影，`Note.title` 是独立持久化的纯文本字段，搜索同时匹配标题和正文。缺少标题分离标记的旧记录将首个非空行迁移为标题，并从正文中移除该行；其余富文本属性保持不变。迁移后的记录保存分离标记，后续不再根据正文猜测；显式空标题保持为空。`NoteAttributeScope` 保存 SwiftUI 属性、`CodeStyleAttribute`、`CodeLanguageAttribute`、`ParagraphStyleAttribute`、`QuoteAttribute`、`TaskStateAttribute`、`InlineEmphasisAttribute` 与 `TableAttribute`。代码属性区分 inline 与带 ID 的 block；段落属性保存标题、列表、任务和代码等内部角色，引用通过独立布尔属性叠加，因此可以包住这些段落类型。引用竖线和默认次要文字色只在原生显示层生成，不写入 Markdown 内容或用户颜色；旧引用的 `│ ` 前缀与旧 quote 段落角色在读取时迁移。任务完成状态独立保存且正文不包含 checkbox 占位字符，旧任务的 `☐ / ☑` 前缀在读取时迁移为该属性。行内强调以独立标志保存加粗和斜体，经过原生桥接、存储和结构化剪贴板保留，避免与标题自身的字重混淆。项目符号和有序列表仍包含文本前缀，不是完整结构化列表树。

读取旧笔记时，仅将明确保存为旧 `.title` / `.title2` / `.title3` 的语义字体迁移为对应标题角色，并补齐旧标题的行内强调。无法确认语义的显式字号保留原样；显示布局不再通过字号阈值猜标题。新标题按角色和独立强调投影到当前排版配置。

表格在富文本中保存一个 U+FFFC 附件字符和矩形 `TableData` 属性，首行为表头；平台附件和 SwiftUI 单元格控件按表格 ID 重建，控件在输入时复用。纯文本投影展开单元格，解码时校验展开内容；旧笔记不含表格时投影不变。表格不使用截图存储，也不使用独立弹窗编辑。每格当前为单行纯文本，超宽表格横向滚动，不支持合并单元格和富文本单元格。

代码语言随块保存，导出包含语言标签；高亮目前为 Swift、JavaScript、TypeScript、Python、JSON、Shell 的基础词法规则，未知语言保留标签。显示颜色通过临时标记从持久化映射中排除，颜色不成为 Markdown 语义。代码不执行。

正文选区同时写入应用自有 Codable 格式、系统 RTF 和纯文本；同一应用内粘贴优先恢复引用、Todo、标题和行内强调等完整语义，跨应用则使用标准 RTF 或纯文本。表格的纯文本回退为 Markdown，粘贴时重建表格和代码块 ID，避免两个副本共用输入视图；代码的纯文本回退保留原文字面量。单元格内部编辑继续使用平台剪贴板。

稳定 UUID 在创建时生成；列表保持创建顺序，输入不触发重新排序。存储由应用实例持有，Observation 驱动 UI。修改先立即进入主线程内存状态，再由串行 actor 合并旧快照并在主线程外编码、原子写入 Application Support 下 `Weave/notes.json`；场景离开 active 时等待当前快照写完。实际目录受沙箱和启动方式影响。

旧数据缺少 richText 时读取为普通文本；已有富文本损坏、为空值或与投影不一致时禁止覆盖。读取失败保留原文件并禁写；保存失败保留当前进程的内存修改，可重试。持久化测试使用隔离临时目录，不能用用户真实笔记进行破坏性验证。

## 未实现与限制

- CloudKit 是确认的后续方向，没有账号、容器或同步实现。当前 JSON 不支持跨设备合并。
- JSON 仍是整库快照，虽然编码和写盘不阻塞输入，长文档与大笔记库的内存复制和文件体积仍待评估。
- 列表缩进和勾选属于文本编辑能力，没有独立待办模型、自动重编号或完整嵌套语义。
- 无删除 / 回收站、画板、导图、附件缓存；冲突策略需另行设计。Markdown 导入创建新记录，导出不改变主数据。
- 多平台编译不能证明触控、输入法、辅助功能或多设备同步通过。

现状依据上述源码；验证方法见[验证清单](verification.md)。

## 测试基础设施

`scripts/check_coverage.py` 读取 LLVM 覆盖率，按核心、桥接、全源码执行门禁；`.github/workflows/ci.yml` 运行单测和两端 UI 测试。Debug App 支持 UUID 命名的隔离测试存储，Release 使用正常存储。具体命令、门槛与限制见[验证清单](verification.md)。
