import Foundation
import LinkPresentation
import QuickLook
import QuickLookThumbnailing
import UIKit
import UniformTypeIdentifiers

nonisolated struct IMessageChatDocumentDraft: Equatable, Sendable {
    enum Status: Equatable, Sendable { case importing, ready, failed }
    var attachment: IMessageChatAttachment
    var status: Status = .ready
    var id: UUID { attachment.id }
}

/// 文件和网页的独立草稿所有者。删除、提交或退出后，迟到的导入结果只做清理。
@available(iOS 26.0, *)
final class IMessageChatDocumentController: NSObject, UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    let store: any IMessageChatAttachmentStoring
    private(set) var drafts: [UUID: IMessageChatDocumentDraft] = [:]
    var draftInserted: ((IMessageChatDocumentDraft) -> Void)?
    var contentsInserted: (([IMessageChatEditorInsertion]) -> Void)?
    var pickerCancelled: (() -> Void)?
    var draftUpdated: ((IMessageChatDocumentDraft) -> Void)?
    var willInsert: (() -> Void)?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var providers: [UUID: LPMetadataProvider] = [:]
    private var imports: [UUID: Progress] = [:]
    private var previewFile: NSURL?
    private var previewID: UUID?
    private weak var previewController: QLPreviewController?

    init(store: any IMessageChatAttachmentStoring) { self.store = store }

    func adoptRecording(_ audio: IMessageChatAudioAttachment) {
        let file = IMessageChatFileAttachment(
            id: audio.id, fileURL: audio.fileURL,
            displayName: "Audio Message.\(audio.fileURL.pathExtension)",
            typeIdentifier: UTType(filenameExtension: audio.fileURL.pathExtension)?.identifier ?? UTType.audio.identifier,
            byteCount: Int64((try? audio.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        )
        insert(.init(attachment: .file(file)))
        fetchThumbnail(file)
    }

    func presentPicker(from controller: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        controller.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        insertPasted(urls.map { .fileURL($0) })
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pickerCancelled?()
    }

    /// 先同步插入有序占位，再异步复制文件；即使导入失败也保留可删除的卡片。
    func importDocument(_ source: URL) {
        let destination = store.makeFileURL(prefix: "document", pathExtension: source.pathExtension)
        let file = IMessageChatFileAttachment(
            id: UUID(), fileURL: destination, displayName: source.lastPathComponent,
            typeIdentifier: UTType(filenameExtension: source.pathExtension)?.identifier ?? UTType.data.identifier,
            byteCount: 0
        )
        insert(.init(attachment: .file(file), status: .importing))
        tasks[file.id] = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Int64? in
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                do {
                    guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
                    try FileManager.default.copyItem(at: source, to: destination)
                    return Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                } catch { return nil }
            }.value
            guard let self, !Task.isCancelled, drafts[file.id] != nil else {
                try? FileManager.default.removeItem(at: destination)
                return
            }
            tasks[file.id] = nil
            guard let size = result else {
                store.removeFile(at: destination)
                update(.init(attachment: .file(file), status: .failed))
                return
            }
            let imported = IMessageChatFileAttachment(
                id: file.id, fileURL: destination, displayName: file.displayName,
                typeIdentifier: file.typeIdentifier, byteCount: size
            )
            update(.init(attachment: .file(imported)))
            fetchThumbnail(imported)
        }
    }

    @discardableResult
    func insertLink(_ url: URL) -> Bool {
        guard IMessageChatLinkAttachment.accepts(url) else { return false }
        willInsert?()
        let link = IMessageChatLinkAttachment(url: url)
        insert(.init(attachment: .link(link)))
        fetchLink(link)
        return true
    }

    private func fetchLink(_ link: IMessageChatLinkAttachment) {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        providers[link.id] = provider
        tasks[link.id] = Task { [weak self] in
            guard let metadata = try? await provider.startFetchingMetadata(for: link.url),
                  let self, !Task.isCancelled, drafts[link.id] != nil else { return }
            var updated = link
            updated.title = metadata.title
            if let imageProvider = metadata.imageProvider ?? metadata.iconProvider,
               let data = try? await Self.imageData(from: imageProvider),
               let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.8),
               !Task.isCancelled, drafts[link.id] != nil {
                let path = store.makeFileURL(prefix: "link", pathExtension: "jpg")
                if (try? jpeg.write(to: path)) != nil { updated.imageURL = path }
            }
            guard !Task.isCancelled, drafts[link.id] != nil else { return }
            update(.init(attachment: .link(updated)))
            tasks[link.id] = nil
            providers[link.id] = nil
        }
    }

    /// 先注册整批占位，按剪贴板顺序替换选区；异步结果只更新同一身份。
    func insertPasted(_ sources: [IMessageChatPasteSource]) {
        guard !sources.isEmpty else { return }
        willInsert?()
        var batch: [IMessageChatDocumentDraft] = []
        var contents: [IMessageChatEditorInsertion] = []
        var work: [(IMessageChatPasteSource, IMessageChatFileAttachment)] = []
        for source in sources {
            if case .text(let text) = source { contents.append(.text(text)); continue }
            if case .link(let url) = source {
                guard IMessageChatLinkAttachment.accepts(url) else { continue }
                let draft = IMessageChatDocumentDraft(attachment: .link(.init(url: url)))
                batch.append(draft)
                contents.append(.attachment(draft))
                continue
            }
            let type: UTType
            let name: String
            switch source {
            case .provider(let provider, let identifier):
                type = UTType(identifier) ?? .data
                name = provider.suggestedName ?? DemoLocalization.text("imessage.attachment.pastedFile")
            case .fileURL(let url):
                type = UTType(filenameExtension: url.pathExtension) ?? .data
                name = url.lastPathComponent
            case .link, .text: continue
            }
            let ext = type.preferredFilenameExtension ?? (type.conforms(to: .image) ? "png" : (name as NSString).pathExtension)
            let filename = (name as NSString).pathExtension.isEmpty && !ext.isEmpty ? "\(name).\(ext)" : name
            let file = IMessageChatFileAttachment(
                id: UUID(), fileURL: store.makeFileURL(prefix: "paste", pathExtension: ext),
                displayName: filename, typeIdentifier: type.identifier, byteCount: 0
            )
            let draft = IMessageChatDocumentDraft(attachment: .file(file), status: .importing)
            batch.append(draft)
            contents.append(.attachment(draft))
            work.append((source, file))
        }
        for draft in batch {
            drafts[draft.id] = draft
            store.registerDraft(draft.attachment)
        }
        contentsInserted?(contents)
        for draft in batch {
            if case .link(let link) = draft.attachment { fetchLink(link) }
        }
        for (source, file) in work { importPasted(source, file: file) }
    }

    private func importPasted(_ source: IMessageChatPasteSource, file: IMessageChatFileAttachment) {
        tasks[file.id] = Task { [weak self] in
            guard let self, !Task.isCancelled, drafts[file.id] != nil else { return }
            let copied = await copyPaste(source, file: file)
            imports[file.id] = nil
            guard !Task.isCancelled, drafts[file.id] != nil else {
                if let copied { store.removeFile(at: copied.fileURL) }
                return
            }
            guard let copied else {
                store.removeFile(at: file.fileURL)
                update(.init(attachment: .file(file), status: .failed))
                tasks[file.id] = nil
                return
            }
            let type = UTType(copied.typeIdentifier) ?? .data
            if type.conforms(to: .image) || type.conforms(to: .movie) {
                let thumbnail = store.makeFileURL(prefix: "paste-thumbnail", pathExtension: "jpg")
                do {
                    let metadata = try await IMessageChatPhotoPickerController.makeMetadata(
                        originalURL: copied.fileURL, thumbnailURL: thumbnail,
                        isVideo: type.conforms(to: .movie), isLivePhoto: false
                    )
                    guard !Task.isCancelled, drafts[file.id] != nil else {
                        store.removeFile(at: copied.fileURL); store.removeFile(at: thumbnail); return
                    }
                    let media = IMessageChatMediaItem(
                        id: file.id, assetIdentifier: nil, originalFileURL: copied.fileURL,
                        thumbnailFileURL: thumbnail, pixelSize: metadata.pixelSize,
                        kind: metadata.kind, isAnimatedImage: metadata.isAnimatedImage
                    )
                    update(.init(attachment: .mediaGroup(.init(id: file.id, items: [media]))))
                } catch {
                    store.removeFile(at: copied.fileURL)
                    store.removeFile(at: thumbnail)
                    update(.init(attachment: .file(file), status: .failed))
                }
                tasks[file.id] = nil
            } else {
                update(.init(attachment: .file(copied)))
                fetchThumbnail(copied)
            }
        }
    }

    private func copyPaste(_ source: IMessageChatPasteSource, file: IMessageChatFileAttachment) async -> IMessageChatFileAttachment? {
        let destination = file.fileURL
        var imported = file
        switch source {
        case .fileURL(let url):
            let success = await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return false }
                    try FileManager.default.copyItem(at: url, to: destination)
                    return true
                } catch { return false }
            }.value
            guard success else { return nil }
        case .provider(let provider, let identifier):
            let success = await withCheckedContinuation { continuation in
                imports[file.id] = provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
                    // NSItemProvider 在回调返回后删除临时文件，必须在这里同步复制。
                    do {
                        guard let url else { continuation.resume(returning: false); return }
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume(returning: true)
                    } catch { continuation.resume(returning: false) }
                }
            }
            if !success {
                guard !Task.isCancelled, drafts[file.id] != nil else { return nil }
                if UTType(identifier)?.conforms(to: .image) == true, provider.canLoadObject(ofClass: UIImage.self) {
                    let png: Data? = await withCheckedContinuation { continuation in
                        imports[file.id] = provider.loadObject(ofClass: UIImage.self) { image, _ in
                            continuation.resume(returning: (image as? UIImage)?.pngData())
                        }
                    }
                    guard let png, !Task.isCancelled, drafts[file.id] != nil else { return nil }
                    let pngURL = destination.deletingPathExtension().appendingPathExtension("png")
                    do { try png.write(to: pngURL) } catch { return nil }
                    imported = .init(id: file.id, fileURL: pngURL,
                        displayName: (file.displayName as NSString).deletingPathExtension + ".png",
                        typeIdentifier: UTType.png.identifier, byteCount: Int64(png.count))
                } else {
                    let data: Data? = await withCheckedContinuation { continuation in
                        imports[file.id] = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                            continuation.resume(returning: data)
                        }
                    }
                    guard let data, !Task.isCancelled, drafts[file.id] != nil else { return nil }
                    do { try data.write(to: destination) } catch { return nil }
                }
            }
        case .link, .text: return nil
        }
        return .init(id: imported.id, fileURL: imported.fileURL, displayName: imported.displayName,
                     typeIdentifier: imported.typeIdentifier,
                     byteCount: Int64((try? imported.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
    }

    private static func imageData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
    }

    private func insert(_ draft: IMessageChatDocumentDraft) {
        drafts[draft.id] = draft
        store.registerDraft(draft.attachment)
        draftInserted?(draft)
    }

    private func update(_ draft: IMessageChatDocumentDraft) {
        guard drafts[draft.id] != nil else { return }
        drafts[draft.id] = draft
        store.registerDraft(draft.attachment)
        draftUpdated?(draft)
    }

    private func fetchThumbnail(_ file: IMessageChatFileAttachment) {
        tasks[file.id] = Task { [weak self] in
            let request = QLThumbnailGenerator.Request(
                fileAt: file.fileURL, size: CGSize(width: 100, height: 120), scale: 2,
                representationTypes: .all
            )
            guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
                  let self, !Task.isCancelled, drafts[file.id] != nil,
                  let data = representation.uiImage.pngData() else { return }
            let url = store.makeFileURL(prefix: "file-thumbnail", pathExtension: "png")
            guard (try? data.write(to: url)) != nil else { return }
            var updated = file
            updated.thumbnailURL = url
            update(.init(attachment: .file(updated)))
            tasks[file.id] = nil
        }
    }

    func attachments(for ids: [UUID]) -> [IMessageChatAttachment]? {
        guard Set(ids) == Set(drafts.keys), Set(ids).count == ids.count else { return nil }
        let values = ids.compactMap { drafts[$0] }
        guard values.allSatisfy({ $0.status == .ready }) else { return nil }
        return values.map(\.attachment)
    }

    func remove(_ id: UUID) {
        cancelWork(id)
        if previewID == id { previewController?.dismiss(animated: true); previewFile = nil; previewID = nil }
        drafts[id] = nil
        store.discardDraft(id: id)
    }

    func commit(_ ids: [UUID]) {
        for id in ids {
            cancelWork(id)
            if let draft = drafts.removeValue(forKey: id), !store.commitDraft(id: id) {
                store.registerCommitted(draft.attachment)
            }
        }
    }

    func discardAll() {
        for id in Array(drafts.keys) { remove(id) }
    }

    private func cancelWork(_ id: UUID) {
        imports.removeValue(forKey: id)?.cancel()
        tasks.removeValue(forKey: id)?.cancel()
        providers.removeValue(forKey: id)?.cancel()
    }

    func open(_ attachment: IMessageChatAttachment, from controller: UIViewController) {
        switch attachment {
        case .file(let file):
            guard FileManager.default.isReadableFile(atPath: file.fileURL.path) else { return }
            previewFile = file.fileURL as NSURL
            previewID = file.id
            let preview = QLPreviewController()
            preview.dataSource = self
            previewController = preview
            controller.present(preview, animated: true)
        case .link(let link): UIApplication.shared.open(link.url)
        case .mediaGroup(let group):
            guard let file = group.items.first?.originalFileURL else { return }
            previewFile = file as NSURL
            previewID = group.id
            let preview = QLPreviewController()
            preview.dataSource = self
            previewController = preview
            controller.present(preview, animated: true)
        case .audio: break
        }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewFile == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        previewFile ?? NSURL()
    }
}
