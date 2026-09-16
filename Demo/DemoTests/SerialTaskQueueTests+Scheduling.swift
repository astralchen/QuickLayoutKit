import Foundation
import Testing
@testable import Demo

/// 调度和替换复用原生句柄测试套件；挂起点显式控制当前操作的实际退出。
extension SerialTaskQueueTests {
    /// 调度优先级独立于 TaskPriority，同级保持 FIFO，高优先级不抢占运行项。
    @Test func schedulingPriorityIsStableAndIndependentOfTaskPriority() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        var events: [String] = []
        let current = queue.addTask(schedulingPriority: .low) {
            try await gate.run()
            events.append("current")
        }
        await gate.started.wait()
        let low = queue.addTask(priority: .userInitiated, schedulingPriority: .low) { events.append("low") }
        let normalA = queue.addTask(priority: .background) { events.append("normal A") }
        let highA = queue.addTask(priority: .background, schedulingPriority: .high) { events.append("high A") }
        let normalB = queue.addTask(priority: .userInitiated) { events.append("normal B") }
        let highB = queue.addTask(priority: .utility, schedulingPriority: .high) { events.append("high B") }
        #expect(queue.isRunning && queue.pendingCount == 5 && events.isEmpty)
        #expect(!current.isCancelled)
        gate.resolve()
        for task in [current, low, normalA, highA, normalB, highB] { try await task.value }
        #expect(events == ["current", "high A", "high B", "normal A", "normal B", "low"])
    }

    /// 已取得许可但尚未进入操作的任务，仍是不可被优先级重排的当前项。
    @Test func grantedPermitIsNotReorderedBeforeOperationStarts() async throws {
        let queue = SerialTaskQueue()
        var events: [String] = []
        let low = queue.addTask(schedulingPriority: .low) { events.append("low") }
        let high = queue.addTask(schedulingPriority: .high) { events.append("high") }
        #expect(events.isEmpty && queue.isRunning && queue.pendingCount == 1)
        try await low.value
        try await high.value
        #expect(events == ["low", "high"])
    }

    /// 替换由新任务的策略决定；普通排队任务也可以成为被替换的相邻等待项。
    @Test(arguments: [SerialTaskQueue.ReplacementPolicy.enqueue, .replaceQueued, .replaceQueuedAndCurrent])
    func queuedReplacementUsesIncomingPolicy(policy: SerialTaskQueue.ReplacementPolicy) async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        var events: [String] = []
        let first = queue.addTask(replacementKey: "message") { events.append("first") }
        let second = queue.addTask(replacementKey: "message", replacementPolicy: policy) { events.append("second") }
        let replaces = policy != .enqueue
        #expect(first.isCancelled == replaces)
        #expect(queue.pendingCount == (replaces ? 1 : 2) && !current.isCancelled)
        if replaces { await expectSchedulingCancellation(first) }
        gate.resolve()
        try await current.value
        if !replaces { try await first.value }
        try await second.value
        #expect(events == (replaces ? ["second"] : ["first", "second"]))
        #expect(!second.isCancelled)
    }

    /// 空 key、不同 key 和中间其他类型任务均阻止替换，不搜索更早的同 key 项。
    @Test func replacementRequiresNonNilEqualAdjacentKey() async throws {
        for (firstKey, secondKey, separated) in [
            (nil as String?, nil as String?, false),
            ("message", nil, false),
            ("message", "follow", false),
            ("message", "message", true),
        ] {
            let queue = SerialTaskQueue()
            let gate = ControlledTaskOperation()
            let current = queue.addTask { try await gate.run() }
            await gate.started.wait()
            var events: [String] = []
            let first = queue.addTask(replacementKey: firstKey) { events.append("first") }
            let separator: Task<Void, Error>? = separated
                ? queue.addTask { events.append("separator") } : nil
            let second = queue.addTask(replacementKey: secondKey, replacementPolicy: .replaceQueuedAndCurrent) {
                events.append("second")
            }
            #expect(!first.isCancelled && !current.isCancelled)
            #expect(queue.pendingCount == (separated ? 3 : 2))
            gate.resolve()
            try await current.value
            try await first.value
            try await separator?.value
            try await second.value
            #expect(events == (separated ? ["first", "separator", "second"] : ["first", "second"]))
        }
    }

    /// 相邻项取自排序后的插入位置，允许跨调度级别匹配，不误用最后提交的任务。
    @Test func replacementUsesSortedPredecessorAcrossPriorities() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask { try await gate.run() }
        await gate.started.wait()
        let old = queue.addTask(schedulingPriority: .high, replacementKey: "message") {
            Issue.record("已被替换的高优先级等待项不得执行")
        }
        var events: [String] = []
        let low = queue.addTask(schedulingPriority: .low, replacementKey: "other") { events.append("low") }
        let replacement = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueued) {
            events.append("replacement")
        }
        #expect(old.isCancelled && !low.isCancelled && queue.pendingCount == 2)
        await expectSchedulingCancellation(old)
        gate.resolve()
        try await current.value
        try await low.value
        try await replacement.value
        #expect(events == ["replacement", "low"])
    }

    /// 只有允许替换当前项的策略请求取消；当前项实际清理结束前，替代项始终等待。
    @Test(arguments: [SerialTaskQueue.ReplacementPolicy.enqueue, .replaceQueued, .replaceQueuedAndCurrent])
    func currentReplacementWaitsForCleanupAndPreservesSuccess(policy: SerialTaskQueue.ReplacementPolicy) async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let cancelled = TaskTestSignal()
        var events: [String] = []
        let current = queue.addTask(replacementKey: "message") {
            defer { events.append("cleanup") }
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: { Task { @MainActor in cancelled.signal() } }
            return 7
        }
        await gate.started.wait()
        let replacement = queue.addTask(replacementKey: "message", replacementPolicy: policy) {
            events.append("replacement")
        }
        let replaces = policy == .replaceQueuedAndCurrent
        if replaces { await cancelled.wait() }
        #expect(current.isCancelled == replaces)
        #expect(queue.isRunning && queue.pendingCount == 1 && events.isEmpty)
        gate.resolve()
        let value = try await current.value
        try await replacement.value
        #expect(value == 7 && current.isCancelled == replaces && !replacement.isCancelled)
        #expect(events == ["cleanup", "replacement"])
    }

    /// 等待项隔开当前同 key 任务时，不能越过它请求取消当前操作。
    @Test func queuedSeparatorPreventsCurrentReplacement() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask(replacementKey: "message") { try await gate.run() }
        await gate.started.wait()
        var events: [String] = []
        let separator = queue.addTask { events.append("follow") }
        let next = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) {
            events.append("message")
        }
        #expect(!current.isCancelled && queue.pendingCount == 2)
        gate.resolve()
        try await current.value
        try await separator.value
        try await next.value
        #expect(events == ["follow", "message"])
    }

    /// 队首先替换当前项，连续提交再替换等待项；后来更高优先级任务仍可排在替代项之前。
    @Test func consecutiveReplacementsRespectLaterHigherPriority() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        var events: [String] = []
        let current = queue.addTask(replacementKey: "message") {
            defer { events.append("cleanup") }
            try await gate.run()
        }
        await gate.started.wait()
        let low = queue.addTask(schedulingPriority: .low) { events.append("low") }
        let replaced = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) {
            Issue.record("中间替代项不得执行")
        }
        #expect(current.isCancelled && queue.isRunning && events.isEmpty)
        let high = queue.addTask(schedulingPriority: .high) { events.append("high") }
        let newest = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) {
            events.append("newest")
        }
        #expect(replaced.isCancelled && queue.pendingCount == 3)
        await expectSchedulingCancellation(replaced)
        gate.resolve()
        for task in [current, low, high, newest] { try await task.value }
        // 已移除项的取消处理和结果观察者只能按身份返回，不能删除 newest 或重复推进。
        #expect(events == ["cleanup", "high", "newest", "low"])
        try await waitForTaskCondition { !queue.isRunning && queue.pendingCount == 0 }
    }

    /// 同步取消句柄后立即提交时，尚未处理的取消通知不能留下相邻判定障碍。
    @Test func cancelledPendingIsRemovedBeforeAdjacencyCheck() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let current = queue.addTask(replacementKey: "message") { try await gate.run() }
        await gate.started.wait()
        let old = queue.addTask(replacementKey: "message") { Issue.record("旧等待项不得执行") }
        let separator = queue.addTask { Issue.record("取消的分隔项不得执行") }
        separator.cancel()
        // 此处不 await：取消处理还没有机会切回主 Actor，必须直接读取原生句柄状态。
        let newest = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) { 9 }
        #expect(old.isCancelled && separator.isCancelled && !current.isCancelled)
        #expect(queue.pendingCount == 1)
        await expectSchedulingCancellation(old)
        await expectSchedulingCancellation(separator)
        gate.resolve()
        try await current.value
        let value = try await newest.value
        #expect(value == 9)
    }

    /// 当前任务的同步取消处理可重新添加或清空任务，始终看到已提交的替代项。
    @Test(arguments: [false, true])
    func replacementCancellationCanReenterQueue(clearAll: Bool) async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let state = ReentrantSchedulingState()
        let current = queue.addTask(replacementKey: "message") {
            defer { state.events.append("cleanup") }
            try await withTaskCancellationHandler {
                try await gate.run()
            } onCancel: {
                // 本用例由主 Actor 上的替换操作同步触发取消，明确检查这一重入边界。
                MainActor.assumeIsolated {
                    if clearAll { queue.cancelAll() }
                    state.nested = queue.addTask(schedulingPriority: .high) { state.events.append("nested") }
                }
            }
        }
        await gate.started.wait()
        let replacement = queue.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) {
            state.events.append("replacement")
        }
        #expect(state.nested != nil && current.isCancelled && state.events.isEmpty)
        #expect(replacement.isCancelled == clearAll)
        #expect(queue.isRunning && queue.pendingCount == (clearAll ? 1 : 2))
        if clearAll { await expectSchedulingCancellation(replacement) }
        gate.resolve()
        try await current.value
        try await state.nested?.value
        if !clearAll { try await replacement.value }
        #expect(state.events == (clearAll ? ["cleanup", "nested"] : ["cleanup", "nested", "replacement"]))
    }

    /// 替换后的队列释放仍取消全部存活句柄，旧操作通过自身退出释放资源。
    @Test func releaseAfterReplacementCancelsRemainingTasks() async throws {
        var queue: SerialTaskQueue? = SerialTaskQueue()
        let isReleased = { [weak queue] in queue == nil }
        let gate = ControlledTaskOperation()
        let current = queue!.addTask(replacementKey: "message") { try await gate.run() }
        await gate.started.wait()
        let replacement = queue!.addTask(replacementKey: "message", replacementPolicy: .replaceQueuedAndCurrent) {
            Issue.record("队列释放后的替代项不得执行")
        }
        let high = queue!.addTask(schedulingPriority: .high) { Issue.record("队列释放后的等待项不得执行") }
        queue = nil
        #expect(isReleased() && current.isCancelled && replacement.isCancelled && high.isCancelled)
        await expectSchedulingCancellation(replacement)
        await expectSchedulingCancellation(high)
        gate.resolve()
        try await current.value
    }
}

/// 同步取消回调与异步操作共享的测试状态，所有读写均由主 Actor 隔离。
@MainActor
private final class ReentrantSchedulingState {
    /// 记录操作退出、清理和重入任务的执行先后。
    var events: [String] = []
    /// 取消回调同步提交的句柄，供测试等待实际结束。
    var nested: Task<Void, Error>?
}

/// 通过原生结果确认等待项取消，保留泛型返回值覆盖，不使用额外完成回调。
@MainActor
private func expectSchedulingCancellation<Success: Sendable>(_ task: Task<Success, Error>) async {
    if case .failure(let error) = await task.result { #expect(error is CancellationError) }
    else { Issue.record("被取消或替换的等待项应以 CancellationError 结束") }
}
