import Foundation
import Testing
@testable import Demo

/// 在 SDK 适配边界验证回调到 async 的桥接，队列本身没有回调式任务。
@MainActor
@Suite(.serialized)
struct GiftPlaybackOperationTests {
    /// 同步失败必须等待 SDK 返回清理闭包，再恢复异步调用。
    @Test func synchronousFailureAndDuplicateEvents() async {
        let operation = GiftPlaybackOperation()
        var events: [String] = []
        do {
            try await operation.run { finish in
                finish(.failure(URLError(.cannotDecodeContentData)))
                finish(.success(()))
                events.append("start returned")
                return { events.append("cleaned") }
            }
            Issue.record("同步失败不得返回成功")
        } catch { events.append("caught") }
        #expect(events == ["start returned", "cleaned", "caught"])
    }

    /// 旧 SDK 回调与旧 Task 的取消处理器不能清理复用后的新播放。
    @Test func cancellationAndLateEventsAcrossReuse() async throws {
        let operation = GiftPlaybackOperation()
        let oldStarted = TaskTestSignal()
        let newStarted = TaskTestSignal()
        var oldFinish: GiftPlaybackOperation.Completion?
        var newFinish: GiftPlaybackOperation.Completion?
        var cleanupCount = 0
        let old = Task {
            try await operation.run { finish in
                oldFinish = finish
                oldStarted.signal()
                return { cleanupCount += 1 }
            }
        }
        await oldStarted.wait()
        old.cancel()
        operation.stop()
        let next = Task {
            try await operation.run { finish in
                newFinish = finish
                newStarted.signal()
                return { cleanupCount += 1 }
            }
        }
        await newStarted.wait()
        oldFinish?(.success(()))
        oldFinish?(.failure(URLError(.badServerResponse)))
        if case .failure(let error) = await old.result { #expect(error is CancellationError) }
        else { Issue.record("旧等待应被取消") }
        #expect(cleanupCount == 1)
        newFinish?(.success(()))
        try await next.value
        operation.stop()
        #expect(cleanupCount == 2)
    }

    /// 仅取消 Swift Task 即可清理 SDK 并恢复等待，不需要外部调用 stop。
    @Test func taskCancellationAloneCleansSDK() async {
        let operation = GiftPlaybackOperation()
        let started = TaskTestSignal()
        var cleaned = 0
        var lateFinish: GiftPlaybackOperation.Completion?
        let task = Task {
            try await operation.run { finish in
                lateFinish = finish
                started.signal()
                return { cleaned += 1 }
            }
        }
        await started.wait()
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("取消必须恢复异步等待") }
        #expect(cleaned == 1)
        lateFinish?(.success(()))
        #expect(cleaned == 1)
    }

    /// 取消先于实际开始时不允许发起 SDK 加载。
    @Test func preCancelledTaskDoesNotStartSDK() async {
        let operation = GiftPlaybackOperation()
        let task = Task {
            try await operation.run { _ in Issue.record("已取消任务不应加载 SDK"); return {} }
        }
        task.cancel()
        if case .failure(let error) = await task.result { #expect(error is CancellationError) }
        else { Issue.record("应抛出取消") }
    }

    /// 启动闭包内同步停止也只清理和恢复一次。
    @Test func stopDuringSDKStart() async {
        let operation = GiftPlaybackOperation()
        var cleaned = 0
        do {
            try await operation.run { finish in
                operation.stop()
                finish(.success(()))
                return { cleaned += 1 }
            }
            Issue.record("同步取消不应成功")
        } catch { #expect(error is CancellationError) }
        #expect(cleaned == 1)
    }
}
