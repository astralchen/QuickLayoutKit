import Foundation

/// 将单次播放器回调转换为可取消异步等待的适配对象。
///
/// 通过独立播放身份隔离迟到回调，并处理同步完成、重复终态和取消竞争。此类型不负责排队或计时。
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

    /// 启动一次底层播放，并等待首次有效的完成、失败或取消结果。
    ///
    /// 开始新播放前先停止旧播放。即使启动闭包同步报告结果，也会等清理闭包返回并执行后再结束等待。
    ///
    /// - Parameter start: 启动底层播放的闭包；接收结果回调并返回同步清理行为。
    /// - Throws: 底层播放失败的错误，或取消和替换产生的 `CancellationError`。
    func run(_ start: @escaping Start) async throws {
        stop()
        let identity = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let session = Session(continuation)
                current = session
                cancellationIdentity = identity
                // SDK 可能在 start 返回前同步完成；先登记身份，稍后再补齐清理行为。
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
                // 取消处理切回主执行器时，新播放可能已开始；只允许结束对应身份。
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

    /// 接收当前播放身份的首次终态，清理资源后恢复异步等待。
    ///
    /// 过期身份的事件会被忽略。启动尚未返回时暂存首次结果，避免清理行为尚未注册就结束等待。
    private func finish(_ session: Session, result: Result<Void, Error>) {
        guard current === session else { return }
        if session.isStarting {
            if session.synchronousResult == nil { session.synchronousResult = result }
            return
        }
        // 先让当前身份失效，再调用底层清理，防止 stop 触发的重入回调重复恢复等待。
        current = nil
        cancellationIdentity = nil
        let cleanup = session.cleanup
        session.cleanup = nil
        cleanup?()
        session.continuation.resume(with: result)
    }
}
