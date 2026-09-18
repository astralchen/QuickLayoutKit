import Foundation
import Testing
@testable import Demo

/// 超时请求取消但等待实际退出，保留结构化并发的资源所有权。
@Suite(.serialized)
struct WithTaskTimeoutTests {
    /// 未标注闭包隔离时，仍可直接访问主 Actor 状态，挂起后也保持隔离。
    @MainActor
    @Test func inheritsMainActorIsolation() async throws {
        let state = TimeoutMainActorState()
        let value = try await withTaskTimeout(for: .seconds(10)) {
            MainActor.assertIsolated()
            state.value += 1
            await Task.yield()
            MainActor.assertIsolated()
            state.value += 1
            return state.value
        }
        #expect(value == 2 && state.value == 2)
    }

    /// 自定义 Actor 的状态可在闭包中同步访问，无需转到 MainActor。
    @Test func inheritsCustomActorIsolation() async throws {
        let state = TimeoutActorState()
        #expect(try await state.incrementWithTaskTimeout() == 2)
    }

    /// 非隔离调用支持普通返回值和独占的非 Sendable 捕获转移。
    @Test func transfersNonSendableCaptureFromNonisolatedContext() async throws {
        let state = TimeoutTransferredState()
        let value = try await withTaskTimeout(for: .seconds(10)) {
            state.value += 1
            await Task.yield()
            state.value += 1
            return state.value
        }
        #expect(value == 2)
    }

    /// 非隔离调用方也可显式传入主 Actor 操作。
    @Test func acceptsExplicitMainActorOperation() async throws {
        let value = try await withTaskTimeout(for: .seconds(10)) { @MainActor in
            MainActor.assertIsolated()
            let state = TimeoutMainActorState()
            state.value = 42
            return state.value
        }
        #expect(value == 42)
    }

    /// 操作是结构化子任务，保留父任务的 Task-local 上下文。
    @Test func inheritsTaskLocalValue() async throws {
        let value = try await TimeoutTaskContext.$requestID.withValue("timeout-request") {
            try await withTaskTimeout(for: .seconds(10)) {
                await Task.yield()
                return TimeoutTaskContext.requestID
            }
        }
        #expect(value == "timeout-request")
        #expect(TimeoutTaskContext.requestID == nil)
    }

    /// 正常完成返回原值，普通失败保持原错误，不把成功操作标记为取消。
    @Test func valuesAndErrors() async throws {
        let value = try await withTaskTimeout(for: .seconds(10)) {
            defer { #expect(!Task.isCancelled) }
            return 42
        }
        #expect(value == 42)
        do {
            try await withTaskTimeout(for: .seconds(10)) { throw URLError(.badURL) }
            Issue.record("应保留普通错误")
        } catch { #expect((error as? URLError)?.code == .badURL) }
    }

    /// 固定 now 的测试时钟记录期限与容差，业务开始事件决定何时到期。
    @MainActor
    @Test(arguments: [nil, Duration.milliseconds(7)] as [Duration?])
    func clockReceivesDurationAndTolerance(_ tolerance: Duration?) async {
        let started = TaskTestSignal()
        let now = ContinuousClock.now
        let duration = Duration.milliseconds(50)
        let clock = TimeoutTestClock(now: now) { deadline, receivedTolerance in
            #expect(deadline == now.advanced(by: duration))
            #expect(receivedTolerance == tolerance)
            await started.wait()
        }
        do {
            let operation: @MainActor () async throws -> Void = {
                started.signal()
                try await Task.sleep(for: .seconds(60))
            }
            if let tolerance {
                try await withTaskTimeout(for: duration, tolerance: tolerance, clock: clock, operation: operation)
            } else {
                try await withTaskTimeout(for: duration, clock: clock, operation: operation)
            }
            Issue.record("测试时钟到期应报告超时")
        } catch { #expect(error is TimeoutError) }
    }

    /// 时钟抛错时保留原错误，并等业务清理完成才返回。
    @MainActor
    @Test func clockErrorIsPreservedAndOperationIsCleaned() async {
        let started = TaskTestSignal()
        var cleaned = false
        let clock = TimeoutTestClock { _, _ in
            await started.wait()
            throw URLError(.cannotConnectToHost)
        }
        do {
            try await withTaskTimeout(for: .seconds(10), clock: clock) {
                defer { cleaned = true }
                started.signal()
                try await Task.sleep(for: .seconds(60))
            }
            Issue.record("应保留时钟错误")
        } catch { #expect((error as? URLError)?.code == .cannotConnectToHost) }
        #expect(cleaned)
    }

    /// 业务先完成时必须取消时钟等待，并保留业务返回值。
    @MainActor
    @Test func successfulOperationCancelsClockSleep() async throws {
        let sleeping = TaskTestSignal()
        let cancellation = TimeoutMainActorState()
        let clock = TimeoutTestClock { _, _ in
            do {
                await sleeping.signal()
                try await Task.sleep(for: .seconds(60))
                Issue.record("计时子任务应被取消")
            } catch {
                #expect(error is CancellationError)
                await MainActor.run { cancellation.value += 1 }
                throw error
            }
        }
        let value = try await withTaskTimeout(for: .seconds(10), clock: clock) {
            await sleeping.wait()
            return 42
        }
        #expect(value == 42)
        #expect(cancellation.value == 1)
    }

    /// 零时长合法；长期挂起的业务不能赢得竞速，不断言它是否已启动。
    @Test func zeroDurationTimesOut() async {
        do {
            try await withTaskTimeout(for: .zero) {
                try await Task.sleep(for: .seconds(60))
            }
            Issue.record("零时长应使挂起的操作超时")
        } catch { #expect(error is TimeoutError) }
    }

    /// 在新系统上直接执行 iOS 15 兼容入口，验证返回值与普通错误。
    @Test func secondsCompatibilityPreservesValuesAndErrors() async throws {
        let value = try await withTaskTimeout(seconds: 10) { 42 }
        #expect(value == 42)
        do {
            try await withTaskTimeout(seconds: 10) { throw URLError(.badURL) }
            Issue.record("秒数兼容入口应保留原错误")
        } catch { #expect((error as? URLError)?.code == .badURL) }
    }

    @Test func secondsCompatibilityTimesOut() async {
        do {
            try await withTaskTimeout(seconds: 0) {
                try await Task.sleep(for: .seconds(60))
            }
            Issue.record("秒数兼容入口应报告超时")
        } catch { #expect(error is TimeoutError) }
    }

    @MainActor
    @Test func secondsCompatibilityPropagatesCancellation() async {
        let started = TaskTestSignal()
        var cleaned = false
        let task = Task {
            try await withTaskTimeout(seconds: 10) {
                MainActor.assertIsolated()
                defer { cleaned = true }
                started.signal()
                try await Task.sleep(for: .seconds(60))
            }
        }
        await started.wait()
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("秒数兼容入口应传播取消") }
        #expect(cleaned)
    }

    /// 超时取消信号已到达，但操作未退出前句柄与队列槽都不能完成。
    @MainActor
    @Test func timeoutWaitsForUncooperativeOperation() async throws {
        let queue = SerialTaskQueue()
        let gate = ControlledTaskOperation()
        let cancellation = TaskTestSignal()
        let clock = TimeoutTestClock { _, _ in await gate.started.wait() }
        var exited = false
        var nextStarted = false
        let task = queue.addTask {
            defer { exited = true }
            try await withTaskTimeout(for: .milliseconds(50), clock: clock) {
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
    @MainActor
    @Test func parentCancellationWaitsForChildren() async {
        let started = TaskTestSignal()
        let cleaned = TaskTestSignal()
        let task = Task {
            try await withTaskTimeout(for: .seconds(10)) {
                defer { cleaned.signal() }
                started.signal()
                try await Task.sleep(for: .seconds(60))
            }
        }
        await started.wait()
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应取消") }
        await cleaned.wait()
    }

    /// 进入超时包装之前已经取消，不启动业务或计时子任务。
    @MainActor
    @Test func preCancelledOperationDoesNotStart() async {
        let task = Task {
            try await withTaskTimeout(for: .seconds(10)) { Issue.record("已取消任务不得开始") }
        }
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应取消") }
    }
}

@MainActor
private final class TimeoutMainActorState {
    var value = 0
}

private actor TimeoutActorState {
    var value = 0

    func incrementWithTaskTimeout() async throws -> Int {
        try await withTaskTimeout(for: .seconds(10)) {
            self.assertIsolated()
            self.value += 1
            await Task.yield()
            self.assertIsolated()
            self.value += 1
            return self.value
        }
    }
}

private final class TimeoutTransferredState {
    var value = 0
}

private enum TimeoutTaskContext {
    @TaskLocal static var requestID: String?
}

/// 由事件驱动 sleep，期限计算使用固定 now，不依赖真实时间推进。
private struct TimeoutTestClock: Clock {
    var now: ContinuousClock.Instant = .now
    var minimumResolution: Duration { .nanoseconds(1) }
    let onSleep: @Sendable (ContinuousClock.Instant, Duration?) async throws -> Void

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        try await onSleep(deadline, tolerance)
    }
}
