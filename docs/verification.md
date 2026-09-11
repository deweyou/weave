# 验证与证据

从工作区根目录运行。按实际改动选择检查，结果注明提交 / 差异、平台、命令、退出码及未验证项；不要长期写死测试数量。

## 自动检查

| 影响范围 | 命令 / 检查 | 能证明什么 |
| --- | --- | --- |
| Swift 行为 / 数据修改 | `swift test` | 现有测试覆盖的规则、存储与桥接行为 |
| Mac 代码与共享代码 | `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build` | Mac target 编译 |
| iOS 代码与共享代码 | `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build` | iOS Simulator target 编译 |
| 文档 / 配置 | 本地链接、入口、源码一致性；Harness `config_inspect` | 文档和配置有效，不证明 App 行为 |
| 交付差异 | `git diff --check`；暂存后 `git diff --cached --check` | 空白与差异检查，未跟踪文件需另查 |

首次使用需 Xcode / Swift 6.2 兼容工具链。沙箱中的宏插件或编译缓存权限失败属于环境问题；明确报告并走宿主授权，不把关闭沙箱作为仓库默认命令。日志和构建产物放 `.build/` 或任务临时目录，Run 中按需记录 Evidence。

## 手动操作矩阵

| 改动 | 必测场景 |
| --- | --- |
| 输入 / 快捷语法 | 中文拼音组合与候选确认、emoji、选区替换；`正文**加粗**` 紧贴文字、转义星号、代码内字面量；多字符粘贴 |
| 字体 / 段落 | 空行光标高度、标题回车恢复正文；选中半段应用标题；格式后继续输入；切换记录不放大字号 |
| 列表 / 待办 | 有序与无序续写、空行退出、前缀退格、Tab / Shift-Tab；点击勾选、拖选与撤销 |
| 代码 / 引用 | 行内代码与连续多行表面、空行退出、边界插入、跨块选区；滚动、窄窗口与深色 |
| 链接 | 选中文字粘贴 URL、Cmd-K、编辑 / 移除链接、标签保持、撤销 |
| 存储 | 隔离目录的重启恢复、旧文本迁移、损坏富文本保护、写失败后重试；不得破坏真实用户数据 |
| 导航 / 窗口 | 新建、搜索、切换记录、焦点、右侧滚动条、窄窗口；修改前后的实际 App 对比 |
| 无障碍 / 移动端 | VoiceOver、字号、对比度、减少透明度 / 动态效果；触控光标与选择、软键盘、硬件键盘、横竖屏 |

小改动只跑受影响行为和必要构建；失败后补最小回归。测试通过后不无理由重复全部检查。首次平台接入或输入架构变化需扩大矩阵。

## 验收边界

没有操作证据的项目写“待验证”；模拟器编译不等于模拟器运行，更不等于真机通过。单元测试对 marked text 的布尔保护不等于真实中文输入法通过。截图不等于撤销、保存或选择行为通过。

当前没有 CloudKit。将来同步验收必须覆盖离线修改、不同设备冲突、账号与配额问题、恢复与重试，并记录真实多设备证据。同步不替代备份。

## 持续集成

`.github/workflows/ci.yml` 在每次 PR、main 推送及手动触发时运行，采用 GitHub `macos-26` 镜像和 Xcode 26.2。工具链变更需重新核对覆盖率和 UI 基线；镜像清单见 [GitHub runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)。

- `Unit tests and coverage`：运行 Swift 测试与 Python 覆盖率门禁自身测试，保留日志、LLVM JSON 和 Markdown 汇总。
- `UI tests (macOS)` / `UI tests (iOS)`：运行 `WeaveUITests`，保存 `.xcresult`（包含截图）和日志。iOS 自动选择可用的 iOS 26 及以上 iPhone 模拟器，不绑死设备 UUID。
- `CI required`：汇总检查；上游失败、取消或跳过都不能通过。仓库分支保护需要将此检查设为必需；仅添加 YAML 不会自动修改 GitHub 分支保护。

本地单测和门禁：

```sh
swift test --enable-code-coverage
python3 scripts/check_coverage.py "$(swift test --show-codecov-path)"
python3 -m unittest discover -s scripts -p 'test_*.py'
```

行覆盖率下限在 `scripts/check_coverage.py` 集中定义：核心逻辑 90%、原生桥接 55%、全源码 35%。核心包含除了 App 入口、SwiftUI 界面和原生桥接以外的全部 Swift 文件，新增文件默认纳入；所有文件都计入全源码。报告缺失、源码缺项、重复条目或非法计数直接失败。门槛基于起步实测，不能把全源码 35% 描述成全项目 90%；后续扩大测试后应提高门槛，不因失败自动降低。

当前覆盖率来自单测，不混入 UI 执行数据；不提供分支覆盖率或新增行覆盖率门禁。UI 测试通过是独立检查，也不等于截图像素回归通过。

本地 UI 测试：

```sh
xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/ui-macos -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
xcodebuild -project Weave.xcodeproj -scheme Weave -destination "platform=iOS Simulator,id=$(python3 scripts/select_simulator.py)" -derivedDataPath .build/ui-ios -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO test
```

添加 `-resultBundlePath` 可保存到尚不存在的 `.xcresult` 路径。Mac UI 测试需要可用桌面与测试自动化权限，会操作测试 App。CI 使用临时宿主；本地不在操作其他 App 时混跑 UI 测试。

每个 UI 测试通过 Debug 专用 `WEAVE_UI_TEST_SESSION` UUID 使用独立的 Application Support/WeaveUITests 子目录；重启同一测试继续读取相同数据，不使用或清理真实 Weave/notes.json。Release 不读取该变量。测试以稳定 accessibilityIdentifier 查找控件，截图和文本断言只证明所覆盖场景；真实中文候选、富文本视觉和触控仍按上面的矩阵验证。
