//
//  PhotoPickerController+Import.swift
//  Demo
//

import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 导入照片视频文件并生成媒体元数据。
@available(iOS 17.0, *)
extension PhotoPickerController {

    /// 从已复制原件提取的媒体尺寸、类型和动态图像信息。
    struct ImportedMetadata: Sendable {
        /// 用于展示宽高比计算的媒体像素尺寸。
        let pixelSize: CGSize
        /// 原件的图像或视频类型及有效时长。
        let kind: MediaKind
        /// 指示原件包含多帧图像或来源为 Live Photo 的布尔值。
        let isAnimatedImage: Bool
    }

    /// 在系统文件表示回调返回前复制原件，再异步提取媒体元数据。
    ///
    /// 复制后和元数据完成后均校验草稿版本与条目身份，失效结果只执行清理。
    func beginImport(
        result: PHPickerResult,
        entry: DraftEntry,
        generation: Int
    ) {
        let provider = result.itemProvider
        let isVideo = provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier)
        // 直接查询选择结果的公开 item-provider 能力，避免为了 Live Photo 标志
        // 反查整个照片库或触发照片库授权。
        let isLivePhoto = provider.canLoadObject(ofClass: PHLivePhoto.self)
        let type = isVideo ? UTType.movie : UTType.image
        let sourceExtension = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: type) })?
            .preferredFilenameExtension
            ?? (isVideo ? "mov" : "jpg")
        let originalURL = attachmentStore.makeFileURL(
            prefix: isVideo ? "video" : "image",
            pathExtension: sourceExtension
        )
        let thumbnailURL = attachmentStore.makeFileURL(
            prefix: "media-thumbnail",
            pathExtension: "jpg"
        )
        entry.originalURL = originalURL
        entry.thumbnailURL = thumbnailURL
        entry.progress = provider.loadFileRepresentation(
            forTypeIdentifier: type.identifier
        ) { [weak self, weak entry] sourceURL, error in
            guard let self, let entry else { return }
            guard error == nil, let sourceURL else {
                Task { @MainActor [weak self] in self?.fail(entry: entry) }
                return
            }
            do {
                // 提供者回调返回后临时 URL 可能立即失效，必须先同步复制原件。
                try FileManager.default.copyItem(at: sourceURL, to: originalURL)
            } catch {
                Task { @MainActor [weak self] in self?.fail(entry: entry) }
                return
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.generation,
                      self.entries.contains(where: { $0.id == entry.id }) else {
                    self.attachmentStore.removeFile(at: originalURL)
                    return
                }
                do {
                    let metadata = try await Self.makeMetadata(
                        originalURL: originalURL,
                        thumbnailURL: thumbnailURL,
                        isVideo: isVideo,
                        isLivePhoto: isLivePhoto
                    )
                    guard generation == self.generation,
                          self.entries.contains(where: { $0.id == entry.id }) else {
                        self.attachmentStore.removeFile(at: originalURL)
                        self.attachmentStore.removeFile(at: thumbnailURL)
                        return
                    }
                    let item = MediaItem(
                        id: entry.id,
                        assetIdentifier: entry.assetIdentifier,
                        originalFileURL: originalURL,
                        thumbnailFileURL: thumbnailURL,
                        pixelSize: metadata.pixelSize,
                        kind: metadata.kind,
                        isAnimatedImage: metadata.isAnimatedImage
                    )
                    entry.content = .ready(item)
                    self.registerReadyDraftIfPossible()
                    self.publishDraft()
                } catch {
                    self.fail(entry: entry)
                }
            }
        }
    }

    /// 移除仍活跃的失败条目，删除部分文件并通知草稿变化与导入失败。
    private func fail(entry: DraftEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries.remove(at: index)
        if let url = entry.originalURL { attachmentStore.removeFile(at: url) }
        if let url = entry.thumbnailURL { attachmentStore.removeFile(at: url) }
        if let identifier = entry.assetIdentifier {
            picker?.deselectAssets(withIdentifiers: [identifier])
        }
        registerReadyDraftIfPossible()
        publishDraft()
        failureDidOccur?()
    }

    /// 在所有媒体项目就绪时将整组附件登记到页面草稿存储。
    func registerReadyDraftIfPossible() {
        guard let attachment = draftAttachment else { return }
        attachmentStore.registerDraft(.mediaGroup(attachment))
    }

    /// 读取媒体原件元数据，并将静态预览写入指定缩略图位置。
    ///
    /// - Parameters:
    ///   - originalURL: 页面拥有的媒体原件。
    ///   - thumbnailURL: JPEG 缩略图的输出位置。
    ///   - isVideo: 是否按视频轨道和时长读取原件。
    ///   - isLivePhoto: 系统提供者是否将来源标为 Live Photo。
    /// - Returns: 媒体展示所需的尺寸、类型和动态图像标记。
    /// - Throws: 原件损坏、元数据无效、解码或缩略图写入失败时产生的错误。
    static func makeMetadata(
        originalURL: URL,
        thumbnailURL: URL,
        isVideo: Bool,
        isLivePhoto: Bool
    ) async throws -> ImportedMetadata {
        if isVideo {
            let asset = AVURLAsset(url: originalURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = tracks.first,
                  duration.isNumeric,
                  duration.seconds.isFinite,
                  duration.seconds > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
                .standardized
                .size
            guard transformedSize.width > 0, transformedSize.height > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 1280)
            let posterTime = CMTime(
                seconds: min(0.1, duration.seconds / 2),
                preferredTimescale: 600
            )
            let result = try await generator.image(at: posterTime)
            try writeJPEG(result.image, to: thumbnailURL)
            return ImportedMetadata(
                pixelSize: transformedSize,
                kind: .video(duration: duration.seconds),
                isAnimatedImage: false
            )
        }

        guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1280,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try writeJPEG(thumbnail, to: thumbnailURL)
        return ImportedMetadata(
            pixelSize: CGSize(width: width.doubleValue, height: height.doubleValue),
            kind: .image,
            isAnimatedImage: isLivePhoto || CGImageSourceGetCount(source) > 1
        )
    }

    /// 以 0.84 压缩质量将图像写入 JPEG 文件；无法创建或完成写入时抛出错误。
    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
