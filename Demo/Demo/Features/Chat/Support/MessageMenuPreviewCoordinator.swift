import UIKit
import QuickLook

/// 页面只持有当前预览的弱引用；UIKit 持有展示中的控制器。
@MainActor
final class MessageMenuPreviewCoordinator {
    private let imageLoader: MediaImageLoader
    private let playbackCoordinator: PlaybackCoordinator
    private let resolve: (MessageMenuTarget) -> MessagePresentation?
    private let allowsAutoplay: () -> Bool
    private let open: (MessageMenuTarget, MessagePreviewPlayback?) -> Void
    private weak var current: MessageMenuPreviewController?

    init(imageLoader: MediaImageLoader, playbackCoordinator: PlaybackCoordinator,
         resolve: @escaping (MessageMenuTarget) -> MessagePresentation?,
         allowsAutoplay: @escaping () -> Bool,
         open: @escaping (MessageMenuTarget, MessagePreviewPlayback?) -> Void) {
        self.imageLoader = imageLoader
        self.playbackCoordinator = playbackCoordinator
        self.resolve = resolve
        self.allowsAutoplay = allowsAutoplay
        self.open = open
    }

    func canPreview(_ target: MessageMenuTarget) -> Bool {
        guard let message = resolve(target), let kind = MessageMenuPreviewPolicy.kind(for: message, target: target) else { return false }
        if kind == .quickLook, case .file(let file) = target.attachment(in: message) {
            return QLPreviewController.canPreview(file.fileURL as NSURL)
        }
        return true
    }

    func makePreview(_ target: MessageMenuTarget, source: UIView) -> MessageMenuPreviewController? {
        guard canPreview(target), let message = resolve(target),
              let attachment = target.attachment(in: message),
              let kind = MessageMenuPreviewPolicy.kind(for: message, target: target) else { return nil }
        current?.finish()
        let available = source.window?.safeAreaLayoutGuide.layoutFrame.size ?? CGSize(width: 390, height: 800)
        let maximumSize = CGSize(width: min(420, max(1, available.width - 32)), height: max(1, available.height * 0.55))
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: kind,
            imageLoader: imageLoader, playbackCoordinator: playbackCoordinator,
            allowsAutoplay: allowsAutoplay, isValid: { [weak self] in self?.resolve(target) != nil },
            maximumContentSize: maximumSize)
        controller.openContent = { [weak self] playback in
            guard let self, resolve(target) != nil else { return }
            open(target, playback)
        }
        controller.view.semanticContentAttribute = source.semanticContentAttribute
        if let item = attachment.mediaGroup?.items.first { controller.updateContentSize(item.pixelSize) }
        current = controller
        return controller
    }

    func openAccessiblePreview(_ target: MessageMenuTarget) {
        guard canPreview(target) else { return }
        open(target, nil)
    }

    func validate() { if let current, resolve(current.target) == nil { current.finish() } }
    func invalidate() { current?.finish(); current = nil }
}
