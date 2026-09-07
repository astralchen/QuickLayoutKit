import AVFAudio
import AVKit
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct IMessageChatAudioLifecycleTests {
    @Test func coveringChatStopsPlaybackButOnlyPoppingChatDeletesAttachments() async throws {
        let fixture = try Fixture()
        let chat = fixture.makeChat()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setViewControllers([navigation.viewControllers[0], chat], animated: false)
        let host = try WindowHost(root: navigation)
        defer { fixture.clean(); host.close() }
        #expect(await eventually { chat.view.window != nil })
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        let cover = UIViewController()
        cover.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { continuation in
            chat.present(cover, animated: false) { continuation.resume() }
        }
        #expect(fixture.media.playbackState == .idle)
        #expect(fixture.fileExists)
        await withCheckedContinuation { continuation in
            cover.dismiss(animated: false) { continuation.resume() }
        }
        #expect(fixture.media.playbackState == .idle)
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.isPlaying })
        navigation.pushViewController(UIViewController(), animated: false)
        #expect(await eventually { fixture.media.playbackState == .idle })
        #expect(fixture.fileExists)
        navigation.popViewController(animated: false)
        #expect(await eventually { navigation.topViewController === chat && chat.view.window != nil })
        // UIKit 即使不带动画也会异步提交导航切换，完成后再发起下一次返回。
        try await Task.sleep(for: .milliseconds(100))
        fixture.play()
        navigation.popViewController(animated: false)
        #expect(await eventually { !fixture.fileExists })
        #expect(fixture.media.playbackState == .idle)
    }

    @Test func changingTabsStopsPlaybackWithoutDiscardingChat() async throws {
        let fixture = try Fixture()
        let chat = fixture.makeChat()
        let tabs = UITabBarController()
        tabs.viewControllers = [UINavigationController(rootViewController: chat), UIViewController()]
        let host = try WindowHost(root: tabs)
        defer { fixture.clean(); host.close() }
        #expect(await eventually { chat.view.window != nil })
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        tabs.selectedIndex = 1
        #expect(await eventually { fixture.media.playbackState == .idle })
        #expect(fixture.fileExists)
        tabs.selectedIndex = 0
        #expect(await eventually { chat.view.window != nil })
        #expect(fixture.media.playbackState == .idle)
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.isPlaying })
    }

    @Test func dismissingParentContainerCleansUpChat() async throws {
        let fixture = try Fixture()
        let root = UIViewController()
        let host = try WindowHost(root: root)
        defer { fixture.clean(); host.close() }
        let navigation = UINavigationController(rootViewController: fixture.makeChat())
        navigation.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { continuation in
            root.present(navigation, animated: false) { continuation.resume() }
        }
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        await withCheckedContinuation { continuation in
            root.dismiss(animated: false) { continuation.resume() }
        }
        #expect(fixture.media.playbackState == .idle)
        #expect(!fixture.fileExists)
    }

    @Test func backgroundResetsPlaybackWithoutDeletingFileOrAutoResuming() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(fixture.media.playbackState == .idle)
        #expect(fixture.fileExists)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(fixture.media.playbackState == .idle)
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.isPlaying })
    }

    @Test func interruptionsAndDisconnectedOutputPauseWithoutAutoResuming() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        #expect(!fixture.media.playbackState.isPlaying)
        #expect(fixture.media.playbackState.progress > 0)
        #expect(fixture.media.playbackState.attachmentID == fixture.audio.id)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                                   AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        #expect(!fixture.media.playbackState.isPlaying)
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.isPlaying })
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification,
                                        object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        #expect(!fixture.media.playbackState.isPlaying)
        #expect(fixture.media.playbackState.progress > 0)
        #expect(fixture.fileExists)
    }

    @Test func startingCaptureResetsPlaybackEvenWhenPermissionIsDenied() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        fixture.media.startRecording()
        #expect(fixture.media.playbackState == .idle)
        await Task.yield()
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        fixture.media.startDictation(locale: Locale(identifier: "zh-CN"))
        #expect(fixture.media.playbackState == .idle)
        #expect(fixture.fileExists)
    }

    @Test func losingPlaybackFileStopsAndReportsFailureOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        var failureCount = 0
        fixture.media.failureDidOccur = { _ in failureCount += 1 }
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        fixture.store.removeFile(at: fixture.audio.fileURL)
        #expect(await eventually { fixture.media.playbackState == .idle })
        #expect(failureCount == 1)
    }

    @Test func idleAudioControllerDoesNotDeactivateAnotherMediaSession() async throws {
        let session = CountingSession()
        let fixture = try Fixture(audioSession: session)
        defer { fixture.clean() }
        fixture.media.stopPlayback()
        fixture.media.stopAll()
        #expect(session.deactivationCount == 0)
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.isPlaying })
        #expect(session.activationCount == 1)
        fixture.media.stopPlayback()
        #expect(session.deactivationCount == 1)
        // 视频接管后，聊天页重复退出或后台通知都不能再次释放共享会话。
        fixture.media.stopPlayback()
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(session.deactivationCount == 1)
    }

    @Test func videoAndAudioAreMutuallyExclusiveAcrossNativePlaybackAndBackground() async throws {
        let fixture = try Fixture()
        let url = try await makeVideo(in: fixture.store)
        let item = IMessageChatMediaItem(assetIdentifier: nil, originalFileURL: url,
                                        thumbnailFileURL: url, pixelSize: CGSize(width: 64, height: 48),
                                        kind: .video(duration: 10))
        let preview = IMessageChatMediaPreviewController(group: .init(items: [item]), initialIndex: 0,
            strings: .init(photo: "Photos", itemsFormat: "%d items", image: "Image", animatedImage: "Animated image",
                           video: "Video", videoDurationFormat: "%@", importing: "Importing", remove: "Remove",
                           play: "Play", openPreview: "Preview", close: "Close", firstItem: "First", lastItem: "Last",
                           positionFormat: "%d of %d"), playbackCoordinator: fixture.media.playbackCoordinator)
        let host = try WindowHost(root: preview)
        defer { fixture.clean(); host.close() }
        let collection = try #require(preview.view.subviews.compactMap { $0 as? UICollectionView }.first)
        #expect(await eventually { !collection.visibleCells.isEmpty })
        func firstButton(in view: UIView) -> UIButton? {
            if let button = view as? UIButton { return button }
            return view.subviews.lazy.compactMap { firstButton(in: $0) }.first
        }
        let cell = try #require(collection.visibleCells.first)
        let button = try #require(firstButton(in: cell))
        fixture.play()
        #expect(await eventually { fixture.media.playbackState.progress > 0 })
        button.sendActions(for: .touchUpInside)
        #expect(await eventually { (preview.presentedViewController as? AVPlayerViewController)?.player?.rate == 1 })
        #expect(fixture.media.playbackState == .idle)
        let controller = try #require(preview.presentedViewController as? AVPlayerViewController)
        let player = try #require(controller.player)
        #expect(!controller.allowsPictureInPicturePlayback)
        #expect(AVAudioSession.sharedInstance().category == .playback)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        #expect(player.rate == 0)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(player.rate == 0)
        // 原生控件暂停后重播仍归视频所有；切换到音频必须同步停止旧视频。
        player.play()
        #expect(player.rate == 1)
        fixture.play()
        #expect(fixture.media.playbackState.isPlaying)
        #expect(player.rate == 0)
        #expect(controller.player == nil)
        #expect(await eventually { preview.presentedViewController == nil })
        #expect(fixture.fileExists)
        // 再切回视频，覆盖连续双向切换和旧对象迟到清理不能释放新所有者。
        button.sendActions(for: .touchUpInside)
        #expect(await eventually { (preview.presentedViewController as? AVPlayerViewController)?.player?.rate == 1 })
        #expect(fixture.media.playbackState == .idle)
        let nextController = try #require(preview.presentedViewController as? AVPlayerViewController)
        let nextPlayer = try #require(nextController.player)
        await withCheckedContinuation { continuation in
            nextController.dismiss(animated: false) { continuation.resume() }
        }
        #expect(nextPlayer.rate == 0)
        #expect(nextController.player == nil)
        #expect(fixture.media.playbackState == .idle)
    }

    private func makeVideo(in store: IMessageChatPageAttachmentStore) async throws -> URL {
        let url = store.makeFileURL(prefix: "lifecycle-video", pathExtension: "mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        try #require(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        try #require(CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(try #require(CVPixelBufferGetBaseAddress(pixels)), 0x7f, CVPixelBufferGetBytesPerRow(pixels) * 48)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for frame in 0..<2 {
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !input.isReadyForMoreMediaData, writer.status == .writing, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(input.isReadyForMoreMediaData && writer.status == .writing)
            try #require(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame * 5), timescale: 1)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 10, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        try #require(writer.status == .completed)
        return url
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<150 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }
}

@MainActor
private final class Fixture {
    let store = IMessageChatPageAttachmentStore()
    let audio: IMessageChatAudioAttachment
    let media: IMessageChatAudioController
    let model = IMessageChatViewModel(localizer: DemoLocalizer { key, _ in key }, clock: Date.init,
                                     sleeper: { _ in try await Task.sleep(for: .seconds(3600)) })

    init(audioSession: IMessageChatAudioSessionControlling? = nil) throws {
        let url = store.makeFileURL(prefix: "lifecycle", pathExtension: "caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160_000))
        buffer.frameLength = 160_000
        buffer.floatChannelData?[0].update(repeating: 0, count: Int(buffer.frameLength))
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        audio = .init(fileURL: url, duration: 10, waveform: [0.2, 0.5, 0.8], transcript: "测试附件")
        media = IMessageChatAudioController(audioSession: audioSession ?? IMessageChatSystemAudioSessionController(),
                                           fileManager: .default, speechTranscriber: NoSpeech(),
                                           permissionProvider: DeniedPermissions(), attachmentStore: store)
        store.registerCommitted(.audio(audio))
    }

    var fileExists: Bool { FileManager.default.fileExists(atPath: audio.fileURL.path) }
    func play() { media.toggleMessagePlayback(messageID: 1, attachment: audio) }
    func makeChat() -> IMessageChatViewController {
        _ = model.sendAttachment(.audio(audio))
        return IMessageChatViewController(viewModel: model, audioController: media)
    }
    func clean() { media.stopAll(); model.cancelPendingReply(); store.removeAll() }
}

@MainActor
private final class CountingSession: IMessageChatAudioSessionControlling {
    let notificationObject: AnyObject = NSObject()
    var activationCount = 0
    var deactivationCount = 0
    func activateCapture() throws { activationCount += 1 }
    func activatePlayback() throws { activationCount += 1 }
    func deactivate() throws { deactivationCount += 1 }
}

@MainActor
private struct WindowHost {
    let window: UIWindow
    let previous: UIWindow?
    init(root: UIViewController) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
    }
    func close() { window.isHidden = true; previous?.makeKey() }
}

@MainActor
private final class DeniedPermissions: IMessageChatMediaPermissionProviding {
    func requestMicrophonePermission() async -> Bool { false }
    func requestSpeechPermission() async -> Bool { false }
}

@MainActor
private final class NoSpeech: IMessageChatSpeechTranscribing {
    func start(locale: Locale, result: @escaping @MainActor (String, Bool) -> Void,
               failure: @escaping @MainActor () -> Void) async throws {}
    func stop() {}
}
