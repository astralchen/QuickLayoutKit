import AVFAudio
import Speech
import XCTest
@testable import Demo

/// 真实系统识别验收；环境没有中文模型时明确跳过，不能算作识别通过。
@MainActor
final class IMessageChatAudioRecognitionIntegrationTests: XCTestCase {
    func testChineseFileAndSilenceWithInstalledSystemModel() async throws {
        let locale = Locale(identifier: "zh-CN")
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw XCTSkip("当前模拟器/设备不支持 SpeechTranscriber 中文文件识别")
        }
        do {
            try await AssetInventory.reserve(locale: supported)
        } catch {
            throw XCTSkip("当前环境无法预留中文识别资源：\(error)")
        }
        let module = SpeechTranscriber(locale: supported, preset: .transcription)
        let status = await AssetInventory.status(forModules: [module])
        guard status == .installed else {
            throw XCTSkip("当前环境没有已安装的中文 SpeechTranscriber 模型：\(status)")
        }
        let audioController = IMessageChatAudioController()
        defer { audioController.stopAll(); audioController.attachmentStore.removeAll() }
        let audio = try await audioController.synthesizeReplyAudio(text: "你好，你吃饭了吗？", locale: locale)
        let service = IMessageChatAudioFileTranscriber(backend: .speechAnalyzer)
        let result = try await service.transcribe(fileURL: audio.fileURL, locale: locale)
        XCTAssertTrue(result?.contains("你好") == true, "真实识别结果：\(result ?? "nil")")

        let silenceURL = audioController.attachmentStore.makeFileURL(prefix: "silence", pathExtension: "caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000))
        buffer.frameLength = 32_000
        if let samples = buffer.floatChannelData?[0] {
            samples.update(repeating: 0, count: Int(buffer.frameLength))
        }
        do {
            let file = try AVAudioFile(forWriting: silenceURL, settings: format.settings)
            try file.write(from: buffer)
        }
        let silenceResult = try await service.transcribe(fileURL: silenceURL, locale: locale)
        XCTAssertTrue(silenceResult?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
    }
}
