//
//  IMessageChatPhotoPickerController.swift
//  Demo
//
//  基于 UIKit 的照片和视频选择，以及页面拥有的文件导入。
//

import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 管理系统照片选择面板、有序媒体草稿及页面文件导入的控制器。
@available(iOS 26.0, *)
@MainActor
final class IMessageChatPhotoPickerController: NSObject,
    PHPickerViewControllerDelegate,
    UISheetPresentationControllerDelegate {

    /// PHPicker 在 iOS 26 会使用全屏透明承载视图；独立 Sheet Host 保证公开的
    /// `UIPresentationController.presentedView` 就是可见面板，便于逐帧读取几何。
    private final class SheetHostController: UIViewController {
        // iOS 26.5 中保留 Sheet 拖动条时，嵌入式 Picker 仍有 15 pt 顶部留白。
        // 只调整公开的子控制器视口，不访问 Photos 的内部滚动视图。
        /// 用于抵消嵌入式照片选择器顶部留白的视口偏移量，单位为点。
        private let pickerTopContentInset: CGFloat = 15
        /// 作为子控制器嵌入可测量面板的系统照片选择器。
        let picker: PHPickerViewController

        /// 创建承载指定照片选择器的面板宿主控制器。
        init(picker: PHPickerViewController) {
            self.picker = picker
            super.init(nibName: nil, bundle: nil)
        }

        /// 不支持从归档创建 `SheetHostController`。
        ///
        /// 请使用代码初始化方法创建此对象。
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// 建立照片选择器的子控制器关系，并补偿顶部安全区。
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            view.clipsToBounds = true
            addChild(picker)
            // 抵消子视图向上延伸时 UIKit 自动补入的顶部安全区。
            picker.additionalSafeAreaInsets.top = -pickerTopContentInset
            view.addSubview(picker.view)
            picker.didMove(toParent: self)
        }

        /// 按宿主边界和顶部补偿量更新照片选择器的视口。
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            picker.view.frame = CGRect(
                x: 0,
                y: -pickerTopContentInset,
                width: view.bounds.width,
                height: view.bounds.height + pickerTopContentInset
            )
        }
    }

    /// 持有单次媒体导入资源和进度的可变草稿条目。
    private final class DraftEntry {
        /// 导入占位与最终媒体项目共享的稳定标识符。
        let id: UUID
        /// 用于同步系统照片选中状态的资源标识符。
        let assetIdentifier: String?
        /// 条目当前的导入占位或已就绪媒体值。
        var content: IMessageChatMediaDraftItemContent = .importing
        /// 系统文件表示加载的可取消进度对象。
        var progress: Progress?
        /// 正在导入的媒体原件目标 URL。
        var originalURL: URL?
        /// 媒体缩略图的目标 URL。
        var thumbnailURL: URL?

        /// 创建带稳定身份和可选照片资源标识符的导入条目。
        init(id: UUID = UUID(), assetIdentifier: String?) {
            self.id = id
            self.assetIdentifier = assetIdentifier
        }

        /// 供输入栏渲染使用、不持有系统进度对象的条目快照。
        var presentation: IMessageChatMediaDraftItemPresentation {
            IMessageChatMediaDraftItemPresentation(
                id: id,
                assetIdentifier: assetIdentifier,
                content: content
            )
        }
    }

    /// 从已复制原件提取的媒体尺寸、类型和动态图像信息。
    struct ImportedMetadata: Sendable {
        /// 用于展示宽高比计算的媒体像素尺寸。
        let pixelSize: CGSize
        /// 原件的图像或视频类型及有效时长。
        let kind: IMessageChatMediaKind
        /// 指示原件包含多帧图像或来源为 Live Photo 的布尔值。
        let isAnimatedImage: Bool
    }

    /// 与键盘内容高度对应的自定义照片面板档位标识符。
    private static let keyboardDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "imessage.photo.keyboard"
    )

    /// 负责页面媒体原件、缩略图及草稿登记的附件存储。
    private let attachmentStore: any IMessageChatAttachmentStoring
    /// 媒体控制器初始化时注入并保留的文件管理器。
    private let fileManager: FileManager
    /// 当前媒体草稿组的身份；提交或丢弃后重新生成。
    private var groupID = UUID()
    /// 按系统连续选择顺序排列的媒体导入条目。
    private var entries: [DraftEntry] = []
    /// 当前系统照片选择器；关闭完成后解除持有。
    private var picker: PHPickerViewController?
    /// 承载系统照片选择器、供外部采样面板几何的宿主。
    private var sheetHost: SheetHostController?
    /// 当前草稿版本；提交或丢弃后递增以拒绝旧导入结果。
    private var generation = 0
    /// 用于计算照片小档高度的稳定键盘内容高度，默认值为 300 点。
    private var storedKeyboardHeight: CGFloat = 300

    /// 有序媒体草稿变化时调用的闭包；没有项目时传入 `nil`。
    var stateDidChange: ((IMessageChatMediaDraftPresentation?) -> Void)?
    /// 媒体导入失败并完成条目清理后调用的闭包。
    var failureDidOccur: (() -> Void)?
    /// 开始展示面板前调用的闭包，使页面能够先跟踪面板并处理键盘交接。
    var pickerDidPresent: ((UIViewController) -> Void)?
    /// 系统入场动画完成时调用，用于解除键盘到照片面板的输入栏位置冻结。
    var pickerDidFinishPresenting: ((UIViewController) -> Void)?
    /// 面板关闭完成时调用的闭包。
    var pickerDidDismiss: (() -> Void)?

    /// 创建使用页面附件存储和指定文件管理器的照片控制器。
    init(
        attachmentStore: any IMessageChatAttachmentStoring,
        fileManager: FileManager = .default
    ) {
        self.attachmentStore = attachmentStore
        self.fileManager = fileManager
        super.init()
    }

    /// 当前媒体草稿的有序展示快照；没有条目时为 `nil`。
    var draft: IMessageChatMediaDraftPresentation? {
        guard !entries.isEmpty else { return nil }
        return IMessageChatMediaDraftPresentation(
            groupID: groupID,
            items: entries.map(\.presentation)
        )
    }

    /// 当前可发送的媒体组；草稿为空或存在未完成导入时为 `nil`。
    var draftAttachment: IMessageChatMediaGroupAttachment? {
        draft?.attachment
    }

    /// 从创建面板到关闭动画完成均视为已展示，覆盖动画期间的键盘通知窗口。
    var isPresented: Bool {
        sheetHost != nil
    }

    /// 展示连续有序选择的照片面板，并以稳定键盘高度配置初始档位。
    ///
    /// 已经展示时仅将面板切回键盘高度档位。
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
        // 隐藏顶部导航栏和底部工具栏，让面板只显示照片网格。
        configuration.edgesWithoutContentMargins = [.top, .bottom]
        configuration.disabledCapabilities = [
            // 选择结果已实时同步至 Composer，由其提供移除和发送入口。
            .selectionActions,
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
            // 拖动条叠加在照片网格上，不单独占用顶部高度。
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

    /// 关闭照片面板，并在动画完成前保留宿主引用供页面跟踪几何。
    ///
    /// - Parameters:
    ///   - animated: 是否使用系统关闭动画。
    ///   - completion: 面板关闭及引用清理完成后调用的闭包。
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

    /// 取消并删除指定草稿项目，同步系统选择状态后发布剩余草稿。
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

    /// 将全部就绪的媒体草稿转为已提交附件，并开始新的草稿版本。
    ///
    /// - Returns: 有可发送媒体组且完成提交时为 `true`；否则为 `false`。
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

    /// 取消全部导入，删除未提交文件并使当前草稿版本失效。
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

    /// 将系统连续选择结果应用到草稿；已有草稿时忽略取消产生的空回调。
    func picker(
        _ picker: PHPickerViewController,
        didFinishPicking results: [PHPickerResult]
    ) {
        // 连续选择已有草稿时，取消回调仍可能返回空数组；保留已有草稿，
        // 由输入栏的显式移除操作决定是否删除选定内容。
        guard !results.isEmpty || entries.isEmpty else { return }
        apply(results)
    }

    /// 将系统面板关闭事件转发给页面协调层。
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        pickerDidDismiss?()
    }

    /// 按新选择顺序复用已有资源条目，导入新增项目并删除不再选择的文件。
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

    /// 在系统文件表示回调返回前复制原件，再异步提取媒体元数据。
    ///
    /// 复制后和元数据完成后均校验草稿版本与条目身份，失效结果只执行清理。
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
    private func registerReadyDraftIfPossible() {
        guard let attachment = draftAttachment else { return }
        attachmentStore.registerDraft(.mediaGroup(attachment))
    }

    /// 向观察者发布当前有序草稿快照。
    private func publishDraft() {
        stateDidChange?(draft)
    }

    /// 设置不低于 220 点的键盘高度档位及系统大档位。
    private func configureDetents(of sheet: UISheetPresentationController) {
        let height = max(220, storedKeyboardHeight)
        let keyboardDetent = UISheetPresentationController.Detent.custom(
            identifier: Self.keyboardDetentIdentifier
        ) { _ in height }
        sheet.detents = [keyboardDetent, .large()]
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
