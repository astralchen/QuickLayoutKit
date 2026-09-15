import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 系统文件导入、后台处理及草稿所有权交接。
@available(iOS 17.0, *)
extension PhotoPickerController {
    /// 按选择顺序启动最多两项导入，文件获取与处理期间均保留导入槽位。
    func drainImports() {
        while activeImports.count < 2, !pendingImports.isEmpty {
            let pending = pendingImports.removeFirst()
            guard pending.generation == generation, entries.contains(where: { $0 === pending.entry }) else { continue }
            activeImports.insert(pending.entry.id)
            beginImport(provider: pending.provider, entry: pending.entry, generation: pending.generation)
        }
    }

    /// 回调返回前复制临时原件；回调和处理完成后均检查条目是否仍然有效。
    func beginImport(provider: NSItemProvider, entry: DraftEntry, generation: Int) {
        let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        let isLivePhoto = provider.canLoadObject(ofClass: PHLivePhoto.self)
        let type = isVideo ? UTType.movie : UTType.image
        let suffix = provider.registeredTypeIdentifiers.compactMap(UTType.init)
            .first(where: { $0.conforms(to: type) })?.preferredFilenameExtension ?? (isVideo ? "mov" : "jpg")
        let original = attachmentStore.makeFileURL(prefix: isVideo ? "video" : "image", pathExtension: suffix)
        let thumbnail = attachmentStore.makeFileURL(prefix: "media-thumbnail", pathExtension: "jpg")
        entry.originalURL = original
        entry.thumbnailURL = thumbnail
        let id = entry.id
        let scheduler = imageLoader.scheduler
        let fileRequest = MediaFileRequest { [weak self, weak entry] copyError in
            Task { @MainActor [weak self, weak entry] in
                guard let self else {
                    await Self.removeUnclaimed(original, thumbnail)
                    return
                }
                guard let entry, self.isCurrent(entry, generation: generation) else {
                    await Self.removeUnclaimed(original, thumbnail)
                    self.finishImport(id)
                    return
                }
                let task = Task { @MainActor [weak self, weak entry] in
                    do {
                        if let copyError { throw copyError }
                        let metadata = try await scheduler.run(kind: .importing) {
                            try await MediaImportProcessor.makeMetadata(originalURL: original, thumbnailURL: thumbnail,
                                isVideo: isVideo, isLivePhoto: isLivePhoto)
                        }
                        try Task.checkCancellation()
                        guard let self, let entry, self.isCurrent(entry, generation: generation) else {
                            await Self.removeUnclaimed(original, thumbnail)
                            self?.finishImport(id)
                            return
                        }
                        entry.content = .ready(MediaItem(id: id, assetIdentifier: entry.assetIdentifier,
                            originalFileURL: original, thumbnailFileURL: thumbnail, pixelSize: metadata.pixelSize,
                            kind: metadata.kind, isAnimatedImage: metadata.isAnimatedImage))
                        entry.task = nil
                        self.registerReadyDraftIfPossible()
                        self.publishDraft()
                        self.finishImport(id)
                    } catch {
                        await Self.removeUnclaimed(original, thumbnail)
                        if let self, let entry, self.isCurrent(entry, generation: generation), !Task.isCancelled, !(error is CancellationError) {
                            self.fail(entry: entry)
                        }
                        self?.finishImport(id)
                    }
                }
                entry.task = task
            }
        }
        entry.fileRequest = fileRequest
        entry.progress = fileRequest.start(provider: provider, typeIdentifier: type.identifier, destination: original)
    }

    /// 只有当前版本中的同一对象可以交付原件所有权。
    private func isCurrent(_ entry: DraftEntry, generation: Int) -> Bool {
        generation == self.generation && entries.contains(where: { $0 === entry })
    }

    /// 实际工作结束后释放导入槽位并唤醒等待项。
    private func finishImport(_ id: UUID) {
        activeImports.remove(id)
        drainImports()
    }

    /// 后台删除未交付或迟到的文件；不创建已被页面删除的目录。
    @concurrent private static func removeUnclaimed(_ original: URL, _ thumbnail: URL) async {
        try? FileManager.default.removeItem(at: original)
        try? FileManager.default.removeItem(at: thumbnail)
    }

    /// 取消条目的所有阶段并使缩略图缓存失效；运行中的回调负责最后一次清理。
    func cancelImport(_ entry: DraftEntry) {
        entry.fileRequest?.cancel()
        entry.progress?.cancel()
        entry.task?.cancel()
        pendingImports.removeAll { $0.entry === entry }
        if let url = entry.thumbnailURL { imageLoader.invalidate(url: url) }
        // 已交付文件可立即删除；未交付文件必须等写入结束再清理。
        if case .ready = entry.content {
            if let url = entry.originalURL { attachmentStore.removeFile(at: url) }
            if let url = entry.thumbnailURL { attachmentStore.removeFile(at: url) }
        }
    }

    /// 失败只影响仍然有效的项目，系统选择与草稿同步更新。
    private func fail(entry: DraftEntry) {
        guard let index = entries.firstIndex(where: { $0 === entry }) else { return }
        entries.remove(at: index)
        if let identifier = entry.assetIdentifier { picker?.deselectAssets(withIdentifiers: [identifier]) }
        registerReadyDraftIfPossible()
        publishDraft()
        failureDidOccur?()
    }

    /// 整组就绪后登记草稿；未就绪的文件仍由各导入操作拥有。
    func registerReadyDraftIfPossible() {
        guard let attachment = draftAttachment else { return }
        attachmentStore.registerDraft(.mediaGroup(attachment))
    }
}
