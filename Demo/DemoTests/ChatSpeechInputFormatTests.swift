import AVFAudio
import Foundation
import Testing
@testable import Demo

/// 验证无效麦克风格式在安装 tap 前可被拒绝，以及取消不会启动系统识别。
@MainActor
struct ChatSpeechInputFormatTests {
    /// 重现日志中的双声道、零采样率格式，错误应通过 Swift 返回。
    @Test func rejectsZeroSampleRateWithTwoChannels() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 0, channels: 2))
        #expect(throws: SpeechInputFormat.ValidationError.self) {
            try SpeechInputFormat.validate(format)
        }
    }

    /// 没有声道的输入不能被当成可录音设备。
    @Test func rejectsZeroChannels() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 0))
        #expect(throws: SpeechInputFormat.ValidationError.self) {
            try SpeechInputFormat.validate(format)
        }
    }

    /// 保留真实设备常见的采样率和声道配置。
    @Test(arguments: [16_000.0, 44_100.0, 48_000.0], [AVAudioChannelCount(1), 2])
    func acceptsValidCaptureFormat(sampleRate: Double, channels: AVAudioChannelCount) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        try SpeechInputFormat.validate(format)
    }

    /// 已取消的请求在访问麦克风或语言模型前结束，两个后端均不发布回调。
    @Test(arguments: [SpeechBackend.speechAnalyzer, .speechRecognizer])
    func cancelledStartDoesNotActivateBackend(backend: SpeechBackend) async throws {
        guard #available(iOS 26.0, *) else { return }
        let service = SpeechRecognitionService(backend: backend)
        var callbackCount = 0
        let task = Task { @MainActor in
            try await service.start(locale: Locale(identifier: "zh-CN")) { _, _ in
                callbackCount += 1
            } failure: {
                callbackCount += 1
            }
        }
        task.cancel()
        do {
            try await task.value
            Issue.record("已取消的识别请求不应启动成功")
        } catch is CancellationError {
            #expect(callbackCount == 0)
        }
        service.stop()
    }
}
