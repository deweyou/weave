# 开发与 Harness

## 日常工作

1. 从用户问题、截图或代码复现开始，明确范围与可观察的验收结果。
2. 读取相关知识；UI 任务先按 DESIGN 适配设计 skills。简单修复直接实现，涉及产品取舍才先收敛方案。
3. 实现最小闭环，维护对应知识；按照验证清单执行受影响检查，UI 变化查看实际 App。
4. 区分完成、验证与交付。外部交付按当前授权执行，不能因为节点存在就自动提交、推送或合并。

## Harness 配置与运行

`harness.yaml` 是能力目录，不是固定流程。配置维护可单独完成；只有显式 `/harness-work`、`$harness-work` 或插件选择才启动 Harness 运行。运行时以安装版 skill 为准。

新任务在实际修改前按配置准备工作区；已有 Run 恢复其原工作区。创建 Commitment 时记录目标、范围、验收 Claims、授权与交付目的地；按任务选择节点并建立依赖，不强制经过每一个节点。

Context 对整个 Run 激活；Skills 在节点分派时激活。配置与资源会在 Run 中冻结，修改仓库配置不会自动更新旧 Run。不要手改用户级 Run 状态来让 Dashboard 显示通过。

## 可复用计划示例

下面是选择建议，依赖属于具体 Run 的 Plan，不能复制成 YAML 中的固定阶段：

| 任务 | 常见节点顺序 |
| --- | --- |
| 编辑器小修复 | editor-implement → swift-tests → coverage-check、受影响平台 build / UI tests → interaction-review → repository-review |
| 文档视觉优化 | design-review → editor-implement → 受影响测试 / build → interaction-review → repository-review |
| 新能力或重大取舍 | scope-design → design-review（有 UI 时）→ editor-implement → 自动与交互验证 → repository-review |
| 知识 / 配置维护 | repository-update → config-review（配置变更时）、repository-review |
| 用户要求提交或 PR | 已有有效验证 → commit-local → pull-request（用户要求时） |

如果任务只是复核、文档或配置，不跑不相关的 App 构建。若代码已在任务开始前完成，复用当前差异的有效证据，不从头重做发现和设计。发现问题，只追加受影响修复和验证节点。

## 节点结果与验收

- `scope-design` 产出范围、可观察场景和未决项；复杂任务可以发布 Spec Export。
- 审核产出具体问题、证据与严重性；无问题也要说明检查范围，不能只有“通过”。
- 命令节点由宿主执行冻结的 command，保留退出码与日志 Evidence；节点成功不能自动满足所有 Claim。
- 交互验收记录平台 / App 构建、操作步骤、实际结果、截图或观察与未测项，绑定受影响 Claim。
- 完成前核对当前承诺、目的地、验收和执行状态。开放问题未经有效授权豁免，不能把 Run 标成完成。
- 配置中的 authority 是最低授权语义，不是用户授权本身；必须与本次任务的授权记录核对。

## 知识维护与交付

维护入口见[知识索引](index.md)。把可复用事实更新到对应文档，避免在 AGENTS 重复整份架构、在 DESIGN 堆历史修复日志。保留第三方 skill 原文，项目适配约束放在 DESIGN 和 AGENTS。

提交前检查完整差异（包括新增文件和删除），用户真实数据、日志、构建产物和 Run 状态不得进入提交。PR 描述面向没有读过对话的评审者，写清问题、最终行为、验证与限制；修改范围变了就重写描述。

使用 GitHub plugin 核对仓库、权限和已有 PR，Git 推送已授权分支，plugin 创建 / 更新 PR。保留已确认的分支和目标，不因为 CLI 未登录要求重复授权。若自动审批拒绝，提供新的可信证据或明确询问用户，不能换工具绕过。

当前配置不包含合并、发布或持续监控节点，这些不是提交 / PR 的隐含动作。

CI 定义在 `.github/workflows/ci.yml`。带覆盖率的单测必须先完成，才能执行 coverage-check；UI 节点可独立运行。任务中新增 CI 不代表 GitHub 已运行或分支保护已启用，交付时分别记录本地测试、远端工作流和合并门禁状态。
