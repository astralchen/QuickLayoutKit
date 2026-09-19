import Foundation
import Testing
@testable import Demo

/// 使用事件和可注入时钟验证重试，不依赖真实时间推进。
@Suite(.serialized)
struct WithTaskRetryTests {
    @MainActor
    @Test(arguments: [1, 3])
    func successStopsImmediately(successAttempt: Int) async throws {
        var attempts = 0
        let value = try await withTaskRetry(maxAttempts: 5, delay: .immediate, shouldRetry: { _ in true }) {
            attempts += 1
            if attempts < successAttempt { throw RetryTestError(attempt: attempts) }
            return 42
        }
        #expect(value == 42 && attempts == successAttempt)
    }

    @MainActor
    @Test(arguments: [1, 3])
    func exhaustionPreservesLastError(limit: Int) async {
        var attempts = 0
        do {
            try await withTaskRetry(maxAttempts: limit, delay: .custom { index, error in
                #expect(index < limit)
                #expect((error as? RetryTestError)?.attempt == index)
                return .zero
            }, shouldRetry: { error in
                #expect((error as? RetryTestError)?.attempt != limit, "耗尽后不再筛选")
                return true
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
            Issue.record("应失败")
        } catch { #expect((error as? RetryTestError)?.attempt == limit) }
        #expect(attempts == limit)
    }

    @Test func rejectedErrorSkipsDelay() async {
        do {
            try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                Issue.record("拒绝重试后不计算间隔")
                return .zero
            }, shouldRetry: { _ in false }) { throw RetryTestError(attempt: 1) }
            Issue.record("应失败")
        } catch { #expect((error as? RetryTestError)?.attempt == 1) }
    }

    @Test(arguments: [false, true])
    func cancellationErrorsBypassPolicies(urlCancellation: Bool) async {
        do {
            try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                Issue.record("取消后不计算间隔")
                return .zero
            }, shouldRetry: { _ in
                Issue.record("取消错误不进入 shouldRetry")
                return true
            }) {
                if urlCancellation { throw URLError(.cancelled) }
                throw CancellationError()
            }
            Issue.record("应取消")
        } catch {
            if urlCancellation { #expect((error as? URLError)?.code == .cancelled) }
            else { #expect(error is CancellationError) }
        }
    }

    @MainActor
    @Test func preCancelledNeverStarts() async {
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delay: .immediate, shouldRetry: { _ in
                Issue.record("不应筛选错误")
                return true
            }) { Issue.record("已取消任务不能启动操作") }
        }
        task.cancel()
        await expectRetryCancellation(task)
    }

    /// 取消不强制结束旧操作；旧操作抛普通错误时，也不能启动重试。
    @MainActor
    @Test(arguments: [false, true])
    func cancellationWaitsForOperation(preservesSuccess: Bool) async throws {
        let gate = ControlledTaskOperation()
        var exited = false
        let task = Task {
            defer { exited = true }
            return try await withTaskRetry(maxAttempts: 3, delay: .immediate, shouldRetry: { _ in
                Issue.record("父任务取消后不得筛选普通错误")
                return true
            }) {
                try await gate.run()
                return 42
            }
        }
        await gate.started.wait()
        task.cancel()
        #expect(!exited)
        gate.resolve(preservesSuccess ? .success(()) : .failure(RetryTestError(attempt: 1)))
        if preservesSuccess { #expect(try await task.value == 42) }
        else { await expectRetryCancellation(task) }
        #expect(exited)
    }

    @MainActor
    @Test func cancellationDuringOperationCleansUp() async {
        let started = TaskTestSignal()
        var cleaned = false
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delay: .immediate, shouldRetry: { _ in
                Issue.record("操作取消不进入筛选")
                return true
            }) {
                defer { cleaned = true }
                started.signal()
                try await Task.sleep(for: .seconds(60))
            }
        }
        await started.wait()
        task.cancel()
        await expectRetryCancellation(task)
        #expect(cleaned)
    }

    @MainActor
    @Test func cancellationDuringDelayStopsNextAttempt() async {
        let sleeping = TaskTestSignal()
        var attempts = 0
        let clock = RetryTestClock { _, _ in
            await sleeping.signal()
            try await Task.sleep(for: .seconds(60))
        }
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delay: .fixed(.seconds(10)), clock: clock, shouldRetry: { _ in true }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
        }
        await sleeping.wait()
        task.cancel()
        await expectRetryCancellation(task)
        #expect(attempts == 1)
    }

    @MainActor
    @Test(arguments: [false, true])
    func cancellationInsidePolicyStopsZeroDelay(cancelInFilter: Bool) async {
        var attempts = 0
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                #expect(!cancelInFilter, "筛选阶段取消后不应调用等待策略")
                withUnsafeCurrentTask { $0?.cancel() }
                return .zero
            }, shouldRetry: { _ in
                if cancelInFilter { withUnsafeCurrentTask { $0?.cancel() } }
                return true
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
        }
        await expectRetryCancellation(task)
        #expect(attempts == 1)
    }

    @MainActor
    @Test(arguments: [nil, Duration.milliseconds(7)] as [Duration?])
    func fixedDelayPassesDeadlineAndTolerance(tolerance: Duration?) async throws {
        let now = ContinuousClock.now
        let clock = RetryTestClock(now: now) { deadline, receivedTolerance in
            #expect(deadline == now.advanced(by: .milliseconds(300)))
            #expect(receivedTolerance == tolerance)
        }
        var attempts = 0
        let result = try await withTaskRetry(maxAttempts: 2, delay: .fixed(.milliseconds(300)), tolerance: tolerance,
                                             clock: clock, shouldRetry: { _ in true }) {
            attempts += 1
            if attempts == 1 { throw RetryTestError(attempt: 1) }
            return attempts
        }
        #expect(result == 2)
    }

    @MainActor
    @Test func zeroDelaySkipsClock() async throws {
        let clock = RetryTestClock { _, _ in Issue.record("零时长不调用 Clock") }
        var attempts = 0
        try await withTaskRetry(maxAttempts: 2, delay: .fixed(.zero), clock: clock, shouldRetry: { _ in true }) {
            attempts += 1
            if attempts == 1 { throw RetryTestError(attempt: 1) }
        }
        #expect(attempts == 2)
    }

    @MainActor
    @Test func clockErrorIsNotRetried() async {
        var attempts = 0
        let clock = RetryTestClock { _, _ in throw URLError(.cannotConnectToHost) }
        do {
            try await withTaskRetry(maxAttempts: 3, delay: .fixed(.seconds(1)), clock: clock, shouldRetry: { error in
                #expect(error is RetryTestError, "时钟错误不进入筛选")
                return true
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
            Issue.record("应报告时钟错误")
        } catch { #expect((error as? URLError)?.code == .cannotConnectToHost) }
        #expect(attempts == 1)
    }

    @Test func exponentialGrowthCapsAndDoesNotShareProgress() {
        let policy: RetryDelay<Duration> = .exponential(initial: .milliseconds(500), maximum: .seconds(5))
        var schedule = durationSchedule(policy)
        let values = (1...6).map { schedule.next(retryIndex: $0, error: RetryTestError(attempt: $0)) }
        #expect(values == [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4), .seconds(5), .seconds(5)])
        var independent = durationSchedule(policy)
        #expect(independent.next(retryIndex: 1, error: RetryTestError(attempt: 1)) == .milliseconds(500))
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func fullJitterDoesNotChangeBackoffProgress(unit: Double) {
        var schedule = durationSchedule(.exponential(initial: .seconds(2), maximum: .seconds(5), jitter: .full), randomUnit: { unit })
        let values = (1...4).map { schedule.next(retryIndex: $0, error: RetryTestError(attempt: $0)) }
        #expect(values == [2.0, 4.0, 5.0, 5.0].map { Duration.seconds($0 * unit) })
    }

    @Test func scalingHandlesFractionalMultiplierAndExtremeValues() {
        #expect(retryScaleDuration(Duration.seconds(2), 1.5, .seconds(10)) == .seconds(3))
        #expect(retryScaleDuration(Duration.seconds(2), 3, .seconds(10)) == .seconds(6))
        let huge = Duration.seconds(Int64.max)
        #expect(retryScaleDuration(huge, 2, huge) == huge)
        #expect(retryScaleDuration(Duration.seconds(1), Double.greatestFiniteMagnitude, huge) == huge)
        #expect(retryScaleDuration(Duration.zero, Double.greatestFiniteMagnitude, huge) == .zero)
        #expect(retryScaleDuration(huge, 1, huge) == huge)
        #expect(retryScaleDuration(Duration(secondsComponent: 0, attosecondsComponent: 8), 0.5, huge)
            == Duration(secondsComponent: 0, attosecondsComponent: 4))
        #expect(retryScaleDuration(Duration(secondsComponent: 0, attosecondsComponent: 3), 0.75, huge)
            == Duration(secondsComponent: 0, attosecondsComponent: 2))
        #expect(retryScaleDuration(Duration.seconds(1), Double.leastNonzeroMagnitude, huge) == .zero)
        #expect(retryScaleSeconds(1, Double.greatestFiniteMagnitude, 5) == 5)
        #expect(retryScaleSeconds(0, Double.greatestFiniteMagnitude, 5) == 0)
        #expect(retryScaleSeconds(2, 1.5, 5) == 3)
    }

    @MainActor
    @Test func supportsClockWithCustomDuration() async throws {
        var attempts = 0
        try await withTaskRetry(maxAttempts: 2, delay: .fixed(RetryTicks(value: 7)), tolerance: .init(value: 1),
                                clock: RetryTickClock(), shouldRetry: { _ in true }) {
            attempts += 1
            if attempts == 1 { throw RetryTestError(attempt: 1) }
        }
        #expect(attempts == 2)
        #expect(retryScaleDuration(RetryTicks(value: 3), 0.75, .init(value: 10)) == .init(value: 2))
        #expect(retryScaleDuration(RetryTicks(value: Int.max), 2, .init(value: Int.max)) == .init(value: Int.max))
    }

    @Test func customDelayReceivesIndexAndOriginalError() {
        var schedule = durationSchedule(.custom { index, error in
            #expect((error as? RetryTestError)?.attempt == index)
            return .milliseconds(index * 100)
        })
        #expect(schedule.next(retryIndex: 1, error: RetryTestError(attempt: 1)) == .milliseconds(100))
        #expect(schedule.next(retryIndex: 2, error: RetryTestError(attempt: 2)) == .milliseconds(200))
    }

    @MainActor
    @Test func inheritsMainActorAcrossAttempts() async throws {
        var count = 0
        #expect(try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: { _ in .retry() }) {
            MainActor.assertIsolated()
            count += 1
            await Task.yield()
            MainActor.assertIsolated()
            if count == 1 { throw RetryTestError(attempt: 1) }
            return count
        } == 2)
    }

    @Test func inheritsCustomActorAcrossAttempts() async throws {
        #expect(try await RetryTestActor().run() == 2)
    }

    @Test func transfersNonSendableCaptureAcrossAttempts() async throws {
        let state = RetryTransferredState()
        let value = try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: { _ in .retry() }) {
            state.count += 1
            await Task.yield()
            if state.count == 1 { throw RetryTestError(attempt: 1) }
            return state.count
        }
        #expect(value == 2)
    }

    @Test func explicitIsolationAndTaskLocalArePreserved() async throws {
        let value = try await RetryTestContext.$requestID.withValue("retry-request") {
            try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: { _ in .retry() }) { @MainActor in
                MainActor.assertIsolated()
                return RetryTestContext.requestID
            }
        }
        #expect(value == "retry-request" && RetryTestContext.requestID == nil)
    }

    @MainActor
    @Test func taskLocalSurvivesFailedAttemptAndDelay() async throws {
        var attempts = 0
        let clock = RetryTestClock { _, _ in #expect(RetryTestContext.requestID == "retry-request") }
        try await RetryTestContext.$requestID.withValue("retry-request") {
            try await withTaskRetry(maxAttempts: 2, delay: .fixed(.seconds(1)), clock: clock, policy: { _ in
                #expect(RetryTestContext.requestID == "retry-request")
                return .retry()
            }) {
                #expect(RetryTestContext.requestID == "retry-request")
                attempts += 1
                if attempts == 1 { throw RetryTestError(attempt: 1) }
            }
        }
        #expect(attempts == 2 && RetryTestContext.requestID == nil)
    }

    /// 超时取消的是一次尝试的子任务，不能把外层重试任务也标记为取消。
    @MainActor
    @Test func retriesPerAttemptTimeoutAfterCleanup() async throws {
        let gate = ControlledTaskOperation()
        let cancelled = TaskTestSignal()
        var attempts = 0
        var cleaned = false
        let clock = RetryTestClock { _, _ in await gate.started.wait() }
        let task = Task {
            try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: { $0.error is TimeoutError ? .retry() : .stop }) {
                attempts += 1
                if attempts == 1 {
                    try await withTaskTimeout(for: .seconds(1), clock: clock) {
                        defer { cleaned = true }
                        try await withTaskCancellationHandler {
                            try await gate.run()
                        } onCancel: { Task { @MainActor in cancelled.signal() } }
                    }
                }
                #expect(cleaned && !Task.isCancelled)
                return 42
            }
        }
        await cancelled.wait()
        #expect(attempts == 1 && !cleaned)
        gate.resolve()
        #expect(try await task.value == 42)
        #expect(attempts == 2 && cleaned)
    }

    @MainActor
    @Test func totalTimeoutCancelsRetryDuringDelay() async {
        let sleeping = TaskTestSignal()
        var attempts = 0
        var delayCleaned = false
        let totalClock = RetryTestClock { _, _ in await sleeping.wait() }
        let delayClock = RetryTestClock { _, _ in
            await sleeping.signal()
            do { try await Task.sleep(for: .seconds(60)) }
            catch {
                await MainActor.run { delayCleaned = true }
                throw error
            }
        }
        do {
            try await withTaskTimeout(for: .seconds(1), clock: totalClock) {
                try await withTaskRetry(maxAttempts: 3, delay: .fixed(.seconds(10)), clock: delayClock, policy: { _ in .retry() }) {
                    attempts += 1
                    throw RetryTestError(attempt: attempts)
                }
            }
            Issue.record("应报告总超时")
        } catch { #expect(error is TimeoutError) }
        #expect(attempts == 1 && delayCleaned)
    }

    @MainActor
    @Test(arguments: [1, 3])
    func secondsEntryRetriesAndPreservesLastError(limit: Int) async {
        var attempts = 0
        do {
            try await withTaskRetry(maxAttempts: limit, delaySeconds: .custom { index, error in
                #expect(index < limit && (error as? RetryTestError)?.attempt == index)
                return 0
            }, shouldRetry: { _ in true }) {
                MainActor.assertIsolated()
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
            Issue.record("应失败")
        } catch { #expect((error as? RetryTestError)?.attempt == limit) }
        #expect(attempts == limit)
    }

    @MainActor
    @Test(arguments: [false, true])
    func secondsEntryReturnsSuccessAndRejectsCancellation(urlCancellation: Bool) async throws {
        var attempts = 0
        let value = try await withTaskRetry(maxAttempts: 2, delaySeconds: .fixed(0), shouldRetry: { _ in true }) {
            attempts += 1
            if attempts == 1 { throw RetryTestError(attempt: 1) }
            return 42
        }
        #expect(value == 42 && attempts == 2)
        do {
            try await withTaskRetry(maxAttempts: 2, delaySeconds: .immediate, shouldRetry: { _ in
                Issue.record("秒数入口也不筛选取消错误")
                return true
            }) {
                if urlCancellation { throw URLError(.cancelled) }
                throw CancellationError()
            }
            Issue.record("应取消")
        } catch {
            if urlCancellation { #expect((error as? URLError)?.code == .cancelled) }
            else { #expect(error is CancellationError) }
        }
    }

    @MainActor
    @Test func secondsEntryCancelsWaiting() async {
        let scheduled = TaskTestSignal()
        var attempts = 0
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delaySeconds: .custom { _, _ in
                Task { @MainActor in scheduled.signal() }
                return 60
            }, shouldRetry: { _ in true }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
        }
        await scheduled.wait()
        task.cancel()
        await expectRetryCancellation(task)
        #expect(attempts == 1)
    }
}

extension WithTaskRetryTests {
    /// 两个决策入口保持旧接口的次数和结果语义；最后一次失败不再询问 policy。
    @MainActor
    @Test(arguments: [false, true], [1, 3])
    func policyReceivesContextAndPreservesResults(seconds: Bool, limit: Int) async throws {
        for succeeds in [false, true] {
            var attempts = 0
            let operation: @MainActor () async throws -> Int = {
                attempts += 1
                if succeeds && attempts == limit { return 42 }
                throw RetryTestError(attempt: attempts)
            }
            let checkContext: @Sendable (RetryContext) -> Void = { context in
                #expect(context.failedAttempt < limit)
                #expect((context.error as? RetryTestError)?.attempt == context.failedAttempt)
            }
            do {
                let result: Int
                if seconds {
                    result = try await withTaskRetry(maxAttempts: limit, delaySeconds: .immediate, policy: {
                        checkContext($0)
                        return .retry()
                    }, operation: operation)
                } else {
                    result = try await withTaskRetry(maxAttempts: limit, delay: .immediate, policy: {
                        checkContext($0)
                        return .retry()
                    }, operation: operation)
                }
                #expect(succeeds && result == 42)
            } catch {
                #expect(!succeeds && (error as? RetryTestError)?.attempt == limit)
            }
            #expect(attempts == limit)
        }
    }

    @MainActor
    @Test(arguments: [false, true])
    func policyStopSkipsDelay(seconds: Bool) async {
        var attempts = 0
        let operation: @MainActor () async throws -> Void = {
            attempts += 1
            throw RetryTestError(attempt: attempts)
        }
        do {
            if seconds {
                try await withTaskRetry(maxAttempts: 3, delaySeconds: .custom { _, _ in
                    Issue.record("停止后不计算退避")
                    return 0
                }, policy: { _ in .stop }, operation: operation)
            } else {
                let clock = RetryTestClock { _, _ in Issue.record("停止后不等待") }
                try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                    Issue.record("停止后不计算退避")
                    return .zero
                }, clock: clock, policy: { _ in .stop }, operation: operation)
            }
            Issue.record("应保留操作错误")
        } catch { #expect((error as? RetryTestError)?.attempt == 1) }
        #expect(attempts == 1)
    }

    @Test(arguments: [false, true], [false, true])
    func cancellationNeverReachesDecision(seconds: Bool, urlCancellation: Bool) async {
        let operation: @Sendable @isolated(any) () async throws -> Void = {
            if urlCancellation { throw URLError(.cancelled) }
            throw CancellationError()
        }
        do {
            if seconds {
                try await withTaskRetry(maxAttempts: 3, delaySeconds: .immediate, policy: { _ in
                    Issue.record("取消不询问决策")
                    return .retry()
                }, operation: operation)
            } else {
                try await withTaskRetry(maxAttempts: 3, delay: .immediate, policy: { _ in
                    Issue.record("取消不询问决策")
                    return .retry()
                }, operation: operation)
            }
            Issue.record("应取消")
        } catch {
            if urlCancellation { #expect((error as? URLError)?.code == .cancelled) }
            else { #expect(error is CancellationError) }
        }
    }

    @MainActor
    @Test(arguments: [false, true])
    func cancellationDuringDecisionWinsEvenWhenStopping(stops: Bool) async {
        var attempts = 0
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                Issue.record("决策中取消后不计算退避")
                return .zero
            }, policy: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return stops ? .stop : .retry(minimumDelay: .seconds(60))
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
        }
        await expectRetryCancellation(task)
        #expect(attempts == 1)
    }

    @MainActor
    @Test(arguments: [Duration.zero, .seconds(1), .seconds(2), .seconds(120)])
    func minimumDelayCombinesWithBackoff(minimum: Duration) async throws {
        let sleeps = RetrySleepRecorder()
        let now = ContinuousClock.now
        let clock = RetryTestClock(now: now) { deadline, _ in await sleeps.append(now.duration(to: deadline)) }
        var attempts = 0
        try await withTaskRetry(maxAttempts: 2, delay: .exponential(initial: .seconds(2), maximum: .seconds(5)),
                                clock: clock, policy: { _ in .retry(minimumDelay: minimum) }) {
            attempts += 1
            if attempts == 1 { throw RetryTestError(attempt: 1) }
        }
        #expect(await sleeps.values == [max(.seconds(2), minimum)])
        #expect(attempts == 2)
    }

    /// 模拟服务端要求比本地上限更长的等待，最终 sleep 不能再被 full jitter 缩短。
    @MainActor
    @Test func serverMinimumSurvivesFullJitter() async throws {
        let sleeps = RetrySleepRecorder()
        let now = ContinuousClock.now
        let clock = RetryTestClock(now: now) { deadline, _ in await sleeps.append(now.duration(to: deadline)) }
        var attempts = 0
        try await withTaskRetry(maxAttempts: 3,
                                delay: .exponential(initial: .seconds(2), maximum: .seconds(5), jitter: .full),
                                clock: clock, policy: { _ in .retry(minimumDelay: .seconds(120)) }) {
            attempts += 1
            if attempts < 3 { throw RetryTestError(attempt: attempts) }
        }
        #expect(await sleeps.values == [.seconds(120), .seconds(120)])
    }

    @Test(arguments: [0.0, 0.5, 1.0])
    func minimumDoesNotChangeJitterOrBackoffProgress(unit: Double) {
        var schedule = durationSchedule(.exponential(initial: .seconds(2), maximum: .seconds(5), jitter: .full), randomUnit: { unit })
        #expect(schedule.next(retryIndex: 1, error: RetryTestError(attempt: 1), minimumDelay: .seconds(120)) == .seconds(120))
        #expect(schedule.next(retryIndex: 2, error: RetryTestError(attempt: 2)) == .seconds(4 * unit))
        #expect(schedule.next(retryIndex: 3, error: RetryTestError(attempt: 3), minimumDelay: .seconds(3)) == max(.seconds(5 * unit), .seconds(3)))
    }

    @Test func invalidDurationMinimumStopsBeforeBackoff() async {
        let clock = RetryTestClock { _, _ in Issue.record("非法动态值不能进入 Clock") }
        do {
            try await withTaskRetry(maxAttempts: 3, delay: .custom { _, _ in
                Issue.record("非法动态值不能触发退避")
                return .zero
            }, clock: clock, policy: { _ in .retry(minimumDelay: .seconds(-1)) }) {
                throw RetryTestError(attempt: 1)
            }
            Issue.record("应保留操作错误")
        } catch { #expect((error as? RetryTestError)?.attempt == 1) }
    }

    @Test(arguments: [-1.0, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, Double(UInt64.max) / 1_000_000_000])
    func invalidSecondsMinimumStopsBeforeBackoff(minimum: Double) async {
        do {
            try await withTaskRetry(maxAttempts: 3, delaySeconds: .custom { _, _ in
                Issue.record("非法动态值不能触发退避")
                return 0
            }, policy: { _ in .retry(minimumDelay: minimum) }) { throw RetryTestError(attempt: 1) }
            Issue.record("应保留操作错误")
        } catch { #expect((error as? RetryTestError)?.attempt == 1) }
    }

    @MainActor
    @Test func secondsMinimumDelayCanBeCancelled() async {
        let scheduled = TaskTestSignal()
        var attempts = 0
        let task = Task {
            try await withTaskRetry(maxAttempts: 3, delaySeconds: .immediate, policy: { _ in
                Task { @MainActor in scheduled.signal() }
                return .retry(minimumDelay: 60)
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
        }
        await scheduled.wait()
        task.cancel()
        await expectRetryCancellation(task)
        #expect(attempts == 1)
    }

    @MainActor
    @Test func decisionClockErrorIsNotRetried() async {
        var attempts = 0
        let clock = RetryTestClock { _, _ in throw URLError(.cannotConnectToHost) }
        do {
            try await withTaskRetry(maxAttempts: 3, delay: .immediate, clock: clock, policy: { context in
                #expect(context.error is RetryTestError)
                return .retry(minimumDelay: .seconds(1))
            }) {
                attempts += 1
                throw RetryTestError(attempt: attempts)
            }
            Issue.record("应保留 Clock 错误")
        } catch { #expect((error as? URLError)?.code == .cannotConnectToHost) }
        #expect(attempts == 1)
    }

    /// 连接等待发生在下一次 operation 内；离线期间没有额外尝试。
    @MainActor
    @Test func connectionRecoveryCompletesOneWaitingAttempt() async throws {
        let connection = RetryConnectionGate()
        var attempts = 0
        var requests = 0
        let task = Task {
            try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: {
                ($0.error as? URLError)?.code == .notConnectedToInternet ? .retry() : .stop
            }) {
                attempts += 1
                if attempts == 1 { throw URLError(.notConnectedToInternet) }
                try await connection.wait()
                requests += 1
                return 42
            }
        }
        await connection.waiting.wait()
        #expect(attempts == 2 && requests == 0)
        connection.restore()
        connection.restore()
        #expect(try await task.value == 42)
        connection.restore()
        #expect(attempts == 2 && requests == 1 && connection.pendingCount == 0)
    }

    @MainActor
    @Test(arguments: [false, true])
    func recoveryAfterCancellationOrTimeoutDoesNotSend(timesOut: Bool) async {
        let connection = RetryConnectionGate()
        var attempts = 0
        var requests = 0
        let clock = RetryTestClock { _, _ in await connection.waiting.wait() }
        let operation: @MainActor () async throws -> Void = {
            try await withTaskRetry(maxAttempts: 3, delay: .immediate, policy: {
                ($0.error as? URLError)?.code == .notConnectedToInternet ? .retry() : .stop
            }) {
                attempts += 1
                if attempts == 1 { throw URLError(.notConnectedToInternet) }
                try await connection.wait()
                requests += 1
            }
        }
        let task = Task {
            if timesOut { try await withTaskTimeout(for: .seconds(10), clock: clock, operation: operation) }
            else { try await operation() }
        }
        await connection.waiting.wait()
        if !timesOut { task.cancel() }
        do {
            try await task.value
            Issue.record("应以取消或总超时结束")
        } catch {
            if timesOut { #expect(error is TimeoutError) }
            else { #expect(error is CancellationError) }
        }
        #expect(connection.pendingCount == 0)
        connection.restore()
        connection.restore()
        #expect(attempts == 2 && requests == 0)
    }
}

private actor RetrySleepRecorder {
    private(set) var values: [Duration] = []
    func append(_ value: Duration) { values.append(value) }
}

/// 测试专用连接门闩；注册与恢复都在 MainActor，取消按等待身份移除 continuation。
/// 不监听真实网络；恢复只解除等待，实际操作还会检查当前任务取消状态。
@MainActor
private final class RetryConnectionGate {
    let waiting = TaskTestSignal()
    private var online = false
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    var pendingCount: Int { pending.count }

    func wait() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else if online { continuation.resume() }
                else {
                    pending[id] = continuation
                    waiting.signal()
                }
            }
        } onCancel: {
            Task { @MainActor in self.pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
        try Task.checkCancellation()
    }

    func restore() {
        online = true
        let continuations = Array(pending.values)
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct RetryTestError: Error { let attempt: Int }

private struct RetryTestClock: Clock {
    var now: ContinuousClock.Instant = .now
    var minimumResolution: Duration { .nanoseconds(1) }
    let onSleep: @Sendable (ContinuousClock.Instant, Duration?) async throws -> Void

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        try await onSleep(deadline, tolerance)
    }
}

/// 用独立的整数时间单位验证接口没有假定 Clock.Duration 必须是 Swift.Duration。
private struct RetryTicks: DurationProtocol {
    let value: Int
    static var zero: Self { .init(value: 0) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    static func + (lhs: Self, rhs: Self) -> Self { .init(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(value: lhs.value - rhs.value) }
    static func * (lhs: Self, rhs: Int) -> Self { .init(value: lhs.value * rhs) }
    static func / (lhs: Self, rhs: Int) -> Self { .init(value: lhs.value / rhs) }
    static func / (lhs: Self, rhs: Self) -> Double { Double(lhs.value) / Double(rhs.value) }
}

private struct RetryTickInstant: InstantProtocol {
    let value: Int
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
    func advanced(by duration: RetryTicks) -> Self { .init(value: value + duration.value) }
    func duration(to other: Self) -> RetryTicks { .init(value: other.value - value) }
}

private struct RetryTickClock: Clock {
    var now: RetryTickInstant { .init(value: 100) }
    var minimumResolution: RetryTicks { .init(value: 1) }
    func sleep(until deadline: RetryTickInstant, tolerance: RetryTicks?) async throws {
        #expect(deadline.value == 107 && tolerance?.value == 1)
    }
}

private func durationSchedule(
    _ delay: RetryDelay<Duration>,
    randomUnit: @escaping @Sendable () -> Double = { Issue.record("无抖动时不应取随机数"); return 0 }
) -> RetryDelaySchedule<Duration> {
    RetryDelaySchedule(delay: delay, validate: { #expect($0 >= .zero) }, scale: retryScaleDuration, randomUnit: randomUnit)
}

private func expectRetryCancellation<T>(_ task: Task<T, Error>) async {
    if case .failure(let error) = await task.result { #expect(error is CancellationError) }
    else { Issue.record("应以 CancellationError 结束") }
}

private final class RetryTransferredState { var count = 0 }

private actor RetryTestActor {
    var count = 0

    func run() async throws -> Int {
        try await withTaskRetry(maxAttempts: 2, delay: .immediate, policy: { _ in .retry() }) {
            self.assertIsolated()
            self.count += 1
            await Task.yield()
            self.assertIsolated()
            if self.count == 1 { throw RetryTestError(attempt: 1) }
            return self.count
        }
    }
}

private enum RetryTestContext {
    @TaskLocal static var requestID: String?
}
