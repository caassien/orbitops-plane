# KubeMoon 边界集成示例

此示例是带独立 [`moon.mod`](../examples/kubemoon_bridge/moon.mod) 的 MoonBit 模块，直接依赖 `cxh04/kubemoon@0.1.1`（Apache-2.0）；KubeMoon 的 `configmirror` 包声明 `supported_targets = "native"`，因此示例只在 native 目标构建。OrbitOps [核心模块](../moon.mod) 不依赖 KubeMoon；未复制它的控制器、队列、WATCH 或 HTTP 实现。

## 使用的真实公开 API

示例接受 KubeMoon 的 [`DynamicObject`](https://github.com/cxh04/KubeMoon/blob/16171c3898db8bbc66f04f801eb114b68626a085/object/object.mbt#L37-L93)，调用 `name()`、`namespace_name()` 与 [`configmirror.content_hash()`](https://github.com/cxh04/KubeMoon/blob/16171c3898db8bbc66f04f801eb114b68626a085/configmirror/content.mbt#L53-L73)。它把命名空间与名称合成 OrbitOps 的 `ResourceId`，把 KubeMoon 内容哈希映射到 `ResourceSpec.config_fingerprint`，并明确拒绝没有命名空间的输入。映射不保留任意 Kubernetes JSON 字段，不能用于通用 Kubernetes 对象的无损往返。

KubeMoon 的 `resourceVersion` 是不透明字符串，而当前 OrbitOps `ObservationSnapshot.generation` 是整数。示例由**模拟宿主**给两次完整观察分配递增的 `1`、`2`；没有把 Kubernetes `resourceVersion` 解析为整数，也不宣称已实现生产环境的快照 token 转换。真实宿主需要把采集批次与稳定的快照标识绑定，并在每次派发前提供最新标识；如果不能证明观测集完整，应拒绝执行。参见 [`validation.mbt`](../validation.mbt)。

## 可复现路径

```bash
moon check --target native --deny-warn examples/kubemoon_bridge
moon test --target native --deny-warn examples/kubemoon_bridge
moon run --target native examples/kubemoon_bridge
```

运行结果为 `initial=valid stale=stale remaining=1`：两个模拟 ConfigMap 先产生两条更新动作；模拟宿主反馈第一条成功后，第二次观察使旧计划过期；`replan_remaining` 从新观察只保留尚未收敛的一条动作。[`main_wbtest.mbt`](../examples/kubemoon_bridge/main_wbtest.mbt) 断言了这三个结果及适配拒绝路径。这里不访问真实集群，执行回执也由模拟宿主提供；KubeMoon 仍负责真实资源发现、观察和对象写入。
