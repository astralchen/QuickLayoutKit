import Foundation
import Testing
@testable import Demo

/// 按业务 ID 取消的回归，使用独立挂起点验证快照范围与实际退出顺序。
extension SerialTaskQueueTests {
    /// 移除指定等待项后同步更新数量，其余优先级和同级顺序保持不变。
    @Test func cancelIDRemovesPendingAndPreservesOtherTasks() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask(id: "current") { try await gate.run() }
        await gate.started.wait()
        var events: [String] = []
        let low = queue.addTask(id: "low", schedulingPriority: .low) { events.append("low") }
        let cancelled = queue.addTask(id: "cancel") { Issue.record("指定取消的等待项不得执行") }
        let first = queue.addTask(id: "first", schedulingPriority: .high) { events.append("first") }
        let second = queue.addTask(id: "second", schedulingPriority: .high) { events.append("second") }
        queue.cancel(id: "cancel")
        queue.cancel(id: "cancel")
        queue.cancel(id: "missing")
        #expect(queue.pendingCount == 3 && queue.isRunning && !current.isCancelled)
        #expect(cancelled.isCancelled && !first.isCancelled && !second.isCancelled && !low.isCancelled)
        await expectIDCancellation(cancelled)
        gate.resolve()
        for task in [current, low, first, second] { try await task.value }
        #expect(events == ["first", "second", "low"])
    }

    /// 同业务 ID 的当前项和不同返回类型的等待项一起取消，实际结果仍由当前操作决定。
    @Test(arguments: [false, true])
    func cancelIDMatchesAllAndWaitsForActualExit(returnsSuccess: Bool) async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let cancellation = TaskTestSignal()
        var events: [String] = []
        let current = queue.addTask(id: "group", replacementKey: "current-style") {
            defer { events.append("cleanup") }
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: { Task { @MainActor in cancellation.signal() } }
            if !returnsSuccess { try Task.checkCancellation() }
            return 7
        }
        await gate.started.wait()
        let first = queue.addTask(id: "group", replacementKey: "first-style") {
            Issue.record("同 ID 的等待项不得执行")
            return "first"
        }
        let second = queue.addTask(id: "group", replacementKey: "second-style", replacementPolicy: .replaceQueuedAndCurrent) {
            Issue.record("同 ID 的另一等待项不得执行")
            return true
        }
        // 相同业务 ID 不触发替换；不同业务 ID 也不会因共享 replacementKey 被一并取消。
        let other = queue.addTask(id: "other", replacementKey: "second-style") { events.append("other") }
        #expect(!first.isCancelled && !second.isCancelled && !current.isCancelled)
        queue.cancel(id: "group")
        #expect(queue.pendingCount == 1 && current.isCancelled && first.isCancelled && second.isCancelled)
        #expect(!other.isCancelled)
        await cancellation.wait()
        await expectIDCancellation(first)
        await expectIDCancellation(second)
        #expect(queue.isRunning && events.isEmpty)
        gate.resolve()
        switch await current.result {
        case .success(let value): #expect(returnsSuccess && value == 7)
        case .failure(let error): #expect(!returnsSuccess && error is CancellationError)
        }
        try await other.value
        #expect(events == ["cleanup", "other"] && current.isCancelled)
    }

    /// 已取得许可但尚未进入业务的当前项，按 ID 取消后同样不能启动操作。
    @Test func cancelIDBeforeOperationStarts() async throws {
        let queue = SerialTaskQueue()
        let task = queue.addTask(id: "not-started") { Issue.record("开始前按 ID 取消不得执行") }
        queue.cancel(id: "not-started")
        #expect(task.isCancelled && queue.isRunning)
        await expectIDCancellation(task)
        let next = queue.addTask { 1 }
        let value = try await next.value
        #expect(value == 1 && !next.isCancelled)
    }

    /// 取消旧等待项后立即重用业务 ID，旧取消回传和结果观察者不能移除新等待项。
    @Test func cancelledIDCanBeReusedBeforeOldCallbacksReturn() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let old = queue.addTask(id: "reused") { Issue.record("旧任务不得执行") }
        queue.cancel(id: "reused")
        let newGate = ControlledTaskOperation()
        let new = queue.addTask(id: "reused") { try await newGate.run(); return 9 }
        // 不让出 Actor 就重用 ID，使旧任务结束时面对的是已经入队的新任务。
        #expect(queue.pendingCount == 1 && !new.isCancelled)
        await expectIDCancellation(old)
        gate.resolve()
        try await current.value
        await newGate.started.wait()
        #expect(queue.isRunning && queue.pendingCount == 0 && !new.isCancelled)
        old.cancel()
        newGate.resolve()
        let value = try await new.value
        #expect(value == 9 && !new.isCancelled)
    }

    /// 无匹配项和已移出队列的 ID 为无操作，已完成任务的成功状态不会被改写。
    @Test func completedAndMissingIDsAreNoOps() async throws {
        let queue = SerialTaskQueue()
        queue.cancel(id: "reused")
        let first = queue.addTask(id: "reused") { 1 }
        let firstValue = try await first.value
        try await waitForTaskCondition { !queue.isRunning }
        queue.cancel(id: "reused")
        queue.cancel(id: "reused")
        #expect(firstValue == 1 && !first.isCancelled && queue.pendingCount == 0)
        let second = queue.addTask(id: "reused") { "second" }
        queue.cancel(id: "missing")
        let secondValue = try await second.value
        #expect(secondValue == "second" && !second.isCancelled)
    }

    /// 同步取消回调重入时先看到等待项已移除；新提交的同 ID 任务不属于外层快照。
    @Test(arguments: [false, true])
    func cancelIDSnapshotSurvivesReentrantSubmission(repeatCancellation: Bool) async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let state = IDCancellationState()
        let current = queue.addTask(id: "group") {
            defer { state.events.append("cleanup") }
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: {
                // 本测试从主 Actor 的 cancel(id:) 同步进入回调，动态验证重入边界。
                MainActor.assumeIsolated {
                    state.pendingAtCancellation = queue.pendingCount
                    if repeatCancellation { queue.cancel(id: "group") }
                    state.newTask = queue.addTask(id: "group") {
                        state.events.append("new")
                        return 42
                    }
                }
            }
        }
        await gate.started.wait()
        let waiting = queue.addTask(id: "group") { Issue.record("旧快照等待项不得执行") }
        queue.cancel(id: "group")
        let newTask = try #require(state.newTask)
        #expect(state.pendingAtCancellation == 0 && queue.pendingCount == 1)
        #expect(current.isCancelled && waiting.isCancelled && !newTask.isCancelled)
        #expect(queue.isRunning && state.events.isEmpty)
        await expectIDCancellation(waiting)
        gate.resolve()
        try await current.value
        let value = try await newTask.value
        #expect(value == 42 && state.events == ["cleanup", "new"])
    }

    /// 相邻替换后继续使用相同业务 ID，旧回调不影响替代项，主动取消仍只按业务 ID 匹配。
    @Test func replacedTaskCallbacksCannotAffectReusedBusinessID() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let old = queue.addTask(id: "message", replacementKey: "popup") { Issue.record("被替换项不得执行") }
        let replacementGate = ControlledTaskOperation()
        let replacement = queue.addTask(id: "message", replacementKey: "popup", replacementPolicy: .replaceQueued) {
            try await replacementGate.run()
            try Task.checkCancellation()
        }
        let other = queue.addTask(id: "other", replacementKey: "popup") { "other" }
        queue.cancel(id: "popup")
        #expect(old.isCancelled && !replacement.isCancelled && !other.isCancelled && queue.pendingCount == 2)
        await expectIDCancellation(old)
        gate.resolve()
        try await current.value
        await replacementGate.started.wait()
        #expect(queue.isRunning && !replacement.isCancelled && queue.pendingCount == 1)
        queue.cancel(id: "message")
        #expect(replacement.isCancelled && !other.isCancelled && queue.isRunning)
        replacementGate.resolve()
        await expectIDCancellation(replacement)
        let value = try await other.value
        #expect(value == "other")
    }
}

/// 取消回调与异步操作共享的测试状态，在主 Actor 上读写以符合 Swift 6 隔离要求。
@MainActor
private final class IDCancellationState {
    /// 回调进入时观察到的等待数量，验证队列已先完成移除。
    var pendingAtCancellation: Int?
    /// 回调重新提交的同业务 ID 句柄，供测试等待实际完成。
    var newTask: Task<Int, Error>?
    /// 记录旧操作清理与新操作启动的顺序。
    var events: [String] = []
}

/// 等待原生句柄结果并检查取消错误，不以固定 yield 次数猜测完成状态。
@MainActor
private func expectIDCancellation<Success: Sendable>(_ task: Task<Success, Error>) async {
    if case .failure(let error) = await task.result { #expect(error is CancellationError) }
    else { Issue.record("指定取消的任务应以 CancellationError 结束") }
}
