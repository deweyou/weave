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
