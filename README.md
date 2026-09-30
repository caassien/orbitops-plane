# OrbitOps Plane

OrbitOps Plane 是一个使用 MoonBit 构建的、与平台无关的变更决策内核，不是另一套运维平台。宿主系统提供期望状态、观测状态、资源依赖和安全策略，内核输出确定性的变更计划、审批要求、可执行批次和审计事件。

项目将决策与执行解耦：核心负责差异识别、依赖排序、风险分级、变更预算、过期状态保护和审计；SSH、Kubernetes、云 API、节点代理等真实副作用继续由宿主执行。因此它可作为 MoonFlow、LunaNexa 或其他控制面的窄内核，而不是与这些产品争夺控制器、调度器、API 和持久化层的职责。

## 具体问题与价值

在 MoonBit 中构建部署或运维工具时，每个宿主都需要重复实现同一组容易出错的规则：期望状态与观测状态如何比较、依赖资源怎样排序、哪些操作必须审批、批量操作怎样限流、旧计划或重复反馈如何拒绝、审计事件怎样稳定重放。直接把这些逻辑写进 Kubernetes 适配器或远程 Agent，会造成难以单元测试、不同平台行为不一致、执行前缺少统一保护等问题。

OrbitOps Plane 把这些规则收敛为无网络、无凭据、无持久化依赖的纯 MoonBit 库。宿主在一个进程内完成以下流水线：

```text
DesiredState + ObservedState + dependencies + SafetyPolicy
  -> compute_diff
  -> build_ordered_plan
  -> batch_plan
  -> evaluate_reconciliation
  -> approve / begin_execution
  -> ExecutionResult feedback
  -> replayable audit events
```

## 核心目标

- 相同输入产生相同计划，重复调和不生成多余动作。
- 依赖资源先于其消费者变更，循环依赖在执行前被拒绝。
- 删除、批量重启等高风险动作必须通过安全策略和审批。
- 过期观测状态或失效计划不能进入执行阶段。
- 每次允许、拒绝、审批和执行反馈都形成可追溯审计事件。
- 执行器只返回结构化反馈，不把平台凭据、网络重试或服务发现耦合进核心。

## 三个可验收场景

1. **依赖感知发布**：输入 `database/primary -> service/api -> worker/jobs`，计划必须稳定排序为数据库迁移、API 更新、Worker 扩容，并在单资源批次预算下逐个执行。运行 `moon run cmd/demo -- rollout` 可复现。
2. **配置漂移修复**：期望配置与观测配置不一致时，核心生成最小修复动作；若观测 generation 已过期，则拒绝复用旧计划。运行 `moon run cmd/demo -- drift` 可复现。
3. **故障处置保护**：同一批次出现多个重启、删除或关键资源操作时，核心要求人工审批；执行器报告失败后，后续操作停止并留下终止审计事件。运行 `moon run cmd/demo -- incident` 可复现。

这些场景不依赖真实集群，但每一步都有明确输入、决策、执行反馈和预期状态，可在 CI 中重复验证。

## 项目边界

首个版本专注无副作用的决策内核和模拟执行器，不实现监控平台、远程 Agent、SSH/Kubernetes 客户端、Web 管理后台、任务调度器、持久化数据库或大模型自动执行。真实凭据、网络隔离、执行重试、资源发现和平台级回滚由宿主负责。

## 与现有 MoonBit 项目的边界

| 项目 | 拥有的职责 | OrbitOps Plane 的关系 |
| --- | --- | --- |
| `vectie/lunanexa` | 模型服务与硬件集群产品控制面，包含节点、运行时、部署、API、持久化、控制台和审计 | 不替代 LunaNexa；目标是把“期望状态到变更决策”的纯逻辑抽成可嵌入内核，LunaNexa 等宿主仍负责资源、执行和持久化 |
| `vectie/moonflow` | 持久化工作图、调度、适配器调用、事件流、重试与闭环外部效果 | 不实现调度和 durable execution；OrbitOps 可以向宿主提供确定性的变更批次和策略决定 |
| Kubernetes Controller / Terraform Plan | 面向具体资源 API 的控制器或基础设施执行工具 | 不依赖 Kubernetes 或具体云厂商；提供更小、更通用的 MoonBit 决策原语，便于单元测试和跨平台复用 |

截至 2026-09-30，`moon search orbitops_plane` 未发现同名模块；相邻项目已经存在，因此本项目不声称“生态中没有控制面”，而是明确补齐“平台无关、可嵌入、可重放”的决策内核位置。

## 安装与使用

需要先安装 MoonBit 工具链。源码复现方式：

```bash
git clone https://github.com/caassien/orbitops-plane.git
cd orbitops-plane
moon check --target all --deny-warn
```

发布到 Mooncakes 后，其他 MoonBit 项目可以通过模块名添加依赖：

```bash
moon add caassien/orbitops_plane
```

## 依赖感知发布演示

在仓库根目录运行：

```bash
moon run cmd/demo -- rollout
moon run cmd/demo -- drift
moon run cmd/demo -- incident
```

`rollout` 按“数据库迁移 → API 更新 → Worker 扩容”的依赖顺序生成计划，使用单资源批次和内存执行器完成一次无副作用调和；`drift` 展示自动允许的配置修复以及过期观测拒绝；`incident` 展示高风险审批和指定动作失败后的停止。三个场景都会打印策略决定、执行反馈和审计事件，并使用固定计划标识和固定时钟保持输出可重复。

## 0.1.0 发布准备

当前模块版本为 `0.1.0`，公开接口摘要由 `moon info` 生成并纳入版本控制。本版本已有 72 个测试，覆盖确定性差异计算、依赖排序与循环依赖拒绝、变更预算、安全策略、调和生命周期、过期状态保护、可回放审计，以及内存执行器和三个端到端演示场景。

后续 `0.2.0` 的目标是稳定宿主适配接口、为计划和审计提供可序列化边界、增加输入排列不变性测试，并发布到 mooncakes.io。明确不在该版本内加入服务器、Agent、凭据管理、具体云厂商 SDK、持久化数据库或 UI。

完整的一页申报书见 [`docs/proposal.md`](docs/proposal.md)。

发布前可在仓库根目录运行：

```bash
moon fmt
moon info
git diff --exit-code
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
# 需先登录 Mooncakes
moon publish --dry-run
```

`moon publish --dry-run` 需要先登录 Mooncakes，只检查待发布包内容；正式发布需在确认 GitHub `main` 分支和版本标签后执行。

## 开源与来源

本项目是原创 MoonBit 实现，不移植或复制第三方项目；项目以 Apache-2.0 许可证发布。

## 本地质量检查

CI 会在推送到 `main`、针对 `main` 创建或更新 Pull Request 时执行以下门禁；提交前可在仓库根目录复现：

```bash
moon fmt --check
moon info
git diff --exit-code
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

## 项目信息

- MoonBit 模块：`caassien/orbitops_plane`
- GitHub：<https://github.com/caassien/orbitops-plane>
- 许可证：Apache-2.0
