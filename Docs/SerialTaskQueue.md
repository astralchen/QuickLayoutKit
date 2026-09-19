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

## 可组合的重试

Demo 并发工具提供内部函数 `withTaskRetry`，操作顺序执行，失败退出后才决定是否再次尝试。
`maxAttempts` **包含首次执行**，必须大于零；值为 1 时不会重试。次数、等待规则和
错误策略（`shouldRetry` 或 `policy` 二选一）必须显式传入。成功立即返回原值；次数耗尽或策略停止时原样抛出最后一次
操作错误，不包装为新的错误。

```swift
// iOS 16 起；示例中的 loadResource 是业务提供的可重复执行闭包。
let resource = try await withTaskRetry(
    maxAttempts: 4,
    delay: .exponential(
        initial: .milliseconds(500),
        maximum: .seconds(5),
        jitter: .full
    ),
    shouldRetry: { ($0 as? URLError)?.code == .networkConnectionLost }
) {
    try await loadResource()
}
```

`RetryDelay<Interval>` 有四种规则：

| 规则 | 行为 |
| --- | --- |
| `.immediate` | 零等待，仍检查取消 |
| `.fixed(interval)` | 每次失败退出后等待相同间隔 |
| `.exponential(initial:multiplier:maximum:jitter:)` | 默认倍率 2，默认不抖动；间隔增长至上限后保持 |
| `.custom { retryIndex, error in ... }` | 按从 1 开始的重试序号及原错误同步计算间隔 |

首次执行不等待。指数退避的未抖动间隔依次为 `initial`、`initial × multiplier`、
`initial × multiplier²`，并在 `maximum` 封顶。`.full` 在零至本轮上限内随机取值，
随机值不影响下一轮的退避进度；`initial` 此时是首轮等待上限。复用策略值不会共享进度。
所有间隔必须非负，倍率须有限且不小于 1，上限不得小于初始间隔；非法配置触发前置条件失败。

现代入口支持 `clock:` 和 `tolerance:`，默认 `.continuous` 和 nil。间隔类型跟随 Clock，
计算直接使用 Duration 的加减及整数缩放，不经浮点秒数中转；非整数倍率与抖动受时长类型
的表示精度约束。达到上限前先判断溢出。零间隔跳过 Clock 等待，非零间隔将 tolerance
原样传入；自定义时钟的等待错误直接传播，不交给业务重试筛选。

iOS 15 使用同一策略形态的秒数入口：

```swift
let resource = try await withTaskRetry(
    maxAttempts: 3,
    delaySeconds: .exponential(initial: 0.5, maximum: 5, jitter: .full),
    shouldRetry: { ($0 as? URLError)?.code == .networkConnectionLost }
) {
    try await loadResource()
}
```

秒数必须有限、非负且可安全转换为 UInt64 纳秒；自定义规则的返回值也会校验。
`shouldRetry`、`policy` 和自定义时间规则均为同步、非抛错的 `@Sendable` 闭包。

**取消错误绝不重试，也不能被策略覆盖。** 操作抛出 `CancellationError` 或
`URLError(.cancelled)` 时立即原样抛出；若抛出普通错误但父任务已取消，则抛出
`CancellationError`。以上分支都不会调用重试筛选和等待规则。其他 SDK 的取消错误由
业务在 `shouldRetry` 或 `policy` 中拒绝。每次尝试前及等待前检查取消，等待期间取消后不再启动操作。
操作忽略取消并成功返回时保留成功值，不强行改写为取消错误。

操作支持调用处 Actor 继承、显式隔离和独占非 Sendable 捕获转移，返回值要求 Sendable。
闭包由单一隔离所有者持有并依次调用，Task-local 保持；不会自动把主 Actor 工作移到后台。

### 重试决策与最短等待

需要合并业务或服务端的等待要求时，使用 `policy:` 入口。`RetryContext` 包含原错误
`error` 和从 1 开始的失败尝试序号 `failedAttempt`，策略返回 `RetryDecision<Interval>`：

- `.stop`：保留本次操作错误，不计算退避或等待。
- `.retry()`：使用本地退避，最短等待默认为零。
- `.retry(minimumDelay: interval)`：本次至少等待指定间隔。

```swift
let resource = try await withTaskRetry(
    maxAttempts: 3,
    delay: .exponential(initial: .milliseconds(500), maximum: .seconds(5)),
    policy: { context in
        guard context.error is TimeoutError else { return .stop }
        return .retry(minimumDelay: .seconds(1))
    }
) {
    try await withTaskTimeout(for: .seconds(2)) { try await loadResource() }
}
```

iOS 15 使用 `delaySeconds:`，决策的最短等待也是秒数：

```swift
let resource = try await withTaskRetry(
    maxAttempts: 3,
    delaySeconds: .exponential(initial: 0.5, maximum: 5),
    policy: { context in
        guard (context.error as? URLError)?.code == .timedOut else { return .stop }
        return .retry(minimumDelay: 1)
    }
) {
    try await loadResource()
}
```

两个旧 `shouldRetry:` 入口内部都适配到决策核心：true 映射为 `.retry()`，false 映射为
`.stop`，不需要迁移现有调用。取消和次数耗尽发生在 policy 之前；policy 返回后再次检查
取消，即使它返回 `.stop`，执行期间发生的父任务取消也优先以 CancellationError 结束。

实际间隔为 `max(本轮本地退避及抖动结果, minimumDelay)`。本地 maximum 不会截短最短
等待，合并后也不会再次应用 full jitter；最短等待不改变下一轮指数退避进度。比如本地
上限为 5 秒、服务端仍要求等待 120 秒，本次实际等待不得少于 120 秒。

policy 的动态最短等待采用非崩溃校验：Duration 不得为负，秒数必须有限、非负且可安全
转换为 UInt64 纳秒。非法值等同于停止，保留操作错误，不调用本地退避或 Clock。
固定、指数配置及 `.custom` 返回值保持原有前置条件校验；外部响应数据应经解析与校验后
进入决策接口，避免把不可信值直接送进 `.custom`。

### 服务端期限与连接等待

HTTP 响应解析属于网络层。下面的错误类型仅用于展示已经解析、校验的结果，不是工程新增的
生产 HTTP 类型。请求须允许安全重复执行；白名单外的错误默认停止。

```swift
struct ParsedHTTPFailure: Error {
    let statusCode: Int
    let retryNotBefore: ContinuousClock.Instant?
    let retryAfterRejected: Bool
}

let clock = ContinuousClock()
let resource = try await withTaskRetry(
    maxAttempts: 3,
    delay: .exponential(initial: .milliseconds(500), maximum: .seconds(5), jitter: .full),
    clock: clock,
    policy: { context in
        guard let failure = context.error as? ParsedHTTPFailure,
              [429, 503].contains(failure.statusCode), !failure.retryAfterRejected else { return .stop }
        let remaining = failure.retryNotBefore.map { max(.zero, clock.now.duration(to: $0)) } ?? .zero
        guard remaining <= .seconds(120) else { return .stop }
        return .retry(minimumDelay: remaining)
    }
) {
    try await loadResource()
}
```

网络层将 Retry-After 转成同一时钟的最早重试期限，决策时重新计算剩余时间。缺失或格式
非法时，示例使用 nil 回退到本地退避；合法但无法表示或超过业务允许范围时，标记
`retryAfterRejected` 并停止，不能用本地上限截短要求。已过期的期限提供零最短等待。
通用工具不会仅因为存在这个响应头就自动重试，也不自行解析 HTTP 日期或维护时钟转换。

连接等待放在网络操作内部。例如，可让 URLSession 在建立连接前等待可用网络，外层统一
限制整个流程的期限：

```swift
let configuration = URLSessionConfiguration.default
configuration.waitsForConnectivity = true
let session = URLSession(configuration: configuration)
defer { session.invalidateAndCancel() }

let data = try await withTaskTimeout(for: .seconds(30)) {
    try await withTaskRetry(
        maxAttempts: 3,
        delay: .exponential(initial: .milliseconds(500), maximum: .seconds(5), jitter: .full),
        policy: { context in
            guard let error = context.error as? URLError,
                  [.networkConnectionLost, .timedOut].contains(error.code) else { return .stop }
            return .retry()
        }
    ) {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
```

该示例只展示连接等待，HTTP 状态策略需要按业务转换成前述网络错误。
`waitsForConnectivity` 处理连接建立前的等待，已建立的连接中断仍会返回错误供策略判断，
见 [Apple 文档](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/waitsforconnectivity)。
一次 operation 调用算一次尝试，等待连接时不会反复增加次数。恢复网络不重置次数或总期限；
已取消、已超时或已结束的调用不能被恢复事件重新启动。通用 policy 始终同步执行，
不承担网络监听或等待联网的职责。

### 与超时、队列的组合

```swift
// 每次尝试独立计时：单次超时后可重试。
let value = try await withTaskRetry(
    maxAttempts: 3, delay: .fixed(.milliseconds(300)),
    shouldRetry: { $0 is TimeoutError }
) {
    try await withTaskTimeout(for: .seconds(2)) { try await loadResource() }
}

// 全部执行和间隔共用总期限。
let valueWithinDeadline = try await withTaskTimeout(for: .seconds(10)) {
    try await withTaskRetry(
        maxAttempts: 3, delay: .fixed(.milliseconds(300)),
        shouldRetry: { ($0 as? URLError)?.code == .networkConnectionLost }
    ) {
        try await loadResource()
    }
}
```

`maximum` 只限制本地退避，不限制最短等待要求或整体耗时。超时仍为协作式取消，必须等旧操作退出和清理
后才开始下一次尝试或完成整个调用。放在队列操作内时，重试等待也占用该任务的执行槽，
排队等待不计入包装函数的期限。

重试可能重复产生副作用，业务须保证闭包可以重复执行，必要时使用幂等请求身份。超时不代表
服务端未完成操作。工具不解析 HTTP Retry-After，不支持无限重试。礼物预下载按下面的业务
白名单有限重试，整组礼物播放和聊天发送仍保留各自业务策略。

## 礼物接入

GiftMainEffectCoordinator 管理 isActive 和页面生命周期；关闭接收时调用 cancelAll，重新显示只接收新的赠送。每次成功赠送提交一个任务，整组通过 withTaskTimeout 共享 60 秒期限。

礼物调用方继续省略业务 ID、调度和替换参数，自动生成 ID，采用 `.normal`、`.enqueue` 和 nil key。每份已扣款赠送独立排队，连续赠送不会被合并或替换。

GiftEffectSequence 直接遍历 Gift.effects，使用统一的 GiftEffectPlaying 异步接口；每次等待前后检查取消，以 defer 清理当前播放器。普通展示失败记录并继续，整组结束后报告首个错误；取消停止后续效果。纯原生赠送继续即时触发。

GiftPlaybackOperation 仅在 SDK 适配边界将回调转换为异步结果：任务取消后停止 SDK、撤销事件、清屏，再恢复等待。每次播放有独立身份，重复事件和迟到取消不能影响新播放。减少动态效果时整组只显示一次图标与数量；远程素材加载和缓存继续交给 SDK。

GiftEffectPrefetcher 在单项资源加载处使用 `withTaskRetry` 的 iOS 15 秒数入口，最多尝试
两次（首次加载加一次重试），默认失败退出后等待 300 毫秒。仅 `URLError.timedOut` 和
`URLError.networkConnectionLost` 进入重试；明确断网、取消、文件缺失、解码或配置错误、
HTTP 失败及未知错误均停止，不等待联网后补播过期礼物。VAP 下载直接抛出 URL 错误；
SVGA 依赖更新至 `39464c8`，`preload` 通过 `SVGAViewError.network(URLError)` 保留
原始网络错误，预下载按其错误码使用同一白名单。包装后的 `.cancelled`、SDK 的
`.cancelled` 和 `CancellationError` 均不重试，也不记为预下载失败日志。
`SVGAViewError.underlying(String)` 仍按未知错误停止，不按文案猜测网络原因。

相同格式与 URL 共享一份重试预算，等待期间继续占用原预下载槽位，不重新入队。任一需求仍
存活时，最终成功或失败的条目都会保留，新登记不会重新获得两次尝试。最后一个需求释放、
页面退出或预下载器销毁会取消加载及退避；底层忽略取消时仍须等待实际退出，迟到网络错误
不能触发下一次尝试。内部可注入等待策略和加载器，用于脱离真实网络时序的测试。

预下载与播放并行，失败后播放仍可走 SDK 正常加载路径。此重试只预热资源缓存，不重复调用
`player.play`、`GiftEffectSequence.play` 或赠送业务，不改变效果顺序、已扣款赠送身份和
整组 60 秒超时；预下载不会为播放重新计时。网络可重复下载并不意味着动画可以安全重播。

## 验证

Scripts/verify-gift-effects.sh 运行队列、重试、超时、SDK 适配、礼物业务和麦位回归，再运行真实网络及组合赠送 UI 测试。测试通过可控挂起点和明确信号验证任务实际退出，不以固定次数的 Task.yield() 猜测状态。

队列测试同时覆盖优先级与同级 FIFO、三种替换策略、排序后的相邻判定、当前项取消后清理、连续替换、同步取消重入、取消等待项及队列释放。编译与回归沿用 Swift 6、默认 nonisolated 和 Debug 测试配置。

2026-09-19 重试工具初版验收：通过 Demo scheme 在 iPhone 17 Pro / iOS 26.5（x86_64）
模拟器运行 `WithTaskRetryTests`、`WithTaskTimeoutTests`、`SerialTaskQueueTests` 和
`TaskQueueTests`，共 86 项测试全部通过。覆盖取消优先级、错误保真、等待与退避、抖动、
自定义 Clock/Duration、最小精度及极大倍率、Actor 隔离、Task-local、两种超时组合和
秒数兼容入口。Demo 保持 iOS 15 部署目标构建通过，文档调用形态另经 Swift 6.3.2
按 iOS 15 部署目标类型检查。秒数入口在当前模拟器执行，不代表已完成真实 iOS 15
系统或真机验证。

同日完成重试决策扩展：上述四个套件共 99 项测试全部通过，覆盖新旧入口、决策上下文、
停止与取消优先级、最短等待和抖动合并、动态非法值安全停止、连接等待后恢复，以及取消或
总超时后恢复不再执行。Demo 继续按 iOS 15 部署目标构建，文档中 7 个调用示例也按该目标
通过类型检查。运行环境仍为 iPhone 17 Pro / iOS 26.5 模拟器；连接状态使用可取消的测试
门闩，服务端要求使用已解析等待值模拟，不代表已验证真实断网、HTTP 响应头解析或 iOS 15 真机。

同日完成礼物预下载接入：通过 Demo scheme 在同一 iPhone 17 Pro / iOS 26.5（x86_64）
模拟器运行上述四个套件以及 `GiftEffectPrefetcherTests`、`GiftPlaybackOperationTests`、
`VoiceRoomGiftMainEffectTests`，共 131 项测试全部通过。新增 6 项测试覆盖瞬时网络失败
重试、共享预算耗尽、终止错误、取消后的迟到失败、释放需求时取消退避，以及页面退出时
停止预下载且不重播礼物。Demo 按 iOS 15 部署目标编译通过；本轮使用可控加载器和退避
信号模拟错误与取消，未运行真实网络、真实断网、UI 截图或 iOS 15 真机测试。

随后将 SVGA 更新至 `39464c8` 并适配类型化网络错误：上述七个套件共 132 项测试全部通过，
新增覆盖 SVGA 超时和连接中断的重试成功、次数耗尽及共享预算，并补充包装后的取消、
断网、HTTP 失败、TLS 失败不重试，以及取消后的迟到网络失败不重试。运行环境仍为
iPhone 17 Pro / iOS 26.5（x86_64）模拟器，Demo 按 iOS 15 部署目标构建通过；
本轮 SDK 错误由加载器替身注入，不代表真实断网或 iOS 15 真机验证。

按业务 ID 的测试覆盖等待项同步移除、同 ID 当前及多个等待项一起取消、开始前取消、成功结果保留、ID 重用、快照取消重入和相邻替换后的迟到回调。

```sh
Scripts/verify-gift-effects.sh

GIFT_EFFECTS_DERIVED_DATA=/private/tmp/GiftEffectsDevice \
  Scripts/verify-gift-effects.sh \
  -destination 'platform=iOS,id=DEVICE_ID' DEVELOPMENT_TEAM=TEAM_ID
```

模拟器、真机和真实网络结果分别记录；设备锁屏或网络不可用不计为通过。
