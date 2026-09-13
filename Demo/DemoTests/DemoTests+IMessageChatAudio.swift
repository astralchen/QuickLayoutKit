import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageReplyWaveformUsesDeterministicPCMAmplitude()
        throws {
        guard #available(iOS 26.0, *) else { return }
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 8_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)
        )
        buffer.frameLength = 512
        let channel = try #require(buffer.floatChannelData?[0])
        for frame in 0..<256 {
            channel[frame] = 0.01
        }
        for frame in 256..<512 {
            channel[frame] = 1
        }

        let samples = IMessageChatAudioController.replyWaveformSamples(
            from: buffer
        )
        #expect(samples.count == 2)
        #expect(abs(samples[0] - 0.1) < 0.0001)
        #expect(samples[1] == 1)
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageRecordingPolicyHonorsMinimumAndMaximumDurations() {
        guard #available(iOS 26.0, *) else { return }
        #expect(
            !IMessageChatRecordingPolicy.accepts(
                duration: 0.99,
                fileExists: true
            )
        )
        #expect(
            IMessageChatRecordingPolicy.accepts(
                duration: 1,
                fileExists: true
            )
        )
        #expect(
            !IMessageChatRecordingPolicy.accepts(
                duration: 1,
                fileExists: false
            )
        )
        #expect(!IMessageChatRecordingPolicy.shouldStop(elapsed: 119.99))
        #expect(IMessageChatRecordingPolicy.shouldStop(elapsed: 120))
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageAttachmentStoreCommitsAndDiscardsTransactionally()
        throws {
        guard #available(iOS 26.0, *) else { return }
        let fileManager = FileManager.default
        let parentDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(
                "IMessageChatStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: parentDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: parentDirectory) }

        let store = IMessageChatPageAttachmentStore(
            fileManager: fileManager,
            parentDirectory: parentDirectory
        )
        let pickerURL = parentDirectory
            .appendingPathComponent("picker-source.jpg")
        try Data([7, 8, 9]).write(to: pickerURL)
        let importedURL = try store.importFile(
            at: pickerURL,
            prefix: "image",
            pathExtension: nil
        )
        #expect(importedURL.deletingLastPathComponent() == store.directoryURL)
        #expect(importedURL.pathExtension == "jpg")
        #expect(try Data(contentsOf: importedURL) == Data([7, 8, 9]))

        let discardedURL = store.makeFileURL(
            prefix: "discarded",
            pathExtension: "m4a"
        )
        try Data([0]).write(to: discardedURL)
        let discarded = IMessageChatAudioAttachment(
            fileURL: discardedURL,
            duration: 2,
            waveform: [0.5]
        )
        store.registerDraft(.audio(discarded))
        store.discardDraft(id: discarded.id)
        #expect(!fileManager.fileExists(atPath: discardedURL.path))

        let committedURL = store.makeFileURL(
            prefix: "committed",
            pathExtension: "m4a"
        )
        try Data([1]).write(to: committedURL)
        let committed = IMessageChatAudioAttachment(
            fileURL: committedURL,
            duration: 2,
            waveform: [0.6]
        )
        store.registerDraft(.audio(committed))
        #expect(store.commitDraft(id: committed.id))
        store.discardDraft(id: committed.id)
        #expect(fileManager.fileExists(atPath: committedURL.path))

        let directoryURL = store.directoryURL
        store.removeAll()
        #expect(!fileManager.fileExists(atPath: importedURL.path))
        #expect(!fileManager.fileExists(atPath: committedURL.path))
        #expect(!fileManager.fileExists(atPath: directoryURL.path))
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageRecordingWaveformKeepsStableDisplaySlots() {
        guard #available(iOS 26.0, *) else { return }
        #expect(IMessageChatRecordingWaveform.displaySampleCount == 60)
        let empty = IMessageChatRecordingWaveform.displaySamples([])
        #expect(
            empty.count == IMessageChatRecordingWaveform.displaySampleCount
        )
        #expect(empty.allSatisfy { $0 == 0.08 })

        let firstSample = IMessageChatRecordingWaveform.displaySamples([0.7])
        #expect(firstSample.count == empty.count)
        #expect(firstSample.dropLast().allSatisfy { $0 == 0.08 })
        #expect(firstSample.last == 0.7)

        let source = (0..<72).map { Float($0) / 72 }
        let scrolled = IMessageChatRecordingWaveform.displaySamples(source)
        #expect(scrolled.count == empty.count)
        #expect(scrolled.first == source[12])
        #expect(scrolled.last == source[71])
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageDictationReplacesPartialResultsAndIgnoresStaleResults()
        async {
        guard #available(iOS 26.0, *) else { return }
        let transcriber = ControlledIMessageSpeechTranscriber()
        let permissions = ControlledIMessageMediaPermissions(
            microphoneGranted: true,
            speechGranted: true
        )
        let audioSession = RecordingIMessageAudioSession()
        let controller = IMessageChatAudioController(
            audioSession: audioSession,
            fileManager: .default,
            speechTranscriber: transcriber,
            permissionProvider: permissions
        )
        var states: [IMessageChatComposerState] = []
        controller.stateDidChange = { states.append($0) }

        controller.startDictation(locale: Locale(identifier: "zh-Hans"))
        #expect(await waitForCondition { transcriber.startCount == 1 })
        #expect(transcriber.locale?.identifier == "zh-CN")
        #expect(audioSession.captureActivationCount == 1)

        transcriber.emit(text: "你", isFinal: false)
        #expect(controller.state == .dictating(text: "你"))
        transcriber.emit(text: "你好", isFinal: false)
        #expect(controller.state == .dictating(text: "你好"))

        controller.stopDictation()
        #expect(controller.state == .idle)
        #expect(transcriber.stopCount == 1)
        transcriber.emit(text: "不应覆盖", isFinal: false)
        #expect(controller.state == .idle)
        #expect(states.contains(.dictating(text: "你")))
        #expect(states.contains(.dictating(text: "你好")))
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageDictationFinalResultStopsWithoutSending() async {
        guard #available(iOS 26.0, *) else { return }
        let transcriber = ControlledIMessageSpeechTranscriber()
        let controller = IMessageChatAudioController(
            audioSession: RecordingIMessageAudioSession(),
            fileManager: .default,
            speechTranscriber: transcriber,
            permissionProvider: ControlledIMessageMediaPermissions(
                microphoneGranted: true,
                speechGranted: true
            )
        )
        var latestDraft = ""
        controller.stateDidChange = { state in
            if case .dictating(let text) = state {
                latestDraft = text
            }
        }

        controller.startDictation(locale: Locale(identifier: "ar"))
        #expect(await waitForCondition { transcriber.startCount == 1 })
        #expect(transcriber.locale?.identifier == "ar-SA")
        transcriber.emit(text: "مرحبا", isFinal: true)

        #expect(latestDraft == "مرحبا")
        #expect(controller.state == .idle)
        #expect(transcriber.stopCount == 1)
    }

    @Test(.enabled(if: IMessageChatTestAvailability.isSupported)) func iMessageDictationPermissionFailureDoesNotStartCapture() async {
        guard #available(iOS 26.0, *) else { return }
        let transcriber = ControlledIMessageSpeechTranscriber()
        let audioSession = RecordingIMessageAudioSession()
        let controller = IMessageChatAudioController(
            audioSession: audioSession,
            fileManager: .default,
            speechTranscriber: transcriber,
            permissionProvider: ControlledIMessageMediaPermissions(
                microphoneGranted: false,
                speechGranted: true
            )
        )
        var failure: IMessageChatMediaFailure?
        controller.failureDidOccur = { failure = $0 }

        controller.startDictation(locale: Locale(identifier: "en-US"))
        #expect(
            await waitForCondition {
                failure == .microphonePermissionDenied
            }
        )
        #expect(controller.state == .idle)
        #expect(transcriber.startCount == 0)
        #expect(audioSession.captureActivationCount == 0)
    }
}

/// iMessage 媒体测试使用的确定性语音转写器。
@available(iOS 26.0, *)
@MainActor
private final class ControlledIMessageSpeechTranscriber:
    IMessageChatSpeechTranscribing {

    private var result: (@MainActor (String, Bool) -> Void)?
    private var failure: (@MainActor () -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var locale: Locale?

    func start(
        locale: Locale,
        result: @escaping @MainActor (String, Bool) -> Void,
        failure: @escaping @MainActor () -> Void
    ) async throws {
        startCount += 1
        self.locale = locale
        self.result = result
        self.failure = failure
    }

    func stop() {
        stopCount += 1
    }

    func emit(text: String, isFinal: Bool) {
        result?(text, isFinal)
    }

    func fail() {
        failure?()
    }
}

/// iMessage 媒体测试使用的确定性权限提供者。
@available(iOS 26.0, *)
@MainActor
private final class ControlledIMessageMediaPermissions:
    IMessageChatMediaPermissionProviding {

    let microphoneGranted: Bool
    let speechGranted: Bool

    init(microphoneGranted: Bool, speechGranted: Bool) {
        self.microphoneGranted = microphoneGranted
        self.speechGranted = speechGranted
    }

    func requestMicrophonePermission() async -> Bool {
        microphoneGranted
    }

    func requestSpeechPermission() async -> Bool {
        speechGranted
    }
}

/// 不执行真实操作，仅为测试记录激活请求的音频会话。
@available(iOS 26.0, *)
@MainActor
private final class RecordingIMessageAudioSession:
    NSObject,
    IMessageChatAudioSessionControlling {

    var notificationObject: AnyObject { self }

    private(set) var captureActivationCount = 0
    private(set) var playbackActivationCount = 0
    private(set) var deactivationCount = 0

    func activateCapture() throws {
        captureActivationCount += 1
    }

    func activatePlayback() throws {
        playbackActivationCount += 1
    }

    func deactivate() throws {
        deactivationCount += 1
    }
}
