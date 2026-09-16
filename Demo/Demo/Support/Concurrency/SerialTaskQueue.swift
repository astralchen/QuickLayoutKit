import Foundation

/// 主 Actor 上的严格串行任务队列；取消只发出请求，当前任务实际退出后才推进。
/// 资源清理由操作自行完成；返回原生 Task，不改写操作的结果或取消语义。
@MainActor
final class SerialTaskQueue {
    /// 一次执行许可，只用于等待调度，不参与业务结果结算。
    @MainActor
    private final class Permit {
        /// 尚未获得执行许可的协程。
        private var continuation: CheckedContinuation<Void, Error>?
        /// 许可或取消可能先于等待发生，仅保存第一次决定。
        private var result: Result<Void, Error>?

        /// 等待队列许可；等待期间取消会恢复为 CancellationError。
        func wait() async throws {
            if let result { return try result.get() }
            try await withCheckedThrowingContinuation { continuation = $0 }
        }

        /// 发放许可或取消等待；迟到的重复决定不影响已经开始的操作。
        func resolve(_ result: Result<Void, Error>) {
            guard self.result == nil else { return }
            self.result = result
            let continuation = continuation
            self.continuation = nil
            continuation?.resume(with: result)
        }
    }

    /// 不同返回类型的任务统一保存调度身份与原生取消行为。
    private struct Entry {
        /// 独立身份，防止等待项或旧观察者结束时清理当前项。
        let id: UUID
        /// 只有当前项可以获得执行许可。
        let permit: Permit
        /// 请求原生 Task 取消，不决定其结果或何时结束。
        let cancel: () -> Void
    }

    /// 当前执行槽，包含取消后仍在退出的任务。
    private var current: Entry?
    /// 尚未获准执行的 FIFO 列表。
    private var pending: [Entry] = []
    /// 当前是否占用执行槽；收到取消请求不会立即变为 false。
    var isRunning: Bool { current != nil }
    /// 尚未开始的任务数量，不含当前项。
    var pendingCount: Int { pending.count }

    /// 创建可立即接收任务的队列；页面接收策略由使用方管理。
    init() {}

    /// 请求所有任务取消并解除等待；运行项通过自身取消处理异步释放资源。
    isolated deinit {
        current?.cancel()
        for entry in pending {
            entry.cancel()
            entry.permit.resolve(.failure(CancellationError()))
        }
    }

    /// 立即返回原生句柄；只有轮到本项时才调用 operation。
    /// 进入操作前检查取消，操作开始后的返回值与错误完全由操作决定。
    @discardableResult
    func addTask<Success: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @MainActor @Sendable () async throws -> Success
    ) -> Task<Success, Error> {
        let id = UUID()
        let permit = Permit()
        let task = Task(priority: priority) { @MainActor [weak self] in
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await permit.wait()
                try Task.checkCancellation()
                return try await operation()
            } onCancel: {
                Task { @MainActor [weak self] in
                    self?.cancelWaiting(id)
                    permit.resolve(.failure(CancellationError()))
                }
            }
        }
        pending.append(Entry(id: id, permit: permit, cancel: { task.cancel() }))
        // 观察者只在原生 Task 实际结束后回传，不跨等待强持有队列。
        Task { @MainActor [weak self] in
            _ = await task.result
            self?.finish(id)
        }
        startNextIfPossible()
        return task
    }

    /// 取消调用时已有的任务；之后仍可添加，新任务等待当前操作实际退出。
    func cancelAll() {
        let waiting = pending
        pending.removeAll()
        current?.cancel()
        for entry in waiting {
            entry.cancel()
            entry.permit.resolve(.failure(CancellationError()))
        }
    }

    /// 单项取消只移除仍在等待的项，不释放当前执行槽。
    private func cancelWaiting(_ id: UUID) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let entry = pending.remove(at: index)
        entry.permit.resolve(.failure(CancellationError()))
    }

    /// 空闲时向第一项发放许可；优先级不改变 FIFO 顺序。
    private func startNextIfPossible() {
        guard current == nil, !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        current = entry
        entry.permit.resolve(.success(()))
    }

    /// 只有当前原生 Task 已实际结束，才能释放执行槽并推进。
    private func finish(_ id: UUID) {
        guard current?.id == id else {
            cancelWaiting(id)
            return
        }
        current = nil
        startNextIfPossible()
    }
}
