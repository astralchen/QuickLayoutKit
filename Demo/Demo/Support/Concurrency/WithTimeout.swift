import Foundation

/// 异步操作超过期限，已请求取消并等待其退出后报告的错误。
struct TimeoutError: LocalizedError, Sendable {
    /// 用于诊断的中文说明；超时不会强制终止不响应取消的操作。
    var errorDescription: String? { "异步操作执行超时" }
}

/// 以结构化子任务竞速操作和计时；先观察到的结果获胜，返回前等待全部子任务退出。
/// 取消是协作式的，忽略取消的操作可能使返回时间超过 interval。
@MainActor
func withTimeout<Success: Sendable>(
    _ interval: TimeInterval,
    operation: @escaping @MainActor @Sendable () async throws -> Success
) async throws -> Success {
    precondition(interval.isFinite && interval >= 0 && interval < Double(UInt64.max) / 1_000_000_000)
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: Success.self) { group in
        group.addTask {
            try Task.checkCancellation()
            return try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        // 始终存在两个子任务；next 返回后，该已完成子任务不再参与取消。
        return try await group.next()!
    }
}
