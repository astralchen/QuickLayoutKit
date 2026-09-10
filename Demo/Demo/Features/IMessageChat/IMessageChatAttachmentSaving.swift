import Photos
import UIKit

/// 保存状态属于当前聊天页面；同一附件出现在不同消息中时分别记录。
nonisolated struct IMessageChatAttachmentSaveKey: Hashable, Sendable {
    /// 保存操作所属消息的稳定标识符。
    let messageID: Int
    /// 保存操作所属附件的稳定标识符。
    let attachmentID: UUID
}

/// 附件保存按钮在当前页面中的显示与交互状态。
nonisolated enum IMessageChatAttachmentSaveState: String, Sendable {
    /// 依次表示可以保存、正在保存、短暂显示完成反馈以及隐藏入口。
    case available, saving, completed, hidden
}

/// 系统保存流程正常结束时返回的结果。
nonisolated enum IMessageChatAttachmentSaveOutcome: Sendable {
    /// 依次表示已保存副本以及用户取消保存。
    case saved, cancelled
}

/// 附件保存前的权限、资源或展示条件不满足时产生的错误。
nonisolated enum IMessageChatAttachmentSaveError: Error, Equatable {
    /// 依次表示照片写入权限不足、附件不可导出以及无法展示系统选择器。
    case photoPermissionDenied, invalidAttachment, presentationUnavailable
}

/// 仅媒体组与文件卡片支持保存；语音气泡不属于文件导出入口。
nonisolated enum IMessageChatAttachmentSavePolicy {
    /// 返回指定附件是否包含可保存的媒体原件或文件。
    ///
    /// - Parameter attachment: 待检查的页面附件。
    /// - Returns: 非空媒体组或文件附件返回 `true`；音频气泡和链接返回 `false`。
    static func supports(_ attachment: IMessageChatAttachment) -> Bool {
        switch attachment {
        case .mediaGroup(let group): !group.items.isEmpty
        case .file: true
        case .audio, .link: false
        }
    }

    /// 返回是否应为指定消息显示保存入口。
    ///
    /// 只有收到的消息且附件支持保存时返回 `true`。
    static func showsButton(for message: IMessageChatMessagePresentation) -> Bool {
        guard message.direction == .incoming,
              case .attachment(let attachment) = message.content else { return false }
        return supports(attachment)
    }
}

/// 将页面附件保存到系统照片图库或用户选择的位置的接口。
@MainActor
protocol IMessageChatAttachmentSaving {
    /// 保存指定附件，并等待系统流程结束。
    ///
    /// - Parameters:
    ///   - attachment: 要保存的媒体组或文件附件。
    ///   - presenter: 用于展示系统文件导出界面的视图控制器。
    /// - Returns: 保存成功或用户取消的结果。
    /// - Throws: 权限、附件读取、界面展示或系统写入错误。
    func save(_ attachment: IMessageChatAttachment, from presenter: UIViewController) async throws -> IMessageChatAttachmentSaveOutcome
}

/// 在进入任何异步系统操作前复制原件，独立于页面附件目录持有导出资源。
@MainActor
final class IMessageChatAttachmentSaveSnapshot {
    /// 用于持有导出副本的独立临时目录。
    let directoryURL: URL
    /// 按附件顺序排列的副本 URL；在快照释放前保持可用。
    let files: [URL]

    /// 复制附件原件，创建不依赖聊天页面生命周期的导出快照。
    ///
    /// - Parameters:
    ///   - attachment: 包含可读原件的媒体组或文件附件。
    ///   - parentDirectory: 导出目录的父目录；默认使用系统临时目录。
    /// - Throws: 附件不支持导出，或创建目录、复制文件失败时产生的错误。
    init(_ attachment: IMessageChatAttachment, parentDirectory: URL = FileManager.default.temporaryDirectory) throws {
        let sources: [(URL, String)]
        switch attachment {
        case .mediaGroup(let group) where !group.items.isEmpty:
            sources = group.items.map { ($0.originalFileURL, $0.originalFileURL.lastPathComponent) }
        case .file(let file):
            // 展示名称只用于副本文件名，移除目录部分并保留原件扩展名。
            // 每个原件使用独立子目录，允许媒体组中出现同名文件。
            var name = (file.displayName as NSString).lastPathComponent
            if name.isEmpty || name == "." || name == ".." { name = file.fileURL.lastPathComponent }
            let ext = file.fileURL.pathExtension
            if !ext.isEmpty && (name as NSString).pathExtension.lowercased() != ext.lowercased() {
                name = (name as NSString).deletingPathExtension + "." + ext
            }
            sources = [(file.fileURL, name)]
        default: throw IMessageChatAttachmentSaveError.invalidAttachment
        }
        directoryURL = parentDirectory.appendingPathComponent("IMessageChat-Export-\(UUID().uuidString)", isDirectory: true)
        let manager = FileManager.default
        var copies: [URL] = []
        do {
            for (index, source) in sources.enumerated() {
                let folder = directoryURL.appendingPathComponent(String(index), isDirectory: true)
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(source.1)
                try manager.copyItem(at: source.0, to: destination)
                copies.append(destination)
            }
            files = copies
        } catch {
            try? manager.removeItem(at: directoryURL)
            throw error
        }
    }

    /// 释放快照时删除导出副本及其临时目录。
    deinit { try? FileManager.default.removeItem(at: directoryURL) }
}

/// 使用 Photos 和系统文件选择器保存附件的对象。
@MainActor
final class IMessageChatSystemAttachmentSaver: IMessageChatAttachmentSaving {
    /// 将有序媒体项目及对应文件副本写入照片图库的异步操作。
    typealias PhotoWriter = ([IMessageChatMediaItem], [URL]) async throws -> Void
    /// 请求照片图库仅添加权限的异步闭包。
    private let authorizePhotos: () async -> PHAuthorizationStatus
    /// 执行媒体原件写入的闭包；文件顺序与媒体项目一一对应。
    private let writePhotos: PhotoWriter

    /// 创建系统附件保存器，并允许替换照片权限与写入操作。
    ///
    /// 未提供闭包时使用 Photos 的仅添加授权和批量资源创建接口。
    init(authorizePhotos: (() async -> PHAuthorizationStatus)? = nil, writePhotos: PhotoWriter? = nil) {
        self.authorizePhotos = authorizePhotos ?? { await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        self.writePhotos = writePhotos ?? { items, files in
            try await PHPhotoLibrary.shared().performChanges {
                for (item, file) in zip(items, files) {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: item.kind.isVideo ? .video : .photo, fileURL: file, options: nil)
                }
            }
        }
    }

    /// 在创建独立副本后保存附件，并将副本保留到系统操作结束。
    ///
    /// 媒体组写入照片图库，文件通过系统选择器导出；取消文件选择返回 `.cancelled`。
    func save(_ attachment: IMessageChatAttachment, from presenter: UIViewController) async throws -> IMessageChatAttachmentSaveOutcome {
        let snapshot = try IMessageChatAttachmentSaveSnapshot(attachment)
        // 显式延长副本生命周期，包含系统保存完成或取消回调。
        defer { withExtendedLifetime(snapshot) {} }
        switch attachment {
        case .mediaGroup(let group):
            let status = await authorizePhotos()
            guard status == .authorized || status == .limited else {
                throw IMessageChatAttachmentSaveError.photoPermissionDenied
            }
            try await writePhotos(group.items, snapshot.files)
            return .saved
        case .file:
            let session = IMessageChatDocumentExportSession()
            return try await session.export(snapshot.files, from: presenter)
        case .audio, .link:
            throw IMessageChatAttachmentSaveError.invalidAttachment
        }
    }
}

/// 系统导出控制器只复制附件；取消选择器不属于错误。
@MainActor
final class IMessageChatDocumentExportSession: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
    /// 展示文件导出选择器的闭包；默认使用动画展示。
    private let presentPicker: (UIDocumentPickerViewController, UIViewController) -> Void

    /// 创建文件导出会话，并可注入系统选择器的展示操作。
    init(presentPicker: ((UIDocumentPickerViewController, UIViewController) -> Void)? = nil) {
        self.presentPicker = presentPicker ?? { picker, presenter in presenter.present(picker, animated: true) }
        super.init()
    }

    /// 等待系统导出结果的延续；完成时先清空，防止重复恢复。
    private var continuation: CheckedContinuation<IMessageChatAttachmentSaveOutcome, Never>?
    /// 系统选择器展示期间对会话自身的强引用；流程结束后解除。
    private var retainedSession: IMessageChatDocumentExportSession?

    /// 展示复制模式的文件选择器，并等待保存或取消结果。
    ///
    /// - Parameters:
    ///   - files: 非空且全部可读的本地文件 URL。
    ///   - presenter: 已进入窗口、未在退出且没有其他模态界面的展示控制器。
    /// - Returns: 系统文件导出结果。
    /// - Throws: 资源不可读或展示条件不满足时产生的错误。
    func export(_ files: [URL], from presenter: UIViewController) async throws -> IMessageChatAttachmentSaveOutcome {
        guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil,
              !presenter.isBeingDismissed else { throw IMessageChatAttachmentSaveError.presentationUnavailable }
        let picker = try Self.makePicker(files)
        picker.delegate = self
        retainedSession = self
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            presentPicker(picker, presenter)
            picker.presentationController?.delegate = self
        }
    }

    /// 校验文件集合并创建以复制方式导出的系统选择器。
    ///
    /// 文件集合为空或任一文件不可读时抛出附件错误。
    static func makePicker(_ files: [URL]) throws -> UIDocumentPickerViewController {
        guard !files.isEmpty, files.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw IMessageChatAttachmentSaveError.invalidAttachment
        }
        let picker = UIDocumentPickerViewController(forExporting: files, asCopy: true)
        return picker
    }

    /// 在系统返回导出位置后完成会话；空结果按取消处理。
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.isEmpty ? .cancelled : .saved)
    }

    /// 在用户取消文件选择时以取消结果完成会话。
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.cancelled) }
    /// 在系统选择器被交互式关闭后以取消结果完成会话。
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(.cancelled) }

    /// 解除会话自持有，并至多一次恢复等待导出的调用方。
    private func finish(_ outcome: IMessageChatAttachmentSaveOutcome) {
        // 系统代理可能先后报告取消与关闭；先取走延续，后续回调即成为空操作。
        let pending = continuation
        continuation = nil
        retainedSession = nil
        pending?.resume(returning: outcome)
    }
}

/// 管理防重入、完成截止时间和页面退出；系统已接收的保存操作不会被页面退出取消。
@MainActor
final class IMessageChatAttachmentSaveCoordinator {
    /// 负责执行系统保存操作的对象。
    private let saver: any IMessageChatAttachmentSaving
    /// 返回当前时间的闭包，用于判断完成反馈是否到期。
    private let clock: () -> Date
    /// 用于等待完成反馈结束的可注入挂起操作。
    private let sleep: (Duration) async throws -> Void
    /// 按消息和附件组合身份保存的交互状态。
    private var states: [IMessageChatAttachmentSaveKey: IMessageChatAttachmentSaveState] = [:]
    /// 保存完成反馈的截止时间；达到后不再显示按钮。
    private var deadlines: [IMessageChatAttachmentSaveKey: Date] = [:]
    /// 按保存身份管理的完成反馈延时任务。
    private var timers: [IMessageChatAttachmentSaveKey: Task<Void, Never>] = [:]
    /// 指示协调器是否仍允许发起操作并发布页面状态的布尔值。
    private var active = true
    /// 指定附件保存状态变化时调用的闭包。
    var stateDidChange: ((IMessageChatAttachmentSaveKey, IMessageChatAttachmentSaveState) -> Void)?
    /// 保存失败且页面仍有效时调用的错误回调。
    var failed: ((Error) -> Void)?

    /// 创建保存协调器，并注入保存器、时间来源与延时操作。
    ///
    /// 省略保存器时使用系统实现；完成反馈默认持续一秒。
    init(saver: (any IMessageChatAttachmentSaving)? = nil,
         clock: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.saver = saver ?? IMessageChatSystemAttachmentSaver()
        self.clock = clock
        self.sleep = sleep
    }

    /// 返回指定保存身份的状态，并根据当前时间处理已到期的完成反馈。
    func state(for key: IMessageChatAttachmentSaveKey) -> IMessageChatAttachmentSaveState {
        // 使用绝对时间兜底，避免主线程繁忙或应用挂起延迟计时任务后仍显示完成图标。
        if let deadline = deadlines[key], clock() >= deadline { return .hidden }
        return states[key] ?? .available
    }

    /// 为支持保存的收到消息启动一次保存操作。
    ///
    /// 同一身份仅在可保存状态下受理请求；页面失效后忽略系统返回的界面更新。
    func save(message: IMessageChatMessagePresentation, from presenter: UIViewController) {
        guard active, IMessageChatAttachmentSavePolicy.showsButton(for: message),
              case .attachment(let attachment) = message.content else { return }
        let key = IMessageChatAttachmentSaveKey(messageID: message.id, attachmentID: attachment.id)
        guard state(for: key) == .available else { return }
        update(key, .saving)
        let saver = saver
        Task { [weak self] in
            guard self?.active == true else { return }
            do {
                let result = try await saver.save(attachment, from: presenter)
                guard let self, active else { return }
                switch result {
                case .cancelled: update(key, .available)
                case .saved:
                    deadlines[key] = clock().addingTimeInterval(1)
                    update(key, .completed)
                    let sleep = sleep
                    timers[key] = Task { [weak self] in
                        do { try await sleep(.seconds(1)) } catch { return }
                        guard let self, active else { return }
                        update(key, .hidden)
                        timers[key] = nil
                    }
                }
            } catch {
                guard let self, active else { return }
                update(key, .available)
                failed?(error)
            }
        }
    }

    /// 使协调器永久失效，取消反馈计时并移除页面回调。
    ///
    /// 已经交给系统的保存流程继续持有自己的导出副本。
    func invalidate() {
        active = false
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        stateDidChange = nil
        failed = nil
    }

    /// 记录指定附件的保存状态并同步通知观察者。
    private func update(_ key: IMessageChatAttachmentSaveKey, _ state: IMessageChatAttachmentSaveState) {
        states[key] = state
        stateDidChange?(key, state)
    }
}

/// 36 pt 圆形视觉置于 44 pt 点击区域；隐藏仅影响内容，不移除布局占位。
@available(iOS 26.0, *)
final class IMessageChatAttachmentSaveButton: UIButton {
    /// 保存按钮的圆形背景视图。
    private let circle = UIView()
    /// 表示下载或保存完成的符号图像视图。
    private let symbol = UIImageView()
    /// 保存期间替代静态符号显示的活动指示器。
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// 使用指定初始边框创建 `IMessageChatAttachmentSaveButton`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        circle.isUserInteractionEnabled = false
        circle.backgroundColor = .secondarySystemFill
        circle.layer.cornerRadius = 18
        addSubview(circle)
        symbol.tintColor = .systemBlue
        symbol.contentMode = .scaleAspectFit
        circle.addSubview(symbol)
        spinner.color = .systemBlue
        circle.addSubview(spinner)
        accessibilityIdentifier = "imessage.attachment.save"
    }

    /// 不支持从归档创建 `IMessageChatAttachmentSaveButton`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// `IMessageChatAttachmentSaveButton` 在当前内容与布局约束下的固有尺寸。
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
    /// 返回 `IMessageChatAttachmentSaveButton` 在指定建议尺寸下所需的大小。
    ///
    /// - Parameter size: 父视图提供的建议尺寸。
    /// - Returns: 当前内容对应的适配尺寸。
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    /// 根据当前边界更新 `IMessageChatAttachmentSaveButton` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        circle.frame = CGRect(x: bounds.midX - 18, y: bounds.midY - 18, width: 36, height: 36)
        symbol.frame = circle.bounds.insetBy(dx: 8, dy: 8)
        spinner.center = CGPoint(x: 18, y: 18)
    }

    /// 根据保存状态更新图标、可交互性和辅助功能标签。
    ///
    /// - Parameters:
    ///   - state: 当前附件的保存状态。
    ///   - isMedia: 是否使用保存到照片图库的辅助功能标签；否则使用文件保存标签。
    func configure(_ state: IMessageChatAttachmentSaveState, isMedia: Bool) {
        isEnabled = state == .available
        circle.isHidden = state == .hidden
        isAccessibilityElement = state != .hidden
        symbol.image = UIImage(systemName: state == .completed ? "checkmark" : "square.and.arrow.down")
        symbol.isHidden = state == .saving
        if state == .saving { spinner.startAnimating() } else { spinner.stopAnimating() }
        let key: String = switch state {
        case .available: isMedia ? "imessage.save.photos" : "imessage.save.files"
        case .saving: "imessage.save.saving"
        case .completed, .hidden: "imessage.save.completed"
        }
        accessibilityLabel = Localization.text(key)
    }
}
