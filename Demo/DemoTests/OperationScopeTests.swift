import Testing
@testable import Demo

/// 验证操作有效期与任务取消、回调生命周期之间的边界。
@MainActor
struct OperationScopeTests {
    /// 新操作和显式停止均使旧回调失效，重复停止后仍可重新开始。
    @Test func replacementAndInvalidationRejectOldCallbacks() throws {
        let scope = OperationScope()
        let first = scope.begin()
        let copiedFirst = first
        let second = scope.begin()
        #expect(!first.isCurrent)
        #expect(!copiedFirst.isCurrent)
        #expect(second.isCurrent)
        #expect(throws: CancellationError.self) { try first.checkCancellation() }
        scope.invalidate()
        scope.invalidate()
        #expect(!second.isCurrent)
        try scope.begin().checkCancellation()
    }

    /// 同一页面中的不同操作通道不应互相取消。
    @Test func independentScopesDoNotInvalidateEachOther() throws {
        let images = OperationScope()
        let speech = OperationScope()
        let image = images.begin()
        let recognition = speech.begin()
        images.invalidate()
        #expect(!image.isCurrent)
        try recognition.checkCancellation()
    }

    /// 捕获令牌的系统回调不应延长 Scope 的生命周期。
    @Test func releasingScopeInvalidatesRetainedToken() {
        var scope: OperationScope? = OperationScope()
        let token = scope!.begin()
        scope = nil
        #expect(!token.isCurrent)
        #expect(throws: CancellationError.self) { try token.checkCancellation() }
    }

    /// 任务取消后仍能识别资源归属，以完成清理，但不能继续正常执行。
    @Test func taskCancellationPreservesOwnershipForCleanup() async {
        let scope = OperationScope()
        let token = scope.begin()
        let task = Task { @MainActor in
            #expect(Task.isCancelled)
            #expect(token.isCurrent)
            #expect(throws: CancellationError.self) { try token.checkCancellation() }
        }
        task.cancel()
        await task.value
        #expect(token.isCurrent)
    }

    /// 异步启动方法返回后，会话回调仍有效，直到业务显式停止。
    @Test func sessionOutlivesStartupTask() async throws {
        let scope = OperationScope()
        let startup = Task { @MainActor in scope.begin() }
        let token = await startup.value
        try token.checkCancellation()
        scope.invalidate()
        #expect(!token.isCurrent)
    }
}
