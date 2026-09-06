//
//  IMessageChatPhotoPickerController.swift
//  Demo
//
//  UIKit-only photo/video selection and page-owned file import.
//

import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

@available(iOS 26.0, *)
@MainActor
final class IMessageChatPhotoPickerController: NSObject,
    PHPickerViewControllerDelegate,
    UISheetPresentationControllerDelegate {

    /// PHPicker 在 iOS 26 会使用全屏透明承载视图；独立 Sheet Host 保证公开的
    /// `UIPresentationController.presentedView` 就是可见面板，便于逐帧读取几何。
    private final class SheetHostController: UIViewController {
        let picker: PHPickerViewController

        init(picker: PHPickerViewController) {
            self.picker = picker
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            addChild(picker)
            picker.view.frame = view.bounds
            picker.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(picker.view)
            picker.didMove(toParent: self)
        }
    }

    private final class DraftEntry {
        let id: UUID
        let assetIdentifier: String?
        var content: IMessageChatMediaDraftItemContent = .importing
        var progress: Progress?
        var originalURL: URL?
        var thumbnailURL: URL?

        init(id: UUID = UUID(), assetIdentifier: String?) {
            self.id = id
            self.assetIdentifier = assetIdentifier
        }

        var presentation: IMessageChatMediaDraftItemPresentation {
            IMessageChatMediaDraftItemPresentation(
                id: id,
                assetIdentifier: assetIdentifier,
                content: content
            )
        }
    }

    struct ImportedMetadata: Sendable {
        let pixelSize: CGSize
        let kind: IMessageChatMediaKind
        let isAnimatedImage: Bool
    }

    private static let keyboardDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "imessage.photo.keyboard"
    )

    private let attachmentStore: any IMessageChatAttachmentStoring
    private let fileManager: FileManager
    private var groupID = UUID()
    private var entries: [DraftEntry] = []
    private var picker: PHPickerViewController?
    private var sheetHost: SheetHostController?
    private var generation = 0
    private var storedKeyboardHeight: CGFloat = 300

    var stateDidChange: ((IMessageChatMediaDraftPresentation?) -> Void)?
    var failureDidOccur: (() -> Void)?
    var pickerDidPresent: ((UIViewController) -> Void)?
    /// 系统入场动画完成时调用，用于解除键盘到照片面板的输入栏位置冻结。
    var pickerDidFinishPresenting: ((UIViewController) -> Void)?
    var pickerDidDismiss: (() -> Void)?

    init(
        attachmentStore: any IMessageChatAttachmentStoring,
        fileManager: FileManager = .default
    ) {
        self.attachmentStore = attachmentStore
        self.fileManager = fileManager
        super.init()
    }

    var draft: IMessageChatMediaDraftPresentation? {
        guard !entries.isEmpty else { return nil }
        return IMessageChatMediaDraftPresentation(
            groupID: groupID,
            items: entries.map(\.presentation)
        )
    }

    var draftAttachment: IMessageChatMediaGroupAttachment? {
        draft?.attachment
    }

    /// 从创建面板到关闭动画完成均视为已展示，覆盖动画期间的键盘通知窗口。
    var isPresented: Bool {
        sheetHost != nil
    }

    func present(
        from presenter: UIViewController,
        keyboardHeight: CGFloat
    ) {
        if keyboardHeight > 0 {
            storedKeyboardHeight = keyboardHeight
        }
        if let sheetHost {
            if sheetHost.presentingViewController != nil {
                sheetHost.sheetPresentationController?.animateChanges {
                    sheetHost.sheetPresentationController?.selectedDetentIdentifier = Self.keyboardDetentIdentifier
                }
            }
            return
        }

        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = IMessageChatMediaGroupAttachment.selectionLimit
        configuration.selection = .continuousAndOrdered
        configuration.preferredAssetRepresentationMode = .current
        configuration.mode = .default
        configuration.disabledCapabilities = [
            .stagingArea,
            .sensitivityAnalysisIntervention,
        ]
        configuration.preselectedAssetIdentifiers = entries.compactMap(\.assetIdentifier)

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        let sheetHost = SheetHostController(picker: picker)
        sheetHost.isModalInPresentation = true
        sheetHost.modalPresentationStyle = .pageSheet
        if let sheet = sheetHost.sheetPresentationController {
            configureDetents(of: sheet)
            sheet.selectedDetentIdentifier = Self.keyboardDetentIdentifier
            sheet.largestUndimmedDetentIdentifier = Self.keyboardDetentIdentifier
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            sheet.delegate = self
        }
        self.picker = picker
        self.sheetHost = sheetHost
        // 顺序不可交换：先让协调器接管遮挡并冻结高度上限，再收键盘、展示面板。
        // 附件菜单关闭可能同步发出较小的键盘高度，若尚未接管就会污染本次上限。
        pickerDidPresent?(sheetHost)
        presenter.view.endEditing(true)
        presenter.present(sheetHost, animated: true) { [weak self] in
            self?.pickerDidFinishPresenting?(sheetHost)
        }
    }

    func dismissPicker(animated: Bool, completion: (() -> Void)? = nil) {
        guard let sheetHost, sheetHost.presentingViewController != nil else {
            completion?()
            return
        }
        sheetHost.dismiss(animated: animated) { [weak self] in
            // 动画完成前保留面板引用，供协调器逐帧读取位置，避免关闭开始时直接落底。
            self?.pickerDidDismiss?()
            self?.picker = nil
            self?.sheetHost = nil
            completion?()
        }
    }

    /// 保存下一次照片小档使用的稳定键盘内容高度。
    ///
    /// 照片 Sheet 与键盘交接时只更新缓存，不重新计算正在 dismiss 的 Sheet；普通
    /// 键盘高度变化则允许调用方同步刷新已经展示的 detent。
    func updateKeyboardHeight(
        _ height: CGFloat,
        invalidatingPresentedDetent: Bool = true
    ) {
        guard height > 0 else { return }
        storedKeyboardHeight = height
        guard invalidatingPresentedDetent else { return }
        guard let sheet = sheetHost?.sheetPresentationController else { return }
        configureDetents(of: sheet)
        sheet.invalidateDetents()
    }

    func removeItem(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = entries.remove(at: index)
        entry.progress?.cancel()
        if let url = entry.originalURL { attachmentStore.removeFile(at: url) }
        if let url = entry.thumbnailURL { attachmentStore.removeFile(at: url) }
        if let assetIdentifier = entry.assetIdentifier {
            picker?.deselectAssets(withIdentifiers: [assetIdentifier])
        }
        registerReadyDraftIfPossible()
        publishDraft()
    }

    @discardableResult
    func commitDraft() -> Bool {
        guard let attachment = draftAttachment else { return false }
        if !attachmentStore.commitDraft(id: attachment.id) {
            attachmentStore.registerCommitted(.mediaGroup(attachment))
        }
        entries.removeAll()
        groupID = UUID()
        generation &+= 1
        publishDraft()
        return true
    }

    func discardDraft() {
        entries.forEach { $0.progress?.cancel() }
        if let draftAttachment {
            attachmentStore.discardDraft(id: draftAttachment.id)
        } else {
            for entry in entries {
                if let url = entry.originalURL { attachmentStore.removeFile(at: url) }
                if let url = entry.thumbnailURL { attachmentStore.removeFile(at: url) }
            }
        }
        entries.removeAll()
        groupID = UUID()
        generation &+= 1
        publishDraft()
    }

    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        // A cancel callback can be empty even when a continuous-selection draft
        // already exists. Composer removal remains the explicit destructive action.
        guard !results.isEmpty || entries.isEmpty else { return }
        apply(results)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        pickerDidDismiss?()
    }

    private func apply(_ results: [PHPickerResult]) {
        let currentGeneration = generation
        let previousByIdentifier = Dictionary(
            uniqueKeysWithValues: entries.compactMap { entry in
                entry.assetIdentifier.map { ($0, entry) }
            }
        )
        var nextEntries: [DraftEntry] = []
        var retainedIDs: Set<UUID> = []

        for result in results.prefix(IMessageChatMediaGroupAttachment.selectionLimit) {
            if let identifier = result.assetIdentifier,
               let existing = previousByIdentifier[identifier] {
                nextEntries.append(existing)
                retainedIDs.insert(existing.id)
                continue
            }
            let entry = DraftEntry(assetIdentifier: result.assetIdentifier)
            nextEntries.append(entry)
            retainedIDs.insert(entry.id)
            beginImport(
                result: result,
                entry: entry,
                generation: currentGeneration
            )
        }

        for entry in entries where !retainedIDs.contains(entry.id) {
            entry.progress?.cancel()
            if let url = entry.originalURL { attachmentStore.removeFile(at: url) }
            if let url = entry.thumbnailURL { attachmentStore.removeFile(at: url) }
        }
        entries = nextEntries
        registerReadyDraftIfPossible()
        publishDraft()
    }

    private func beginImport(
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
                    let item = IMessageChatMediaItem(
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

    private func registerReadyDraftIfPossible() {
        guard let attachment = draftAttachment else { return }
        attachmentStore.registerDraft(.mediaGroup(attachment))
    }

    private func publishDraft() {
        stateDidChange?(draft)
    }

    private func configureDetents(of sheet: UISheetPresentationController) {
        let height = max(220, storedKeyboardHeight)
        let keyboardDetent = UISheetPresentationController.Detent.custom(
            identifier: Self.keyboardDetentIdentifier
        ) { _ in height }
        sheet.detents = [keyboardDetent, .large()]
    }

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
