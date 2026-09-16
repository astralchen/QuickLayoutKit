import Foundation
import Testing
@testable import Demo

/// 验证原生句柄与严格串行，使用明确挂起点而非固定调度次数。
@MainActor
@Suite(.serialized)
struct SerialTaskQueueTests {
    /// 任意返回类型、普通失败和多个结果观察者保持原生 Task 语义。
    @Test func valuesErrorsAndObservers() async throws {
        let queue = SerialTaskQueue()
        var events: [String] = []
        let first = queue.addTask {
            defer { events.append("clean A"); #expect(!Task.isCancelled) }
            events.append("A")
            return 42
        }
        let failed = queue.addTask { () throws -> String in
            defer { events.append("clean B"); #expect(!Task.isCancelled) }
            events.append("B")
            throw URLError(.badServerResponse)
        }
        let last = queue.addTask { events.append("C"); return "done" }
        let observerA = Task { try await first.value }
        let observerB = Task { try await first.value }
        let a = try await observerA.value
        let b = try await observerB.value
        #expect(a == 42 && b == 42)
        if case .failure(let error) = await failed.result { #expect((error as? URLError)?.code == .badServerResponse) }
        else { Issue.record("应保留业务错误") }
        let value = try await last.value
        #expect(value == "done" && events == ["A", "clean A", "B", "clean B", "C"])
        #expect(!first.isCancelled && !failed.isCancelled && !last.isCancelled)
        try await waitForTaskCondition { !queue.isRunning }
    }

    /// 运行项不合作时仍占用执行槽，取消后主动返回成功不会被队列改写。
    @Test func cancellationWaitsForActualExitAndPreservesSuccess() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let cancelled = TaskTestSignal()
        var events: [String] = []
        let first = queue.addTask {
            defer { events.append("clean") }
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: { Task { @MainActor in cancelled.signal() } }
            return 7
        }
        let next = queue.addTask { events.append("next") }
        await gate.started.wait()
        first.cancel()
        await cancelled.wait()
        #expect(queue.isRunning && queue.pendingCount == 1 && events.isEmpty)
        gate.resolve()
        let value = try await first.value
        #expect(value == 7 && first.isCancelled)
        try await next.value
        #expect(events == ["clean", "next"])
    }

    /// 等待项取消可立即结束等待，不调用操作或释放尚未退出的当前项。
    @Test func pendingCancellationDoesNotRunOrReleaseCurrent() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let first = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let pending = queue.addTask { Issue.record("已取消等待项不得执行") }
        let next = queue.addTask { 9 }
        pending.cancel()
        if case .failure(let error) = await pending.result { #expect(error is CancellationError) }
        else { Issue.record("等待项应取消") }
        try await waitForTaskCondition { queue.pendingCount == 1 }
        #expect(queue.isRunning)
        gate.resolve()
        try await first.value
        let value = try await next.value
        #expect(value == 9)
    }

    /// 已获准但尚未进入操作的任务，取消后同样不调用业务。
    @Test func cancellationBeforeOperationStarts() async throws {
        let queue = SerialTaskQueue()
        let task = queue.addTask { Issue.record("开始前取消不应执行") }
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应取消") }
        let next = queue.addTask { 1 }
        let value = try await next.value
        #expect(value == 1)
    }

    /// cancelAll 是已有任务的快照，新任务仍等待已取消的当前任务退出。
    @Test func cancelAllThenAdd() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let first = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let discarded = queue.addTask { Issue.record("被清空项不得执行") }
        queue.cancelAll()
        var nextStarted = false
        let next = queue.addTask { nextStarted = true }
        if case .failure(let error) = await discarded.result { #expect(error is CancellationError) }
        else { Issue.record("等待项应取消") }
        #expect(first.isCancelled && queue.isRunning && !nextStarted)
        gate.resolve()
        try await first.value
        try await next.value
        #expect(nextStarted && !next.isCancelled)
    }

    /// 任务内添加其他任务仍遵守 FIFO，清理先于下一项开始。
    @Test func reentrantSubmission() async throws {
        let queue = SerialTaskQueue()
        var events: [String] = []
        var nested: Task<Void, Error>?
        let task = queue.addTask {
            defer { events.append("clean") }
            nested = queue.addTask { events.append("nested") }
            events.append("outer")
        }
        try await task.value
        try await nested?.value
        #expect(events == ["outer", "clean", "nested"])
    }

    /// 队列释放不被内部观察者阻止，等待项结束、运行项自行响应取消。
    @Test func releaseCancelsTasksWithoutRetainingQueue() async throws {
        var queue: SerialTaskQueue? = SerialTaskQueue()
        let isReleased = { [weak queue] in queue == nil }
        let gate = ControlledTaskOperation()
        let cancelled = TaskTestSignal()
        let first = queue!.addTask {
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: { Task { @MainActor in cancelled.signal() } }
        }
        await gate.started.wait()
        let pending = queue!.addTask { Issue.record("释放后不得执行等待项") }
        queue = nil
        #expect(isReleased() && first.isCancelled && pending.isCancelled)
        await cancelled.wait()
        if case .failure(let error) = await pending.result { #expect(error is CancellationError) }
        else { Issue.record("释放后的等待项应取消") }
        gate.resolve()
        try await first.value
    }

    /// 取消结果观察者不会自动取消被等待的非结构化任务。
    @Test func cancellingObserverDoesNotCancelOperation() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let task = queue.addTask { try await gate.run(); return 3 }
        await gate.started.wait()
        let observing = TaskTestSignal()
        let observer = Task { observing.signal(); return try await task.value }
        await observing.wait()
        observer.cancel()
        #expect(!task.isCancelled)
        gate.resolve()
        let value = try await observer.value
        #expect(value == 3 && observer.isCancelled && !task.isCancelled)
    }

    /// 丢弃原生句柄不取消任务，大量立即返回的任务仍按 FIFO 完成。
    @Test func discardedHandlesAndManyTasks() async throws {
        let queue = SerialTaskQueue()
        var values: [Int] = []
        for index in 0..<1_000 { queue.addTask { values.append(index) } }
        let last = queue.addTask { values.count }
        let count = try await last.value
        #expect(count == 1_000 && values == Array(0..<1_000))
    }
}
