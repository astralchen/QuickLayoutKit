# 原生 Swift Task 严格串行队列

`Demo/Support/Concurrency/SerialTaskQueue.swift` 只管理主 Actor 上任务的执行顺序。初始化后即可添加任务；页面是否接收新请求由功能协调器管理。

## 原生句柄

```swift
let queue = SerialTaskQueue()
let task = queue.addTask(priority: .userInitiated) {
    try await service.refresh()
}

let value = try await task.value
// 也可以使用 await task.result 读取 Result，或 task.cancel() 请求取消。
```

`addTask<Success: Sendable>(id:priority:schedulingPriority:replacementKey:replacementPolicy:operation:)` 立即返回 `Task<Success, Error>`。任务创建后等待内部执行许可，只有当前项能进入 operation。省略新增参数时仍按 FIFO 执行，不替换任务。没有 cleanup、completion 或 Bool 接收结果，也没有回调式添加入口。

- `isRunning` 表示当前执行槽被占用，包含任务收到取消后仍在退出的时间。
- `pendingCount` 表示尚未获得执行许可的任务数量。
- 正常返回或普通失败不调用 cancel，也不在操作返回后把成功改为取消错误。
- 可以重复或由多个观察者等待同一个句柄。丢弃句柄不会取消任务。
- 取消等待 task.value 的另一个 Task，不会自动取消被等待的非结构化 Task。
- 句柄结果可能先于内部观察者更新队列状态被读取；结果已就绪保证操作退出，队列状态在主 Actor 后续调度中更新。

## 调度优先级

```swift
let task = queue.addTask(
    priority: .userInitiated,
    schedulingPriority: .high
) {
    try await service.refresh()
}
```

两个参数分别控制不同层级：

| 参数 | 类型与默认值 | 作用 |
|---|---|---|
| `priority` | `TaskPriority? = nil` | 直接传给 Swift Task，控制执行优先级，不决定等待顺序 |
| `schedulingPriority` | `SerialTaskQueue.SchedulingPriority = .normal` | 等待项按 `.high → .normal → .low` 排序，同级保持 FIFO |

优先级只作用于等待项。任务一旦获得许可就占用当前执行槽，即使其 operation 尚未进入，高优先级任务也不能抢占或重新排序它。没有优先级老化或动态调整；持续提交高优先级任务可能延长低优先级任务的等待。

## 相邻替换

```swift
let first = queue.addTask(
    replacementKey: "message-popup",
    replacementPolicy: .replaceQueuedAndCurrent
) {
    try await presenter.show("消息 A")
}
let latest = queue.addTask(
    replacementKey: "message-popup",
    replacementPolicy: .replaceQueuedAndCurrent
) {
    try await presenter.show("消息 B")
}
let firstResult = await first.result
try await latest.value
```

示例中的 presenter 负责响应 Task 取消、关闭界面，并在清理完成后结束异步等待。队列不持有 UIKit 或消息模型。

替换规则参考 Nirvana 的 UIMessageCenter：先按调度优先级算出插入位置，再只检查该位置的直接前驱。

| `SerialTaskQueue.ReplacementPolicy` | 行为 |
|---|---|
| `.enqueue`（默认） | 正常排队，即使 key 相同也不替换 |
| `.replaceQueued` | 替换插入位置前一个同 key 等待项，新任务占用其位置 |
| `.replaceQueuedAndCurrent` | 先检查等待项；插入位置为队首时，可请求取消同 key 当前项 |

- 新任务的策略决定是否替换，旧任务可以使用默认 `.enqueue`。只有非 nil 且相等的 key 才匹配，不要求调度优先级相同。
- 不搜索更早的同 key 项，不批量删除。同级的“消息 A → 关注 B → 消息 C”，C 不能跨过 B 替换 A。
- 相邻位置以排序结果为准，不是最后提交的位置。例如等待项为“高优先级消息 A、低优先级关注 B”，普通优先级消息 C 可以替换 A，保留 B。
- 当前项被替换时仍占用执行槽，替代项在队首等待其实际退出。之后提交的更高优先级任务仍按排序规则插入，替代项没有保留执行名额。
- 被替换等待项的原生句柄收到取消，并以 CancellationError 结束，操作不会启动。当前项收到取消后仍保留实际返回值或错误，包括主动返回成功的结果。
- 直接取消等待句柄后，其主 Actor 取消处理可能尚未执行；队列在插入或选择下一项前读取原生取消状态并清除这些项，避免干扰相邻判定。

队列先完成替换和插入，再请求旧任务取消。即使业务的同步取消处理重新添加任务或调用 cancelAll，也会看到完整的新状态。内部取消回传及结果观察者按独立身份处理，迟到事件不会清除新任务。

## 严格串行与取消

`task.cancel()`、`queue.cancel(id:)` 和 `queue.cancelAll()` 都只请求取消，不强制结束正在执行的操作。当前操作返回或抛错、包括其 defer 完成之后，队列内部观察者才会释放执行槽。

等待项取消时解除内部等待并抛出 CancellationError，不调用业务操作。`cancelAll()` 取消调用时已有的运行项和等待项，之后仍可添加新任务；新任务继续等待旧运行项实际退出。

队列释放时请求所有任务取消并解除等待项的调度等待。运行项通过自身取消处理退出，可能晚于队列释放。内部任务和结果观察者不强持有队列；业务闭包仍应避免强持有拥有队列的页面。

清理属于操作自身：正常退出使用 defer；SDK 加载、播放等回调接口在适配层使用 withTaskCancellationHandler。onCancel 不保证在 MainActor，UIKit 清理需要切回 MainActor，完成资源清理后再恢复异步等待。忽略取消的任意操作会阻塞队列，这是严格串行的边界。

此规则同样适用于相邻替换：不引入参考旧实现中的 50 毫秒放弃机制，不增加独立取消令牌或替换专用错误。

### 按业务 ID 取消

```swift
let task = queue.addTask(id: "message-123") {
    try await presenter.showMessage()
}

queue.cancel(id: "message-123")
let result = await task.result
```

- `id: String = UUID().uuidString` 是业务取消标识。需要按 ID 定位时由调用方指定；省略时生成唯一字符串，仍可通过返回句柄调用 `task.cancel()`。
- 多个任务可以共享业务 ID，`cancel(id:)` 同步取得调用时的匹配项快照，取消所有同 ID 当前项和等待项，返回 Void。没有匹配项时直接返回。
- 匹配等待项先从队列移除，再请求原生 Task 取消并解除执行许可等待；方法返回前 `pendingCount` 已反映移除结果。这些操作不会启动，句柄以 CancellationError 结束。
- 当前项只接收取消请求，`isRunning` 在操作退出及清理期间仍为 true。操作主动返回成功时，其成功结果与原生取消状态均保持不变。
- 先更新等待队列，再触发取消回调；回调重入后新提交的同 ID 任务不属于外层取消快照。其他 ID 的调度顺序保持不变。
- `id` 与 `replacementKey` 各自独立：前者定位主动取消，后者判断相邻替换。同 ID 不会自动替换，同 replacementKey 也不会被按业务 ID 一并取消。

每次提交另行生成内部 `executionID: UUID`，取消回传、执行许可清理与结果观察者仅使用这一执行身份。业务 ID 可以重用；旧任务的迟到回调不能移除或推进新任务。重复取消也不会重复恢复 continuation 或释放当前执行槽。

## 可组合的超时

名称参照 `withTaskGroup`、`withTaskCancellationHandler`。iOS 16 起，时间接口与 `Task.sleep(for:tolerance:clock:)` 一致：

```swift
let task = queue.addTask {
    try await withTaskTimeout(for: .seconds(60)) {
        try await sequence.play(gift: gift, quantity: 1, reducedMotion: false)
    }
}
let result = await task.result
```

`for:` 接受 `C.Instant.Duration`，默认 `clock: .continuous`、`tolerance: nil`。也可使用 `withTaskTimeout(for: .milliseconds(500), tolerance: .milliseconds(10), clock: clock) { ... }` 指定容差或注入自定义时钟。时长要求非负，零时长仍参与竞速，不保证操作一定不会启动。Duration 路径直接调用标准库计时，不经过浮点秒数或纳秒转换。

Demo 和库继续支持 iOS 15；该系统使用 `withTaskTimeout(seconds: 60) { ... }` 兼容入口。礼物协调器保留秒数配置，按系统版本选择入口并共用播放闭包。两个入口共用竞速与取消实现，均保持调用方隔离。

`withTaskTimeout` 使用结构化任务组竞速操作与计时，先观察到的结果获胜，取消剩余子任务并等待其退出后返回。普通错误保持原样，计时获胜后抛出 TimeoutError。

仅计时正常结束时产生 TimeoutError；计时取消和自定义时钟错误原样传播。容差原样交给 Clock，可能使实际计时晚于指定时长。

操作闭包参照 `Task {}` 默认继承调用处的 Actor 隔离：主 Actor、自定义 Actor 和非隔离代码均可调用，也可显式传入 `@MainActor` 闭包。接口通过 `@_inheritActorContext` 继承上下文、`@isolated(any)` 保留操作自身的隔离，并通过 `sending` 接受可安全转移的捕获；结果仍要求 `Sendable`。继承 Actor 隔离不等于固定线程，也不会自动把主 Actor 上的耗时计算转移到后台。礼物调用继续继承其调用处的 MainActor。

超时从任务获得执行许可并进入包装函数时开始，不包含排队时间。到期意味着请求取消，不保证在指定秒数内返回；不合作的操作退出前，不报告最终结果或开始下一队列项。父 Task 取消会传播到子任务，调用前已经取消时不会启动操作。

## 礼物接入

GiftMainEffectCoordinator 管理 isActive 和页面生命周期；关闭接收时调用 cancelAll，重新显示只接收新的赠送。每次成功赠送提交一个任务，整组通过 withTaskTimeout 共享 60 秒期限。

礼物调用方继续省略业务 ID、调度和替换参数，自动生成 ID，采用 `.normal`、`.enqueue` 和 nil key。每份已扣款赠送独立排队，连续赠送不会被合并或替换。

GiftEffectSequence 直接遍历 Gift.effects，使用统一的 GiftEffectPlaying 异步接口；每次等待前后检查取消，以 defer 清理当前播放器。普通展示失败记录并继续，整组结束后报告首个错误；取消停止后续效果。纯原生赠送继续即时触发。

GiftPlaybackOperation 仅在 SDK 适配边界将回调转换为异步结果：任务取消后停止 SDK、撤销事件、清屏，再恢复等待。每次播放有独立身份，重复事件和迟到取消不能影响新播放。减少动态效果时整组只显示一次图标与数量；远程素材加载和缓存继续交给 SDK。

## 验证

Scripts/verify-gift-effects.sh 运行队列、超时、SDK 适配、礼物业务和麦位回归，再运行真实网络及组合赠送 UI 测试。测试通过可控挂起点和明确信号验证任务实际退出，不以固定次数的 Task.yield() 猜测状态。

队列测试同时覆盖优先级与同级 FIFO、三种替换策略、排序后的相邻判定、当前项取消后清理、连续替换、同步取消重入、取消等待项及队列释放。编译与回归沿用 Swift 6、默认 nonisolated 和 Debug 测试配置。

按业务 ID 的测试覆盖等待项同步移除、同 ID 当前及多个等待项一起取消、开始前取消、成功结果保留、ID 重用、快照取消重入和相邻替换后的迟到回调。

```sh
Scripts/verify-gift-effects.sh

GIFT_EFFECTS_DERIVED_DATA=/private/tmp/GiftEffectsDevice \
  Scripts/verify-gift-effects.sh \
  -destination 'platform=iOS,id=DEVICE_ID' DEVELOPMENT_TEAM=TEAM_ID
```

模拟器、真机和真实网络结果分别记录；设备锁屏或网络不可用不计为通过。
