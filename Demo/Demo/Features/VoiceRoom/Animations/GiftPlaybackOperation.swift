import Foundation

/// 播放器适配层内部的回调桥接，处理同步 SDK 回调、重复事件和取消竞争。
/// 不调度任务、不管理队列或超时，调用方只通过异步结果等待一次播放。
@MainActor
final class GiftPlaybackOperation {
    /// SDK 一次播放的结果回调，仅用于适配层内部。
    typealias Completion = @MainActor (Result<Void, Error>) -> Void
    /// 取消底层加载、事件和画面的同步清理。
    typealias Cleanup = @MainActor () -> Void
    /// 创建底层播放并返回清理行为，允许同步失败。
    typealias Start = @MainActor (@escaping Completion) -> Cleanup

    /// 一次播放的独立身份，旧回调不能影响复用后的新播放。
    private final class Session {
        /// 恢复异步等待的唯一 continuation。
        let continuation: CheckedContinuation<Void, Error>
        /// SDK 启动尚未返回清理闭包时，暂存第一次终态。
        var isStarting = true
        /// SDK 返回的清理行为。
        var cleanup: Cleanup?
        /// 启动过程中最先发生的完成、失败或取消。
        var synchronousResult: Result<Void, Error>?
        /// 绑定本次异步等待。
        init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    }

    /// 当前有效的播放身份。
    private var current: Session?

    /// 异步等待一次 SDK 播放；取消或替换时停止资源并恢复等待。
    func run(_ start: @escaping Start) async throws {
        stop()
        let identity = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let session = Session(continuation)
                current = session
                cancellationIdentity = identity
                let cleanup = start { [weak self, weak session] result in
                    guard let session else { return }
                    self?.finish(session, result: result)
                }
                session.cleanup = cleanup
                session.isStarting = false
                if let result = session.synchronousResult { finish(session, result: result) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.cancellationIdentity == identity else { return }
                self?.stop()
            }
        }
    }

    /// 本次取消处理器的身份，延迟送达的旧取消请求不能停止新播放。
    private var cancellationIdentity: UUID?

    /// 同步使旧事件失效，释放资源并以 CancellationError 恢复正在等待的调用。
    func stop() {
        guard let current else { return }
        finish(current, result: .failure(CancellationError()))
    }

    /// 第一终态获胜；启动期间等待清理闭包就绪后再恢复 continuation。
    private func finish(_ session: Session, result: Result<Void, Error>) {
        guard current === session else { return }
        if session.isStarting {
            if session.synchronousResult == nil { session.synchronousResult = result }
            return
        }
        current = nil
        cancellationIdentity = nil
        let cleanup = session.cleanup
        session.cleanup = nil
        cleanup?()
        session.continuation.resume(with: result)
    }
}
