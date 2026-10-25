# OrbitOps Plane 差异化重构验证报告

验证日期：2026-10-26。工具链：`moon 0.1.20260920`、`moonc v0.10.14`。本报告记录本地实际执行结果，不把本地模拟当作生产集群验证。

## 增量与提交

| 阶段 | Commit ID | 实际交付 | 当次验证 |
| --- | --- | --- | --- |
| 一：生态审计 | `b3de24a` | `docs/ecosystem-differentiation.md`，按源码与测试区分 KubeMoon/OrbitOps 能力 | 文档差异及链接检查通过；未改可执行代码 |
| 三：计划验证 | `b135833` | `ValidationResult`、违规列表、快照前提、独立验证入口与黑盒测试 | `moon fmt`、`moon check --deny-warn`、根包 71/71 测试、`moon info` 通过 |
| 四：解释和比较 | `80bdaca` | 动作解释、计划比较与 JSON 输出 | `moon fmt`、`moon check --deny-warn`、根包 74/74 测试、`moon info` 通过 |
| 五：KubeMoon 边界示例 | `505596a` | 直接依赖 `cxh04/kubemoon@0.1.1` 的 native 适配示例与测试 | 示例 2/2；`moon check --target all --deny-warn`；全目标测试 89/89（wasm、wasm-gc、js）及 91/91（native）；运行输出 `initial=valid stale=stale remaining=1` |
| 六：独立消费 | `b2e028a` | 独立 MoonBit 模块、两个无 Kubernetes 场景及验证结果 JSON | 工作区全目标检查；91/91（wasm、wasm-gc、js）及 93/93（native）；消费示例输出两项 `valid=true` |

阶段二的定位体现在新增验证入口及 README/申报书的职责边界；阶段七的文档和最终检查由本次文档提交交付。

## 最终复现结果

| 命令 | 结果 |
| --- | --- |
| `moon fmt --check` | 通过 |
| `moon info` | 通过，生成的 `.mbti` 已核对并提交 |
| `moon check --target all --deny-warn` | 通过 |
| `moon build --target all --deny-warn` | 通过 |
| `moon test --target all --deny-warn` | wasm 93/93、wasm-gc 93/93、js 93/93、native 95/95；最终增补预算超限与显式缺失资源用例 |
| `moon run --target native examples/kubemoon_bridge` | `initial=valid stale=stale remaining=1` |
| 在 `examples/external_consumer` 执行 `moon run .` | `release_actions=2 release_valid=true`；`config_actions=1 config_valid=true` |
| `moon publish --dry-run` | **未通过预检**：本机缺少 `C:\Users\li135\.moon\credentials.json`，工具要求先登录；没有执行实际发布 |

## 已核对的发布边界

- 根模块 `caassien/orbitops_plane` 当前版本仍为 `0.1.0`，仓库、README、描述和关键词已与“计划验证与安全决策库”定位对齐；`LICENSE` 与 `moon.mod` 均标注 Apache-2.0。
- KubeMoon 直接依赖固定为 `0.1.1`，Mooncakes 元数据显示其为 Apache-2.0；其 `configmirror` 包只支持 native，因此该示例声明 native。核心库及两个无 Kubernetes 用例已通过四个后端检查与测试。
- 实际注册表发布、空白项目从 Mooncakes 安装、真实 Kubernetes 集群调用和生产审批/执行链路**尚未验证**。发布前仍需作者登录 Mooncakes 并重新运行 `moon publish --dry-run`；正式发布、标签和版本策略由作者确认。
- 快照完整性与递增代数由宿主保证；KubeMoon 的不透明 `resourceVersion` 不能直接当作 OrbitOps 的整数代数。验证 API 返回安全决策，不替代 Kubernetes 写入时的并发检查，也不提供审计持久化。
