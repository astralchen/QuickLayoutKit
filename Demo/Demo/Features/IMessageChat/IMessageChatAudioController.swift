//
//  IMessageChatAudioController.swift
//  Demo
//
//  iMessage Demo 的页面级音频录制、播放与语音转写协调器。
//

import AVFAudio
import Foundation
import Speech
import UIKit

/// 媒体控制器向用户呈现的错误。
nonisolated enum IMessageChatMediaFailure: Equatable, Sendable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case recordingTooShort
    case recordingFailed
    case playbackFailed
    case speechUnavailable
    case speechFailed
    case mediaImportFailed
    case mediaInvalid
}

/// 媒体层支持的语音识别实现。
nonisolated enum IMessageChatSpeechBackend: Equatable, Sendable {
    case speechAnalyzer
    case speechRecognizer
}

/// 解析语音识别能力，而不向视图控制器暴露可用性检查。
nonisolated enum IMessageChatSpeechConfiguration {

    /// 返回指定能力对应的首选语音识别后端。
    ///
    /// - Parameter supportsSpeechAnalyzer: iOS 26 Speech Analyzer API 可用时为
    ///   `true`。
    /// - Returns: 支持时返回现代分析器后端；否则返回旧版语音识别器后端。
    static func preferredBackend(
        supportsSpeechAnalyzer: Bool
    ) -> IMessageChatSpeechBackend {
        supportsSpeechAnalyzer ? .speechAnalyzer : .speechRecognizer
    }

    /// 返回首选后端启动失败后可以尝试的兼容后端。
    ///
    /// 只有系统自动选择 `SpeechAnalyzer` 时允许回退。测试或调用方显式指定后端
    /// 时保持严格语义，便于验证单个实现的能力和错误。
    ///
    /// - Parameters:
    ///   - failedBackend: 本次未能启动的语音识别后端。
    ///   - wasExplicitlyRequested: 后端是否由调用方明确指定。
    /// - Returns: 可以继续尝试的后端；不应回退时为 `nil`。
    static func fallbackBackend(
        afterFailureOf failedBackend: IMessageChatSpeechBackend,
        wasExplicitlyRequested: Bool
    ) -> IMessageChatSpeechBackend? {
        guard failedBackend == .speechAnalyzer,
              !wasExplicitlyRequested else {
            return nil
        }
        return .speechRecognizer
    }

    /// 返回与应用区域设置对应的语音识别区域设置。
///
    /// Demo 支持英语、简体中文和阿拉伯语。带地区的识别区域设置可以让旧版识别器和
    /// iOS 26 资源解析器针对这些语言选项产生确定结果。
    ///
    /// - Parameter appLocale: 当前应用内本地化区域设置。
    /// - Returns: 适用于语音识别的区域设置。
    static func recognitionLocale(for appLocale: Locale) -> Locale {
        speechLocale(for: appLocale)
    }

    /// 返回与应用区域设置对应的语音处理区域设置。
    ///
    /// 此映射同时供语音识别和文本转语音使用，保证两条链路对 Demo 支持的语言
    /// 使用相同的地区变体。
    ///
    /// - Parameter appLocale: 当前应用内本地化区域设置。
    /// - Returns: 英语、简体中文或阿拉伯语对应的确定地区设置。
    static func speechLocale(for appLocale: Locale) -> Locale {
        let languageCode = appLocale.language.languageCode?.identifier
        switch languageCode {
        case "zh":
            return Locale(identifier: "zh-CN")
        case "ar":
            return Locale(identifier: "ar-SA")
        default:
            return Locale(identifier: "en-US")
        }
    }

    /// 返回可直接交给系统语音声线查询的 BCP 47 语言标签。
    ///
    /// `Locale.identifier` 在部分系统版本会使用下划线分隔语言与地区；
    /// `AVSpeechSynthesisVoice` 使用连字符形式的 BCP 47 标签进行匹配。
    ///
    /// - Parameter locale: 已完成地区映射的语音处理区域设置。
    /// - Returns: 使用连字符分隔的系统声线语言标签。
    static func speechVoiceLanguage(for locale: Locale) -> String {
        locale.identifier.replacingOccurrences(of: "_", with: "-")
    }
}

/// 所有可见及可复用音频消息 Cell 共享的播放状态。
nonisolated struct IMessageChatPlaybackState: Equatable, Sendable {
    /// 当前与播放器关联的消息；没有关联消息时为 `nil`。
    let messageID: Int?

    /// 当前与播放器关联的附件；没有关联附件时为 `nil`。
    let attachmentID: UUID?

    /// 指示音频当前是否正在播放的布尔值。
    let isPlaying: Bool

    /// 位于 `0...1` 范围内的归一化播放位置。
    let progress: Double

    static let idle = IMessageChatPlaybackState(
        messageID: nil,
        attachmentID: nil,
        isPlaying: false,
        progress: 0
    )
}

/// 将实时麦克风输入转换为文本草稿的对象。
@MainActor
protocol IMessageChatSpeechTranscribing: AnyObject {
    /// 开始按照指定区域设置转写麦克风输入。
    ///
    /// - Parameters:
    ///   - locale: 决定识别语言的区域设置。
    ///   - result: 识别结果变化时调用的闭包，参数为当前转写文本及其是否为最终结果。
    ///   - failure: 识别因错误终止时调用的闭包。
    func start(
        locale: Locale,
        result: @escaping @MainActor (String, Bool) -> Void,
        failure: @escaping @MainActor () -> Void
    ) async throws

    /// 停止当前转写并释放其音频输入。
    func stop()
}

/// 将模拟回复文本生成为可在消息气泡中回放的本地音频附件。
///
/// 实现负责文件创建、波形提取和取消清理。调用方只接收值类型附件，不持有
/// `AVSpeechSynthesizer` 或 `AVAudioFile`。
@MainActor
protocol IMessageChatReplyAudioSynthesizing: AnyObject {
    /// 使用指定语言合成一条模拟回复音频。
    ///
    /// - Parameters:
    ///   - text: 已按发送时语言解析的回复文本。
    ///   - locale: 决定系统声线的语音处理区域设置。
    /// - Returns: 位于页面临时目录内的可回放音频附件。
    func synthesizeReplyAudio(
        text: String,
        locale: Locale
    ) async throws -> IMessageChatAudioAttachment
}

/// 文本转音频回复在生成本地附件时可能产生的错误。
nonisolated enum IMessageChatReplyAudioSynthesisError: Error, Equatable {
    /// 输入文本移除首尾空白后为空。
    case emptyText

    /// 当前系统没有与目标语言匹配的可用声线。
    case voiceUnavailable

    /// 系统没有返回可写入且具有有效时长的 PCM 缓冲区。
    case invalidBuffer

    /// 临时音频文件无法创建、写入或重新打开校验。
    case fileWriteFailed
}

/// 请求媒体操作所需权限的对象。
@MainActor
protocol IMessageChatMediaPermissionProviding: AnyObject {
    /// 请求访问音频输入。
    func requestMicrophonePermission() async -> Bool

    /// 请求访问语音识别。
    func requestSpeechPermission() async -> Bool
}

/// 配置并激活页面音频会话的对象。
@MainActor
protocol IMessageChatAudioSessionControlling: AnyObject {
    /// 用于限定音频会话通知范围的对象。
    var notificationObject: AnyObject { get }

    /// 激活会话以捕获麦克风输入。
    func activateCapture() throws

    /// 激活会话以播放音频消息。
    func activatePlayback() throws

    /// 停用会话并通知被中断的音频客户端。
    func deactivate() throws
}

/// 由 AVFAudio 和 Speech 支持的真实权限提供者。
@MainActor
final class IMessageChatSystemPermissionProvider:
    IMessageChatMediaPermissionProviding {

    func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

/// 聊天页面使用的真实音频会话控制器。
@MainActor
final class IMessageChatSystemAudioSessionController:
    IMessageChatAudioSessionControlling {

    private let session: AVAudioSession

    var notificationObject: AnyObject { session }

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activateCapture() throws {
        try activateForSpokenAudio()
    }

    func activatePlayback() throws {
        try activateForSpokenAudio()
    }

    func deactivate() throws {
        try session.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func activateForSpokenAudio() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .spokenAudio,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setActive(true)
    }
}

/// 将非 Sendable 的音频回调缓冲区安全转交给主 Actor。
///
/// `AVSpeechSynthesizer` 的回调队列不属于页面状态机；包装对象只负责跨越任务
/// 边界，缓冲区仍只会在主 Actor 上读取。
private final class IMessageChatReplyAudioBufferBox: @unchecked Sendable {
    let buffer: AVAudioBuffer

    init(_ buffer: AVAudioBuffer) {
        self.buffer = buffer
    }
}

/// 保存单次文本转音频操作的文件写入状态。
nonisolated private final class IMessageChatReplyAudioSynthesisContext {
    let generation: UUID
    let fileURL: URL
    let fileSettings: [String: Any]
    var continuation: CheckedContinuation<
        IMessageChatAudioAttachment,
        any Error
    >?
    var audioFile: AVAudioFile?
    var duration: TimeInterval = 0
    var waveformSamples: [Float] = []

    init(
        generation: UUID,
        fileURL: URL,
        fileSettings: [String: Any],
        continuation: CheckedContinuation<
            IMessageChatAudioAttachment,
            any Error
        >
    ) {
        self.generation = generation
        self.fileURL = fileURL
        self.fileSettings = fileSettings
        self.continuation = continuation
    }
}

/// 为单个聊天页面协调音频录制、播放、语音转写和音频会话所有权。
///
/// 此控制器串行执行音频操作，确保录音与语音转写不会同时使用麦克风。页面附件
/// 文件由独立的 ``IMessageChatAttachmentStoring`` 管理，图片和视频功能不应加入
/// 此控制器。
@MainActor
final class IMessageChatAudioController: NSObject {

    typealias StateHandler = (IMessageChatComposerState) -> Void
    typealias PlaybackHandler = (IMessageChatPlaybackState) -> Void
    typealias FailureHandler = (IMessageChatMediaFailure) -> Void

    private enum PlaybackTarget: Equatable {
        case preview(UUID)
        case message(id: Int, attachmentID: UUID)
    }

    /// 输入栏媒体状态发生变化时调用的闭包。
    var stateDidChange: StateHandler?

    /// 时间线音频播放状态发生变化时调用的闭包。
    var playbackDidChange: PlaybackHandler?

    /// 当前操作需要向用户反馈时调用的闭包。
    var failureDidOccur: FailureHandler?

    private(set) var state: IMessageChatComposerState = .idle {
        didSet {
            guard state != oldValue else { return }
            stateDidChange?(state)
        }
    }

    private(set) var playbackState: IMessageChatPlaybackState = .idle {
        didSet {
            guard playbackState != oldValue else { return }
            playbackDidChange?(playbackState)
        }
    }

    private let audioSession: IMessageChatAudioSessionControlling
    let attachmentStore: any IMessageChatAttachmentStoring
    private let fileManager: FileManager
    private let speechTranscriber: IMessageChatSpeechTranscribing
    private let permissionProvider: IMessageChatMediaPermissionProviding

    private var recorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingSamples: [Float] = []
    private var recordingURL: URL?
    private var player: AVAudioPlayer?
    private var playbackTarget: PlaybackTarget?
    private var playbackTimer: Timer?
    private var replyAudioSynthesizer: AVSpeechSynthesizer?
    private var replyAudioSynthesisContext:
        IMessageChatReplyAudioSynthesisContext?
    private var operationTask: Task<Void, Never>?
    private var dictationGeneration: UUID?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?

    /// 创建使用共享音频会话和系统语音识别器的媒体控制器。
    convenience override init() {
        self.init(
            audioSession: IMessageChatSystemAudioSessionController(),
            fileManager: .default,
            speechTranscriber: IMessageChatSpeechRecognitionService(),
            permissionProvider: IMessageChatSystemPermissionProvider(),
            attachmentStore: nil
        )
    }

    /// 创建与其他页面媒体协调器共享附件目录的真实音频控制器。
    convenience init(attachmentStore: any IMessageChatAttachmentStoring) {
        self.init(
            audioSession: IMessageChatSystemAudioSessionController(),
            fileManager: .default,
            speechTranscriber: IMessageChatSpeechRecognitionService(),
            permissionProvider: IMessageChatSystemPermissionProvider(),
            attachmentStore: attachmentStore
        )
    }

    /// 使用可注入的系统协作者创建媒体控制器。
    ///
    /// - Parameters:
    ///   - audioSession: 用于捕获和播放会话的控制器。
    ///   - fileManager: 用于创建和移除录音的文件管理器。
    ///   - speechTranscriber: 提供实时语音结果的对象。
    ///   - permissionProvider: 请求麦克风和 Speech 权限的对象。
    ///   - attachmentStore: 页面附件存储。传入 `nil` 时创建独立临时目录。
    init(
        audioSession: IMessageChatAudioSessionControlling,
        fileManager: FileManager,
        speechTranscriber: IMessageChatSpeechTranscribing,
        permissionProvider: IMessageChatMediaPermissionProviding,
        attachmentStore: (any IMessageChatAttachmentStoring)? = nil
    ) {
        self.audioSession = audioSession
        self.fileManager = fileManager
        self.speechTranscriber = speechTranscriber
        self.permissionProvider = permissionProvider
        self.attachmentStore = attachmentStore
            ?? IMessageChatPageAttachmentStore(fileManager: fileManager)
        super.init()
        observeAudioLifecycle()
    }

    deinit {
        operationTask?.cancel()
        replyAudioSynthesizer?.stopSpeaking(at: .immediate)
        if let context = replyAudioSynthesisContext {
            context.audioFile = nil
            try? fileManager.removeItem(at: context.fileURL)
            context.continuation?.resume(throwing: CancellationError())
            context.continuation = nil
        }
        recordingTimer?.invalidate()
        playbackTimer?.invalidate()
        recorder?.stop()
        player?.stop()
        let speechTranscriber = speechTranscriber
        Task { @MainActor in
            speechTranscriber.stop()
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    /// 请求麦克风访问权限并开始录制音频消息。
    func startRecording() {
        guard state == .idle else { return }
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            guard await permissionProvider.requestMicrophonePermission() else {
                operationTask = nil
                failureDidOccur?(.microphonePermissionDenied)
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try configureCaptureSession()
                try beginRecording()
                operationTask = nil
            } catch {
                operationTask = nil
                finishAudioSession()
                failureDidOccur?(.recordingFailed)
            }
        }
    }

    /// 停止录音，并在录音有效时生成预览。
    func stopRecording() {
        guard recorder != nil else { return }
        finishRecording(keepValidRecording: true)
    }

    /// 取消当前录音或预览，并删除其本地文件。
    func cancelRecordingOrPreview() {
        operationTask?.cancel()
        operationTask = nil
        speechTranscriber.stop()
        if recorder != nil {
            finishRecording(keepValidRecording: false)
        }
        if case .audioPreview(let attachment, _, _) = state {
            stopPlayback()
            attachmentStore.discardDraft(id: attachment.id)
        }
        state = .idle
        finishAudioSession()
    }

    /// 交出未提交文件；接收方必须立即在同一页面存储中登记文件附件。
    /// 停止播放器但不删除文件，之后的录音回调不能再持有该草稿。
    func takePreviewForFileAttachment() -> IMessageChatAudioAttachment? {
        guard case .audioPreview(let attachment, _, _) = state else { return nil }
        stopPlayback()
        state = .idle
        finishAudioSession()
        return attachment
    }

    /// 当前音频预览所表示的页面附件。
    ///
    /// 读取不会改变预览状态。调用方应先让 ViewModel 接受附件，再调用
    /// ``commitPreviewAttachment(id:)``，保证发送失败时草稿仍可重试或取消。
    var previewAttachment: IMessageChatAttachment? {
        guard case .audioPreview(let attachment, _, _) = state else {
            return nil
        }
        return .audio(attachment)
    }

    /// 提交已经成功进入消息时间线的音频预览。
    ///
    /// - Parameter id: ViewModel 已接受附件的稳定标识符。
    /// - Returns: 当前预览与标识符一致且成功提交时为 `true`。
    @discardableResult
    func commitPreviewAttachment(id: UUID) -> Bool {
        guard case .audioPreview(let attachment, _, _) = state,
              attachment.id == id else {
            return false
        }
        if !attachmentStore.commitDraft(id: id) {
            // 状态中的有效附件已经被 ViewModel 接受。即使测试替身或恢复流程
            // 没有保留草稿登记，也要把文件转为页面已提交所有权，避免消息存在
            // 但预览无法退出。
            attachmentStore.registerCommitted(.audio(attachment))
        }
        stopPlayback()
        state = .idle
        finishAudioSession()
        return true
    }

    /// 切换输入栏预览中附件的播放状态。
    func togglePreviewPlayback() {
        guard case .audioPreview(
            let attachment,
            let isPlaying,
            _
        ) = state else {
            return
        }
        if isPlaying {
            pausePlayback()
        } else {
            play(
                attachment,
                target: .preview(attachment.id)
            )
        }
    }

    /// 切换时间线中音频消息的播放状态。
    ///
    /// - Parameters:
    ///   - messageID: 消息的稳定身份。
    ///   - attachment: 要播放的音频附件。
    func toggleMessagePlayback(
        messageID: Int,
        attachment: IMessageChatAudioAttachment
    ) {
        let target = PlaybackTarget.message(
            id: messageID,
            attachmentID: attachment.id
        )
        if playbackTarget == target, player?.isPlaying == true {
            pausePlayback()
        } else if playbackTarget == target, player != nil {
            resumePlayback()
        } else {
            play(attachment, target: target)
        }
    }

    /// 请求所需权限并开始实时语音转写。
    ///
    /// - Parameter locale: 用于选择识别语言的区域设置。
    func startDictation(locale: Locale) {
        guard state == .idle else { return }
        pausePlayback()
        state = .preparingSpeech
        let generation = UUID()
        dictationGeneration = generation
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            guard await permissionProvider.requestMicrophonePermission() else {
                operationTask = nil
                state = .idle
                failureDidOccur?(.microphonePermissionDenied)
                return
            }
            guard await permissionProvider.requestSpeechPermission() else {
                operationTask = nil
                state = .idle
                failureDidOccur?(.speechPermissionDenied)
                return
            }
            guard !Task.isCancelled else { return }
            do {
                try configureCaptureSession()
                try await speechTranscriber.start(
                    locale: IMessageChatSpeechConfiguration
                        .recognitionLocale(for: locale),
                    result: { [weak self] text, isFinal in
                        guard let self,
                              self.dictationGeneration == generation else {
                            return
                        }
                        self.state = .dictating(text: text)
                        if isFinal {
                            self.operationTask = nil
                            self.dictationGeneration = nil
                            self.speechTranscriber.stop()
                            self.state = .idle
                            self.finishAudioSession()
                        }
                    },
                    failure: { [weak self] in
                        guard let self,
                              self.dictationGeneration == generation else {
                            return
                        }
                        self.dictationGeneration = nil
                        self.operationTask = nil
                        self.speechTranscriber.stop()
                        self.state = .idle
                        self.finishAudioSession()
                        self.failureDidOccur?(.speechFailed)
                    }
                )
                guard !Task.isCancelled else {
                    speechTranscriber.stop()
                    return
                }
                if state == .preparingSpeech {
                    state = .dictating(text: "")
                }
                operationTask = nil
            } catch {
                guard dictationGeneration == generation else { return }
                operationTask = nil
                dictationGeneration = nil
                speechTranscriber.stop()
                state = .idle
                finishAudioSession()
                failureDidOccur?(.speechUnavailable)
            }
        }
    }

    /// 停止语音转写，并在编辑器中保留最新文本。
    func stopDictation() {
        let isActive: Bool
        if case .dictating = state {
            isActive = true
        } else {
            isActive = state == .preparingSpeech
        }
        guard isActive else { return }
        operationTask?.cancel()
        operationTask = nil
        dictationGeneration = nil
        speechTranscriber.stop()
        state = .idle
        finishAudioSession()
    }

    /// 停止所有活动的媒体操作并释放音频会话。
///
    /// 有效的活动录音会保留为预览。播放和语音转写不会自动恢复。
    func stopAll() {
        operationTask?.cancel()
        operationTask = nil
        cancelReplyAudioSynthesis()
        dictationGeneration = nil
        speechTranscriber.stop()
        if recorder != nil {
            finishRecording(keepValidRecording: true)
        }
        stopPlayback()
        if case .dictating = state {
            state = .idle
        } else if state == .preparingSpeech {
            state = .idle
        }
        finishAudioSession()
    }

    private func beginRecording() throws {
        pausePlayback()
        let url = attachmentStore.makeFileURL(
            prefix: "audio",
            pathExtension: "m4a"
        )
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.recorder = recorder
        recordingURL = url
        recordingSamples = []
        state = .recording(
            elapsed: 0,
            waveform: IMessageChatRecordingWaveform.displaySamples([])
        )
        recordingTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleRecording()
            }
        }
        RunLoop.main.add(recordingTimer!, forMode: .common)
    }

    private func sampleRecording() {
        guard let recorder else { return }
        recorder.updateMeters()
        let normalized = Self.normalizedPower(
            recorder.averagePower(forChannel: 0)
        )
        recordingSamples.append(normalized)
        let elapsed = recorder.currentTime
        state = .recording(
            elapsed: elapsed,
            waveform: IMessageChatRecordingWaveform.displaySamples(
                recordingSamples
            )
        )
        if IMessageChatRecordingPolicy.shouldStop(elapsed: elapsed) {
            finishRecording(keepValidRecording: true)
        }
    }

    private func finishRecording(keepValidRecording: Bool) {
        recordingTimer?.invalidate()
        recordingTimer = nil
        guard let recorder else { return }
        let duration = recorder.currentTime
        let url = recordingURL ?? recorder.url
        self.recorder = nil
        recordingURL = nil
        recorder.stop()

        guard keepValidRecording,
              IMessageChatRecordingPolicy.accepts(
                  duration: duration,
                  fileExists: fileManager.fileExists(atPath: url.path)
              )
        else {
            try? fileManager.removeItem(at: url)
            state = .idle
            finishAudioSession()
            if keepValidRecording {
                failureDidOccur?(.recordingTooShort)
            }
            return
        }

        let attachment = IMessageChatAudioAttachment(
            fileURL: url,
            duration: duration,
            waveform: Self.condensedWaveform(recordingSamples, count: 36)
        )
        attachmentStore.registerDraft(.audio(attachment))
        recordingSamples = []
        state = .audioPreview(
            attachment: attachment,
            isPlaying: false,
            progress: 0
        )
        finishAudioSession()
    }

    private func play(
        _ attachment: IMessageChatAudioAttachment,
        target: PlaybackTarget
    ) {
        stopPlayback()
        guard fileManager.fileExists(atPath: attachment.fileURL.path) else {
            failureDidOccur?(.playbackFailed)
            return
        }
        do {
            try configurePlaybackSession()
            let player = try AVAudioPlayer(contentsOf: attachment.fileURL)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            self.player = player
            playbackTarget = target
            publishPlayback(isPlaying: true, progress: 0)
            startPlaybackTimer()
        } catch {
            stopPlayback()
            failureDidOccur?(.playbackFailed)
        }
    }

    private func resumePlayback() {
        guard let player, playbackTarget != nil else { return }
        do {
            try configurePlaybackSession()
            guard player.play() else { throw CocoaError(.fileReadUnknown) }
            publishPlayback(
                isPlaying: true,
                progress: player.duration > 0
                    ? player.currentTime / player.duration
                    : 0
            )
            startPlaybackTimer()
        } catch {
            stopPlayback()
            failureDidOccur?(.playbackFailed)
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(
            withTimeInterval: 0.05,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.samplePlayback()
            }
        }
        RunLoop.main.add(playbackTimer!, forMode: .common)
    }

    private func samplePlayback() {
        guard let player else { return }
        let progress = player.duration > 0
            ? min(1, max(0, player.currentTime / player.duration))
            : 0
        publishPlayback(isPlaying: player.isPlaying, progress: progress)
    }

    private func pausePlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        player?.pause()
        let progress: Double
        if let player, player.duration > 0 {
            progress = min(1, max(0, player.currentTime / player.duration))
        } else {
            progress = 0
        }
        publishPlayback(isPlaying: false, progress: progress)
        if case .audioPreview(let attachment, _, _) = state {
            state = .audioPreview(
                attachment: attachment,
                isPlaying: false,
                progress: progress
            )
        }
        finishAudioSession()
    }

    private func stopPlayback() {
        let progress: Double
        if let player, player.duration > 0 {
            progress = min(1, max(0, player.currentTime / player.duration))
        } else {
            progress = 0
        }
        playbackTimer?.invalidate()
        playbackTimer = nil
        player?.stop()
        publishPlayback(isPlaying: false, progress: progress)
        player = nil
        playbackTarget = nil
        playbackState = .idle
        if case .audioPreview(let attachment, _, _) = state {
            state = .audioPreview(
                attachment: attachment,
                isPlaying: false,
                progress: progress
            )
        }
        finishAudioSession()
    }

    private func publishPlayback(isPlaying: Bool, progress: Double) {
        switch playbackTarget {
        case .preview(let attachmentID):
            if case .audioPreview(let attachment, _, _) = state,
               attachment.id == attachmentID {
                state = .audioPreview(
                    attachment: attachment,
                    isPlaying: isPlaying,
                    progress: progress
                )
            }
        case .message(let messageID, let attachmentID):
            playbackState = IMessageChatPlaybackState(
                messageID: messageID,
                attachmentID: attachmentID,
                isPlaying: isPlaying,
                progress: progress
            )
        case nil:
            break
        }
    }

    private func configureCaptureSession() throws {
        try audioSession.activateCapture()
    }

    private func configurePlaybackSession() throws {
        try audioSession.activatePlayback()
    }

    private func finishAudioSession() {
        guard recorder == nil, player?.isPlaying != true else { return }
        try? audioSession.deactivate()
    }

    private func observeAudioLifecycle() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession.notificationObject,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let typeValue = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: typeValue)
                        == .began else { return }
                self?.handleCaptureInterruption()
            }
        }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession.notificationObject,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let reasonValue = notification.userInfo?[
                    AVAudioSessionRouteChangeReasonKey
                ] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: reasonValue)
                        == .oldDeviceUnavailable else { return }
                self?.pausePlayback()
            }
        }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCaptureInterruption()
            }
        }
    }

    private func handleCaptureInterruption() {
        if recorder != nil {
            finishRecording(keepValidRecording: true)
            return
        }
        if case .dictating = state {
            stopDictation()
        } else if state == .preparingSpeech {
            stopDictation()
        }
        pausePlayback()
    }

    private static func normalizedPower(_ power: Float) -> Float {
        guard power.isFinite else { return 0.08 }
        return min(1, max(0.08, pow(10, power / 40)))
    }

    private static func condensedWaveform(
        _ samples: [Float],
        count: Int
    ) -> [Float] {
        guard !samples.isEmpty, count > 0 else { return placeholderWaveform }
        let bucketSize = max(1, Int(ceil(Double(samples.count) / Double(count))))
        var result: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + bucketSize)
            result.append(samples[index..<end].max() ?? 0.08)
            index = end
        }
        if result.count < count {
            result.append(contentsOf: repeatElement(0.08, count: count - result.count))
        }
        return Array(result.prefix(count))
    }

    private static let placeholderWaveform: [Float] = Array(
        repeating: 0.08,
        count: 36
    )
}

extension IMessageChatAudioController: IMessageChatReplyAudioSynthesizing {

    /// 使用系统声线把本地化回复文本写入页面临时音频文件。
    ///
    /// 此方法只生成文件，不通过扬声器朗读，也不会激活页面的录音或播放音频
    /// 会话。任务取消时会停止当前合成并删除尚未完成的文件。
    ///
    /// - Parameters:
    ///   - text: 已按发送时应用语言解析的回复文本。
    ///   - locale: 用于选择系统声线的语音处理区域设置。
    /// - Returns: 包含精确时长和固定槽位波形的本地音频附件。
    func synthesizeReplyAudio(
        text: String,
        locale: Locale
    ) async throws -> IMessageChatAudioAttachment {
        let trimmedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedText.isEmpty else {
            throw IMessageChatReplyAudioSynthesisError.emptyText
        }
        guard let voice = AVSpeechSynthesisVoice(
            language: IMessageChatSpeechConfiguration.speechVoiceLanguage(
                for: locale
            )
        ) else {
            throw IMessageChatReplyAudioSynthesisError.voiceUnavailable
        }

        cancelReplyAudioSynthesis()
        try Task.checkCancellation()

        let generation = UUID()
        let fileURL = attachmentStore.makeFileURL(
            prefix: "reply-\(generation.uuidString)",
            pathExtension: "caf"
        )
        let utterance = AVSpeechUtterance(string: trimmedText)
        utterance.voice = voice
        let synthesizer = AVSpeechSynthesizer()
        replyAudioSynthesizer = synthesizer

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let context = IMessageChatReplyAudioSynthesisContext(
                    generation: generation,
                    fileURL: fileURL,
                    fileSettings: voice.audioFileSettings,
                    continuation: continuation
                )
                replyAudioSynthesisContext = context
                synthesizer.write(utterance) { [weak self] buffer in
                    let bufferBox = IMessageChatReplyAudioBufferBox(buffer)
                    Task { @MainActor [weak self, bufferBox] in
                        self?.consumeReplyAudioBuffer(
                            bufferBox.buffer,
                            generation: generation
                        )
                    }
                }
                if Task.isCancelled {
                    cancelReplyAudioSynthesis(generation: generation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelReplyAudioSynthesis(generation: generation)
            }
        }
    }

    /// 接收系统合成缓冲区并写入当前回复文件。
    ///
    /// 零帧缓冲区表示本次合成结束。迟到或属于已取消代次的缓冲区会被忽略。
    private func consumeReplyAudioBuffer(
        _ buffer: AVAudioBuffer,
        generation: UUID
    ) {
        guard let context = replyAudioSynthesisContext,
              context.generation == generation else {
            return
        }
        guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
            finishReplyAudioSynthesis(
                generation: generation,
                result: .failure(
                    IMessageChatReplyAudioSynthesisError.invalidBuffer
                )
            )
            return
        }

        guard pcmBuffer.frameLength > 0 else {
            completeReplyAudioSynthesis(generation: generation)
            return
        }

        do {
            if context.audioFile == nil {
                context.audioFile = try AVAudioFile(
                    forWriting: context.fileURL,
                    settings: context.fileSettings
                )
            }
            try context.audioFile?.write(from: pcmBuffer)
            let sampleRate = pcmBuffer.format.sampleRate
            guard sampleRate > 0 else {
                throw IMessageChatReplyAudioSynthesisError.invalidBuffer
            }
            context.duration += TimeInterval(pcmBuffer.frameLength)
                / sampleRate
            context.waveformSamples.append(
                contentsOf: Self.replyWaveformSamples(from: pcmBuffer)
            )
        } catch {
            finishReplyAudioSynthesis(
                generation: generation,
                result: .failure(
                    IMessageChatReplyAudioSynthesisError.fileWriteFailed
                )
            )
        }
    }

    /// 校验已写入的回复文件并生成音频附件。
    private func completeReplyAudioSynthesis(generation: UUID) {
        guard let context = replyAudioSynthesisContext,
              context.generation == generation else {
            return
        }
        context.audioFile = nil
        do {
            let audioFile = try AVAudioFile(forReading: context.fileURL)
            guard audioFile.length > 0, context.duration > 0 else {
                throw IMessageChatReplyAudioSynthesisError.invalidBuffer
            }
            let attachment = IMessageChatAudioAttachment(
                fileURL: context.fileURL,
                duration: context.duration,
                waveform: Self.condensedWaveform(
                    context.waveformSamples,
                    count: 36
                )
            )
            attachmentStore.registerCommitted(.audio(attachment))
            finishReplyAudioSynthesis(
                generation: generation,
                result: .success(attachment)
            )
        } catch {
            finishReplyAudioSynthesis(
                generation: generation,
                result: .failure(
                    IMessageChatReplyAudioSynthesisError.fileWriteFailed
                )
            )
        }
    }

    /// 结束当前合成并仅恢复一次等待中的 continuation。
    private func finishReplyAudioSynthesis(
        generation: UUID,
        result: Result<IMessageChatAudioAttachment, any Error>
    ) {
        guard let context = replyAudioSynthesisContext,
              context.generation == generation else {
            return
        }
        replyAudioSynthesisContext = nil
        replyAudioSynthesizer = nil
        context.audioFile = nil
        let continuation = context.continuation
        context.continuation = nil

        if case .failure = result {
            attachmentStore.removeFile(at: context.fileURL)
        }
        continuation?.resume(with: result)
    }

    /// 取消正在生成的回复音频并删除部分文件。
    private func cancelReplyAudioSynthesis() {
        let context = replyAudioSynthesisContext
        replyAudioSynthesisContext = nil
        let synthesizer = replyAudioSynthesizer
        replyAudioSynthesizer = nil
        let continuation = context?.continuation
        context?.continuation = nil
        context?.audioFile = nil

        synthesizer?.stopSpeaking(at: .immediate)
        if let fileURL = context?.fileURL {
            attachmentStore.removeFile(at: fileURL)
        }
        continuation?.resume(throwing: CancellationError())
    }

    /// 取消指定代次的回复音频生成。
    ///
    /// 旧任务的取消处理可能晚于下一次合成回到主 Actor。只有当前上下文仍属于
    /// 指定代次时才执行取消，避免旧任务误删新回复的临时文件。
    ///
    /// - Parameter generation: 发起合成时创建的稳定代次标识。
    private func cancelReplyAudioSynthesis(generation: UUID) {
        guard replyAudioSynthesisContext?.generation == generation else {
            return
        }
        cancelReplyAudioSynthesis()
    }

    /// 从合成 PCM 缓冲区提取用于消息气泡的振幅采样。
    static func replyWaveformSamples(
        from buffer: AVAudioPCMBuffer
    ) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return [] }

        let bucketSize = 256
        var samples: [Float] = []
        var start = 0
        while start < frameCount {
            let end = min(frameCount, start + bucketSize)
            var peak: Float = 0
            for channel in 0..<channelCount {
                for frame in start..<end {
                    peak = max(peak, abs(channelData[channel][frame]))
                }
            }
            samples.append(min(1, max(0.08, sqrt(peak))))
            start = end
        }
        return samples
    }
}

extension IMessageChatAudioController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.finishRecording(keepValidRecording: false)
            self.failureDidOccur?(.recordingFailed)
        }
    }
}

extension IMessageChatAudioController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.publishPlayback(isPlaying: false, progress: 1)
            self.playbackTimer?.invalidate()
            self.playbackTimer = nil
            self.player = nil
            self.playbackTarget = nil
            self.playbackState = .idle
            if case .audioPreview(let attachment, _, _) = self.state {
                self.state = .audioPreview(
                    attachment: attachment,
                    isPlaying: false,
                    progress: 0
                )
            }
            self.finishAudioSession()
            if !flag {
                self.failureDidOccur?(.playbackFailed)
            }
        }
    }
}

/// iMessage 聊天 Demo 使用的系统语音识别器。
///
/// 在 iOS 26 及更高版本中，此对象优先使用 `SpeechAnalyzer`，并安装
/// `SpeechTranscriber` 所需资源。Analyzer 启动阶段不可用时会降级到
/// `SFSpeechRecognizer`；两个后端均不可用时才把启动错误返回给调用方。旧版实现
/// 同时为未来降低 Demo 部署目标而保留，并在支持时优先采用设备端识别。
@MainActor
final class IMessageChatSpeechRecognitionService: IMessageChatSpeechTranscribing {

    private let requestedBackend: IMessageChatSpeechBackend?
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var stableModernTranscript = ""
    private var partialModernTranscript = ""
    private var modernTranscriptSeparator = " "

    /// 创建系统语音识别服务。
    ///
    /// - Parameter backend: 能力测试使用的后端覆盖值。传入 `nil` 可为当前运行系统
    ///   选择最佳后端。
    init(backend: IMessageChatSpeechBackend? = nil) {
        requestedBackend = backend
    }

    func start(
        locale: Locale,
        result: @escaping @MainActor (String, Bool) -> Void,
        failure: @escaping @MainActor () -> Void
    ) async throws {
        stop()
        let backend: IMessageChatSpeechBackend
        if let requestedBackend {
            backend = requestedBackend
        } else if #available(iOS 26.0, *) {
            backend = .speechAnalyzer
        } else {
            backend = .speechRecognizer
        }

        if backend == .speechAnalyzer {
            if #available(iOS 26.0, *) {
                do {
                    try await startModern(
                        locale: locale,
                        result: result,
                        failure: failure
                    )
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard IMessageChatSpeechConfiguration.fallbackBackend(
                        afterFailureOf: backend,
                        wasExplicitlyRequested: requestedBackend != nil
                    ) == .speechRecognizer else {
                        throw error
                    }
                    stop()
                    try startLegacy(
                        locale: locale,
                        result: result,
                        failure: failure
                    )
                    return
                }
            }
            throw CocoaError(.featureUnsupported)
        }
        try startLegacy(
            locale: locale,
            result: result,
            failure: failure
        )
    }

    func stop() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        analysisTask?.cancel()
        resultsTask?.cancel()
        analysisTask = nil
        resultsTask = nil
        stableModernTranscript = ""
        partialModernTranscript = ""
        if let analyzer {
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }
        analyzer = nil
    }

    @available(iOS 26.0, *)
    private func startModern(
        locale: Locale,
        result: @escaping @MainActor (String, Bool) -> Void,
        failure: @escaping @MainActor () -> Void
    ) async throws {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(
            equivalentTo: locale
        ) else {
            throw CocoaError(.featureUnsupported)
        }
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            preset: .progressiveTranscription
        )
        modernTranscriptSeparator = (
            supportedLocale.language.languageCode?.identifier == "zh"
        ) ? "" : " "
        if let installationRequest = try await AssetInventory
            .assetInstallationRequest(supporting: [transcriber]) {
            try await installationRequest.downloadAndInstall()
        }

        let engine = AVAudioEngine()
        let naturalFormat = engine.inputNode.outputFormat(forBus: 0)
        guard let analyzerFormat = await SpeechAnalyzer
            .bestAvailableAudioFormat(
                compatibleWith: [transcriber],
                considering: naturalFormat
            ) else {
            throw CocoaError(.featureUnsupported)
        }
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        audioEngine = engine

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: analyzerFormat
        ) { buffer, _ in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        engine.prepare()
        try engine.start()

        resultsTask = Task {
            do {
                for try await transcription in transcriber.results {
                    guard !Task.isCancelled else { return }
                    let text = String(transcription.text.characters)
                    if transcription.isFinal {
                        stableModernTranscript = joinedTranscript(
                            stableModernTranscript,
                            text
                        )
                        partialModernTranscript = ""
                    } else {
                        partialModernTranscript = text
                    }
                    result(
                        joinedTranscript(
                            stableModernTranscript,
                            partialModernTranscript
                        ),
                        false
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                failure()
            }
        }
        analysisTask = Task {
            do {
                _ = try await analyzer.analyzeSequence(stream)
            } catch is CancellationError {
                return
            } catch {
                failure()
            }
        }
    }

    private func startLegacy(
        locale: Locale,
        result: @escaping @MainActor (String, Bool) -> Void,
        failure: @escaping @MainActor () -> Void
    ) throws {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw CocoaError(.featureUnsupported)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = recognizer
            .supportsOnDeviceRecognition

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { buffer, _ in
            request.append(buffer)
        }
        recognitionRequest = request
        audioEngine = engine
        recognitionTask = recognizer.recognitionTask(with: request) {
            recognitionResult,
            error in
            if let recognitionResult {
                let text = recognitionResult.bestTranscription.formattedString
                Task { @MainActor in
                    result(text, recognitionResult.isFinal)
                }
            }
            if error != nil {
                Task { @MainActor in failure() }
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func joinedTranscript(_ prefix: String, _ suffix: String) -> String {
        guard !prefix.isEmpty else { return suffix }
        guard !suffix.isEmpty else { return prefix }
        return prefix + modernTranscriptSeparator + suffix
    }
}
