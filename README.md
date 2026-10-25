# OrbitOps Plane

OrbitOps Plane 是 MoonBit 的**可嵌入资源变更计划验证与安全决策库**。宿主提供整组期望状态、完整观测快照、资源依赖和策略；库计算差异、依赖顺序与批次，验证快照和执行前提，并返回可解释的审批、风险与反馈诊断。真实采集、派发、重试、审批身份及持久化由宿主负责。

## 为什么需要它

一次发布可能同时修改数据库配置、API 版本和 Worker 副本数。逐个资源比较只能得出三条动作，不能保证 API 在数据库成功后执行、Worker 在 API 成功后执行，也不能在观察变化时拒绝旧批次。`build_resource_plan` 把资源状态编译为稳定的依赖计划；`validate_change_plan` 在派发点把计划、快照、预算、审批和反馈放在一起检查，返回 `Valid / Invalid / Stale` 及违规列表。

这项定位依据 [OrbitOps 与 KubeMoon 源码审计](docs/ecosystem-differentiation.md)：KubeMoon 已提供 Kubernetes 动态客户端、LIST/WATCH、队列、重试和 ConfigMirror 控制器，也有 ConfigMap 级差异与版本保护。OrbitOps 的可复用职责是**宿主可调用的跨资源计划及其安全验证**；单资源字段比较和“调和”字样本身不是差异化主张。MoonFlow、LunaNexa 可作为潜在宿主，但本次未验证其集成，不能宣称已有适配器。

## 已实现的公开能力

- `build_resource_plan`：从期望/观测数组生成动作，校验依赖图并排序；删除计划按依赖逆序，传递依赖不能共用批次。
- `validate_change_plan`：独立返回结构化状态、违规列表、资源/动作引用、风险与解释；未知状态不能默认为缺失，任意快照代数变化都保守地使旧计划过期。
- `explain_change_plan` 与 `compare_change_plans`：给出变化字段名、前置资源、审批条件和快照前提；比较动作、顺序、风险及基线代数。结果有 `to_json` 方法，不序列化配置值。
- `replan_remaining`：在部分执行反馈与**新的完整观察**之后，使用新计划 ID 重算仍有差异的动作。
- 审计事件记录和内存重放；不提供审计持久化或完整执行消息恢复。

公开签名见 [`pkg.generated.mbti`](pkg.generated.mbti)，语义及 JSON 边界见 [计划验证文档](docs/plan-validation.md)。`ObservationSnapshot.generation` 由宿主分配；调用方负责证明观察集合完整。当前库不能自行读取最新状态，也不能替代平台在最终写入时的并发控制。

## 运行示例

从仓库根目录运行原有三个模拟场景：

```bash
moon run cmd/demo -- rollout
moon run cmd/demo -- drift
moon run cmd/demo -- incident
```

直接依赖 `cxh04/kubemoon@0.1.1` 的 [边界示例](docs/kubemoon-integration.md) 使用 KubeMoon `DynamicObject` 与 `content_hash` 构造测试输入，演示旧计划过期和剩余动作重算。KubeMoon `configmirror` 仅支持 native，运行：

```bash
moon run --target native examples/kubemoon_bridge
moon test --target native --deny-warn examples/kubemoon_bridge
```

[`examples/external_consumer`](examples/external_consumer/) 是带独立 `moon.mod` 的 MoonBit 消费项目，用同一公开 API 验证多服务发布和本地配置文件变更：

```bash
cd examples/external_consumer
moon run .
moon test --deny-warn
```

本地通过 `moon.work` 连接当前源码。模块**尚未发布到 Mooncakes**，所以该示例不代表注册表安装已经验证。KubeMoon 示例使用模拟宿主，没有连接真实集群或复制其控制器。

## 验证与边界

项目使用 Apache-2.0 许可证；新增的 KubeMoon 依赖也是 Apache-2.0，固定在 `0.1.1`。本仓库没有引入 Kubernetes API Client、LIST/WATCH、工作队列、远程执行器、服务端或数据库。安全验证由宿主在每次派发前调用，并由宿主在真实写入时再次执行平台并发保护；它不是授权系统。

```bash
moon fmt --check
moon info
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

发布预检、测试结果及当前限制见 [验证报告](docs/verification-report.md)。申报材料见 [项目申报书](docs/proposal.md)。
