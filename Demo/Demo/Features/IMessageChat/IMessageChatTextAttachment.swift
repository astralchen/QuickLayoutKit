import LinkPresentation
import QuickLayout
import QuickLayoutKit
import UIKit
import UniformTypeIdentifiers

/// 编辑器保存值模型和稳定身份；文件由文档控制器管理，与录音状态无关。
@available(iOS 26.0, *)
final class IMessageChatTextAttachment: NSTextAttachment {
    static let separatorKey = NSAttributedString.Key("imessage.attachment.generatedSeparator")
    var draft: IMessageChatDocumentDraft
    var direction: UIUserInterfaceLayoutDirection = .leftToRight
    var open: (() -> Void)? { didSet { cards.allObjects.forEach(configureActions) } }
    var remove: (() -> Void)? { didSet { cards.allObjects.forEach(configureActions) } }
    private let cards = NSHashTable<IMessageChatAttachmentCard>.weakObjects()

    init(draft: IMessageChatDocumentDraft) {
        self.draft = draft
        super.init(data: nil, ofType: "com.quicklayout.demo.file-draft")
        allowsTextAttachmentView = true
    }
    required init?(coder: NSCoder) { return nil }
    override var usesTextAttachmentView: Bool { true }

    static func height(for traits: UITraitCollection) -> CGFloat {
        let title = UIFont.preferredFont(forTextStyle: .headline, compatibleWith: traits)
        let detail = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        return max(96, ceil(title.lineHeight * 2 + detail.lineHeight) + 28)
    }

    override func viewProvider(for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = IMessageChatAttachmentProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    func register(_ card: IMessageChatAttachmentCard) {
        cards.add(card)
        configure(card)
    }
    func refresh() { cards.allObjects.forEach(configure) }
    private func configure(_ card: IMessageChatAttachmentCard) {
        card.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        card.configure(draft)
        configureActions(card)
    }

    /// nil 必须传递到已注册视图；编辑器移除附件后不能留下空闭包和可用动作。
    private func configureActions(_ card: IMessageChatAttachmentCard) {
        if open != nil {
            card.open = { [weak self] in self?.open?() }
        } else {
            card.open = nil
        }
        if remove != nil {
            card.remove = { [weak self] in self?.remove?() }
        } else {
            card.remove = nil
        }
    }
}

@available(iOS 26.0, *)
private final class IMessageChatAttachmentProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? IMessageChatTextAttachment else { return }
        let card = IMessageChatAttachmentCard(frame: .zero)
        attachment.register(card)
        view = card
    }
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        CGRect(x: 0, y: 0, width: max(1, proposedLineFragment.width),
               height: IMessageChatTextAttachment.height(for: view?.traitCollection ?? UITraitCollection()))
    }
}

/// 网页使用系统富链接视图，文件与单项媒体共用带独立删除区的附件卡片。
@available(iOS 26.0, *)
final class IMessageChatAttachmentCard: QuickLayoutView, UIGestureRecognizerDelegate {
    private let icon = UIImageView()
    private let playBadge = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    private let openGesture = UITapGestureRecognizer()
    private var linkView = LPLinkView(metadata: LPLinkMetadata())
    private var isLink = false
    private var isVideo = false
    private var configuredDraft: IMessageChatDocumentDraft?
    var open: (() -> Void)? { didSet { refreshAccessibilityActions() } }
    var remove: (() -> Void)? {
        didSet {
            removeButton.isHidden = remove == nil
            removeButton.isEnabled = remove != nil
            refreshAccessibilityActions()
            setNeedsQuickLayout()
        }
    }

    @LayoutBuilder override var body: Layout {
        // 删除区独占宽度，不覆盖富链接、文件名或视频时长；RTL 下仍固定在物理右上角。
        HStack(alignment: .top, spacing: 0) {
            if effectiveUserInterfaceLayoutDirection == .rightToLeft, remove != nil {
                removeButton.resizable().frame(width: 44, height: 44).padding(4)
            }
            cardContent.frame(maxWidth: .infinity, maxHeight: .infinity)
            if effectiveUserInterfaceLayoutDirection != .rightToLeft, remove != nil {
                removeButton.resizable().frame(width: 44, height: 44).padding(4)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @LayoutBuilder private var cardContent: Layout {
        if isLink && !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            linkView.resizable().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .center, spacing: 12) {
                if !isLink || !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
                    ZStack {
                        icon.resizable().frame(width: 48, height: 56)
                        if isVideo { playBadge.resizable().frame(width: 28, height: 28) }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleLabel.resizable(axis: .horizontal).fixedSize(axis: .vertical)
                    detailLabel.resizable(axis: .horizontal).fixedSize(axis: .vertical)
                }
            }.padding(12)
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 20
        clipsToBounds = true
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 8
        playBadge.image = UIImage(systemName: "play.circle.fill")?.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.7)])
        )
        playBadge.contentMode = .scaleAspectFit
        titleLabel.numberOfLines = 2
        detailLabel.numberOfLines = 1
        detailLabel.textColor = .secondaryLabel
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.adjustsFontForContentSizeCategory = true
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark.circle.fill")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 28)
        configuration.baseForegroundColor = .secondaryLabel
        configuration.contentInsets = .zero
        removeButton.configuration = configuration
        removeButton.isHidden = true
        removeButton.isEnabled = false
        removeButton.accessibilityIdentifier = "imessage.attachment.remove"
        removeButton.addTarget(self, action: #selector(removeAttachment), for: .touchUpInside)
        // 卡片作为一个 VO 元素，移除通过自定义动作提供，避免重复朗读内部装饰。
        removeButton.isAccessibilityElement = false
        isAccessibilityElement = true
        openGesture.addTarget(self, action: #selector(openAttachment))
        openGesture.delegate = self
        addGestureRecognizer(openGesture)
        refreshAccessibilityActions()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) {
            (card: IMessageChatAttachmentCard, _: UITraitCollection) in
            if let draft = card.configuredDraft { card.configure(draft) }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ draft: IMessageChatDocumentDraft) {
        titleLabel.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        isLink = false
        isVideo = false
        icon.contentMode = .scaleAspectFit
        titleLabel.text = nil
        detailLabel.text = nil
        icon.image = nil
        switch draft.attachment {
        case .file(let file):
            titleLabel.text = file.displayName
            let type = UTType(file.typeIdentifier)
            let typeName = type?.conforms(to: .audio) == true
                ? DemoLocalization.text("imessage.audio.attachment.recording")
                : file.fileURL.pathExtension.uppercased()
            detailLabel.text = "\(typeName) · \(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))"
            let symbol = type?.conforms(to: .audio) == true ? "music.note"
                : type?.conforms(to: .pdf) == true ? "doc.richtext" : "doc.text"
            icon.image = file.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(systemName: symbol)
            accessibilityIdentifier = "imessage.attachment.file.card"
        case .link(let link):
            isLink = true
            if configuredDraft != draft {
                let metadata = LPLinkMetadata()
                metadata.originalURL = link.url
                metadata.url = link.url
                metadata.title = link.title ?? link.url.host
                if let url = link.imageURL, let image = UIImage(contentsOfFile: url.path) {
                    metadata.imageProvider = NSItemProvider(object: image)
                }
                linkView = LPLinkView(metadata: metadata)
                linkView.isUserInteractionEnabled = false
                linkView.accessibilityElementsHidden = true
            }
            titleLabel.text = link.title ?? link.url.host ?? link.url.absoluteString
            detailLabel.text = link.url.path.isEmpty || link.url.path == "/" ? link.url.scheme?.uppercased() : link.url.path
            icon.image = UIImage(systemName: "link")
            accessibilityIdentifier = "imessage.attachment.link.card"
        case .mediaGroup(let group):
            accessibilityIdentifier = "imessage.attachment.media.card"
            if let media = group.items.first {
                isVideo = media.kind.isVideo
                let thumbnail = UIImage(contentsOfFile: media.thumbnailFileURL.path)
                icon.image = thumbnail ?? UIImage(systemName: isVideo ? "video.fill" : "photo")
                icon.contentMode = thumbnail == nil ? .scaleAspectFit : .scaleAspectFill
                titleLabel.text = DemoLocalization.text(isVideo ? "imessage.media.video"
                    : media.isAnimatedImage ? "imessage.media.animatedImage" : "imessage.media.image")
                if let duration = media.kind.duration {
                    detailLabel.text = IMessageAudioBubbleView.durationText(duration)
                } else {
                    detailLabel.text = "\(Int(media.pixelSize.width)) × \(Int(media.pixelSize.height))"
                }
            } else {
                titleLabel.text = DemoLocalization.text("imessage.media.image")
                icon.image = UIImage(systemName: "photo")
            }
        case .audio(let audio):
            titleLabel.text = DemoLocalization.text("imessage.audio.attachment.recording")
            detailLabel.text = IMessageAudioBubbleView.durationText(audio.duration)
            icon.image = UIImage(systemName: "waveform")
            accessibilityIdentifier = "imessage.attachment.audio.card"
        }
        configuredDraft = draft
        if draft.status != .ready {
            detailLabel.text = DemoLocalization.text(draft.status == .importing
                ? "imessage.media.importing" : "imessage.attachment.importFailed")
        }
        titleLabel.textAlignment = .natural
        detailLabel.textAlignment = .natural
        accessibilityLabel = "\(titleLabel.text ?? ""), \(detailLabel.text ?? "")"
        if case .link(let link) = draft.attachment {
            accessibilityLabel = "\(link.title ?? ""), \(link.url.absoluteString)"
        }
        refreshAccessibilityActions()
        setNeedsQuickLayout()
    }

    private func refreshAccessibilityActions() {
        let canOpen = configuredDraft?.status == .ready && open != nil
        openGesture.isEnabled = canOpen
        accessibilityTraits = canOpen ? .button : .staticText
        var actions: [UIAccessibilityCustomAction] = []
        if canOpen {
            actions.append(UIAccessibilityCustomAction(
                name: DemoLocalization.text("imessage.media.openPreview"), target: self, selector: #selector(accessibleOpen)
            ))
        }
        removeButton.accessibilityLabel = DemoLocalization.text("imessage.media.remove")
        if remove != nil {
            actions.append(UIAccessibilityCustomAction(
                name: DemoLocalization.text("imessage.media.remove"), target: self, selector: #selector(accessibleRemove)
            ))
        }
        accessibilityCustomActions = actions.isEmpty ? nil : actions
    }

    /// 按钮及其内部视图的整个 44pt 区域都不参与打开手势。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return false }
        return touchedView !== removeButton && !touchedView.isDescendant(of: removeButton)
    }

    @objc private func openAttachment() { _ = accessibleOpen() }
    @objc private func removeAttachment() { _ = accessibleRemove() }
    override func accessibilityActivate() -> Bool { accessibleOpen() }
    @objc private func accessibleOpen() -> Bool {
        guard configuredDraft?.status == .ready, let open else { return false }
        open()
        return true
    }
    @objc private func accessibleRemove() -> Bool {
        guard let remove else { return false }
        remove()
        return true
    }
}

@available(iOS 26.0, *)
final class IMessageChatDocumentBubbleCell: QuickLayoutCollectionViewCell {
    let card = IMessageChatAttachmentCard(frame: .zero)
    let deliveryLabel = UILabel()
    private var message: IMessageChatMessagePresentation?
    private var maximumBubbleWidth: CGFloat = 300
    var open: ((IMessageChatAttachment) -> Void)?
    override var quickLayoutDirectionViews: [UIView] { super.quickLayoutDirectionViews + [card] }
    @LayoutBuilder override var body: Layout {
        HStack(spacing: 0) {
            if message?.direction == .outgoing { Spacer() }
            VStack(alignment: message?.direction == .outgoing ? .trailing : .leading, spacing: 3) {
                card.frame(width: maximumBubbleWidth, height: IMessageChatTextAttachment.height(for: traitCollection))
                if message?.deliveryText != nil { deliveryLabel }
            }
            if message?.direction != .outgoing { Spacer() }
        }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 2)
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        deliveryLabel.font = .preferredFont(forTextStyle: .caption2)
        deliveryLabel.adjustsFontForContentSizeCategory = true
        deliveryLabel.textColor = .secondaryLabel
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        maximumBubbleWidth = max(230, attributes.size.width * 0.78)
        setNeedsQuickLayout()
        return super.preferredLayoutAttributesFitting(attributes)
    }
    func configure(_ message: IMessageChatMessagePresentation) {
        guard case .attachment(let attachment) = message.content else { return }
        self.message = message
        card.remove = nil
        card.configure(.init(attachment: attachment))
        card.open = { [weak self] in self?.open?(attachment) }
        deliveryLabel.text = message.deliveryText
        setNeedsQuickLayout()
    }
}

#if DEBUG
import QuickLayout
import QuickLayoutKit
import UIKit

@MainActor
private func documentCardPreview(
    text: String, direction: UIUserInterfaceLayoutDirection, photos: Bool, largeText: Bool = false,
    pastedMedia: Bool = false, interleaved: Bool = false
) -> UIViewController {
    let composer = IMessageChatComposerView(frame: .zero)
    composer.configure(strings: IMessageChatPreviewData.composerStrings)
    composer.applyLayoutDirection(direction)
    if largeText { composer.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge }
    composer.textView.text = text
    composer.textViewDidChange(composer.textView)
    composer.textView.selectedRange = NSRange(location: interleaved ? (text as NSString).length : 0, length: 0)
    for draft in IMessageChatPreviewData.documentDrafts {
        composer.insertDocument(draft)
        if interleaved { composer.insertContents([.text(text)]) }
    }
    if pastedMedia { composer.insertContents(IMessageChatPreviewData.pastedMediaDrafts.map { .attachment($0) }) }
    if photos {
        composer.applyMediaDraft(.init(groupID: UUID(), items: [
            .init(id: UUID(), assetIdentifier: nil, content: .importing),
        ]))
    }
    let background = UIView()
    background.backgroundColor = .systemBackground
    return QuickLayoutHostingController {
        ZStack(alignment: .bottom) {
            background.resizable()
            composer.resizable(axis: .horizontal).fixedSize(axis: .vertical)
        }.frame(width: 390, height: largeText ? 1000 : 680)
    }
}

#Preview("多类型附件 · 光标处插入") {
    documentCardPreview(text: "在", direction: .leftToRight, photos: true)
}

#Preview("多类型附件 · 删除全部照片后") {
    documentCardPreview(text: "", direction: .leftToRight, photos: false)
}

#Preview("多类型附件 · RTL 大字体") {
    documentCardPreview(text: "مرحبا", direction: .rightToLeft, photos: true, largeText: true)
}

#Preview("粘贴图片视频 · 右上角删除") {
    documentCardPreview(text: "图片和视频分别发送", direction: .leftToRight, photos: false, pastedMedia: true)
}

#Preview("粘贴图片视频 · RTL 大字体") {
    documentCardPreview(text: "صور وفيديو", direction: .rightToLeft, photos: false, largeText: true, pastedMedia: true)
}
#endif

#Preview("按位置分段 · 文字与多个附件") {
    documentCardPreview(text: " 一段正文\n", direction: .leftToRight, photos: false, interleaved: true)
}

#Preview("按位置分段 · RTL 大字体") {
    documentCardPreview(text: " نص الرسالة\n", direction: .rightToLeft, photos: false, largeText: true, interleaved: true)
}
