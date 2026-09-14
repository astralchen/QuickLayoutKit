//
//  PhotoPickerController.swift
//  Demo
//

import AVFoundation
import ImageIO
import Photos
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// 管理系统照片选择面板、有序媒体草稿及页面文件导入的控制器。
@available(iOS 17.0, *)
@MainActor
final class PhotoPickerController: NSObject,
    PHPickerViewControllerDelegate,
    UISheetPresentationControllerDelegate {

    /// 持有单次媒体导入资源和进度的可变草稿条目。
    final class DraftEntry {
        /// 导入占位与最终媒体项目共享的稳定标识符。
        let id: UUID
        /// 用于同步系统照片选中状态的资源标识符。
        let assetIdentifier: String?
        /// 条目当前的导入占位或已就绪媒体值。
        var content: MediaDraftItemContent = .importing
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
        var presentation: MediaDraftItemPresentation {
            MediaDraftItemPresentation(
                id: id,
                assetIdentifier: assetIdentifier,
                content: content
            )
        }
    }

    /// 与键盘内容高度对应的自定义照片面板档位标识符。
    private static let keyboardDetentIdentifier = UISheetPresentationController.Detent.Identifier(
        "imessage.photo.keyboard"
    )

    /// 负责页面媒体原件、缩略图及草稿登记的附件存储。
    let attachmentStore: any AttachmentStoring
    /// 媒体控制器初始化时注入并保留的文件管理器。
    private let fileManager: FileManager
    /// 当前媒体草稿组的身份；提交或丢弃后重新生成。
    private var groupID = UUID()
    /// 按系统连续选择顺序排列的媒体导入条目。
    var entries: [DraftEntry] = []
    /// 当前系统照片选择器；关闭完成后解除持有。
    var picker: PHPickerViewController?
    /// 承载系统照片选择器、供外部采样面板几何的宿主。
    private var sheetHost: SheetHostController?
    /// 当前草稿版本；提交或丢弃后递增以拒绝旧导入结果。
    var generation = 0
    /// 用于计算照片小档高度的稳定键盘内容高度，默认值为 300 点。
    private var storedKeyboardHeight: CGFloat = 300

    /// 有序媒体草稿变化时调用的闭包；没有项目时传入 `nil`。
    var stateDidChange: ((MediaDraftPresentation?) -> Void)?
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
        attachmentStore: any AttachmentStoring,
        fileManager: FileManager = .default
    ) {
        self.attachmentStore = attachmentStore
        self.fileManager = fileManager
        super.init()
    }

    #if DEBUG
    /// 使用真实本地样例覆盖导入步骤，以确定性验证照片草稿入口。
    func applyPreviewFixture(_ group: MediaGroupAttachment) {
        discardDraft()
        groupID = group.id
        entries = group.items.map { item in
            let entry = DraftEntry(id: item.id, assetIdentifier: item.assetIdentifier)
            entry.content = .ready(item)
            entry.originalURL = item.originalFileURL
            entry.thumbnailURL = item.thumbnailFileURL
            return entry
        }
        registerReadyDraftIfPossible()
        publishDraft()
    }
    #endif

    /// 当前媒体草稿的有序展示快照；没有条目时为 `nil`。
    var draft: MediaDraftPresentation? {
        guard !entries.isEmpty else { return nil }
        return MediaDraftPresentation(
            groupID: groupID,
            items: entries.map(\.presentation)
        )
    }

    /// 当前可发送的媒体组；草稿为空或存在未完成导入时为 `nil`。
    var draftAttachment: MediaGroupAttachment? {
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
        configuration.selectionLimit = MediaGroupAttachment.selectionLimit
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

    /// 将全部就绪的媒体草稿转为已提交附件，清除系统勾选并保留面板当前档位。
    ///
    /// - Returns: 有可发送媒体组且完成提交时为 `true`；否则为 `false`。
    @discardableResult
    func commitDraft() -> Bool {
        guard let attachment = draftAttachment else { return false }
        if !attachmentStore.commitDraft(id: attachment.id) {
            attachmentStore.registerCommitted(.mediaGroup(attachment))
        }
        let selectedIdentifiers = entries.compactMap(\.assetIdentifier)
        entries.removeAll()
        groupID = UUID()
        generation &+= 1
        // 先清空草稿并推进版本，再同步系统选择，避免同步回调复用已提交的条目。
        if !selectedIdentifiers.isEmpty {
            picker?.deselectAssets(withIdentifiers: selectedIdentifiers)
        }
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

        for result in results.prefix(MediaGroupAttachment.selectionLimit) {
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

    /// 向观察者发布当前有序草稿快照。
    func publishDraft() {
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
}
