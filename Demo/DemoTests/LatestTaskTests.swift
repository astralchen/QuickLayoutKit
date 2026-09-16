import Foundation
import Testing
@testable import Demo

/// 用不响应取消的等待点验证新旧任务竞争及资源释放语义。
@MainActor
struct LatestTaskTests {
    /// 测试中的普通失败，区别于取消。
    private enum Failure: Error { case expected }

    /// 通过显式恢复模拟不支持取消的系统 API，不依赖固定睡眠决定返回顺序。
    @MainActor
    private final class Gate {
        /// 等待外部恢复的任务。
        private var continuation: CheckedContinuation<Void, Never>?
        /// 是否已有任务到达等待点。
        var isWaiting: Bool { continuation != nil }
        /// 挂起调用任务，即使收到取消也继续等待。
        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }
        /// 恢复挂起任务；清空句柄保证不会重复恢复。
        func release() {
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
    }

    /// 等待任务进入明确的测试阶段，设置超时避免失败时永久挂起。
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try #require(condition())
    }

    /// 旧任务的成功或失败都不能清掉新句柄、发布旧结果或报告旧错误。
    @Test(arguments: [false, true])
    func staleCompletionCannotOverwriteNewTask(fails: Bool) async throws {
        let latest = LatestTask()
        let oldGate = Gate()
        let newGate = Gate()
        defer { oldGate.release(); newGate.release(); latest.cancel() }
        var results: [String] = []
        var errors = 0
        let old = latest.run { token in
            await oldGate.wait()
            if fails { throw Failure.expected }
            try token.checkCancellation()
            results.append("old")
        } onError: { _ in errors += 1 }
        try await waitUntil { oldGate.isWaiting }
        let new = latest.run { token in
            await newGate.wait()
            try token.checkCancellation()
            results.append("new")
        } onError: { _ in errors += 1 }
        try await waitUntil { newGate.isWaiting }
        #expect(old.isCancelled)
        oldGate.release()
        await old.value
        #expect(latest.isRunning)
        #expect(results.isEmpty)
        #expect(errors == 0)
        // 如果旧任务清掉了新句柄，这里将无法取消仍挂起的新任务。
        latest.cancel()
        #expect(new.isCancelled)
        newGate.release()
        await new.value
        #expect(results.isEmpty)
        #expect(!latest.isRunning)
    }

    /// 启动后立即取消时，不执行任何任务体中的副作用。
    @Test func cancellingBeforeExecutionSkipsOperation() async {
        let latest = LatestTask()
        var started = false
        let task = latest.run { _ in started = true } onError: { _ in
            Issue.record("取消不应报告失败")
        }
        #expect(latest.isRunning)
        latest.cancel()
        #expect(!latest.isRunning)
        #expect(latest.currentTask == nil)
        await task.value
        #expect(!started)
    }

    /// 显式取消立即使令牌失效，即使底层等待仍未结束。
    @Test func cancellationInvalidatesSuspendedOperationImmediately() async throws {
        let latest = LatestTask()
        let gate = Gate()
        defer { gate.release(); latest.cancel() }
        var token: OperationScope.Token?
        var completed = false
        let task = latest.run { operation in
            token = operation
            await gate.wait()
            try operation.checkCancellation()
            completed = true
        } onError: { _ in Issue.record("取消不应报告失败") }
        try await waitUntil { gate.isWaiting }
        latest.cancel()
        #expect(token?.isCurrent == false)
        #expect(gate.isWaiting)
        gate.release()
        await task.value
        #expect(!completed)
    }

    /// 成功任务完成后清理句柄和令牌，后续请求仍可正常执行。
    @Test func successFinishesTokenAndAllowsAnotherRun() async {
        let latest = LatestTask()
        var token: OperationScope.Token?
        var results = 0
        await latest.run { operation in
            token = operation
            results += 1
        } onError: { _ in Issue.record("任务应成功") }.value
        #expect(!latest.isRunning)
        #expect(token?.isCurrent == false)
        await latest.run { _ in results += 1 } onError: { _ in
            Issue.record("重试应成功")
        }.value
        #expect(results == 2)
    }

    /// 当前失败只报告一次，普通取消不会进入错误处理。
    @Test(arguments: [false, true])
    func reportsOnlyNonCancellationErrors(cancelled: Bool) async {
        let latest = LatestTask()
        var errors = 0
        await latest.run { _ in
            if cancelled { throw CancellationError() }
            throw Failure.expected
        } onError: { _ in errors += 1 }.value
        #expect(errors == (cancelled ? 0 : 1))
        #expect(!latest.isRunning)
    }

    /// 错误回调内立即重试时，旧任务的 defer 不得清理新任务。
    @Test func retryInsideErrorHandlerSurvivesOldCleanup() async throws {
        let latest = LatestTask()
        let gate = Gate()
        defer { gate.release(); latest.cancel() }
        var retry: Task<Void, Never>?
        var completed = false
        let first = latest.run { _ in throw Failure.expected } onError: { _ in
            retry = latest.run { token in
                await gate.wait()
                try token.checkCancellation()
                completed = true
            } onError: { _ in Issue.record("重试应成功") }
        }
        await first.value
        try await waitUntil { gate.isWaiting }
        #expect(latest.isRunning)
        gate.release()
        await retry?.value
        #expect(completed)
        #expect(!latest.isRunning)
    }

    /// 外部释放任务槽时，任务闭包不会反向持有它，迟到结果也应失效。
    @Test func releasingOwnerCancelsSuspendedTask() async throws {
        var latest: LatestTask? = LatestTask()
        let gate = Gate()
        defer { gate.release(); latest?.cancel() }
        var token: OperationScope.Token?
        let task = latest!.run { operation in
            token = operation
            await gate.wait()
            try operation.checkCancellation()
            Issue.record("释放任务槽后不应继续执行")
        } onError: { _ in Issue.record("取消不应报告失败") }
        try await waitUntil { gate.isWaiting }
        latest = nil
        #expect(token?.isCurrent == false)
        #expect(task.isCancelled)
        gate.release()
        await task.value
    }
}
