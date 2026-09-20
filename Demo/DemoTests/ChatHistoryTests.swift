import AppLocalization
import AVFAudio
import PDFKit
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized, .enabled(if: ChatTestAvailability.isSupported))
struct ChatHistoryTests {
    @Test func completeHistoryHasRealResourcesAndNoSendSideEffects() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = PageAttachmentStore()
        defer { store.removeAll() }
        let samples = try await SampleChatHistory.load(store: store)
        let model = ChatViewModel()
        #expect(model.messages.isEmpty && model.state.timeline.isEmpty)
        #expect(model.nextMessageID == 0)
        model.insertInitialHistory(samples)
        #expect(samples.count == 26)
        #expect(model.messages.count == 26)
        #expect(model.nextMessageID == 26)
        #expect(model.messages.filter { $0.direction == .outgoing }.count == 13)
        #expect(model.messages.allSatisfy { $0.deliveryState == ($0.direction == .outgoing ? .read : nil) })
        #expect(model.sendTasks.isEmpty && model.pendingReplies.isEmpty && model.pendingReplyTask == nil)
        #expect(!model.state.isProcessingMessages && !model.state.isTyping)
        #expect(Set(model.messages.map(\.id)).count == 26)
        var media: [MediaItem] = []
        var attachmentIDs: [UUID] = []
        var files: Set<URL> = []
        for sample in samples {
            switch sample.content {
            case .userText(let text):
                #expect(!text.isEmpty)
            case .richText(let text):
                #expect(text.runs.contains { $0.style == [.bold, .italic, .underline] })
                #expect(text.runs.contains { $0.style == .strikethrough })
            case .attachment(let attachment):
                attachmentIDs.append(attachment.id)
                for url in attachment.localFileURLs {
                    #expect(url.path.hasPrefix(store.directoryURL.path + "/"))
                    #expect(FileManager.default.isReadableFile(atPath: url.path))
                    files.insert(url)
                }
                switch attachment {
                case .audio(let audio):
                    let player = try AVAudioPlayer(contentsOf: audio.fileURL)
                    #expect(abs(player.duration - audio.duration) < 0.01)
                    #expect(audio.duration > 1 && audio.waveform.contains { $0 > 0.08 })
                    #expect(audio.transcript?.contains("语音消息") == true)
                case .file(let file):
                    #expect((PDFDocument(url: file.fileURL)?.pageCount ?? 0) > 0)
                    #expect(file.byteCount > 0)
                case .mediaGroup(let group): media += group.items
                case .link(let link):
                    #expect(LinkAttachment.accepts(link.url) && link.title != nil)
                    #expect(link.imageURL == nil && link.iconURL == nil)
                }
            default: Issue.record("Unexpected sample history content")
            }
        }
        #expect(Set(attachmentIDs).count == 14)
        #expect(media.count == 8 && Set(media.map(\.id)).count == 8)
        #expect(media.filter(\.isLivePhoto).count == 2)
        #expect(media.filter(\.isAnimatedImage).count == 2)
        #expect(media.filter { $0.kind.isVideo }.count == 2)
        #expect(media.allSatisfy { !($0.isLivePhoto && $0.isAnimatedImage) })
        model.insertInitialHistory(samples)
        #expect(model.messages.count == 26)
        store.removeAll()
        #expect(files.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func loadingPreservesNewMessagesAndTheirIDs() async throws {
        guard #available(iOS 26.0, *) else { return }
        let model = ChatViewModel()
        #expect(model.send("sent during loading"))
        let sent = try #require(model.messages.last)
        let store = PageAttachmentStore()
        defer { store.removeAll(); model.cancelPendingReply() }
        let samples = try await SampleChatHistory.load(store: store)
        model.insertInitialHistory(samples)
        #expect(model.messages[26].id == sent.id)
        #expect(model.messages[26].content == sent.content)
        #expect(Set(model.messages.map(\.id)).count == model.messages.count)
        #expect(model.messages.map(\.sentAt) == model.messages.map(\.sentAt).sorted())
        let nextID = model.nextMessageID
        #expect(model.send("sent after loading"))
        #expect(model.messages.last?.id == nextID)
    }

    @Test func partialLivePhotoFailureRemovesOrphansAndKeepsOtherTypes() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = InterceptingStore()
        defer { store.removeAll() }
        store.rejectedName = "live-photo.mov"
        let samples = try await SampleChatHistory.load(store: store)
        #expect(samples.count == 24)
        let referenced = Set(samples.flatMap { sample -> [URL] in
            if case .attachment(let attachment) = sample.content { return attachment.localFileURLs }
            return []
        })
        let actual = try FileManager.default.contentsOfDirectory(at: store.directoryURL, includingPropertiesForKeys: nil)
        #expect(Set(actual) == referenced)
    }

    @Test func cancellationAfterImportRemovesAllPartialFiles() async throws {
        guard #available(iOS 26.0, *) else { return }
        let store = InterceptingStore()
        defer { store.removeAll() }
        var task: Task<[MessageHistoryEntry], Error>?
        var importCount = 0
        store.imported = {
            importCount += 1
            if importCount == 2 { task?.cancel() }
        }
        task = Task { try await SampleChatHistory.load(store: store) }
        do {
            _ = try await task!.value
            Issue.record("Cancelled history should not be inserted")
        } catch is CancellationError {} catch { Issue.record(error) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path).isEmpty)
    }

    @Test func onlyOrdinaryEntryLoadsInitialHistory() async throws {
        guard #available(iOS 26.0, *) else { return }
        #expect(SampleChatHistory.isEnabled(arguments: []))
        for argument in ["-imessage-save-fixture", "preview-video", "-media-benchmark", "-imessage-basic-history"] {
            #expect(!SampleChatHistory.isEnabled(arguments: [argument]))
        }
        let injected = ChatViewController(viewModel: ChatViewModel())
        injected.loadViewIfNeeded()
        #expect(injected.viewModel.messages.isEmpty)
        for _ in 0..<2 {
            let page = ChatViewController()
            page.loadViewIfNeeded()
            for _ in 0..<150 where page.viewModel.messages.count != 26 {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(page.viewModel.messages.count == 26)
            #expect(page.viewModel.sendTasks.isEmpty)
        }
    }

    @Test func leavingBeforeLoadCompletesCannotAppendHistory() async throws {
        guard #available(iOS 26.0, *) else { return }
        var page: ChatViewController? = ChatViewController()
        let pageWasReleased = { [weak page] in page == nil }
        let model = page!.viewModel
        let directory = page!.attachmentStore.directoryURL
        page!.loadViewIfNeeded()
        page = nil
        for _ in 0..<50 where !pageWasReleased() || FileManager.default.fileExists(atPath: directory.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(pageWasReleased())
        #expect(model.messages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func historyInsertionKeepsAnchorAndSendingStillReachesBottom() async throws {
        guard #available(iOS 26.0, *) else { return }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIViewController()
        let conversation = ConversationView(frame: window.bounds)
        host.view = conversation
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let model = ChatViewModel()
        let now = Date()
        model.messages += (0..<45).map {
            Message(id: $0, direction: .incoming, content: .userText("History \($0)\nSecond line"),
                    sentAt: now, deliveryState: nil)
        }
        model.nextMessageID = 45
        model.state = model.makeState()
        model.bind { state, reason in conversation.render(state, reason: reason) }
        let list = conversation.collectionView
        #expect(await eventually {
            conversation.layoutIfNeeded()
            list.layoutIfNeeded()
            return list.numberOfItems(inSection: 0) == model.state.timeline.count
                && !list.visibleCells.isEmpty && list.contentSize.height > list.bounds.height
                && conversation.isNearBottom
        })
        conversation.scrollViewWillBeginDragging(list)
        list.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        list.layoutIfNeeded()
        #expect(await eventually { !list.indexPathsForVisibleItems.isEmpty })
        let index = try #require(list.indexPathsForVisibleItems.sorted().first)
        let id = model.state.timeline[index.item].id
        let beforeY = try #require(list.layoutAttributesForItem(at: index)).frame.minY - list.contentOffset.y
        model.insertInitialHistory((0..<16).map { _ in
            .init(direction: .incoming, content: .userText("Earlier history\nSecond line"))
        })
        let newIndex = try #require(model.state.timeline.firstIndex { $0.id == id })
        #expect(await eventually {
            list.layoutIfNeeded()
            guard list.numberOfItems(inSection: 0) == model.state.timeline.count,
                  let attributes = list.layoutAttributesForItem(at: IndexPath(item: newIndex, section: 0)) else { return false }
            return abs(attributes.frame.minY - list.contentOffset.y - beforeY) < 2
        })
        defer { model.cancelPendingReply() }
        #expect(model.send("Sent from long history"))
        let sentID = model.messages.last?.id
        #expect(await eventually {
            conversation.layoutIfNeeded()
            list.layoutIfNeeded()
            return model.messages.first(where: { $0.id == sentID })?.deliveryState == .read
                && conversation.isNearBottom && list.visibleCells.contains {
                ($0 as? BubbleCell)?.bubbleView.accessibilityLabel == "Sent from long history"
            }
        })
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

/// 在真实页面目录上注入部分导入失败或取消，检查实际文件回收。
@MainActor
private final class InterceptingStore: AttachmentStoring {
    let base = PageAttachmentStore()
    var rejectedName: String?
    var imported: (() -> Void)?
    var directoryURL: URL { base.directoryURL }
    func makeFileURL(prefix: String, pathExtension: String) -> URL {
        base.makeFileURL(prefix: prefix, pathExtension: pathExtension)
    }
    func importFile(at sourceURL: URL, prefix: String, pathExtension: String?) throws -> URL {
        if sourceURL.lastPathComponent == rejectedName { throw CocoaError(.fileReadNoSuchFile) }
        let url = try base.importFile(at: sourceURL, prefix: prefix, pathExtension: pathExtension)
        imported?()
        return url
    }
    func registerDraft(_ attachment: Demo.Attachment) { base.registerDraft(attachment) }
    func registerCommitted(_ attachment: Demo.Attachment) { base.registerCommitted(attachment) }
    func commitDraft(id: UUID) -> Bool { base.commitDraft(id: id) }
    func discardDraft(id: UUID) { base.discardDraft(id: id) }
    func removeFile(at url: URL) { base.removeFile(at: url) }
    func removeAll() { base.removeAll() }
}
