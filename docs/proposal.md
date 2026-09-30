# OrbitOps Plane 项目申报书

- 申报人（GitHub 用户名）：[`caassien`](https://github.com/caassien)
- 联系邮箱：`3501146946@qq.com`
- GitHub 仓库：<https://github.com/caassien/orbitops-plane>
- 项目类型：原创 MoonBit 实现
- 开源许可证：Apache-2.0

## 一、项目名称与简介

**OrbitOps Plane：MoonBit 平台无关变更决策内核。**

宿主提供期望状态、观测状态、资源依赖和安全策略，本项目输出确定性的差异动作、依赖有序计划、执行批次、审批要求与可重放审计事件。它是 LunaNexa 等控制面可调用的纯决策函数，不拥有节点、运行时、API、数据库或执行器，也不与 LunaNexa 争夺控制面职责。

## 二、项目方向与通用性

MoonBit 已有 `vectie/lunanexa` 这类产品控制面和 `vectie/moonflow` 这类持久化编排引擎，但缺少可被多个宿主复用的纯变更决策层。各平台重复实现 diff、依赖排序、风险策略、预算和审计会导致行为不一致，且必须依赖真实集群才能测试。本项目补齐“平台无关、可嵌入、可重放”的通用内核位置，不依赖 Kubernetes、SSH、云 API 或特定运维平台。

## 三、预期使用场景

1. **依赖感知发布**：输入 `database/primary -> service/api -> worker/jobs`，必须稳定生成数据库迁移、API 更新、Worker 扩容的依赖顺序，并在单资源批次预算下执行。`moon run cmd/demo -- rollout` 可复现。
2. **配置漂移修复**：比较期望与观测配置，只生成必要动作；观测 generation 落后时，在执行前拒绝旧计划。`moon run cmd/demo -- drift` 可复现。
3. **故障处置保护**：批量重启、删除和关键资源配置为高风险，必须显式审批；执行器失败后停止后续操作并记录终止事件。`moon run cmd/demo -- incident` 可复现。

## 四、核心功能与交付

- 类型安全的资源、状态、操作、计划、审批和执行反馈模型。
- 确定性 `compute_diff`，覆盖创建、更新、扩缩容、重启、删除和未知动作 fail-closed。
- 依赖图校验、循环依赖拒绝、稳定排序和删除反向排序。
- 可解释安全策略、风险分级、关键资源保护、审批状态机和变更预算。
- generation 保护、重复反馈拒绝、调和生命周期和可重放审计。
- 当前 72 个测试、三个端到端示例和 CI；`0.2.0` 完成宿主适配接口、序列化边界并发布 mooncakes.io。

## 五、原创与参考说明

本项目为原创 MoonBit 实现，不移植或复制第三方代码。Kubernetes Controller、Terraform Plan、LunaNexa 和 MoonFlow 仅用于职责边界比较，不存在代码、模型或数据复制。

## 六、边界与 LunaNexa 对比

LunaNexa 负责节点清单、运行时适配、部署放置、回滚、API、持久化和控制台；OrbitOps Plane 只负责“期望状态到变更决策”，执行与真实副作用仍由宿主完成。明确不提供服务器、远程 Agent、SSH/Kubernetes SDK、云 SDK、凭据管理、数据库、UI、监控或大模型自动执行，也不替代 Terraform、Kubernetes Controller、LunaNexa 或 MoonFlow。

## 七、实现理解与验收

计划生成保持纯函数和确定性：输入顺序不能改变结果，独立资源按稳定 key 排序，依赖边采用 `(dependency, dependent)` 语义。执行分为计划、校验、执行、反馈四阶段，执行前再次校验 generation。

验收要求：72 个测试与三个 demo 可复现；不同输入排列产生相同计划；循环依赖、过期计划和重复反馈显式失败；高风险操作无审批不得执行；审计流可重放出相同状态。
