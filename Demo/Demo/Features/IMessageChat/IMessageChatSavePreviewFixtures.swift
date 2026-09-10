#if DEBUG
import AVFoundation
import UIKit

/// UI 回归通过启动参数使用真实本地附件；正常启动不改变会话内容。
@MainActor
enum IMessageChatSavePreviewFixtures {
    static func attachment(store: any IMessageChatAttachmentStoring) throws -> IMessageChatAttachment? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-imessage-save-fixture"), arguments.indices.contains(index + 1) else { return nil }
        let attachment: IMessageChatAttachment
        switch arguments[index + 1] {
        case "photo", "group":
            let url = store.makeFileURL(prefix: "save-preview", pathExtension: "png")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
                UIColor.systemYellow.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 210, y: 24, width: 48, height: 48))
                UIColor.systemGreen.setFill()
                context.fill(CGRect(x: 0, y: 140, width: 300, height: 60))
            }
            try image.pngData()?.write(to: url)
            let count = arguments[index + 1] == "group" ? 3 : 1
            attachment = .mediaGroup(.init(items: (0..<count).map { _ in
                .init(assetIdentifier: nil, originalFileURL: url, thumbnailFileURL: url,
                      pixelSize: image.size, kind: .image)
            }))
        case "audio":
            let url = store.makeFileURL(prefix: "save-preview", pathExtension: "caf")
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
            buffer.frameLength = 16_000
            if let channel = buffer.floatChannelData?[0] { channel.initialize(repeating: 0, count: 16_000) }
            let audio = try AVAudioFile(forWriting: url, settings: format.settings)
            try audio.write(from: buffer)
            attachment = .file(.init(id: UUID(), fileURL: url, displayName: "Audio Message.caf",
                typeIdentifier: "com.apple.coreaudio-format", byteCount: 64_000))
        case "document":
            let url = store.makeFileURL(prefix: "save-preview", pathExtension: "pdf")
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200)).writePDF(to: url) { context in
                context.beginPage()
                ("Attachment save preview" as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: nil)
            }
            attachment = .file(.init(id: UUID(), fileURL: url, displayName: "Attachment.pdf",
                typeIdentifier: "com.adobe.pdf", byteCount: 1000))
        default: return nil
        }
        store.registerCommitted(attachment)
        return attachment
    }
}
#endif
