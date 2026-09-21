import Foundation
import UniformTypeIdentifiers

/// 预览能力独立于菜单操作；例如图像文件仍使用文件的导出菜单。
nonisolated enum MessageMenuPreviewKind: Equatable, Sendable {
    case image, video, livePhoto, pdf, text, quickLook, web
}

nonisolated enum MessageMenuPreviewPolicy {
    static func kind(for message: MessagePresentation, target: MessageMenuTarget) -> MessageMenuPreviewKind? {
        guard let attachment = target.attachment(in: message) else { return nil }
        switch attachment {
        case .audio: return nil
        case .link: return .web
        case .mediaGroup(let group):
            guard let item = group.items.first else { return nil }
            return item.kind.isVideo ? .video : item.isLivePhoto ? .livePhoto : .image
        case .file(let file):
            guard let type = UTType(file.typeIdentifier) else { return nil }
            if type.conforms(to: .audio) { return nil }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) { return .video }
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .plainText) { return .text }
            return .quickLook
        }
    }

    static func allowsAutoplay(composer: ComposerState) -> Bool {
        switch composer {
        case .idle, .audioPreview: true
        case .preparingSpeech, .dictating, .recording: false
        }
    }

    static func allowsWebNavigation(_ url: URL?) -> Bool {
        guard let url else { return false }
        return LinkAttachment.accepts(url)
    }
}

/// 菜单提交时的值快照；完整浏览器只消费一次，普通打开不携带该值。
nonisolated struct MessagePreviewPlayback: Equatable, Sendable {
    var time: Double = 0
    var isPlaying = false
    var playLivePhoto = false
}
