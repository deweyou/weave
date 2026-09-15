# Weave Swift 代码规范

本规则适用于仓库内的 Swift、SwiftUI、AppKit 和 UIKit 代码。以
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
为基础；`AGENTS.md`、当前源码边界和产品约束优先于第三方 skill 的通用建议。

## API 与命名

- 让调用点读起来清楚。参数标签表达参数角色，不重复类型信息，不为缩短名字牺牲语义。
- 有副作用的操作使用动词；无副作用的值使用名词或结果描述。布尔值写成可判断的谓词，例如
  `isEmpty`、`hasMarkedText`、`canRetry`。
- 按领域角色命名，避免 `data`、`info`、`manager`、`helper` 等无法说明职责的名字。
- 成对的可变与不可变 API 遵循 Swift 习惯，例如 `sort()` / `sorted()`；工厂方法使用
  `make`，仅在确实产生新实例时使用。
- 文档化跨模块契约、非显然复杂度与平台限制。注释解释原因、兼容约束和取舍，不复述代码。

## 类型、状态与错误

- 默认使用 `struct`、`enum` 和不可变值。只有身份、共享生命周期、框架继承或受控可变状态需要
  引用类型。
- 每份状态有明确所有者。SwiftUI 区分 owned state 与 injected state；不要在 `body` 中创建会改变
  身份的模型或副作用。
- 使用 `guard` 处理前置条件和提前返回。避免强制解包、强制转换和 `try!`；只有由本地不变量证明
  安全时才使用，并让证明在相邻代码中可见。
- 错误在有意义的边界转换，保留可诊断信息。不要用空 `catch`、默认值或日志吞掉保存、迁移和导入错误。

## 并发与平台边界

- UI 状态和 AppKit/UIKit 对象由 `@MainActor` 隔离。跨 actor 传递值时满足 `Sendable`，不要用
  `@unchecked Sendable` 掩盖未证明的线程安全。
- 优先结构化并发并传播取消。`Task {}` 必须有明确生命周期；避免为绕过隔离错误引入
  `Task.detached`、GCD 跳转或 `MainActor.assumeIsolated`。
- GCD、锁和 `MainActor.assumeIsolated` 只用于同步框架回调或底层互操作，并在代码附近说明框架保证。
- SwiftUI 负责声明式界面和状态流；AppKit/UIKit 负责原生文本输入、选区、窗口及平台交互。
  不为满足第三方 skill 把已确认的原生桥接改写成纯 SwiftUI。
- 共享领域模型和编辑命令不依赖平台视图类型；平台适配层负责 UTF-16、组合输入、选区、撤销和输入属性转换。

## 组织与改动

- 一个类型或函数只承担一个清晰职责。复杂视图按真实的状态与刷新边界拆分，不机械执行“一类型一文件”。
- 保持改动聚焦，不把行为修复、目录重排、批量重命名和格式化混在同一差异中。
- 不预建抽象、协议或空包。出现稳定的重复和明确变化边界后再提取复用。
- 新增源码时同时核对 Swift Package 与 Xcode target；使用当前部署目标和工具链可用的 API。

## 测试与验证

- 单元和集成测试使用 Swift Testing；UI 自动化继续使用 XCTest。
- 测试可观察行为和数据契约。修复缺陷时覆盖触发序列、结果与后续输入，不冻结无关实现细节。
- 编辑器用例覆盖中文组合输入、UTF-16 选区、撤销/重做、空段落、文档首尾和格式边界。
- 参数化真正平行的 case；共享 setup 不能隐藏关键操作顺序。
- 按 `docs/verification.md` 运行受影响测试和平台构建。界面或输入行为还需在对应原生 App 中复现验收。
