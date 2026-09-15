# Weave

用中文沟通。Weave 是面向 macOS、iPadOS、iOS 的原生个人工作空间，第一期为本地富文本编辑器。CloudKit、独立待办模型和画板是后续方向；可勾选文本标记已经实现。

## 开始工作

先读 [知识索引](docs/index.md)，按任务读取对应资料；以当前源码为实现事实，以用户确认的产品方向为范围。发现文档过时时随相关修改修正，不能把提案或编译通过写成已实现、已验收。

- [产品边界](docs/product.md)：已确认方向与未决问题。
- [架构](docs/architecture.md)：代码入口、数据边界与限制。
- [设计](DESIGN.md)：原生界面和文档编辑的设计准则。
- [验证](docs/verification.md)：按影响范围选择检查与证据。
- [开发与 Harness](docs/development.md)：任务计划、资源激活、知识维护和交付。

## 实现约定

- Swift / SwiftUI 与 AppKit / UIKit，保持单仓库；只按实际代码边界拆分，不预建空包。
- 保持改动聚焦；共享领域模型和编辑命令，分别适配平台导航、输入与窗口。
- 编辑必须保留中文组合输入、UTF-16 选区、撤销与后续输入属性；排版不能损害光标和选区。
- `Note.richText` 为主数据，纯文本用于搜索与标题。新增持久化属性时检查 `NoteAttributeScope`、平台桥接、旧数据与重启恢复。
- 本地保存与同步分离。未上传内容不能作为缓存清理；同步不替代备份。不用云盘中的 JSON 冒充 CloudKit 同步。
- 新增源码同时核对 Swift Package 与 Xcode target。命令从工作区根目录执行，产物放 `.build/`，不提交用户笔记、账号信息或机器路径。
- App 预览默认复用并激活已有实例，不反复使用 `open -n`。需要加载新构建时，先确认对应测试实例已保存，再正常退出并重启该实例；核对进程路径和隔离会话，不关闭用户正式实例，不使用全局 `killall`。操作后检查实例数量，避免遗留重复 App。

## Swift 规则与 skills

编写或评审 Swift 代码前读取 [Weave Swift 代码规范](.agents/rules/swift-code-style.md)。
它与本文件共同构成仓库约束，并优先于第三方 skill 的通用建议。

- SwiftUI 状态、视图组合、性能、无障碍或 macOS 场景任务使用
  [swiftui-expert-skill](.agents/skills/swiftui-expert-skill/SKILL.md)，只加载与当前任务相关的 reference。
- 涉及 `async`/`await`、actor、`Sendable`、取消或同步/异步桥接时使用
  [swift-concurrency-pro](.agents/skills/swift-concurrency-pro/SKILL.md)。
- 编写或评审 Swift Testing 用例时使用
  [swift-testing-pro](.agents/skills/swift-testing-pro/SKILL.md)；UI tests 继续使用 XCTest。
- AppKit/UIKit 桥接是编辑器的既定边界。第三方 skill 中偏 iOS、纯 SwiftUI 或文件拆分的建议不能覆盖
  当前源码、`DESIGN.md` 和本文件确认的边界。

## 设计 skills 的使用边界

UI 任务使用 [apple-design](.agents/skills/apple-design/SKILL.md)；视觉审核按需加用 [high-end-visual-design](.agents/skills/high-end-visual-design/SKILL.md)。二者包含 Web 专用建议，使用前先读 DESIGN.md 的适配规则。

沿用用户确认的 Apple 原生控件、系统字体、SF Symbols、正文清晰背景和稳定编辑。界面图标默认使用 SF Symbols；例外条件、依赖边界和验收要求见 `DESIGN.md` 的“图标系统”。审美 skill 用于检查层级、留白、材质与反馈，不引入 React/Tailwind、营销页布局、强制入场动画或随机视觉风格；不为满足第三方 skill 更换原生技术路线。

## Harness 与交付

- `harness.yaml` 声明 Context、Skills 和可复用节点；依赖关系属于每次 Run 的 Plan，不是固定流水线。
- 仅用户显式调用 `/harness-work`、`$harness-work` 或选择插件时启动运行流程。配置维护不自动创建 Run；普通修复不自动启用 Harness。
- 按安装版本的 skill 管理工作区、承诺、计划、证据和验收；恢复已有 Run 时使用其工作区和冻结配置，不重复准备。
- Run 状态存放用户级目录。仓库保存可复用知识和验收方法，不保存历史 Run 状态或机器专属日志。
- 只执行本次已授权交付动作。提交、推送、PR、合并、发布分别报告；要求创建 PR 包含推送所需分支，提交本身不包含推送。
- GitHub PR 优先用 GitHub plugin；推送用 Git。先核对远端、目标分支、现有 PR 与差异，不能把工具切换当作绕过审批拒绝的方法。
