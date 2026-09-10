import Foundation
import Testing
@testable import Demo

@MainActor
@Suite(.serialized)
struct IMessageChatEquivalentReplyTests {
    @Test func mixedBatchAndConsecutiveSendsReplyInOrderWithIndependentIdentities() async throws {
        let fixture = try ReplyFiles()
        defer { fixture.remove() }
        let group = fixture.group
        let audioFile = fixture.file(extension: "m4a")
        let document = fixture.file(extension: "pdf")
        let link = IMessageChatLinkAttachment(url: URL(string: "https://www.apple.com")!, title: "Apple")
        let model = makeModel()
        defer { model.cancelPendingReply() }
        let payloads: [IMessageChatMessageContent] = [
            .attachment(.mediaGroup(group)), .userText("正文"),
            .attachment(.file(audioFile)), .attachment(.file(document)), .attachment(.link(link))
        ]
        #expect(model.sendContents(payloads))
        #expect(model.send("后续消息"))
        #expect(await eventually { !model.state.isProcessingMessages })
        let received = messages(model).filter { $0.id >= 3 && $0.direction == .incoming }
        let outgoing = messages(model).filter { $0.id >= 3 && $0.direction == .outgoing }
        #expect(received.count == 6)
        #expect(received.map(\.id) == [9, 10, 11, 12, 13, 14])
        guard received.count == 6 else { return }
        let media = try #require(received[0].attachment?.mediaGroup)
        #expect(media.id != group.id)
        #expect(media.items.map(\.kind) == group.items.map(\.kind))
        #expect(media.items.map(\.originalFileURL) == group.items.map(\.originalFileURL))
        #expect(media.items.map(\.thumbnailFileURL) == group.items.map(\.thumbnailFileURL))
        #expect(media.items.map(\.pixelSize) == group.items.map(\.pixelSize))
        #expect(media.items.map(\.isAnimatedImage) == group.items.map(\.isAnimatedImage))
        #expect(Set(media.items.map(\.id)).isDisjoint(with: group.items.map(\.id)))
        #expect(received[1].text == "imessage.reply.1")
        for (index, source) in [(2, audioFile), (3, document)] {
            guard case .file(let reply) = received[index].attachment else {
                Issue.record("Expected file reply"); continue
            }
            #expect(reply.id != source.id)
            #expect(reply.fileURL == source.fileURL)
            #expect(reply.displayName == source.displayName)
            #expect(reply.typeIdentifier == source.typeIdentifier)
            #expect(reply.byteCount == source.byteCount)
            #expect(reply.thumbnailURL == source.thumbnailURL)
            #expect(try Data(contentsOf: reply.fileURL) == Data(contentsOf: source.fileURL))
        }
        guard case .link(let reply) = received[4].attachment else { Issue.record("Expected link"); return }
        #expect(reply.id != link.id)
        #expect(reply.url == link.url && reply.title == link.title)
        #expect(received[5].text == "imessage.reply.1")
        #expect(outgoing.last?.deliveryText == "imessage.status.read")
        let snapshot = received.map(\.attachment)
        model.refreshLocalizedContent()
        #expect(messages(model).filter { $0.id >= 3 && $0.direction == .incoming }.map(\.attachment) == snapshot)
    }

    @Test(arguments: [false, true])
    func singlePhotoAndVideoPreserveTheirKind(video: Bool) async throws {
        let fixture = try ReplyFiles()
        defer { fixture.remove() }
        let source = IMessageChatMediaGroupAttachment(items: [fixture.group.items[video ? 1 : 0]])
        let model = makeModel()
        defer { model.cancelPendingReply() }
        #expect(model.sendAttachment(.mediaGroup(source)))
        #expect(await eventually { !model.state.isProcessingMessages })
        let reply = try #require(messages(model).last?.attachment?.mediaGroup)
        #expect(reply.items.count == 1)
        #expect(reply.items.first?.kind == source.items.first?.kind)
        #expect(reply.id != source.id)
    }

    @Test func waveformAudioWithoutSynthesizerRemainsAudio() async throws {
        let fixture = try ReplyFiles()
        defer { fixture.remove() }
        let source = IMessageChatAudioAttachment(fileURL: fixture.url("m4a"), duration: 2, waveform: [0.2, 0.8])
        let model = makeModel()
        defer { model.cancelPendingReply() }
        #expect(model.sendAttachment(.audio(source)))
        #expect(await eventually { !model.state.isProcessingMessages })
        let reply = try #require(messages(model).last?.audio)
        #expect(reply.id != source.id)
        #expect(reply.fileURL == source.fileURL)
        #expect(reply.waveform == source.waveform && reply.duration == source.duration)
    }

    @Test func cancellationClearsQueueAndIgnoresLateReplyThenAllowsNewSend() async throws {
        let gate = ReplyGate()
        let model = makeModel(sleeper: { _ in await gate.wait() })
        defer { model.cancelPendingReply() }
        #expect(model.send("first"))
        #expect(model.send("second"))
        #expect(await eventually { await gate.count == 1 })
        model.cancelPendingReply()
        #expect(!model.state.isProcessingMessages)
        #expect(model.send("new"))
        #expect(await eventually { await gate.count == 2 })
        await gate.releaseFirst()
        await gate.releaseFirst()
        #expect(await eventually { await gate.count == 3 })
        await gate.releaseFirst()
        #expect(await eventually { !model.state.isProcessingMessages })
        #expect(messages(model).filter { $0.id >= 3 && $0.direction == .incoming }.map(\.id) == [6])
    }

    @Test func invalidBatchDoesNotQueuePartialReplies() async throws {
        let fixture = try ReplyFiles()
        defer { fixture.remove() }
        let invalid = IMessageChatFileAttachment(id: UUID(), fileURL: fixture.directory.appendingPathComponent("missing"),
                                                displayName: "missing.pdf", typeIdentifier: "com.adobe.pdf", byteCount: 1)
        let model = makeModel()
        defer { model.cancelPendingReply() }
        #expect(!model.sendContents([.userText("text"), .attachment(.file(invalid))]))
        #expect(!model.state.isProcessingMessages)
        #expect(messages(model).count == 3)
    }

    private func makeModel(sleeper: @escaping IMessageChatViewModel.Sleeper = { _ in }) -> IMessageChatViewModel {
        IMessageChatViewModel(localizer: DemoLocalizer { key, _ in key }, clock: Date.init, sleeper: sleeper)
    }

    private func messages(_ model: IMessageChatViewModel) -> [IMessageChatMessagePresentation] {
        model.state.timeline.compactMap { if case .message(let message) = $0.content { message } else { nil } }
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private actor ReplyGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var count = 0
    func wait() async {
        count += 1
        await withCheckedContinuation { continuations.append($0) }
    }
    func releaseFirst() { continuations.removeFirst().resume() }
}

@MainActor
private struct ReplyFiles {
    let directory: URL
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for ext in ["png", "mov", "m4a", "pdf"] { try Data([1, 2, 3]).write(to: url(ext)) }
    }
    func url(_ ext: String) -> URL { directory.appendingPathComponent("original.\(ext)") }
    var group: IMessageChatMediaGroupAttachment {
        .init(items: [
            .init(assetIdentifier: "image", originalFileURL: url("png"), thumbnailFileURL: url("png"),
                  pixelSize: .init(width: 640, height: 480), kind: .image, isAnimatedImage: true),
            .init(assetIdentifier: "video", originalFileURL: url("mov"), thumbnailFileURL: url("png"),
                  pixelSize: .init(width: 480, height: 640), kind: .video(duration: 3))
        ])
    }
    func file(extension ext: String) -> IMessageChatFileAttachment {
        .init(id: UUID(), fileURL: url(ext), displayName: "原文件.\(ext)",
              typeIdentifier: ext == "pdf" ? "com.adobe.pdf" : "public.mpeg-4-audio", byteCount: 3,
              thumbnailURL: url("png"))
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private extension IMessageChatMessagePresentation {
    var attachment: IMessageChatAttachment? {
        if case .attachment(let attachment) = content { attachment } else { nil }
    }
}
