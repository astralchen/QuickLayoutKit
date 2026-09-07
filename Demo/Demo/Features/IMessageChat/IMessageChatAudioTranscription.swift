import AVFAudio
import Foundation
import Speech

/// 读取已提交的音频文件。实现不得启动麦克风或更改播放音频会话。
@MainActor
protocol IMessageChatAudioFileTranscribing: AnyObject {
    func transcribe(fileURL: URL, locale: Locale) async throws -> String?
}

/// 页面内的串行识别队列。结果与消息、附件双重身份绑定，失败也记为已尝试。
@MainActor
final class IMessageChatAudioTranscriptionCoordinator {
    private struct Key: Hashable {
        let messageID: Int
        let attachmentID: UUID
    }

    private struct Job {
        let key: Key
        let fileURL: URL
        let locale: Locale
    }

    private let transcriber: any IMessageChatAudioFileTranscribing
    private let completion: (Int, UUID, String) -> Void
    private var attempted: Set<Key> = []
    private var queue: [Job] = []
    private var worker: Task<Void, Never>?
    private var invalidated = false

    init(
        transcriber: any IMessageChatAudioFileTranscribing,
        completion: @escaping (Int, UUID, String) -> Void
    ) {
        self.transcriber = transcriber
        self.completion = completion
    }

    deinit { worker?.cancel() }

    func enqueue(_ state: IMessageChatViewModel.State, locale: Locale) {
        guard !invalidated else { return }
        for item in state.timeline {
            guard case .message(let message) = item.content,
                  let audio = message.audio, audio.transcript == nil else { continue }
            let key = Key(messageID: message.id, attachmentID: audio.id)
            guard attempted.insert(key).inserted else { continue }
            queue.append(Job(key: key, fileURL: audio.fileURL, locale: locale))
        }
        guard worker == nil, !queue.isEmpty else { return }
        // Task 不会在同步发送调用栈内执行；录音草稿先完成提交、退出预览。
        worker = Task { [weak self] in
            while !Task.isCancelled {
                guard let job = self?.takeNext() else { break }
                guard let transcriber = self?.transcriber else { break }
                do {
                    let result = try await transcriber.transcribe(fileURL: job.fileURL, locale: job.locale)
                    guard !Task.isCancelled, self?.invalidated == false else { break }
                    if let text = result?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        self?.completion(job.key.messageID, job.key.attachmentID, text)
                    }
                } catch {
                    // 识别是可选增强；失败不改变已发送消息，也不重复请求。
                }
            }
            self?.worker = nil
        }
    }

    func cancelAll() {
        invalidated = true
        queue.removeAll()
        worker?.cancel()
        worker = nil
    }

    private func takeNext() -> Job? {
        guard !invalidated, !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
}

/// 文件识别使用独立的系统请求，与输入栏的实时转写互不取消。
@MainActor
final class IMessageChatAudioFileTranscriber: IMessageChatAudioFileTranscribing {
    private let requestedBackend: IMessageChatSpeechBackend?
    private let permissionProvider: any IMessageChatMediaPermissionProviding

    init(
        backend: IMessageChatSpeechBackend? = nil,
        permissionProvider: (any IMessageChatMediaPermissionProviding)? = nil
    ) {
        requestedBackend = backend
        self.permissionProvider = permissionProvider ?? IMessageChatSystemPermissionProvider()
    }

    func transcribe(fileURL: URL, locale: Locale) async throws -> String? {
        try Task.checkCancellation()
        let backend = requestedBackend ?? IMessageChatSpeechConfiguration.preferredBackend(
            supportsSpeechAnalyzer: ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
            )
        )
        if backend == .speechAnalyzer {
            if #available(iOS 26.0, *) {
                let prepared: (SpeechAnalyzer, SpeechTranscriber, AVAudioFile)
                do {
                    prepared = try await prepareModern(fileURL: fileURL, locale: locale)
                } catch {
                    try Task.checkCancellation()
                    if error is CancellationError { throw error }
                    guard IMessageChatSpeechConfiguration.fallbackBackend(
                        afterFailureOf: backend, wasExplicitlyRequested: requestedBackend != nil
                    ) != nil else { throw error }
                    return try await transcribeLegacy(fileURL: fileURL, locale: locale)
                }
                // 成功准备后发生的运行错误不重启另一个后端。
                return try await runModern(prepared, locale: locale)
            }
            throw CocoaError(.featureUnsupported)
        }
        return try await transcribeLegacy(fileURL: fileURL, locale: locale)
    }

    @available(iOS 26.0, *)
    private func prepareModern(fileURL: URL, locale: Locale) async throws -> (SpeechAnalyzer, SpeechTranscriber, AVAudioFile) {
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw CocoaError(.featureUnsupported)
        }
        try Task.checkCancellation()
        // 在请求模型安装前明确预留语言，避免新安装的 App 尚未订阅该语言资源。
        try await AssetInventory.reserve(locale: supported)
        try Task.checkCancellation()
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: fileURL)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.prepareToAnalyze(in: file.processingFormat)
            try Task.checkCancellation()
            return (analyzer, transcriber, file)
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    @available(iOS 26.0, *)
    private func runModern(_ prepared: (SpeechAnalyzer, SpeechTranscriber, AVAudioFile), locale: Locale) async throws -> String? {
        let (analyzer, transcriber, file) = prepared
        return try await withTaskCancellationHandler {
            let results = Task { () throws -> String in
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    if result.isFinal { segments.append(String(result.text.characters)) }
                }
                return segments.joined(separator: locale.language.languageCode?.identifier == "zh" ? "" : " ")
            }
            do {
                try Task.checkCancellation()
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                let text = try await results.value
                try Task.checkCancellation()
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    private func transcribeLegacy(fileURL: URL, locale: Locale) async throws -> String? {
        let authorized = await permissionProvider.requestSpeechPermission()
        try Task.checkCancellation()
        guard authorized, let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return nil
        }
        if recognizer.supportsOnDeviceRecognition {
            do {
                return try await LegacyFileRequest().run(recognizer: recognizer, fileURL: fileURL, onDevice: true)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw error }
            }
        }
        return try await LegacyFileRequest().run(recognizer: recognizer, fileURL: fileURL, onDevice: false)
    }
}

/// 单个请求拥有自己的 continuation；取消和迟到的回调都只能完成一次。
@MainActor
private final class LegacyFileRequest {
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String?, any Error>?

    func run(recognizer: SFSpeechRecognizer, fileURL: URL, onDevice: Bool) async throws -> String? {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let request = SFSpeechURLRecognitionRequest(url: fileURL)
                request.shouldReportPartialResults = false
                request.requiresOnDeviceRecognition = onDevice
                request.addsPunctuation = true
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                    Task { @MainActor [weak self] in
                        if let text { self?.finish(.success(text)) }
                        else if let error { self?.finish(.failure(error)) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<String?, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        let task = task
        self.task = nil
        task?.cancel()
        continuation.resume(with: result)
    }
}
