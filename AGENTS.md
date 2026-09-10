# Weave

请用中文与用户沟通。

Weave 是面向 macOS、iPadOS、iOS 的原生个人工作空间，连接记录、写作与待办。第一期为本地基础富文本编辑器；CloudKit、待办和画板尚未实现。

## 工作约定

- 使用 Swift 和 Apple 原生 UI 技术，保持单仓库。按实际代码边界组织工程，不预建空应用或共享包。
- 区分已确认决策、提案和待验证技术，不把计划写成现状。
- 用户显式调用 Deweyou Harness 时，按其技能管理 Run、计划、证据和验收；配置在 `harness.yaml`。不自动启用未被调用的工作流。
- Harness 运行状态存放在用户级目录，不提交到仓库。
- 共享领域模型和编辑命令，分别适配平台窗口、导航与输入。
- 本地保存与云端同步分离；未上传内容不得作为缓存清理；同步不替代备份。
- 验证覆盖中文输入法、撤销、离线保存、冲突与恢复。没有真实多设备证据，不宣称同步通过。
- 提交、推送、发布与测试状态分别报告。

## 阅读入口

- 产品边界：[docs/product.md](docs/product.md)
- 架构与未决项：[docs/architecture.md](docs/architecture.md)
- 设计原则：[DESIGN.md](DESIGN.md)
- 第一版流程提案：[docs/specs/first-release.md](docs/specs/first-release.md)

## 当前工程与验证

- `Sources/Weave`：SwiftUI 界面和本地记录存储；`Tests/WeaveTests`：存储行为测试。
- `Weave.xcodeproj`：共享 macOS / iOS App target，最低系统版本均为 26。
- `swift test`：本地存储测试；`open Weave.xcodeproj`：用 Xcode 选择平台运行。
- `xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build`：本机未签名构建。
- `git diff --check` 与 Harness `config_inspect`：差异和配置验证。
- 真机运行需配置开发团队。不得把模拟器编译通过报告为真机、输入法或同步验收通过。
