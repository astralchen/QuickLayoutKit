import Foundation
import Testing
@testable import Demo

/// 超时请求取消但等待实际退出，保留结构化并发的资源所有权。
@MainActor
@Suite(.serialized)
struct WithTimeoutTests {
    /// 正常完成返回原值，普通失败保持原错误，不把成功操作标记为取消。
    @Test func valuesAndErrors() async throws {
        let value = try await withTimeout(10) {
            defer { #expect(!Task.isCancelled) }
            return 42
        }
        #expect(value == 42)
        do {
            try await withTimeout(10) { throw URLError(.badURL) }
            Issue.record("应保留普通错误")
        } catch { #expect((error as? URLError)?.code == .badURL) }
    }

    /// 超时取消信号已到达，但操作未退出前句柄与队列槽都不能完成。
    @Test func timeoutWaitsForUncooperativeOperation() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let cancellation = TaskTestSignal()
        var exited = false
        var nextStarted = false
        let task = queue.addTask {
            defer { exited = true }
            try await withTimeout(0.05) {
                try await withTaskCancellationHandler {
                    try await gate.run()
                } onCancel: { Task { @MainActor in cancellation.signal() } }
            }
        }
        let next = queue.addTask { nextStarted = true }
        await gate.started.wait()
        await cancellation.wait()
        #expect(!exited && !nextStarted && queue.isRunning)
        gate.resolve()
        if case .failure(let error) = await task.result { #expect(error is TimeoutError) }
        else { Issue.record("计时获胜后应报告超时") }
        try await next.value
        #expect(exited && nextStarted)
    }

    /// 父任务取消会传入操作，操作退出前不会完成父任务。
    @Test func parentCancellationWaitsForChildren() async {
        let started = TaskTestSignal()
        let cleaned = TaskTestSignal()
        let task = Task {
            try await withTimeout(10) {
                defer { cleaned.signal() }
                started.signal()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        await started.wait()
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应取消") }
        await cleaned.wait()
    }

    /// 进入超时包装之前已经取消，不启动业务或计时子任务。
    @Test func preCancelledOperationDoesNotStart() async {
        let task = Task {
            try await withTimeout(10) { Issue.record("已取消任务不得开始") }
        }
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应取消") }
    }
}
