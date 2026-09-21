import AVFoundation
import ImageIO
import PDFKit
import PhotosUI
import Testing
import UIKit
import WebKit
import UniformTypeIdentifiers
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: ChatTestAvailability.isSupported))
struct ChatMessageMenuPreviewTests {
    private func message(_ attachment: Demo.Attachment) -> (MessagePresentation, MessageMenuTarget) {
        (.init(id: 12, direction: .incoming, attachment: attachment, deliveryText: nil),
         .init(messageID: 12, attachmentID: attachment.id, mediaItemID: attachment.mediaGroup?.items.first?.id))
    }

    @Test func contentCapabilitiesDoNotChangeMenuSemantics() {
        let url = URL(fileURLWithPath: "/tmp/preview")
        let types: [(String, MessageMenuPreviewKind?)] = [
            ("public.jpeg", .image), ("com.compuserve.gif", .image), ("public.mpeg-4", .video),
            ("com.adobe.pdf", .pdf), ("public.plain-text", .text), ("public.rtf", .quickLook), ("public.mp3", nil)
        ]
        for (type, expected) in types {
            let attachment = Demo.Attachment.file(.init(id: UUID(), fileURL: url, displayName: "File", typeIdentifier: type, byteCount: 10))
            let (message, target) = message(attachment)
            #expect(MessageMenuPreviewPolicy.kind(for: message, target: target) == expected)
            #expect(MessageMenuPolicy.items(for: message, target: target).map(\.operation) == [.save, .share, .delete])
        }
        let audio = Demo.Attachment.audio(.init(fileURL: url, duration: 1, waveform: []))
        let (audioMessage, audioTarget) = message(audio)
        #expect(MessageMenuPreviewPolicy.kind(for: audioMessage, target: audioTarget) == nil)
        let plain = MessagePresentation(id: 12, direction: .incoming, text: "Text", deliveryText: nil)
        #expect(MessageMenuPreviewPolicy.kind(for: plain, target: .init(messageID: 12)) == nil)
        let live = Demo.Attachment.mediaGroup(.init(items: [.init(assetIdentifier: nil, originalFileURL: url,
            thumbnailFileURL: url, pixelSize: .init(width: 100, height: 100), kind: .image, livePhotoVideoURL: url)]))
        let (liveMessage, liveTarget) = message(live)
        #expect(MessageMenuPreviewPolicy.kind(for: liveMessage, target: liveTarget) == .livePhoto)
        #expect(MessageMenuPreviewPolicy.kind(for: liveMessage, target: .init(messageID: 99)) == nil)
    }

    @Test func recordingAndNavigationPolicies() {
        #expect(MessageMenuPreviewPolicy.allowsAutoplay(composer: .idle))
        #expect(!MessageMenuPreviewPolicy.allowsAutoplay(composer: .preparingSpeech))
        #expect(!MessageMenuPreviewPolicy.allowsAutoplay(composer: .dictating(text: "draft")))
        #expect(!MessageMenuPreviewPolicy.allowsAutoplay(composer: .recording(elapsed: 2, waveform: [])))
        for url in ["https://example.com/path", "http://example.com"] {
            #expect(MessageMenuPreviewPolicy.allowsWebNavigation(URL(string: url)))
        }
        for url in ["tel:123", "file:///tmp/file", "javascript:alert(1)", "custom-app://open", "about:blank"] {
            #expect(!MessageMenuPreviewPolicy.allowsWebNavigation(URL(string: url)))
        }
    }

    @Test func constrainedMediaPreviewKeepsLockedItemsAspectRatio() throws {
        let url = URL(fileURLWithPath: "/tmp/preview-photo.jpg")
        for size in [CGSize(width: 480, height: 640), CGSize(width: 1080, height: 1920),
                     CGSize(width: 1920, height: 1080), CGSize(width: 600, height: 600)] {
            let first = MediaItem(assetIdentifier: nil, originalFileURL: url, thumbnailFileURL: url,
                                  pixelSize: .init(width: 1920, height: 1080), kind: .image)
            let selected = MediaItem(assetIdentifier: nil, originalFileURL: url, thumbnailFileURL: url,
                                     pixelSize: size, kind: .image, livePhotoVideoURL: url)
            let attachment = Demo.Attachment.mediaGroup(.init(items: [first, selected]))
            let (presentation, _) = message(attachment)
            let target = MessageMenuTarget(messageID: presentation.id, attachmentID: attachment.id, mediaItemID: selected.id)
            let coordinator = MessageMenuPreviewCoordinator(imageLoader: .init(), playbackCoordinator: .init(),
                resolve: { _ in presentation }, allowsAutoplay: { false }, open: { _, _ in })
            let preview = try #require(coordinator.makePreview(target, source: UIView()))
            let actual = preview.preferredContentSize
            #expect(abs(actual.width / actual.height - size.width / size.height) < 0.0001)
            #expect(actual.width <= 358.001 && actual.height <= 440.001)
            #expect(preview.attachment.mediaGroup?.items.first?.id == selected.id)
            preview.finish()
        }
    }

    @Test func filePreviewsFollowDecodedDimensionsAndRotation() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let photo = store.makeFileURL(prefix: "rotated-photo", pathExtension: "jpg")
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        let destination = try #require(CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(bitmap.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let pdfURL = store.makeFileURL(prefix: "rotated-page", pathExtension: "pdf")
        let document = try #require(PDFDocument(data: UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
            .pdfData { $0.beginPage() }))
        try #require(document.page(at: 0)).rotation = 90
        #expect(document.write(to: pdfURL))
        let video = try await AttachmentSavePreviewFixtures.videoAttachment(store: store, transform: .init(rotationAngle: .pi / 2))
        let videoURL = try #require(video.mediaGroup?.items.first?.originalFileURL)
        let bundle = try #require(Bundle.main.url(forResource: "AttachmentPreviewResources", withExtension: "bundle"))
        let files: [(URL, String, MessageMenuPreviewKind, CGFloat)] = [
            (photo, UTType.jpeg.identifier, .image, 0.5),
            (bundle.appendingPathComponent("preview-image-01.gif"), UTType.gif.identifier, .image, 1),
            (videoURL, UTType.quickTimeMovie.identifier, .video, 0.75),
            (pdfURL, UTType.pdf.identifier, .pdf, 2.0 / 3.0)
        ]
        for (url, type, kind, ratio) in files {
            let attachment = Demo.Attachment.file(.init(id: UUID(), fileURL: url, displayName: url.lastPathComponent,
                                                        typeIdentifier: type, byteCount: 0))
            let (_, target) = message(attachment)
            let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: kind,
                imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { false }, isValid: { true },
                maximumContentSize: CGSize(width: 320, height: 250))
            let window = try window(controller)
            #expect(await eventually { abs(controller.preferredContentSize.width / controller.preferredContentSize.height - ratio) < 0.001 },
                    "Incorrect preview ratio for \(url.lastPathComponent)")
            #expect(controller.preferredContentSize.width <= 320.001 && controller.preferredContentSize.height <= 250.001)
            #expect(!controller.playback.isPlaying)
            controller.finish()
            let finishedSize = controller.preferredContentSize
            controller.updateContentSize(CGSize(width: 1000, height: 100))
            #expect(controller.preferredContentSize == finishedSize)
            window.isHidden = true
        }
    }

    @Test func videoStartsOnlyWhenVisibleAndStopsOnCommit() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.videoAttachment(store: store)
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .video,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true })
        controller.loadViewIfNeeded()
        #expect(controller.playback.player == nil)
        #expect(!controller.hasAppeared)
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.playback.isPlaying && controller.playback.time > 0.3 })
        #expect(controller.playback.player?.isMuted == false)
        var captured: MessagePreviewPlayback?
        controller.openContent = { captured = $0 }
        let commit = try #require(controller.commitAction())
        #expect(controller.playback.player == nil)
        #expect(controller.isFinished)
        #expect(controller.commitAction() == nil)
        #expect(captured == nil)
        commit()
        #expect(captured?.isPlaying == true)
        #expect((captured?.time ?? 0) > 0)
    }

    @Test func recordingPreventsAutoplayEvenAfterReadiness() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.videoAttachment(store: store)
        let (_, target) = message(attachment)
        var allowed = false
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .video,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { allowed }, isValid: { true })
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.playback.player?.currentItem?.status == .readyToPlay })
        #expect(!controller.didStartVideo)
        allowed = true
        controller.playback.didChange?()
        #expect(!controller.didStartVideo)
        #expect(!controller.playback.isPlaying)
    }

    @Test func dismissedAndInvalidTargetsCannotStartOrCommit() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.videoAttachment(store: store)
        let (presentation, target) = message(attachment)
        var current: MessagePresentation? = presentation
        var opens = 0
        let coordinator = MessageMenuPreviewCoordinator(imageLoader: .init(), playbackCoordinator: .init(),
            resolve: { _ in current }, allowsAutoplay: { true }, open: { _, _ in opens += 1 })
        let preview = try #require(coordinator.makePreview(target, source: UIView()))
        let window = try window(preview)
        defer { preview.finish(); window.isHidden = true }
        current = nil
        coordinator.validate()
        #expect(preview.isFinished)
        #expect(preview.commitAction() == nil)
        try await Task.sleep(for: .milliseconds(150))
        #expect(preview.playback.player == nil)
        #expect(opens == 0)
    }

    @Test func webPreviewLoadsControlledHTMLAndCancelsWithoutCommit() async throws {
        let attachment = Demo.Attachment.link(.init(url: URL(string: "https://example.com/preview")!, title: "Preview"))
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .web,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true },
            webLoader: { web, url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
                web.loadSimulatedRequest(URLRequest(url: url), response: response,
                    responseData: Data("<html><body><h1>Controlled menu preview</h1></body></html>".utf8))
            })
        controller.loadViewIfNeeded()
        #expect(controller.webView == nil)
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.webView?.isHidden == false })
        let web = try #require(controller.webView)
        #expect(!web.isUserInteractionEnabled)
        #expect(web.configuration.mediaTypesRequiringUserActionForPlayback == .all)
        let text = try await web.evaluateJavaScript("document.body.innerText") as? String
        #expect(text?.contains("Controlled menu preview") == true)
        controller.finish()
        #expect(!web.isLoading)
        #expect(controller.webView == nil)
        #expect(controller.commitAction() == nil)
    }

    @Test func webFailureRetainsExternalOpenAndIgnoresLateCompletion() async throws {
        let attachment = Demo.Attachment.link(.init(url: URL(string: "https://example.com")!))
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .web,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true }, webLoader: { _, _ in })
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.webView != nil })
        let web = try #require(controller.webView)
        controller.webView(web, didFailProvisionalNavigation: nil, withError: URLError(.notConnectedToInternet))
        controller.webView(web, didFinish: nil)
        #expect(web.isHidden)
        #expect(controller.commitAction() != nil)
    }

    @Test func textAndQuickLookFilesLoadActualContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (ext, type, content, kind) in [
            ("txt", "public.plain-text", "Readable menu preview", MessageMenuPreviewKind.text),
            ("rtf", "public.rtf", "{\\rtf1\\ansi Quick Look menu preview.}", .quickLook)
        ] {
            let url = directory.appendingPathComponent("preview.\(ext)")
            try Data(content.utf8).write(to: url)
            let attachment = Demo.Attachment.file(.init(id: UUID(), fileURL: url, displayName: url.lastPathComponent,
                                                        typeIdentifier: type, byteCount: Int64(content.utf8.count)))
            let (_, target) = message(attachment)
            let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: kind,
                imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true })
            let window = try window(controller)
            if kind == .text {
                #expect(await eventually { controller.page.textView?.text == content })
            } else {
                func thumbnail(_ view: UIView) -> UIImageView? {
                    if view.accessibilityIdentifier == "imessage.menu.preview.thumbnail" { return view as? UIImageView }
                    return view.subviews.lazy.compactMap { thumbnail($0) }.first
                }
                #expect(await eventually { thumbnail(controller.view)?.image != nil })
                let image = try #require(thumbnail(controller.view)?.image)
                #expect(abs(controller.preferredContentSize.width / controller.preferredContentSize.height
                            - image.size.width / image.size.height) < 0.001)
            }
            controller.finish()
            window.isHidden = true
        }
    }

    @Test func playbackHandoffSeeksBeforeResuming() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.videoAttachment(store: store)
        let player = AttachmentPreviewPlayer(coordinator: .init())
        defer { player.stop() }
        player.prepare(url: try #require(attachment.mediaGroup?.items.first?.originalFileURL))
        #expect(await eventually { player.player?.currentItem?.status == .readyToPlay })
        player.restore(.init(time: 4, isPlaying: false))
        #expect(await eventually { abs(player.time - 4) < 0.1 })
        #expect(!player.isPlaying)
        player.restore(.init(time: 5, isPlaying: true))
        #expect(await eventually { player.isPlaying && player.time >= 5 })
    }

    @Test(arguments: [UIApplication.willResignActiveNotification, AVAudioSession.interruptionNotification])
    func interruptionEndsPreviewWithoutLateRestart(_ notification: Notification.Name) async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.videoAttachment(store: store)
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .video,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true })
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.playback.isPlaying })
        NotificationCenter.default.post(name: notification, object: nil)
        #expect(controller.isFinished)
        #expect(controller.playback.player == nil)
        controller.playback.didChange?()
        controller.viewDidAppear(false)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(controller.playback.player == nil)
        #expect(controller.commitAction() == nil)
    }

    @Test func livePhotoPreviewAutoplaysWithSoundAndStops() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let attachment = try await AttachmentSavePreviewFixtures.resourceAttachment(named: "resources-live-audio", store: store)
        let video = try #require(attachment.mediaGroup?.items.first?.livePhotoVideoURL)
        #expect(try await AVURLAsset(url: video).loadTracks(withMediaType: .audio).count == 1)
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .livePhoto,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true })
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.page.livePhotoPlayer?.isPlaying == true })
        #expect(controller.page.livePhotoPlayer?.view.isMuted == false)
        controller.finish()
        #expect(controller.page.livePhotoPlayer?.isPlaying == false)
        #expect(controller.page.livePhotoPlayer?.view.livePhoto == nil)
    }

    @Test func gifPreviewChangesRealFramesAndStopsAfterDismissal() async throws {
        let directory = try #require(Bundle.main.url(forResource: "AttachmentPreviewResources", withExtension: "bundle"))
        let url = directory.appendingPathComponent("preview-image-01.gif")
        let attachment = Demo.Attachment.mediaGroup(.init(items: [.init(assetIdentifier: nil,
            originalFileURL: url, thumbnailFileURL: url, pixelSize: .init(width: 320, height: 240), kind: .image, isAnimatedImage: true)]))
        let (_, target) = message(attachment)
        let controller = MessageMenuPreviewController(target: target, attachment: attachment, kind: .image,
            imageLoader: .init(), playbackCoordinator: .init(), allowsAutoplay: { true }, isValid: { true })
        let window = try window(controller)
        defer { controller.finish(); window.isHidden = true }
        #expect(await eventually { controller.page.hasOriginalImage })
        let first = try #require(controller.page.imageView.image?.pngData())
        #expect(await eventually { controller.page.imageView.image?.pngData() != first })
        controller.finish()
        let stopped = controller.page.imageView.image?.pngData()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(controller.page.imageView.image?.pngData() == stopped)
        #expect(!controller.page.isOriginalActive)
    }

    private func window(_ controller: UIViewController) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 400)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return window
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}
