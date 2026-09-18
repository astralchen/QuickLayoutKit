import Foundation
import Testing
@testable import Demo

@MainActor
@Suite(.serialized)
struct GiftEffectPrefetcherTests {
    private let vap = GiftEffect.vap(URL(string: "https://example.com/a.mp4")!)
    private let svga = GiftEffect.svga(URL(string: "https://example.com/b.svga")!)
    private let other = GiftEffect.vap(URL(string: "https://example.com/c.mp4")!)

    private func gift(_ effects: [GiftEffect]) -> Gift {
        Gift(id: "prefetch", titleKey: "prefetch", symbolName: "gift", price: 1,
             themeIndex: 0, effectStyle: .trail, effects: effects)
    }

    @Test func limitsConcurrencyAndPreservesResourceOrder() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        prefetcher.register(effects: [.native(.burst), vap, vap, svga])
        prefetcher.register(effects: [other])
        try await waitForTaskCondition { loader.effects.count == 2 }
        #expect(loader.effects.count == 2 && loader.effects.contains(vap) && loader.effects.contains(svga))
        #expect(prefetcher.runningCount == 2)
        loader.finish(0)
        try await waitForTaskCondition { loader.effects.count == 3 }
        #expect(loader.effects.count == 3 && loader.effects.last == other)
        #expect(prefetcher.runningCount == 2)
        loader.finishAll()
        try await waitForTaskCondition { prefetcher.runningCount == 0 }
        prefetcher.cancelAll()
    }

    @Test func sharesOnlyMatchingFormatAndKeepsRemainingOwner() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        let url = URL(string: "https://example.com/shared")!
        let first = prefetcher.register(effects: [.vap(url), .vap(url)])
        let second = prefetcher.register(effects: [.vap(url), .svga(url)])
        try await waitForTaskCondition { loader.effects.count == 2 }
        #expect(loader.effects.count == 2 && loader.effects.contains(.vap(url)) && loader.effects.contains(.svga(url)))
        prefetcher.release(first)
        #expect(prefetcher.requestCount == 1)
        loader.finishAll()
        try await waitForTaskCondition { prefetcher.runningCount == 0 }
        #expect(loader.cancelled.isEmpty, "仍有共享需求时不能取消加载")
        prefetcher.release(second)
        #expect(prefetcher.requestCount == 0)
    }

    @Test func cancelledLoadsKeepSlotsAndOldCompletionCannotRemoveNewRequest() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(maxConcurrentLoads: 1, load: loader.load)
        prefetcher.register(effects: [vap, svga])
        try await waitForTaskCondition { loader.effects.count == 1 }
        prefetcher.cancelAll()
        let newRequest = prefetcher.register(effects: [vap, other])
        try await waitForTaskCondition { loader.cancelled.contains(0) }
        #expect(loader.effects == [vap])
        #expect(prefetcher.runningCount == 1)
        loader.finish(0) // 模拟 VAP 忽略取消后迟到成功。
        try await waitForTaskCondition { loader.effects.count == 2 }
        #expect(loader.effects == [vap, vap])
        let sharedRequest = prefetcher.register(effects: [vap])
        prefetcher.release(newRequest)
        loader.finish(1)
        try await waitForTaskCondition { prefetcher.runningCount == 0 }
        #expect(loader.effects == [vap, vap], "旧 svga 和无需求的 other 均不得启动")
        #expect(loader.cancelled == [0])
        prefetcher.release(sharedRequest)
        #expect(prefetcher.requestCount == 0)
    }

    @Test func failedResourceDoesNotRetryWhileRequestIsAlive() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        let first = prefetcher.register(effects: [vap, vap])
        try await waitForTaskCondition { loader.effects.count == 1 }
        loader.finish(0, result: .failure(URLError(.notConnectedToInternet)))
        try await waitForTaskCondition { prefetcher.runningCount == 0 }
        let second = prefetcher.register(effects: [vap])
        #expect(prefetcher.runningCount == 0)
        #expect(loader.effects == [vap])
        prefetcher.release(first)
        prefetcher.release(second)
        prefetcher.register(effects: [vap])
        try await waitForTaskCondition { loader.effects.count == 2 }
        loader.finishAll()
        prefetcher.cancelAll()
    }

    @Test func destructionCancelsWithoutRetainingPrefetcher() async throws {
        let loader = ControlledGiftLoader()
        var prefetcher: GiftEffectPrefetcher? = GiftEffectPrefetcher(load: loader.load)
        weak var weakPrefetcher = prefetcher
        prefetcher?.register(effects: [vap])
        try await waitForTaskCondition { loader.effects.count == 1 }
        prefetcher = nil
        #expect(weakPrefetcher == nil)
        try await waitForTaskCondition { loader.cancelled.contains(0) }
        loader.finishAll()
    }

    @Test func playbackStartsImmediatelyAndDuplicateEffectsStillPlay() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        var players: [PrefetchTestPlayer] = []
        let factory: @MainActor () -> any GiftEffectPlaying = {
            let player = PrefetchTestPlayer()
            players.append(player)
            return player
        }
        let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }, prefetcher: prefetcher, makePlayer: factory)
        coordinator.activate()
        let effects: [GiftEffect] = [.native(.burst), vap, svga, vap]
        let task = try #require(coordinator.enqueue(gift: gift(effects), quantity: 1, makeNativePlayer: factory))
        try await waitForTaskCondition { players.count == 1 && loader.effects.count == 2 }
        #expect(players[0].effect == .native(.burst))
        // 预下载尚未完成也不能阻挡播放，失败也不能跳过对应效果。
        let vapIndex = try #require(loader.effects.firstIndex(of: vap))
        let svgaIndex = try #require(loader.effects.firstIndex(of: svga))
        loader.finish(vapIndex, result: .failure(URLError(.cannotLoadFromNetwork)))
        for index in effects.indices {
            try await waitForTaskCondition { players.count == index + 1 }
            #expect(players[index].effect == effects[index])
            players[index].finish()
        }
        try await task.value
        #expect(prefetcher.requestCount == 0)
        try await waitForTaskCondition { loader.cancelled.contains(svgaIndex) }
        #expect(loader.effects.count == 2 && loader.effects.contains(vap) && loader.effects.contains(svga))
        loader.finishAll()
        coordinator.deactivate()
    }

    @Test func cancellingQueuedGiftReleasesItsPrefetchWithoutStartingPlayback() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        var players: [PrefetchTestPlayer] = []
        let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { false }, prefetcher: prefetcher) {
            let player = PrefetchTestPlayer()
            players.append(player)
            return player
        }
        coordinator.activate()
        let first = try #require(coordinator.enqueue(gift: gift([vap]), quantity: 1))
        try await waitForTaskCondition { players.count == 1 && loader.effects.count == 1 }
        let queued = try #require(coordinator.enqueue(gift: gift([svga, other]), quantity: 1))
        try await waitForTaskCondition { loader.effects.count == 2 }
        #expect(players.count == 1, "排队中已预下载，但不能提前播放")
        queued.cancel()
        _ = await queued.result
        try await waitForTaskCondition { prefetcher.requestCount == 1 && loader.cancelled.contains(1) }
        loader.finishAll()
        try await waitForTaskCondition { prefetcher.runningCount == 0 }
        #expect(loader.effects == [vap, svga], "取消需求的 other 不得开始")
        players[0].finish()
        try await first.value
        #expect(players.count == 1 && prefetcher.requestCount == 0)
    }

    @Test func reducedMotionSkipsRegistrationAndRechecksAtPlaybackStart() async throws {
        let loader = ControlledGiftLoader()
        let prefetcher = GiftEffectPrefetcher(load: loader.load)
        var reduced = true
        var players: [PrefetchTestPlayer] = []
        let coordinator = GiftMainEffectCoordinator(reduceMotionEnabled: { reduced }, prefetcher: prefetcher) {
            let player = PrefetchTestPlayer()
            players.append(player)
            return player
        }
        coordinator.activate()
        let first = try #require(coordinator.enqueue(gift: gift([vap, svga]), quantity: 1))
        try await waitForTaskCondition { players.count == 1 }
        #expect(prefetcher.requestCount == 0 && loader.effects.isEmpty)
        reduced = false
        let second = try #require(coordinator.enqueue(gift: gift([vap, svga]), quantity: 1))
        try await waitForTaskCondition { loader.effects.count == 2 }
        reduced = true
        players[0].finish()
        try await first.value
        try await waitForTaskCondition { players.count == 2 && loader.cancelled.count == 2 }
        #expect(prefetcher.requestCount == 0)
        players[1].finish()
        try await second.value
        #expect(players.count == 2, "每份赠送只做一次静态展示")
        loader.finishAll()
    }

    @Test func deactivationAndDestructionCancelPlaybackAndPrefetch() async throws {
        for destroy in [false, true] {
            let loader = ControlledGiftLoader()
            let prefetcher = GiftEffectPrefetcher(load: loader.load)
            let player = PrefetchTestPlayer()
            var coordinator: GiftMainEffectCoordinator? = GiftMainEffectCoordinator(reduceMotionEnabled: { false }, prefetcher: prefetcher) { player }
            weak var weakCoordinator = coordinator
            coordinator?.activate()
            let task = try #require(coordinator?.enqueue(gift: gift([vap, svga, other]), quantity: 1))
            try await waitForTaskCondition { loader.effects.count == 2 && player.effect != nil }
            if destroy { coordinator = nil } else { coordinator?.deactivate() }
            _ = await task.result
            try await waitForTaskCondition { loader.cancelled.count == 2 }
            #expect(prefetcher.requestCount == 0)
            if destroy { #expect(weakCoordinator == nil) }
            loader.finishAll()
            try await waitForTaskCondition { prefetcher.runningCount == 0 }
            #expect(loader.effects.count == 2 && loader.effects.contains(vap) && loader.effects.contains(svga))
        }
    }
}

/// 有意忽略取消直到显式完成，覆盖 SDK 共享下载迟到退出的情况。
@MainActor
private final class ControlledGiftLoader {
    private(set) var effects: [GiftEffect] = []
    private(set) var cancelled: Set<Int> = []
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]

    func load(_ effect: GiftEffect) async throws {
        let index = effects.count
        effects.append(effect)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuations[index] = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelled.insert(index) }
        }
    }

    func finish(_ index: Int, result: Result<Void, Error> = .success(())) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }

    func finishAll() {
        for index in Array(continuations.keys) { finish(index) }
    }
}

@MainActor
private final class PrefetchTestPlayer: GiftEffectPlaying {
    private(set) var effect: GiftEffect?
    private var continuation: CheckedContinuation<Void, Error>?

    func play(effect: GiftEffect, gift: Gift, quantity: Int) async throws {
        self.effect = effect
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func finish() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    func stop() {
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: CancellationError())
    }
}
