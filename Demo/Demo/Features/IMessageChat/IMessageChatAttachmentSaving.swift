import Photos
import UIKit

/// 保存状态属于当前聊天页面；同一附件出现在不同消息中时分别记录。
nonisolated struct IMessageChatAttachmentSaveKey: Hashable, Sendable {
    let messageID: Int
    let attachmentID: UUID
}

nonisolated enum IMessageChatAttachmentSaveState: String, Sendable {
    case available, saving, completed, hidden
}

nonisolated enum IMessageChatAttachmentSaveOutcome: Sendable {
    case saved, cancelled
}

nonisolated enum IMessageChatAttachmentSaveError: Error, Equatable {
    case photoPermissionDenied, invalidAttachment, presentationUnavailable
}

/// 仅媒体组与文件卡片支持保存；语音气泡不属于文件导出入口。
nonisolated enum IMessageChatAttachmentSavePolicy {
    static func supports(_ attachment: IMessageChatAttachment) -> Bool {
        switch attachment {
        case .mediaGroup(let group): !group.items.isEmpty
        case .file: true
        case .audio, .link: false
        }
    }

    static func showsButton(for message: IMessageChatMessagePresentation) -> Bool {
        guard message.direction == .incoming,
              case .attachment(let attachment) = message.content else { return false }
        return supports(attachment)
    }
}

@MainActor
protocol IMessageChatAttachmentSaving {
    func save(_ attachment: IMessageChatAttachment, from presenter: UIViewController) async throws -> IMessageChatAttachmentSaveOutcome
}

/// 在进入任何异步系统操作前复制原件，独立于页面附件目录持有导出资源。
@MainActor
final class IMessageChatAttachmentSaveSnapshot {
    let directoryURL: URL
    let files: [URL]

    init(_ attachment: IMessageChatAttachment, parentDirectory: URL = FileManager.default.temporaryDirectory) throws {
        let sources: [(URL, String)]
        switch attachment {
        case .mediaGroup(let group) where !group.items.isEmpty:
            sources = group.items.map { ($0.originalFileURL, $0.originalFileURL.lastPathComponent) }
        case .file(let file):
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

    deinit { try? FileManager.default.removeItem(at: directoryURL) }
}

@MainActor
final class IMessageChatSystemAttachmentSaver: IMessageChatAttachmentSaving {
    typealias PhotoWriter = ([IMessageChatMediaItem], [URL]) async throws -> Void
    private let authorizePhotos: () async -> PHAuthorizationStatus
    private let writePhotos: PhotoWriter

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
    private let presentPicker: (UIDocumentPickerViewController, UIViewController) -> Void

    init(presentPicker: ((UIDocumentPickerViewController, UIViewController) -> Void)? = nil) {
        self.presentPicker = presentPicker ?? { picker, presenter in presenter.present(picker, animated: true) }
        super.init()
    }

    private var continuation: CheckedContinuation<IMessageChatAttachmentSaveOutcome, Never>?
    private var retainedSession: IMessageChatDocumentExportSession?

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

    static func makePicker(_ files: [URL]) throws -> UIDocumentPickerViewController {
        guard !files.isEmpty, files.allSatisfy({ FileManager.default.isReadableFile(atPath: $0.path) }) else {
            throw IMessageChatAttachmentSaveError.invalidAttachment
        }
        let picker = UIDocumentPickerViewController(forExporting: files, asCopy: true)
        return picker
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.isEmpty ? .cancelled : .saved)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(.cancelled) }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(.cancelled) }

    private func finish(_ outcome: IMessageChatAttachmentSaveOutcome) {
        let pending = continuation
        continuation = nil
        retainedSession = nil
        pending?.resume(returning: outcome)
    }
}

/// 管理防重入、完成截止时间和页面退出；系统已接收的保存操作不会被页面退出取消。
@MainActor
final class IMessageChatAttachmentSaveCoordinator {
    private let saver: any IMessageChatAttachmentSaving
    private let clock: () -> Date
    private let sleep: (Duration) async throws -> Void
    private var states: [IMessageChatAttachmentSaveKey: IMessageChatAttachmentSaveState] = [:]
    private var deadlines: [IMessageChatAttachmentSaveKey: Date] = [:]
    private var timers: [IMessageChatAttachmentSaveKey: Task<Void, Never>] = [:]
    private var active = true
    var stateDidChange: ((IMessageChatAttachmentSaveKey, IMessageChatAttachmentSaveState) -> Void)?
    var failed: ((Error) -> Void)?

    init(saver: (any IMessageChatAttachmentSaving)? = nil,
         clock: @escaping () -> Date = Date.init,
         sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.saver = saver ?? IMessageChatSystemAttachmentSaver()
        self.clock = clock
        self.sleep = sleep
    }

    func state(for key: IMessageChatAttachmentSaveKey) -> IMessageChatAttachmentSaveState {
        if let deadline = deadlines[key], clock() >= deadline { return .hidden }
        return states[key] ?? .available
    }

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

    func invalidate() {
        active = false
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        stateDidChange = nil
        failed = nil
    }

    private func update(_ key: IMessageChatAttachmentSaveKey, _ state: IMessageChatAttachmentSaveState) {
        states[key] = state
        stateDidChange?(key, state)
    }
}

/// 36 pt 圆形视觉置于 44 pt 点击区域；隐藏仅影响内容，不移除布局占位。
@available(iOS 26.0, *)
final class IMessageChatAttachmentSaveButton: UIButton {
    private let circle = UIView()
    private let symbol = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)

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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        circle.frame = CGRect(x: bounds.midX - 18, y: bounds.midY - 18, width: 36, height: 36)
        symbol.frame = circle.bounds.insetBy(dx: 8, dy: 8)
        spinner.center = CGPoint(x: 18, y: 18)
    }

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
        accessibilityLabel = DemoLocalization.text(key)
    }
}
