# OrbitOps Plane 项目申报书

## 基本信息

- **项目名称**：OrbitOps Plane——可嵌入的资源变更计划验证与安全决策库
- **作者**：GitHub `caassien`；联系邮箱 `3501146946@qq.com`
- **仓库**：<https://github.com/caassien/orbitops-plane>
- **实现与许可证**：原创 MoonBit 实现，Apache-2.0；直接依赖的 `cxh04/kubemoon@0.1.1` 也为 Apache-2.0

## 要解决的具体问题

多服务发布中，数据库配置、API 版本和 Worker 副本数可能同时变化。单资源 diff 只能说明“各自需要更新”，不能证明数据库成功后才更新 API、API 成功后才扩容 Worker；观察快照变化时，未执行动作也不能沿用旧计划。已有运维宿主需要一个**不接管采集和执行**的内核，把整组资源状态编译成可审查的变更计划，并在每次派发前给出明确的有效、违规或过期判断。

输入是期望状态、带代数的观测快照、资源依赖、批次预算、安全策略、审批状态及已收到的执行反馈。输出包括确定性动作与批次、`Valid / Invalid / Stale` 结果、逐项违规、风险解释、计划差异和新快照下的剩余动作。宿主负责观察来源、真实写入、最终并发控制、审批身份和持久化。

## 对初审重叠意见的回应

对 [KubeMoon 的源码、公开 API 和测试](ecosystem-differentiation.md) 逐项审计后，确认它已有 Kubernetes 动态客户端、LIST/WATCH、工作队列、重试、ConfigMirror 控制器，以及 ConfigMap 内容比较和 `resourceVersion` 保护。OrbitOps 不把这些能力再做一遍，也不把“单资源字段比较”作为独有贡献。

本项目当前可独立复用的职责是**跨资源计划与执行前安全验证**：在宿主提供的完整状态集上排序依赖、隔离冲突批次、检查预算与审批、拒绝旧快照和缺失前置反馈，并对部分执行后的新观察重新规划。KubeMoon 示例直接使用其公开 `DynamicObject` 与 `content_hash`，把对象状态交给 OrbitOps，决策结果回到模拟宿主；未复制 KubeMoon 的控制器、队列或 WATCH。两项目的差别只按已核对版本和实际演示陈述，不声称“全生态唯一”或“优于 KubeMoon”。

MoonFlow、LunaNexa 是潜在宿主或相邻项目；本次没有完成它们的直接依赖集成，不把它们的调度、运行时或持久化能力计入本项目交付。

## 已完成的可验收案例

1. **依赖感知发布**：数据库→API→Worker 的动作被稳定排序；前置成功缺失或批次顺序被篡改时，验证器返回具体违规。`resource_plan_test.mbt`、`validation_test.mbt` 与 `cmd/demo/rollout.mbt` 覆盖规划及派发前提。
2. **KubeMoon 边界集成**：直接依赖 `cxh04/kubemoon@0.1.1` 的 native 示例把两个测试 ConfigMap 转换为计划输入，得到 `initial=valid stale=stale remaining=1`；第一次动作反馈成功后，新快照使旧计划失效，只重算一个未收敛资源。`examples/kubemoon_bridge/main_wbtest.mbt` 验证结果。示例没有连接真实集群。
3. **跨平台复用**：独立 `moon.mod` 的 `examples/external_consumer` 用同一公开 API 分别验证多服务发布和本地配置文件变更，无 Kubernetes 导入；`main_wbtest.mbt` 验证两个场景。
4. **可解释决策**：`explanation_test.mbt` 验证动作变化字段名、依赖、快照前提及 JSON 输出；`validation_test.mbt` 覆盖过期、未知资源、审批、重复或失败反馈、输入排列与批次篡改。解释只包含字段名，不包含配置值或凭据。

## 技术边界与交付证据

公开 API 以 `pkg.generated.mbti` 为准；详细语义见 `docs/plan-validation.md`，KubeMoon 转换与版本不兼容点见 `docs/kubemoon-integration.md`，全目标检查、测试及发布预检见 `docs/verification-report.md`。项目仍是库与测试示例，不提供 Kubernetes Client、Controller Manager、工作流调度器、服务端、远程执行器或数据库。

当前的 `ObservationSnapshot.generation` 是宿主分配的整数，不等于 Kubernetes 不透明字符串 `resourceVersion`；快照完整性由宿主保证。审批状态是决策输入，不是身份认证。审计可在内存中重放状态，尚无持久化与完整消息恢复。独立消费示例只验证本地工作区引用；OrbitOps 还未发布到 Mooncakes，不能宣称注册表安装通过。以上限制明确列入后续真实宿主接入的验收条件。

## 复现方式

在仓库根目录运行 `moon check --target all --deny-warn`、`moon build --target all --deny-warn` 和 `moon test --target all --deny-warn`；再运行 `moon run --target native examples/kubemoon_bridge`。进入 `examples/external_consumer` 运行 `moon run .` 可查看两个无 Kubernetes 场景。没有性能或生产集群效果声明，所有结果均以源码、测试和验证报告为准。
