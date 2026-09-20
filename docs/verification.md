# 验证与证据

从工作区根目录运行。按实际改动选择检查，结果注明提交 / 差异、平台、命令、退出码及未验证项；不要长期写死测试数量。

## 自动检查

| 影响范围 | 命令 / 检查 | 能证明什么 |
| --- | --- | --- |
| Swift 格式 / 静态风格 | `swift format lint --recursive --strict --configuration .swift-format Sources Tests UITests Package.swift` | Swift 源码符合仓库格式与基础静态规则 |
| Swift 行为 / 数据修改 | `swift test` | 现有测试覆盖的规则、存储与桥接行为 |
| Mac 代码与共享代码 | `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build` | Mac target 编译 |
| iOS 代码与共享代码 | `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build` | iOS Simulator target 编译 |
| 文档 / 配置 | 本地链接、入口、源码一致性；Harness `config_inspect` | 文档和配置有效，不证明 App 行为 |
| 交付差异 | `git diff --check`；暂存后 `git diff --cached --check` | 空白与差异检查，未跟踪文件需另查 |

首次使用需 Xcode / Swift 6.2 兼容工具链。沙箱中的宏插件或编译缓存权限失败属于环境问题；明确报告并走宿主授权，不把关闭沙箱作为仓库默认命令。日志和构建产物放 `.build/` 或任务临时目录，Run 中按需记录 Evidence。

Mac 实际预览使用 `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build` 做本地 ad-hoc 签名，保留工程的 App Sandbox 配置。`CODE_SIGNING_ALLOWED=NO` 只用于编译验证；直接运行无签名产物可能改用非容器 Application Support，不能据此判定原笔记丢失。重启按 AGENTS 的单实例规则操作，先核对会话、保存状态与实际数据目录。

## 手动操作矩阵

| 改动 | 必测场景 |
| --- | --- |
| 输入 / 快捷语法 | 中文拼音组合与候选确认、emoji、选区替换；加粗、斜体、删除线与反引号行内代码前后紧贴中英文、数字或 emoji；在已有后文或不同格式标记前补结束符，同类连续分隔符不提前转换，标题内闭合后保留层级与后续输入属性；完整删除行内代码、粗体、斜体或删除线后继续输入应恢复当前段落普通文字；转义星号、代码内字面量；多字符粘贴 |
| 字体 / 段落 | 空行光标高度、标题回车恢复正文；标题文字删空后再次退格恢复正文，包含文档首段；空行输入首字和删除至空时，检查下方正文及标题位置稳定；选中半段应用标题；正文与六级标题互转后，保留加粗、斜体、链接及行内代码；强调经过导出、剪贴板和重启恢复；格式后继续输入；旧语义字体迁移及大字号正文不被误判；切换记录不放大字号 |
| 列表 / 待办 | 有序与无序续写、空行退出、前缀退格、Tab / Shift-Tab；点击勾选、拖选与撤销 |
| 表格 | 单元格原位输入、Tab / Shift-Tab、末格新增行、增删行列、列对齐、超宽横向滚动、正文前后不重叠、撤销和重启；含表格/代码的复制、剪切、粘贴到同一或不同笔记；空格与管道转义的 Markdown 往返 |
| 代码 / 引用 | 行内代码与连续多行表面、空行退出、边界插入、跨块选区；代码内与文末空行之间反复点击，背景范围和圆角保持稳定；Mac 点击代码块下方退出、撤销、重做及继续输入正文；结束围栏后的空段不继承代码；点击已有正文空段后继续输入不继承前一个代码块；相邻或分离的代码范围背景不叠色；引用默认次要文字色、竖线首尾、连续行和双 Return 退出；引用内分别输入标题、Todo、有序/无序列表和围栏代码快捷语法并完成 Markdown 往返；滚动、窄窗口与深色 |
| 链接 | 选中文字粘贴 URL、Cmd-K、编辑 / 移除链接、标签保持、撤销 |
| Markdown 交换 | UTF-8 文件导入创建新记录；复制 / 导出后再导入；分隔空行只生成段落边界，额外空段和段内换行重复往返不累积；TextKit 换段相对段内换行增加 6 pt，空段输入前后下文位置稳定；格式空白边界、反引号围栏、标点转义；系统面板取消与读取 / 写入错误 |
| 独立标题 | 空标题 placeholder、长文本自动折行和四行内增长、Return / Tab / 点击进入正文、粘贴换行折叠为空格、标题输入与撤销、切换记录和重启保留；正文修改不改标题、摘要包含正文首行、搜索匹配标题与正文；旧记录迁移不删正文；导入以文件名命名、导出内容不附加标题 |
| 存储 | 隔离目录的重启恢复、旧文本迁移、损坏富文本保护、写失败后重试；不得破坏真实用户数据 |
| 导航 / 窗口 | 新建、搜索、切换记录、焦点、右侧滚动条、窄窗口；修改前后的实际 App 对比 |
| 无障碍 / 移动端 | VoiceOver、字号、对比度、减少透明度 / 动态效果；触控光标与选择、软键盘、硬件键盘、横竖屏 |

小改动只跑受影响行为和必要构建；失败后补最小回归。测试通过后不无理由重复全部检查。首次平台接入或输入架构变化需扩大矩阵。

## 验收边界

Mac 文字布局调整需检查中文、英文、空段、标题、跨行选择、emoji、代码块首行及表格附件；文字基线和下方段落位置应保持不变。几何回归与实际 App 截图分别记录，原生光标与选区几何通过 TextKit API 检查，并在 App 中验证焦点、移动和闪烁，不用自定义绘制辅助函数作为验收依据。

没有操作证据的项目写“待验证”；模拟器编译不等于模拟器运行，更不等于真机通过。单元测试对 marked text 的布尔保护不等于真实中文输入法通过。截图不等于撤销、保存或选择行为通过。

当前没有 CloudKit。将来同步验收必须覆盖离线修改、不同设备冲突、账号与配额问题、恢复与重试，并记录真实多设备证据。同步不替代备份。

## 持续集成

`.github/workflows/ci.yml` 在每次 PR、main 推送及手动触发时运行，采用 GitHub `macos-26` 镜像和 Xcode 26.2。工具链变更需重新核对覆盖率和 UI 基线；镜像清单见 [GitHub runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)。

- `Unit tests and coverage`：运行 Swift 测试与 Python 覆盖率门禁自身测试，保留日志、LLVM JSON 和 Markdown 汇总。
- `UI tests (macOS)` / `UI tests (iOS)`：运行 `WeaveUITests`，保存 `.xcresult`（包含截图）和日志。iOS 自动选择可用的 iOS 26 及以上 iPhone 模拟器，不绑死设备 UUID。
- `CI required`：汇总检查；上游失败、取消或跳过都不能通过。仓库分支保护需要将此检查设为必需；仅添加 YAML 不会自动修改 GitHub 分支保护。

本地单测和门禁：

```sh
swift format lint --recursive --strict --configuration .swift-format Sources Tests UITests Package.swift
swift test --enable-code-coverage
python3 scripts/check_coverage.py "$(swift test --show-codecov-path)"
python3 -m unittest discover -s scripts -p 'test_*.py'
```

行覆盖率下限在 `scripts/check_coverage.py` 集中定义：核心逻辑 90%、原生桥接 55%、全源码 35%。UI 组包含 App 入口、WorkspaceView 和 NativeTableView；桥接组包含 NativeRichTextEditor、NativeTextAttributes 与 NativeTableOverlay。核心包含除这两组以外的全部 Swift 文件，新增文件默认纳入；所有文件都计入全源码。报告缺失、源码缺项、重复条目或非法计数直接失败。门槛基于起步实测，不能把全源码 35% 描述成全项目 90%；后续扩大测试后应提高门槛，不因失败自动降低。

当前覆盖率来自单测，不混入 UI 执行数据；不提供分支覆盖率或新增行覆盖率门禁。UI 测试通过是独立检查，也不等于截图像素回归通过。

本地 UI 测试：

```sh
xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/ui-macos -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
xcodebuild -project Weave.xcodeproj -scheme Weave -destination "platform=iOS Simulator,id=$(python3 scripts/select_simulator.py)" -derivedDataPath .build/ui-ios -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
```

添加 `-resultBundlePath` 可保存到尚不存在的 `.xcresult` 路径。Mac UI 测试需要可用桌面与测试自动化权限，会操作测试 App。CI 使用临时宿主；本地不在操作其他 App 时混跑 UI 测试。

每个 UI 测试通过 Debug 专用 `WEAVE_UI_TEST_SESSION` UUID 使用独立的 Application Support/WeaveUITests 子目录；重启同一测试继续读取相同数据，不使用或清理真实 Weave/notes.json。Release 不读取该变量。测试以稳定 accessibilityIdentifier 查找控件；Mac 小屏幕会把工具栏动作收进溢出菜单，首次新建通过空状态主按钮完成，不假设工具栏动作始终可见。截图和文本断言只证明所覆盖场景；真实中文候选、富文本视觉和触控仍按上面的矩阵验证。
