# Demo 操作生命周期与可替换任务

这两个类型供 Demo 各功能在 `MainActor` 上共用，支持 iOS 15 及更高版本。

## OperationScope：会话与普通回调

每个独立操作通道持有一个 Scope。`begin()` 使旧令牌失效；`invalidate()` 在停止、
复用或离屏时使当前令牌失效。令牌弱引用 Scope，回调不会因此延长所属对象的生命周期。

```swift
private let thumbnailScope = OperationScope()

func loadThumbnail() {
    let operation = thumbnailScope.begin()
    request = loader.load(url: url, pixels: 90) { [weak self] image in
        guard operation.isCurrent, let self else { return }
        self.imageView.image = image
    }
}

func stopLoading() {
    thumbnailScope.invalidate()
    loader.cancel(request)
    request = nil
}
```

`isCurrent` 只表示操作归属，不读取当前 Task 的取消状态。清理资源时可使用它，
避免旧操作停止新操作的设备。`checkCancellation()` 同时检查操作归属和当前 Task
是否取消，失败时抛出 `CancellationError`。

异步函数返回不会自动使 Scope 失效。例如语音 `start()` 只完成启动，之后的持续
识别回调仍使用同一令牌，直到 `stop()`；自动切换识别后端也使用同一会话令牌。

## LatestTask：只允许最新请求继续发布结果

每个独立请求通道持有一个任务槽。`run` 先使旧令牌失效、取消旧任务，再启动新任务。
任务完成时只清理自己的句柄，防止旧任务的 `defer` 清空新任务。

```swift
private let loadingTask = LatestTask()

func reload() {
    loadingTask.run { [weak self] operation in
        let image = try await loadImage()
        try operation.checkCancellation()
        self?.imageView.image = image
    } onError: { [weak self] error in
        self?.showError(error)
    }
}

func stop() {
    loadingTask.cancel()
}
```

- 关键 `await` 后、更新状态或启动硬件之前仍需检查令牌。
- `onError` 必须显式提供，只收到仍有效任务的非取消错误；可在其中开始下一次请求。
- 正常结束也会使任务令牌失效。任务返回后需要继续接收回调的会话应另用 `OperationScope`。
- `cancel()` 立即清空句柄，因此 `isRunning == false` 不表示不支持取消的底层工作已经结束。
- `run` 的返回值及 `currentTask` 可用于等待特定任务结束；停止业务操作应调用任务槽的 `cancel()`。
- 任务槽释放时请求取消，但业务闭包仍应按需弱捕获页面，避免页面与闭包互相持有。

## 资源和执行顺序

Scope 失效或 Task 取消不会撤销已经发生的副作用。晚到的播放器、文件和系统请求句柄
仍由业务代码释放。多个 `await` 之间的状态检查、附件身份检查、账号或页面归属检查
仍按业务需要保留。

需要等前一项系统操作真正结束再启动下一项时，应继续使用相应的串行队列，例如
`AudioSessionOperationQueue`。`LatestTask` 不等待旧任务结束，不能替代串行队列。

布局缓存的数据版本、批次内多个并行导入及独立资源所有权应先确认语义，再选择
是否使用这些类型。不要仅根据变量名包含 `generation` 就替换。

## 当前接入点

- `SpeechRecognitionService`：整个识别会话共用一个 Scope。
- `MediaImageView`：每次缩略图请求使用一个 Token。
- `AttachmentThumbnailStripCell`：取消加载、重新显示和复用时更新有效期。
- `AudioController`：播放与恢复播放的准备工作共用一个 LatestTask。

`OperationScopeTests` 和 `LatestTaskTests` 覆盖替换、取消、迟到失败、回调内重试、
Scope 释放以及不响应取消的底层等待；业务接入继续由语音、缩略图和音频生命周期测试验证。
