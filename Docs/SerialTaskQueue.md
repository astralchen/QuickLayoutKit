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

`addTask<Success: Sendable>(priority:operation:)` 立即返回 `Task<Success, Error>`。任务创建后等待内部执行许可，只有当前项能进入 operation；优先级不改变 FIFO 顺序。没有 cleanup、completion 或 Bool 接收结果，也没有回调式添加入口。

- `isRunning` 表示当前执行槽被占用，包含任务收到取消后仍在退出的时间。
- `pendingCount` 表示尚未获得执行许可的任务数量。
- 正常返回或普通失败不调用 cancel，也不在操作返回后把成功改为取消错误。
- 可以重复或由多个观察者等待同一个句柄。丢弃句柄不会取消任务。
- 取消等待 task.value 的另一个 Task，不会自动取消被等待的非结构化 Task。
- 句柄结果可能先于内部观察者更新队列状态被读取；结果已就绪保证操作退出，队列状态在主 Actor 后续调度中更新。

## 严格串行与取消

`task.cancel()` 和 `queue.cancelAll()` 都只请求取消，不强制结束正在执行的操作。当前操作返回或抛错、包括其 defer 完成之后，队列内部观察者才会释放执行槽。

等待项取消时解除内部等待并抛出 CancellationError，不调用业务操作。`cancelAll()` 取消调用时已有的运行项和等待项，之后仍可添加新任务；新任务继续等待旧运行项实际退出。

队列释放时请求所有任务取消并解除等待项的调度等待。运行项通过自身取消处理退出，可能晚于队列释放。内部任务和结果观察者不强持有队列；业务闭包仍应避免强持有拥有队列的页面。

清理属于操作自身：正常退出使用 defer；SDK 加载、播放等回调接口在适配层使用 withTaskCancellationHandler。onCancel 不保证在 MainActor，UIKit 清理需要切回 MainActor，完成资源清理后再恢复异步等待。忽略取消的任意操作会阻塞队列，这是严格串行的边界。

## 可组合的超时

```swift
let task = queue.addTask {
    try await withTimeout(60) {
        try await sequence.play(gift: gift, quantity: 1, reducedMotion: false)
    }
}
let result = await task.result
```

`withTimeout` 使用结构化任务组竞速操作与计时，先观察到的结果获胜，取消剩余子任务并等待其退出后返回。普通错误保持原样，计时获胜后抛出 TimeoutError。

超时从任务获得执行许可并进入包装函数时开始，不包含排队时间。到期意味着请求取消，不保证在指定秒数内返回；不合作的操作退出前，不报告最终结果或开始下一队列项。父 Task 取消会传播到子任务，调用前已经取消时不会启动操作。

## 礼物接入

GiftMainEffectCoordinator 管理 isActive 和页面生命周期；关闭接收时调用 cancelAll，重新显示只接收新的赠送。每次成功赠送提交一个任务，整组通过 withTimeout 共享 60 秒期限。

GiftEffectSequence 直接遍历 Gift.effects，使用统一的 GiftEffectPlaying 异步接口；每次等待前后检查取消，以 defer 清理当前播放器。普通展示失败记录并继续，整组结束后报告首个错误；取消停止后续效果。纯原生赠送继续即时触发。

GiftPlaybackOperation 仅在 SDK 适配边界将回调转换为异步结果：任务取消后停止 SDK、撤销事件、清屏，再恢复等待。每次播放有独立身份，重复事件和迟到取消不能影响新播放。减少动态效果时整组只显示一次图标与数量；远程素材加载和缓存继续交给 SDK。

## 验证

Scripts/verify-gift-effects.sh 运行队列、超时、SDK 适配、礼物业务和麦位回归，再运行真实网络及组合赠送 UI 测试。测试通过可控挂起点和明确信号验证任务实际退出，不以固定次数的 Task.yield() 猜测状态。

```sh
Scripts/verify-gift-effects.sh

GIFT_EFFECTS_DERIVED_DATA=/private/tmp/GiftEffectsDevice \
  Scripts/verify-gift-effects.sh \
  -destination 'platform=iOS,id=DEVICE_ID' DEVELOPMENT_TEAM=TEAM_ID
```

模拟器、真机和真实网络结果分别记录；设备锁屏或网络不可用不计为通过。
