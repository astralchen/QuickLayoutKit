import Foundation
import Testing
@testable import Demo

@MainActor
@Suite(.serialized)
struct TaskQueueTests {
    @Test(arguments: [1, 2])
    func boundedAdmissionAndFIFO(limit: Int) async throws {
        let queue = TaskQueue(maxConcurrentTasks: limit)
        let gates = (0..<4).map { _ in ControlledTaskOperation() }
        var started: [Int] = []
        let tasks = gates.enumerated().map { index, gate in
            queue.addTask {
                started.append(index)
                try await gate.run()
                return index
            }
        }
        try await waitForTaskCondition { started.count == limit }
        #expect(Set(started) == Set(0..<limit))
        #expect(queue.runningCount == limit && queue.pendingCount == 4 - limit)
        for index in 0..<(4 - limit) {
            gates[index].resolve()
            _ = try await tasks[index].value
            try await waitForTaskCondition { started.count == limit + index + 1 }
            #expect(started.last == limit + index, "每次腾出一个槽位时，按 FIFO 发放下一许可")
        }
        gates.forEach { $0.resolve() }
        for (index, task) in tasks.enumerated() { #expect(try await task.value == index) }
        try await waitForTaskCondition { queue.runningCount == 0 }
        #expect(queue.pendingCount == 0)
    }

    @Test func differentResultsAndBusinessErrors() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 2)
        let number = queue.addTask { 42 }
        let text = queue.addTask { "ready" }
        let failed = queue.addTask { () throws -> Bool in throw QueueTestError.failed }
        #expect(try await number.value == 42)
        #expect(try await text.value == "ready")
        guard case .failure(let error) = await failed.result else { Issue.record("应保留业务错误"); return }
        #expect(error as? QueueTestError == .failed)
        #expect(try await queue.withTask { true })
    }

    @Test func addTaskAndWithTaskShareBudget() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let firstGate = ControlledTaskOperation()
        let scopedGate = ControlledTaskOperation()
        let first = queue.addTask { try await firstGate.run() }
        await firstGate.started.wait()
        let scoped = Task { try await queue.withTask { try await scopedGate.run(); return "scoped" } }
        try await waitForTaskCondition { queue.pendingCount == 1 }
        var lastStarted = false
        let last = queue.addTask { lastStarted = true }
        #expect(queue.pendingCount == 2 && queue.runningCount == 1)
        firstGate.resolve()
        try await first.value
        await scopedGate.started.wait()
        #expect(!lastStarted && queue.pendingCount == 1)
        scopedGate.resolve()
        #expect(try await scoped.value == "scoped")
        try await last.value
    }

    @Test func immediatelyCancelledAndQueuedOperationsNeverExecute() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let immediate = queue.addTask { @MainActor in Issue.record("已取消的操作不能开始") }
        immediate.cancel() // 不让出 MainActor，即使许可已发放也不能执行操作。
        await expectCancellation(immediate)
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let queued = queue.addTask { Issue.record("排队取消不能执行操作") }
        queued.cancel()
        await expectCancellation(queued)
        #expect(queue.runningCount == 1 && queue.pendingCount == 0)
        gate.resolve()
        try await current.value
    }

    @Test(arguments: [false, true])
    func runningCancellationPreservesSlotAndActualResult(throwsError: Bool) async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let current = queue.addTask {
            try await gate.run()
            if throwsError { throw QueueTestError.failed }
            return 17
        }
        await gate.started.wait()
        current.cancel()
        var nextStarted = false
        let next = queue.addTask { nextStarted = true }
        #expect(queue.runningCount == 1 && queue.pendingCount == 1 && !nextStarted)
        gate.resolve()
        switch await current.result {
        case .success(let value): #expect(!throwsError && value == 17)
        case .failure(let error): #expect(throwsError && error as? QueueTestError == .failed)
        }
        try await next.value
    }

    @Test func cancelAllRetainsOldSlotAndNewTaskSurvivesOldCompletion() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let oldGate = ControlledTaskOperation()
        let newGate = ControlledTaskOperation()
        let old = queue.addTask { try await oldGate.run() }
        await oldGate.started.wait()
        let removed = queue.addTask { Issue.record("旧等待项不能执行") }
        queue.cancelAll()
        let fresh = queue.addTask { try await newGate.run() }
        await expectCancellation(removed)
        #expect(!fresh.isCancelled && queue.pendingCount == 1 && queue.runningCount == 1)
        oldGate.resolve()
        try await old.value
        await newGate.started.wait()
        #expect(queue.runningCount == 1)
        newGate.resolve()
        try await fresh.value
    }

    @Test func cancellationHandlerCanReenterAndNewSubmissionIsOutsideSnapshot() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let inserted = QueueTestBox<Task<Int, Error>?>(nil)
        let current = queue.addTask {
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: {
                // 若取消回调在队列锁内执行，这里会死锁。
                queue.cancelAll()
                inserted.update { $0 = queue.addTask { 9 } }
            }
        }
        await gate.started.wait()
        let waiting = queue.addTask { Issue.record("取消快照内的等待项不能执行") }
        queue.cancelAll()
        let fresh = try #require(inserted.value)
        await expectCancellation(waiting)
        #expect(!fresh.isCancelled && queue.runningCount == 1 && queue.pendingCount == 1)
        gate.resolve()
        try await current.value
        #expect(try await fresh.value == 9)
    }

    @Test func destructionCancelsRunningAndReleasesPendingWithoutCycle() async throws {
        let gate = ControlledTaskOperation()
        var queue: TaskQueue? = TaskQueue(maxConcurrentTasks: 1)
        weak var weakQueue = queue
        let current = try #require(queue?.addTask { try await gate.run() })
        await gate.started.wait()
        let waiting = try #require(queue?.addTask { Issue.record("销毁后不能执行") })
        queue = nil
        #expect(weakQueue == nil && current.isCancelled)
        await expectCancellation(waiting)
        gate.resolve()
        try await current.value
    }

    @Test func preCancelledWithTaskDoesNotRegister() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let parent = Task {
            try await gate.run()
            try await queue.withTask { Issue.record("预取消不能提交操作") }
        }
        await gate.started.wait()
        parent.cancel()
        gate.resolve()
        await expectCancellation(parent)
        #expect(queue.runningCount == 0 && queue.pendingCount == 0)
    }

    @Test func scopedCancellationRemovesWaitingChild() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let parent = Task { try await queue.withTask { Issue.record("作用域排队取消不能执行") } }
        try await waitForTaskCondition { queue.pendingCount == 1 }
        parent.cancel()
        await expectCancellation(parent)
        #expect(queue.pendingCount == 0 && !current.isCancelled)
        gate.resolve()
        try await current.value
    }

    @Test(arguments: [false, true])
    func scopedCancellationWaitsForRealExit(throwsError: Bool) async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let cancellation = TaskTestSignal()
        var returned = false
        let parent = Task {
            defer { returned = true }
            return try await queue.withTask {
                try await withTaskCancellationHandler {
                    try await gate.run()
                } onCancel: { Task { @MainActor in cancellation.signal() } }
                if throwsError { throw QueueTestError.failed }
                return 23
            }
        }
        await gate.started.wait()
        parent.cancel()
        await cancellation.wait()
        #expect(!returned && queue.runningCount == 1)
        gate.resolve()
        switch await parent.result {
        case .success(let value): #expect(!throwsError && value == 23)
        case .failure(let error): #expect(throwsError && error as? QueueTestError == .failed)
        }
        #expect(returned)
    }

    @Test func taskGroupCancellationPropagatesIntoScopedOperation() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let cancellation = TaskTestSignal()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await queue.withTask { @MainActor in
                    try await withTaskCancellationHandler {
                        try await gate.run()
                        try Task.checkCancellation()
                    } onCancel: { Task { @MainActor in cancellation.signal() } }
                }
            }
            await gate.started.wait()
            group.cancelAll()
            await cancellation.wait()
            #expect(queue.runningCount == 1)
            gate.resolve()
            do { try await group.waitForAll(); Issue.record("子任务应被取消") }
            catch { #expect(error is CancellationError) }
        }
    }

    @Test func independentTaskDoesNotInheritParentCancellation() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let parentGate = ControlledTaskOperation()
        let handle = QueueTestBox<Task<Int, Error>?>(nil)
        let parent = Task {
            handle.update { $0 = queue.addTask { try await gate.run(); return 31 } }
            try await parentGate.run()
        }
        await gate.started.wait()
        parent.cancel()
        let child = try #require(handle.value)
        #expect(!child.isCancelled)
        gate.resolve()
        #expect(try await child.value == 31)
        parentGate.resolve()
        try await parent.value
    }

    @Test func actorIsolationTaskLocalsAndNativeHandles() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 2)
        let main = QueueMainActorProbe()
        #expect(try await QueueTestContext.$name.withValue("main") {
            try await main.run(queue)
        } == "main:2")
        let worker = QueueActorProbe()
        #expect(try await QueueTestContext.$name.withValue("actor") {
            try await worker.run(queue)
        } == "actor:2")
        #expect(try await QueueTestContext.$name.withValue("nonisolated") {
            try await nonisolatedQueueProbe(queue)
        } == "nonisolated")
    }

    @Test func nativePriorityDoesNotReorderFIFO() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 1)
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        var order: [String] = []
        let low = queue.addTask(priority: .background) { order.append("low") }
        let high = queue.addTask(priority: .high) { order.append("high"); return Task.currentPriority }
        gate.resolve()
        try await current.value
        try await low.value
        #expect(try await high.value >= .high)
        #expect(order == ["low", "high"])
    }

    /// 同时从不同任务提交，检查锁保护的实际执行峰值与完整返回值。
    @Test nonisolated func concurrentSubmissionAndCompletion() async throws {
        let queue = TaskQueue(maxConcurrentTasks: 2)
        let counter = QueueConcurrencyProbe()
        let values = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<40 {
                group.addTask {
                    let task = queue.addTask {
                        await counter.enter()
                        await Task.yield()
                        await counter.leave()
                        return index
                    }
                    return try await task.value
                }
            }
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(values.sorted() == Array(0..<40))
        #expect(await counter.maximum <= 2)
        #expect(await counter.active == 0)
    }

    private func expectCancellation<T>(_ task: Task<T, Error>) async {
        switch await task.result {
        case .success: Issue.record("应返回取消错误")
        case .failure(let error): #expect(error is CancellationError)
        }
    }
}

private enum QueueTestError: Error { case failed }

private enum QueueTestContext {
    @TaskLocal static var name = "missing"
}

/// 只用于同步取消回调的跨执行器测试状态。
private final class QueueTestBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value { lock.lock(); defer { lock.unlock() }; return storage }
    func update(_ body: (inout Value) -> Void) { lock.lock(); defer { lock.unlock() }; body(&storage) }
}

@MainActor
private final class QueueMainActorProbe {
    private var value = 0
    func run(_ queue: TaskQueue) async throws -> String {
        let task = queue.addTask { value += 1; return value }
        _ = try await task.value
        return try await queue.withTask { value += 1; return "\(QueueTestContext.name):\(value)" }
    }
}

private actor QueueActorProbe {
    private var value = 0
    func run(_ queue: TaskQueue) async throws -> String {
        let task = queue.addTask { value += 1; return value }
        _ = try await task.value
        return try await queue.withTask { value += 1; return "\(QueueTestContext.name):\(value)" }
    }
}

private nonisolated func nonisolatedQueueProbe(_ queue: TaskQueue) async throws -> String {
    try await queue.withTask { QueueTestContext.name }
}

private actor QueueConcurrencyProbe {
    private(set) var active = 0
    private(set) var maximum = 0
    func enter() { active += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
}
