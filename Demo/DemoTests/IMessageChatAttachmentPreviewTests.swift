import AVFoundation
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: IMessageChatTestAvailability.isSupported))
struct IMessageChatAttachmentPreviewTests {
    @Test func thumbnailStripRevealsSelectionAfterInitialLayoutAndResize() throws {
        guard #available(iOS 26.0, *) else { return }
        let base = IMessageChatPreviewData.attachmentPreviewItems[0]
        let strip = IMessageChatAttachmentThumbnailStripView(items: Array(repeating: base, count: 20), selectedIndex: 19)
        func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
        func layout(width: CGFloat) {
            strip.frame = CGRect(x: 0, y: 0, width: width, height: 64)
            strip.setNeedsLayout()
            strip.layoutIfNeeded()
        }
        layout(width: 370)
        let scroll = try #require(descendants(strip).compactMap { $0 as? UIScrollView }.first)
        let buttons = descendants(strip).compactMap { $0 as? UIButton }
        let last = try #require(buttons.first { $0.accessibilityIdentifier == "imessage.preview.thumbnail.19" })
        func isVisible(_ button: UIButton) -> Bool {
            scroll.bounds.insetBy(dx: -0.01, dy: -0.01).contains(button.convert(button.bounds, to: scroll))
        }
        #expect(strip.selectedIndex == 19)
        #expect(last.isSelected)
        #expect(isVisible(last))
        layout(width: 220)
        #expect(isVisible(last))
        layout(width: 560)
        #expect(isVisible(last))
        var requestedIndex: Int?
        strip.didSelectItem = { requestedIndex = $0 }
        let first = try #require(buttons.first { $0.accessibilityIdentifier == "imessage.preview.thumbnail.0" })
        first.sendActions(for: .touchUpInside)
        #expect(requestedIndex == 0)
        #expect(strip.selectedIndex == 19) // 宿主尚未完成翻页，不提前改变描边。
        strip.select(-1)
        strip.layoutIfNeeded()
        #expect(strip.selectedIndex == 0)
        #expect(first.isSelected && !last.isSelected)
        #expect(isVisible(first))
        #expect(requestedIndex == 0)
        strip.select(100)
        strip.layoutIfNeeded()
        #expect(strip.selectedIndex == 19)
        #expect(isVisible(last))
    }

    @Test func emptyThumbnailStripHasNoSelectionOrCallback() {
        guard #available(iOS 26.0, *) else { return }
        let strip = IMessageChatAttachmentThumbnailStripView(items: [])
        var callbacks = 0
        strip.didSelectItem = { _ in callbacks += 1 }
        strip.select(10)
        strip.frame = CGRect(x: 0, y: 0, width: 370, height: 64)
        strip.layoutIfNeeded()
        #expect(strip.selectedIndex == nil)
        #expect(callbacks == 0)
    }

    @Test func fileRoutingUsesUTTypeAndActualFileContents() throws {
        guard #available(iOS 26.0, *) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("Hello 世界".utf8).write(to: url)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.plainText.identifier) == .text("Hello 世界"))
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.pdf.identifier) == .pdf)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.png.identifier) == .image)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.mpeg4Movie.identifier) == .video)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.mp3.identifier) == .audio)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: "org.openxmlformats.wordprocessingml.document") == .quickLook)
        try Data([0xff, 0xfe, 0x41, 0x00]).write(to: url)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.plainText.identifier) == .text("A"))
        try Data([0xff, 0x80, 0x01]).write(to: url)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.plainText.identifier) == .quickLook)
        try Data(repeating: 65, count: 5 * 1024 * 1024 + 1).write(to: url)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.plainText.identifier) == .quickLook)
        try FileManager.default.removeItem(at: url)
        #expect(IMessageChatAttachmentPreviewItem.fileKind(url: url, typeIdentifier: UTType.pdf.identifier) == .unavailable)
    }

    @Test func currentPageRemainsSelectedAfterSizeChange() {
        guard #available(iOS 26.0, *) else { return }
        let base = IMessageChatPreviewData.attachmentPreviewItems[0]
        let items = (0..<20).map { index in
            IMessageChatAttachmentPreviewItem(id: UUID(), url: base.url, thumbnailURL: base.thumbnailURL, title: "\(index)", kind: .image)
        }
        let controller = IMessageChatAttachmentPreviewController(items: items, initialIndex: 4, playbackCoordinator: .init())
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        controller.view.layoutIfNeeded()
        #expect(controller.currentIndex == 4)
        #expect(controller.collectionView.contentOffset.x == CGFloat(4 * (402 + 20)))
        controller.select(0, animated: false)
        controller.view.layoutIfNeeded()
        #expect(controller.collectionView.contentOffset.x == 0)
        controller.select(18, animated: false)
        controller.view.frame.size = CGSize(width: 874, height: 402)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        #expect(controller.currentIndex == 18)
        #expect(abs(controller.collectionView.contentOffset.x - CGFloat(18 * (874 + 20))) < 0.5)
        controller.select(80, animated: false)
        #expect(controller.currentIndex == 19)
        controller.select(-2, animated: false)
        #expect(controller.currentIndex == 0)
        controller.completeDismissal()
    }

    @Test func dismissalThresholdRequiresDownwardIntent() {
        guard #available(iOS 26.0, *) else { return }
        #expect(!IMessageChatPreviewPolicy.shouldDismiss(distance: 20, velocity: 1200, height: 874))
        #expect(!IMessageChatPreviewPolicy.shouldDismiss(distance: 100, velocity: -1200, height: 874))
        #expect(IMessageChatPreviewPolicy.shouldDismiss(distance: 25, velocity: 901, height: 874))
        #expect(IMessageChatPreviewPolicy.shouldDismiss(distance: 193, velocity: 0, height: 874))
    }

    @Test func textSelectionAndImageZoomPreventDismissal() {
        guard #available(iOS 26.0, *) else { return }
        let page = IMessageChatPreviewPage(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let base = IMessageChatPreviewData.attachmentPreviewItems[0]
        page.configure(.init(id: base.id, url: base.url, thumbnailURL: nil, title: "Text", kind: .text("Selectable text")))
        page.layoutIfNeeded()
        #expect(page.permitsDismissal)
        page.documentTopInset = 240
        page.layoutIfNeeded()
        #expect(page.textView?.frame.minY == 240)
        page.textView?.selectedRange = NSRange(location: 0, length: 4)
        #expect(!page.permitsDismissal)
        page.textView?.selectedRange = NSRange(location: 0, length: 0)
        page.textView?.contentOffset.y = 50
        #expect(!page.permitsDismissal)
        page.configure(base)
        page.layoutIfNeeded()
        page.imageScrollView.zoomScale = 2
        #expect(!page.permitsDismissal)
        page.reset()
    }

    @Test func resettingPageRejectsLateImageLoad() async {
        guard #available(iOS 26.0, *) else { return }
        let page = IMessageChatPreviewPage(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        page.configure(IMessageChatPreviewData.attachmentPreviewItems[0])
        page.reset()
        for _ in 0..<20 { await Task.yield() }
        #expect(page.itemID == nil)
        #expect(page.imageView.image == nil)
        #expect(page.playerLayer.player == nil)
    }

    @Test func closingTwiceReleasesPlaybackAndCallsCompletionOnce() {
        guard #available(iOS 26.0, *) else { return }
        let controller = IMessageChatAttachmentPreviewController(items: IMessageChatPreviewData.attachmentPreviewItems, initialIndex: 0, playbackCoordinator: .init())
        controller.loadViewIfNeeded()
        var count = 0
        controller.didClose = { count += 1 }
        controller.completeDismissal()
        controller.completeDismissal()
        #expect(count == 1)
        #expect(controller.playback.player == nil)
    }
    @Test func detachedSourceFallsBackAndRestoresPresenter() async throws {
        guard #available(iOS 26.0, *) else { return }
        let presenter = UIViewController()
        let window = try makeVisibleTestWindow(rootViewController: presenter)
        defer { window.isHidden = true; window.rootViewController = nil }
        let preview = IMessageChatAttachmentPreviewController(items: IMessageChatPreviewData.attachmentPreviewItems, initialIndex: 0, playbackCoordinator: .init())
        let detachedCard = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        var resolvedForDismissal = false
        var completions = 0
        preview.sourceResolver = { _, synchronizing in
            resolvedForDismissal = resolvedForDismissal || synchronizing
            return synchronizing ? detachedCard : nil
        }
        preview.didClose = { completions += 1 }
        await withCheckedContinuation { continuation in
            presenter.present(preview, animated: true) { continuation.resume() }
        }
        #expect(preview.view.window === window)
        await withCheckedContinuation { continuation in
            preview.dismiss(animated: true) { continuation.resume() }
        }
        #expect(resolvedForDismissal)
        #expect(completions == 1)
        #expect(presenter.presentedViewController == nil)
        #expect(preview.view.superview == nil)
        #expect(presenter.view.alpha == 1)
        #expect(detachedCard.alpha == 1)
    }

}
