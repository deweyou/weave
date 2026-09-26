# 当前架构

## 工程与输入

现状：SwiftUI 组织界面，macOS / iOS 26 为基线；Swift Package 使用 Swift 6.2。共享 App target 位于 `Weave.xcodeproj`，Package 用于带覆盖率的单测；`UITests/WeaveUITests.swift` 通过 Xcode UI test target 在 Mac 和 iPhone 模拟器运行。

| 文件 | 职责 |
| --- | --- |
| `Sources/Weave/App/ToastPresenter.swift` | 页面级短暂反馈消息、替换与关闭状态 |
| `Sources/Weave/App/Toast.swift` | Liquid Glass 反馈浮层；生命周期由 SwiftUI task 管理 |
| `Sources/Weave/App/AppTheme.swift` | SwiftUI 与原生绘制共用的主题色，默认系统蓝；不属于文档持久化属性 |
| `Sources/Weave/App/WeaveApp.swift` | 生命周期、存储实例、Mac 新建命令 |
| `Sources/Weave/App/WorkspaceView.swift` | 平台入口、共享记录瀑布流、记录编辑器及格式菜单 |
| `Sources/Weave/App/MobileWorkspaceView.swift` | iOS/iPadOS 自适应双栏、分类选择、卡片与编辑导航栈、长按整理与移动分类 sheet |
| `Sources/Weave/App/MacWorkspaceView.swift` | Mac 综合侧栏、分类/搜索、右侧浏览与编辑、窗口级导航与新建命令上下文 |
| `Sources/Weave/Editor/Native/NativeRichTextEditor.swift` | NSTextView / UITextView 桥接、选区、输入事件和平台交互 |
| `Sources/Weave/Editor/Features/EditorFeatureRegistry.swift` | 不可变输入上下文、feature 协议、语义命令与优先级 registry |
| `Sources/Weave/Editor/Features/StandardEditorFeatures.swift` | quote、task/list、code block、inline 和 Markdown shortcut 等内置输入 feature |
| `Sources/Weave/Editor/Native/NativeTextAttributes.swift` | TextKit 绘制、字体映射、原生属性与持久化属性转换 |
| `Sources/Weave/Editor/ParagraphEditing.swift` | `DocumentTypography` 排版配置、独立行内强调、整段格式操作、旧语义字体迁移、待办标记切换 |
| `Sources/Weave/Editor/MarkdownShortcut.swift` | 单次输入触发的局部转换规则，UTF-16 范围 |
| `Sources/Weave/Markdown/MarkdownFormatting.swift` | 常用 Markdown 导入与语义导出，非全部富文本的无损编解码器 |
| `Sources/Weave/Markdown/MarkdownFile.swift` | Markdown 文件类型与 SwiftUI 文档读写适配 |
| `Sources/Weave/Model/Note.swift` | 记录值模型、纯文本投影和兼容解码 |
| `Sources/Weave/Model/TableData.swift` | 表格 Codable 模型、行列操作、Markdown 表格交换与纯文本投影 |
| `Sources/Weave/Editor/Native/NativeTableView.swift` | 表格附件尺寸、原位单元格控件与行列菜单 |
| `Sources/Weave/Editor/Native/NativeTableOverlay.swift` | 表格控件与代码块工具栏随原生文本布局定位、复用与移除 |
| `Sources/Weave/Editor/RichTextClipboard.swift` | 结构化选区剪贴板编解码与粘贴时的块标识去重 |
| `Sources/Weave/Editor/CodeBlockEditing.swift` | 代码语言、别名、块范围、缩进和基础词法高亮规则 |
| `Sources/Weave/Editor/CodeFormatting.swift` | 独立 actor 中的离线 Prettier / JavaScriptCore 格式化；资源随 App 打包 |
| `Sources/Weave/Persistence/NoteStore.swift` | 身份、标题、搜索投影、JSON 读写和失败恢复 |

当前自定义 `CodeLayoutManager: NSLayoutManager` 绘制行内代码、代码块背景和引用竖线，走 TextKit 1 布局路径；不能称作 TextKit 2 编辑器。macOS 以滚动容器内边距限制正文宽度，滚动条留在编辑区右边。

原生输入先捕获为 `EditorInputContext`，再由 `EditorFeatureRegistry` 依次匹配 feature。feature 只返回 `EditorInputCommand`；
`NativeRichTextEditor.Coordinator` 统一执行文本修改、输入属性、选区、撤销和发布。新增 feature 必须显式确定优先级，并覆盖与 quote、task、list、code 等已有 feature 的组合行为。

输入事件经过平台 delegate、`Coordinator.intercept` 与局部转换规则，再发布富文本和选区。组合输入期间跳过转换；格式操作和快捷转换注册撤销。显示字体通过平台倍率放大，写回时还原，避免反复桥接导致字号增长。

原生正文用 LF 表示段落边界、U+2028 表示段内换行；正文段后距由 `DocumentTypography.bodyParagraphSpacing` 控制。Markdown 交换在导入时消费块间的一个分隔空行，保留多余空段和代码块内部空行；导出恢复分隔语法，连续列表或引用保持紧凑。已有富文本中的换行不自动迁移，存储与结构化剪贴板直接保留这些字符。

代码块的 `CodeHeaderOverlayController` 承载语言、自动换行和复制操作，代码文字继续留在同一 TextKit 文本存储中。布局委托在首行预留工具栏高度，避免文档开头忽略段前距时发生遮挡。语言编辑按块 ID 定位，通过原生编辑器的撤销路径修改，并保留正文选区。`CodeTextContainer` 为不换行代码段提供按内容测量的独立行宽，`CodeLayoutManager` 按块 ID 保存临时换行与水平偏移、裁剪文字并绘制滚动位置指示；Mac 横向滚轮和移动端横向拖动修改该偏移。普通正文宽度不变，光标移动时滚动到可见范围；这些显示状态不写入 `Note.richText`，重建编辑视图后恢复自动换行。

代码块默认总高度限制为 400 pt；当前编辑视图按块保存临时展开状态，展开后按完整内容高度布局，收起重置纵向偏移。工具栏由自然内容高度决定是否提供展开入口，边缘不绘制渐变。`CodeLayoutManager` 保留自然行位置与块内纵向偏移，行片段只贡献其与可见窗口相交的高度；文字、UTF-16 选区及撤销仍使用原存储，绘制裁剪在工具栏下方。原生方向键移动前先显示相邻视觉行，折叠光标变化后按需滚动；修改、窗口宽度变化和换行切换后钳制偏移。Mac 滚轮和移动端 pan 按主要方向路由至当前块，共用滚动条渐隐状态。平台手势、输入法和选择操作仍需按验证矩阵实际检查。

## 数据与恢复

`Note.richText` 是主数据，`text` 为正文搜索和摘要使用的纯文本投影，`Note.title` 是独立持久化的纯文本字段，搜索同时匹配标题和正文。缺少标题分离标记的旧记录将首个非空行迁移为标题，并从正文中移除该行；其余富文本属性保持不变。迁移后的记录保存分离标记，后续不再根据正文猜测；显式空标题保持为空。`NoteAttributeScope` 保存 SwiftUI 属性、`CodeStyleAttribute`、`CodeLanguageAttribute`、`ParagraphStyleAttribute`、`QuoteAttribute`、`TaskStateAttribute`、`InlineEmphasisAttribute`、`ListMarkerAttribute` 与 `TableAttribute`。代码属性区分 inline 与带 ID 的 block；段落属性保存标题、列表、任务和代码等内部角色，引用通过独立布尔属性叠加，因此可以包住这些段落类型。引用竖线和默认次要文字色只在原生显示层生成，不写入 Markdown 内容或用户颜色；旧引用的 `│ ` 前缀与旧 quote 段落角色在读取时迁移。任务完成状态独立保存且正文不包含 checkbox 占位字符，旧任务的 `☐ / ☑` 前缀在读取时迁移为该属性。行内强调以独立标志保存加粗和斜体，经过原生桥接、存储和结构化剪贴板保留，避免与标题自身的字重混淆。无序圆点和有序编号由 `ListMarkerAttribute` 保存，原生布局在正文左侧绘制，正文与选区不包含标记字符；缩进仍使用 Tab，不是完整结构化列表树。显示标记按三层循环；嵌套有序列表根据父项边界重新计数，主级保留指定起始值，Markdown 仍使用数字编号。旧记录仅对明确的列表角色迁移旧文本标记，先校验旧纯文本投影再迁移，重复读取不再剥离正文开头的数字。

读取旧记录时，仅将明确保存为旧 `.title` / `.title2` / `.title3` 的语义字体迁移为对应标题角色，并补齐旧标题的行内强调。无法确认语义的显式字号保留原样；显示布局不再通过字号阈值猜标题。新标题按角色和独立强调投影到当前排版配置。

表格在富文本中保存一个 U+FFFC 附件字符和矩形 `TableData` 属性，首行为表头；平台附件和 SwiftUI 单元格控件按表格 ID 重建，控件在输入时复用。纯文本投影展开单元格，解码时校验展开内容；旧记录不含表格时投影不变。表格不使用截图存储，也不使用独立弹窗编辑。每格当前为单行纯文本，超宽表格横向滚动，不支持合并单元格和富文本单元格。

代码语言随块保存，导出包含语言标签；高亮目前为 Swift、JavaScript、TypeScript、Python、JSON、Shell 的基础词法规则，未知语言保留标签。显示颜色通过临时标记从持久化映射中排除，颜色不成为 Markdown 语义。代码不执行。

正文选区同时写入应用自有 Codable 格式、系统 RTF 和纯文本；同一应用内粘贴优先恢复引用、Todo、标题和行内强调等完整语义，跨应用则使用标准 RTF 或纯文本。表格的纯文本回退为 Markdown，粘贴时重建表格和代码块 ID，避免两个副本共用输入视图；代码的纯文本回退保留原文字面量。外部纯文本粘贴在解析后存在已支持 Markdown 语义时复用同一插入、撤销和发布路径；普通文本及外部 RTF/HTML 回退原生粘贴，代码上下文不解析 Markdown。单元格内部编辑继续使用平台剪贴板。

稳定 UUID 在创建时生成；存储数组保持创建顺序，Mac 与移动端浏览视图均按最后编辑时间排序。分类操作不修改编辑时间。各窗口独立持有导航状态，新建命令作用于当前窗口分类。Mac 启动进入浏览列表；紧凑移动端从分类导航开始。移动端以一个 NavigationSplitView 和 detail NavigationStack 适配窗口尺寸，UUID 路径驱动编辑页，不在横竖屏切换时创建另一套编辑器。存储由应用实例持有，Observation 驱动 UI。修改先立即进入主线程内存状态，再由串行 actor 合并旧快照并在主线程外编码、原子写入 Application Support 下 `Weave/notes.json`；场景离开 active 时等待当前快照写完。实际目录受沙箱和启动方式影响。

记录的 `folderID` 是记录级字段，不属于 `NoteAttributeScope`；旧记录缺字段时默认未分类。`NoteFolder` 独立保存空分类。`notes.json` 当前以 `version: 1 / folders / notes` 单个原子快照存储；读取兼容旧记录数组，首次实际修改才写新版。未知版本、缺字段、重复身份、空分类名和悬空分类引用均禁止覆盖原文件。旧版本 App 不支持新版容器，不应交替写同一目录。

旧数据缺少 richText 时读取为普通文本；已有富文本损坏、为空值或与投影不一致时禁止覆盖。读取失败保留原文件并禁写；保存失败保留当前进程的内存修改，可重试。持久化测试使用隔离临时目录，不能用用户真实记录进行破坏性验证。

## 未实现与限制

- CloudKit 是确认的后续方向，没有账号、容器或同步实现。当前 JSON 不支持跨设备合并。
- JSON 仍是整库快照，虽然编码和写盘不阻塞输入，长文档与大记录库的内存复制和文件体积仍待评估。
- 列表缩进和勾选属于文本编辑能力；有序列表回车递增编号，但修改中间项目尚不自动重编号，没有独立待办模型或完整嵌套语义。
- 无删除 / 回收站、画板、导图、附件缓存；冲突策略需另行设计。Markdown 导入创建新记录，导出不改变主数据。
- 多平台编译不能证明触控、输入法、辅助功能或多设备同步通过。

现状依据上述源码；验证方法见[验证清单](verification.md)。

## 测试基础设施

`scripts/check_coverage.py` 读取 LLVM 覆盖率，按核心、桥接、全源码执行门禁；`.github/workflows/ci.yml` 运行单测和两端 UI 测试。Debug App 支持 UUID 命名的隔离测试存储，Release 使用正常存储。具体命令、门槛与限制见[验证清单](verification.md)。

记录瀑布流使用 `RecordMasonryLayout` 按实际列宽测量卡片并填入最短列，记录顺序和 ID 保持稳定。当前自定义 Layout 会测量全部卡片，尚无离屏虚拟化；大资料库的性能需独立验证。

收藏功能及模型字段已删除。解码时忽略旧文件中的 `isFavorite` 字段，下次保存不再写出该字段；记录内容和分类不受影响。


### 代码语言与格式化（现状）

基础词法高亮覆盖 26 种语言：Swift、JavaScript、TypeScript、JSX、TSX、Python、JSON、Shell、HTML、XML、CSS、SCSS、Less、SQL、YAML、Markdown、GraphQL、Go、Rust、Java、Kotlin、C、C++、C#、Ruby、PHP。它识别关键词、字符串、注释、数字及常见标签/属性，不承诺 IDE 级语义、所有方言或嵌套语言解析。

格式化覆盖 JavaScript、TypeScript、JSX、TSX、JSON、HTML、CSS、SCSS、Less、YAML、Markdown、GraphQL。Prettier 3.9.9 standalone 与所需插件固定版本打包在 `Resources/CodeFormatting`，许可证和第三方声明同目录保留。Swift Package 与 Xcode target 都复制该目录；运行不依赖网络、Node.js 或用户机器的命令行工具。

`CodeFormatting` actor 独占 JavaScriptCore VM，代码作为字符串传给解析器，不执行用户代码。所有插件本地加载，关闭嵌入语言格式化；每种解析器有 Promise 返回完成、幂等和尾部段落边界测试。统一 2 空格、LF，单块最多 200,000 UTF-16 单元，超过时保留原文并提示。

按钮任务由 SwiftUI 生命周期管理；完成后先检查取消、组合输入、存储实例及目标块完整快照，再通过 coordinator 的原生撤销路径替换当前块。格式化期间修改代码或语言会丢弃过期结果。相邻块、引用属性与正文边界保留，外围选区跟随长度变化，块内选区偏移钳制到合法组合字符边界。


编辑页通过 `@State ToastPresenter` 持有短暂反馈；原生编辑器向 `onToast` 回调传递消息，代码块格式化错误和剪贴板写入失败共享该出口。Toast 不访问文本存储、不操作焦点、不保存到笔记。每条消息具有独立 ID，替换后重建卡片并取消旧任务；关闭操作核对 ID，避免旧计时器误关新提示。格式化错误保留详细诊断供用户主动展开。

浮层光标：Mac Toast 按钮通过非拦截的 `PointingHandRegion` 声明实际点击热区；原生 `ReadingMacTextView.cursorUpdate` 先检查同窗口的可见浮层区域，避免正文 tracking 事件用 I 形光标覆盖按钮手型。区域弱引用管理，隐藏、移除和不同窗口不参与命中。
