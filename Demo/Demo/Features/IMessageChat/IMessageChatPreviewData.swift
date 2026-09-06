//
//  IMessageChatPreviewData.swift
//  Demo
//

#if DEBUG
import Foundation
import UIKit

@MainActor
enum IMessageChatPreviewData {

    static let audioWaveform: [Float] = [
        0.18, 0.24, 0.34, 0.45, 0.72, 0.48, 0.38, 0.84, 0.62,
        0.42, 0.28, 0.56, 0.78, 0.52, 0.36, 0.22, 0.18, 0.12,
        0.16, 0.22, 0.30, 0.52, 0.88, 0.64, 0.42, 0.76, 0.58,
        0.38, 0.26, 0.48, 0.70, 0.46, 0.32, 0.20, 0.16, 0.10,
    ]

    /// 与真实录音状态使用相同固定槽位规则的确定性波形。
    static let recordingWaveform = IMessageChatRecordingWaveform
        .displaySamples(audioWaveform + Array(audioWaveform.reversed()))

    static let audioAttachment = IMessageChatAudioAttachment(
        id: UUID(uuidString: "3B8B4C03-3AEF-4126-B6D9-B073905955F4")!,
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("imessage-preview.m4a"),
        duration: 3,
        waveform: audioWaveform
    )

    static let pastedMediaDrafts: [IMessageChatDocumentDraft] = {
        let thumbnail = FileManager.default.temporaryDirectory.appendingPathComponent("imessage-paste-preview.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 120))
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 80, width: 160, height: 40))
            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 106, y: 14, width: 28, height: 28))
        }
        try? image.pngData()?.write(to: thumbnail, options: .atomic)
        return [IMessageChatMediaKind.image, .video(duration: 12)].enumerated().map { index, kind in
            let id = UUID(uuidString: index == 0 ? "F0CBF955-17EA-4AF3-8713-A099113A3034" : "F0CBF955-17EA-4AF3-8713-A099113A3035")!
            return .init(attachment: .mediaGroup(.init(id: id, items: [.init(
                id: id, assetIdentifier: nil, originalFileURL: thumbnail, thumbnailFileURL: thumbnail,
                pixelSize: CGSize(width: 160, height: 120), kind: kind
            )])))
        }
    }()

    static let documentDrafts: [IMessageChatDocumentDraft] = [
        .init(attachment: .file(.init(
            id: UUID(uuidString: "F0CBF955-17EA-4AF3-8713-A099113A3031")!,
            fileURL: URL(fileURLWithPath: "/preview/Audio Message.m4a"),
            displayName: "Audio Message.m4a", typeIdentifier: "public.mpeg-4-audio", byteCount: 10_240
        ))),
        .init(attachment: .file(.init(
            id: UUID(uuidString: "F0CBF955-17EA-4AF3-8713-A099113A3032")!,
            fileURL: URL(fileURLWithPath: "/preview/Example.json"),
            displayName: "Example.json", typeIdentifier: "public.json", byteCount: 2_048
        ))),
        .init(attachment: .link(.init(
            id: UUID(uuidString: "F0CBF955-17EA-4AF3-8713-A099113A3033")!,
            url: URL(string: "https://developer.apple.com")!, title: "Apple Developer"
        ))),
    ]

    static let incomingAudioAttachment = IMessageChatAudioAttachment(
        id: UUID(uuidString: "71FA16C1-CFC2-49DB-979A-8F7188D0E768")!,
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("imessage-incoming-preview.m4a"),
        duration: 3,
        waveform: audioWaveform
    )

    static let outgoingAudioAttachment = IMessageChatAudioAttachment(
        id: UUID(uuidString: "54BBE51E-6E67-46D0-B665-4441800620D2")!,
        fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("imessage-outgoing-preview.m4a"),
        duration: 7,
        waveform: Array(audioWaveform.reversed())
    )

    static let timestamp = IMessageChatTimestampPresentation(
        sourceMessageID: 0,
        text: "19:09"
    )

    static let incomingMessage = IMessageChatMessagePresentation(
        id: 0,
        direction: .incoming,
        text: "嗨！我们今天还是按原计划见面吗？",
        deliveryText: nil
    )

    static let outgoingMessage = IMessageChatMessagePresentation(
        id: 1,
        direction: .outgoing,
        text: "当然，七点我没问题。",
        deliveryText: "已读"
    )

    static let followUpMessage = IMessageChatMessagePresentation(
        id: 2,
        direction: .incoming,
        text: "太好了，我会提前几分钟到。",
        deliveryText: nil
    )

    static let incomingAudioMessage = IMessageChatMessagePresentation(
        id: 3,
        direction: .incoming,
        attachment: .audio(incomingAudioAttachment),
        deliveryText: nil
    )

    static let outgoingAudioMessage = IMessageChatMessagePresentation(
        id: 4,
        direction: .outgoing,
        attachment: .audio(outgoingAudioAttachment),
        deliveryText: "已读"
    )

    static let typingAccessibilityLabel = "Alex 正在输入"
    static let contactSubtitle = "iMessage"
    static let composerPlaceholder = "iMessage"
    static let sendAccessibilityLabel = "发送"
    static let composerStrings = IMessageChatComposerStrings(
        placeholder: composerPlaceholder,
        send: sendAccessibilityLabel,
        addAttachment: "Add attachment",
        audio: "Audio",
        dictate: "Dictate",
        stopDictation: "Stop dictation",
        stopRecording: "Stop recording",
        cancelAudio: "Cancel audio",
        playAudio: "Play audio",
        pauseAudio: "Pause audio",
        recordingRequiresEmptyDraft: "若要录音，请清除输入栏。",
        file: "文件",
        link: "链接"
    )
    static let composerMultilineText = "今晚七点见\n我会提前几分钟到"
    static let composerRTLText = "مساء الخير\nسأصل في السابعة"
    static let fixedDate = Date(timeIntervalSince1970: 1_788_257_740)

    static let state = IMessageChatViewModel.State(
        timeline: [
            IMessageChatTimelineItem(
                id: .timestamp(sourceMessageID: timestamp.sourceMessageID),
                content: .timestamp(timestamp)
            ),
            IMessageChatTimelineItem(
                id: .message(incomingMessage.id),
                content: .message(incomingMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(outgoingMessage.id),
                content: .message(outgoingMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(followUpMessage.id),
                content: .message(followUpMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(incomingAudioMessage.id),
                content: .message(incomingAudioMessage)
            ),
            IMessageChatTimelineItem(
                id: .message(outgoingAudioMessage.id),
                content: .message(outgoingAudioMessage)
            ),
            IMessageChatTimelineItem(
                id: .typing,
                content: .typing(
                    accessibilityLabel: typingAccessibilityLabel
                )
            ),
        ],
        isTyping: true
    )
}
#endif
