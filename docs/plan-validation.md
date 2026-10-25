# 计划验证与 JSON 边界

OrbitOps Plane 的公开入口是 [`build_resource_plan`](../resource_plan.mbt)、[`validate_change_plan`](../validation.mbt)、[`explain_change_plan`](../explanation.mbt)、[`compare_change_plans`](../explanation.mbt) 和 [`replan_remaining`](../resource_plan.mbt)。公开签名以 [`pkg.generated.mbti`](../pkg.generated.mbti) 为准。库只作内存计算；状态采集、审批身份、派发、持久化和实际副作用由宿主负责。

## 验证输入和结果

`PlanValidationInput` 包含计划、期望状态、`ObservationSnapshot`、依赖边、批次预算、策略、审批状态、已接收的执行反馈和下一动作的零基 `dispatch_index`。依赖边采用 `(dependency, dependent)`。快照同时提供 `states` 与 `absent`：每个期望资源必须出现在观测列表，或被**显式**标记为缺失；未出现于两者的是未知状态，不能被当作“可创建”。调用方必须保证这些条目来自同一观察批次；类型本身无法向外部系统证明其来源。

`ValidationResult` 返回 `Valid`、`Invalid` 或 `Stale`，以及 `ValidationIssue[]` 和最高风险等级。每条 issue 包含稳定代码、可选资源与动作、风险和说明。检查包括：计划与当前差异是否一致、依赖和跨批次顺序、并发与资源预算、策略和审批、反馈的计划 ID/顺序/重复、前置成功条件及快照代数。任何全局快照代数变化都保守地返回 `Stale`，包括看似不相关的资源变化；宿主必须重新规划，不能静默沿用旧动作。失败或跳过的反馈也要求新计划。

验证器可独立于执行器调用。它会汇集多个发现的违规，但 `Stale` 优先于 `Invalid`；调用方仍应读取 `issues`。旧的 `batch_plan` 不接收依赖边，依赖场景应使用 `build_resource_plan` 或 `batch_plan_with_dependencies`。`ObservationSnapshot.generation` 是宿主分配的整数批次代数；它**不是** Kubernetes 的不透明 `resourceVersion`，二者不能直接互转。

## 解释与计划比较

`explain_change_plan` 为动作列出变化的**字段名**、直接前置资源、快照代数、策略决定和风险。字段值和调用方可填写的 `Operation.reason` 不进入解释/比较 JSON；先调用 `validate_change_plan`，再把解释标为“可派发”。`PlanExplanation::to_json` 和 `ActionExplanation::to_json` 提供 JSON 值。`compare_change_plans` 报告新增、删除、修改、零基索引变化、动作风险变化及基线代数变化；`PlanComparison::to_json` 可用于 UI 或日志。索引变化表示同一资源在两个计划数组中的位置不同，新增动作也可能使后续索引变化。

## JSON 输入输出约定

公开 API 接受 MoonBit 类型，**尚未提供通用 `PlanValidationInput` JSON 反序列化器**。宿主可按下列字段构造类型；以下 JSON 是边界格式说明，不是声称库可直接解析的网络协议：

```json
{
  "plan_id": "release-1",
  "baseline_generation": 4,
  "snapshot": {"generation": 4, "states": ["host-mapped ObservedState"], "absent": []},
  "desired": ["host-mapped DesiredState"],
  "dependencies": [["database/primary", "service/api"]],
  "budget": {"max_parallel": 2, "max_affected_resources": 2, "isolate_high_risk": false},
  "approval": "not_required",
  "feedback": [],
  "dispatch_index": 0
}
```

实际已实现的输出可由 `ValidationResult::to_json().stringify()` 取得，例如：

```json
{"status":"stale","risk":"unknown","issues":[{"code":"stale_snapshot","resource":null,"action":null,"risk":"unknown","explanation":"snapshot generation differs from the plan baseline; replan even if the change seems unrelated"}]}
```

输出的 `status` 为 `valid|invalid|stale`，风险为 `low|medium|high|unknown`；issue 的 `resource` 为 `{kind,name}` 或 `null`，`action` 为动作名或 `null`。解释与比较 JSON 的实际字段由 [`explanation.mbt`](../explanation.mbt) 的 `to_json` 方法定义，测试见 [`explanation_test.mbt`](../explanation_test.mbt) 和 [`validation_test.mbt`](../validation_test.mbt)。不应把原始配置、生产凭据或完整 Kubernetes 对象写入审计或解释。

## 可嵌入性验证

[`examples/external_consumer`](../examples/external_consumer/) 是独立 `moon.mod` 的 MoonBit 模块，用 `moon.work` 在本地引用当前源码。它用同一个 `build_resource_plan` → `validate_change_plan` API 验证多服务发布和本地配置文件变更；没有导入 Kubernetes 包。运行 `moon run .` 和 `moon test --deny-warn` 时，工作目录设为该示例目录。模块尚未发布到 Mooncakes，故此例**只证明本地工作区的外部模块调用**，不证明从注册表安装成功。
