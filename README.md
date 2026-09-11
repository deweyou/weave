# Weave

面向 Mac、iPad 和 iPhone 的原生个人工作空间。

第一期专注于干净的文本编辑体验：新建记录、列表搜索、原生富文本输入、格式菜单、Markdown 排版、字符统计和本地自动保存。使用 SwiftUI 原生导航与工具栏，采用系统 Liquid Glass 外观，正文保持清晰。

## 开发

要求 Xcode 26.2 或兼容版本，macOS / iOS 26 及以上，无第三方依赖。

打开 `Weave.xcodeproj`，选择 Weave scheme 和目标设备运行。真机需要配置开发团队。

```sh
swift test
xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'platform=macOS' -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build
open .build/xcode/Build/Products/Debug/Weave.app
```

移动端编译检查：

```sh
xcodebuild -project Weave.xcodeproj -scheme Weave -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
```

记录保存在应用容器 Application Support 下的 `Weave/notes.json`，每次修改原子写入。Swift Package 直接运行与 Xcode App 的存储位置可能因沙箱不同而不同；日常体验请运行 Xcode 构建的 App。
文件损坏时暂停编辑，保存失败时保留当前进程内的内容并显示重试；未保存成功前不要退出应用。

## 富文本与 Markdown

格式菜单提供加粗、斜体、下划线、删除线、标题与等宽字体，作用于选区或后续输入。Mac 支持 Command-B / I / U。
输入 Markdown 后，从 Markdown 菜单选择排版选区或全文，可撤销；常用语法也支持输入时自动转换。
支持标题、加粗、斜体、删除线、链接、行内/围栏代码、列表、引用和勾选标记。列表为文本标记，支持续写、空行退出、Mac 基本缩进和点击勾选，尚无完整嵌套结构或独立待办模型；表格和图片不在本期范围。排版会替换 Markdown 源文，也会重置所选范围既有样式，不提供无损 Markdown 往返。
旧纯文本 JSON 可直接读取，首次编辑保存增加富文本字段。格式使用包含 SwiftUI、代码与段落角色的属性范围编码，保留原正文投影用于搜索。

## 边界

目前支持基础富文本，尚无删除、CloudKit 同步、独立待办模型或画板。保存采用简单 JSON 全量写入，适合本期小规模文本验证；大规模数据与同步接入前需要重新验证存储性能和迁移策略。

- [本期规格](docs/specs/first-release.md)
- [产品方向](docs/product.md)
- [当前架构](docs/architecture.md)
- [设计原则](DESIGN.md)
- [开发约定](AGENTS.md)

_Last updated: 2026-09-10 — 实现第一期本地原生文本编辑器。_

Markdown 快捷输入：行首 `#` 至 `######`、`-` / `*` / `+`、`>` 加空格；行内 `**加粗**`、`*斜体*`、反引号代码闭合后自动转换。支持有序列表和待办快捷输入，以及三个反引号加回车进入代码块。标题回车恢复正文，列表回车续写、空行退出；macOS 列表支持 Tab / Shift-Tab 缩进。代码块空行回车退出。选中文字粘贴 URL 添加链接，Cmd-K 打开链接编辑。待办标记可点击切换并撤销。多字符 Markdown 粘贴仍需手动转换。

## 项目协作

从[知识索引](docs/index.md)进入项目；验证方法见[验证清单](docs/verification.md)，Harness 能力目录与任务计划方式见[开发流程](docs/development.md)。配置维护不自动创建 Run；运行任务时显式调用 `/harness-work`。
