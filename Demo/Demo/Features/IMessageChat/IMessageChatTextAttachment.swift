import QuickLayout
import QuickLayoutKit
import UIKit
import UniformTypeIdentifiers

/// 文件与链接附件卡片共用的字体和布局规格。
@available(iOS 26.0, *)
private enum IMessageChatAttachmentCardStyle {
    /// 文件卡片缩略图的边长，单位为点。
    static let thumbnailSize: CGFloat = 60
    /// 文件缩略图的圆角半径，单位为点。
    static let thumbnailCornerRadius: CGFloat = 4
    /// 附件标题与详情文字之间的垂直间距，单位为点。
    static let textSpacing: CGFloat = 2
    /// 附件卡片内容的四周内边距，单位为点。
    static let contentInset: CGFloat = 12
    /// 缩略图与文字内容之间的间距，单位为点。
    static let iconTextSpacing: CGFloat = 12
    // 内容自身的右内边距也计入删除按钮的 44 pt 点击区域，避免重复留白。
    /// 扣除内容内边距后，删除按钮还需要额外保留的宽度。
    static let removeReservedWidth: CGFloat = 44 - contentInset

    /// 返回按指定特征集合缩放的附件标题字体。
    static func titleFont(for traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .semibold), compatibleWith: traits
        )
    }

    /// 返回按指定特征集合缩放的附件详情字体。
    static func detailFont(for traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13), compatibleWith: traits
        )
    }
}

/// 编辑器保存值模型和稳定身份；文件由文档控制器管理，与录音状态无关。
@available(iOS 26.0, *)
final class IMessageChatTextAttachment: NSTextAttachment {
    /// 标记编辑器自动生成附件分隔符的富文本属性键。
    static let separatorKey = NSAttributedString.Key("imessage.attachment.generatedSeparator")
    /// 当前附件卡片对应的文档草稿值；更新后调用 `refresh()` 刷新已注册视图。
    var draft: IMessageChatDocumentDraft
    /// 内联卡片采用的界面布局方向，默认从左向右。
    var direction: UIUserInterfaceLayoutDirection = .leftToRight
    /// 用户打开内联附件时调用的闭包；变化时同步到已注册卡片。
    var open: (() -> Void)? { didSet { cards.allObjects.forEach(configureActions) } }
    /// 用户删除内联附件时调用的闭包；为 `nil` 时移除卡片上的删除动作。
    var remove: (() -> Void)? { didSet { cards.allObjects.forEach(configureActions) } }
    /// 附件首选尺寸变化后通知编辑器重新测量的闭包。
    var sizeDidChange: (() -> Void)?
    /// 当前注册卡片的弱引用集合，供内容与动作更新使用。
    private let cards = NSHashTable<IMessageChatAttachmentCard>.weakObjects()
    /// TextKit 重排时会更换 provider；同一布局管理器继续使用已加载的卡片。
    /// 弱键避免延长编辑器生命周期，不同编辑器也不会争用同一个 UIView。
    private let editorCards = NSMapTable<NSTextLayoutManager, IMessageChatAttachmentCard>.weakToStrongObjects()

    /// 创建绑定指定文档草稿、使用 TextKit 视图提供者渲染的文本附件。
    init(draft: IMessageChatDocumentDraft) {
        self.draft = draft
        super.init(data: nil, ofType: "com.quicklayout.demo.file-draft")
        allowsTextAttachmentView = true
    }
    /// 不支持从归档创建 `IMessageChatTextAttachment`。
    ///
    /// 此初始化方法始终返回 `nil`。
    required init?(coder: NSCoder) { return nil }
    /// 指示此附件始终使用视图提供者进行呈现的布尔值。
    override var usesTextAttachmentView: Bool { true }

    /// 根据动态字体行高返回文件卡片所需高度，最小值为 84 点。
    static func height(for traits: UITraitCollection) -> CGFloat {
        let title = IMessageChatAttachmentCardStyle.titleFont(for: traits)
        let detail = IMessageChatAttachmentCardStyle.detailFont(for: traits)
        return max(84, ceil(title.lineHeight * 2 + detail.lineHeight
            + IMessageChatAttachmentCardStyle.textSpacing) + 24)
    }

    /// 为当前文本位置创建附件视图提供者，并启用边界跟踪。
    override func viewProvider(for parentView: UIView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = IMessageChatAttachmentProvider(
            textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }

    /// 以弱引用登记卡片，并立即应用草稿、布局方向和交互回调。
    func register(_ card: IMessageChatAttachmentCard) {
        cards.add(card)
        configure(card)
    }

    /// 返回指定文本布局管理器专用的卡片，首次访问时创建并缓存。
    ///
    /// 同一编辑器的 TextKit 重排复用原卡片；不同编辑器各自持有视图。
    fileprivate func card(for layoutManager: NSTextLayoutManager?) -> IMessageChatAttachmentCard {
        if let layoutManager, let card = editorCards.object(forKey: layoutManager) {
            return card
        }
        let card = IMessageChatAttachmentCard(frame: .zero)
        register(card)
        card.preferredSizeDidChange = { [weak self, weak layoutManager] in
            if let layoutManager, let content = layoutManager.textContentManager {
                layoutManager.invalidateLayout(for: content.documentRange)
            }
            self?.sizeDidChange?()
        }
        if let layoutManager { editorCards.setObject(card, forKey: layoutManager) }
        return card
    }
    /// 使用对应编辑器的实际卡片测量指定最大宽度下的附件尺寸。
    func preferredSize(maximumWidth: CGFloat, layoutManager: NSTextLayoutManager?) -> CGSize {
        card(for: layoutManager).preferredSize(maximumWidth: maximumWidth)
    }
    /// 刷新所有注册卡片，并使各文本布局管理器的文档布局失效。
    func refresh() {
        cards.allObjects.forEach(configure)
        for case let manager as NSTextLayoutManager in editorCards.keyEnumerator() {
            if let content = manager.textContentManager {
                manager.invalidateLayout(for: content.documentRange)
            }
        }
        sizeDidChange?()
    }
    /// 将附件的布局方向、草稿内容和动作同步到指定卡片。
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

/// 将编辑器专用卡片装入独立宿主视图的 TextKit 附件提供者。
@available(iOS 26.0, *)
private final class IMessageChatAttachmentProvider: NSTextAttachmentViewProvider {
    /// 获取当前编辑器的缓存卡片，并装入此提供者独占的宿主视图。
    ///
    /// 旧提供者释放宿主时不会移除已经转交给新宿主的卡片。
    override func loadView() {
        guard let attachment = textAttachment as? IMessageChatTextAttachment else { return }
        // 每个 provider 独占宿主，旧 provider 卸载时不会移除已交给新宿主的卡片。
        let card = attachment.card(for: textLayoutManager)
        let host = UIView(frame: card.bounds)
        card.frame = host.bounds
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(card)
        view = host
    }
    /// 按建议行宽测量实际卡片，并返回从零点开始的附件布局边界。
    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? IMessageChatTextAttachment else { return .zero }
        return CGRect(origin: .zero, size: attachment.preferredSize(
            maximumWidth: max(1, proposedLineFragment.width), layoutManager: textLayoutManager
        ))
    }
}

/// 使用已经缓存的元数据渲染链接，测量与绘制共用同一份内容和字体。
@available(iOS 26.0, *)
final class IMessageChatLinkPreviewView: UIView {
    /// 初始化时绑定的链接元数据；为 `nil` 时显示空预览。
    let link: IMessageChatLinkAttachment?
    /// 显示网页封面的图像视图。
    private let coverView = UIImageView()
    /// 显示网站图标的图像视图，与大尺寸封面分开布局。
    private let siteIconView = UIImageView()
    /// 显示网页标题的多行标签。
    private let titleLabel = UILabel()
    /// 显示网页主机名的标签。
    private let domainLabel = UILabel()
    /// 指示紧凑链接布局是否应为删除按钮保留文字空间的布尔值。
    var showsRemoveButton = false { didSet { setNeedsLayout() } }
    /// 指示当前预览是否具有可显示封面的布尔值。
    var hasCover: Bool { coverView.image != nil }
    /// 指示当前预览是否具有可显示站点图标的布尔值。
    var hasSiteIcon: Bool { siteIconView.image != nil }

    /// 创建使用指定缓存链接元数据的预览视图，不启动网络请求。
    init(link: IMessageChatLinkAttachment? = nil) {
        self.link = link
        super.init(frame: .zero)
        coverView.image = link?.imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
        siteIconView.image = link?.iconURL.flatMap { UIImage(contentsOfFile: $0.path) }
        coverView.contentMode = .scaleAspectFit
        coverView.backgroundColor = .systemGray6
        siteIconView.contentMode = .scaleAspectFit
        siteIconView.layer.cornerRadius = 4
        siteIconView.clipsToBounds = true
        titleLabel.text = link?.title ?? link?.url.host ?? link?.url.absoluteString
        domainLabel.text = link?.url.host ?? link?.url.absoluteString
        titleLabel.numberOfLines = hasCover ? 2 : 1
        titleLabel.lineBreakMode = .byTruncatingTail
        domainLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.textColor = .label
        domainLabel.textColor = .secondaryLabel
        backgroundColor = .systemGray5
        [coverView, siteIconView, titleLabel, domainLabel].forEach(addSubview)
        coverView.isHidden = !hasCover
        siteIconView.isHidden = hasCover || !hasSiteIcon
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }
    /// 不支持从归档创建 `IMessageChatLinkPreviewView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 根据当前内容大小类别更新动态字体。
    private func updateFonts() {
        titleLabel.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold), compatibleWith: traitCollection)
        domainLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14), compatibleWith: traitCollection)
    }
    /// 根据卡片宽度计算受限的封面高度，单位为点。
    private func coverHeight(width: CGFloat) -> CGFloat {
        guard let image = coverView.image, image.size.width > 0 else { return 0 }
        return ceil(width * min(0.75, max(0.45, image.size.height / image.size.width)))
    }
    /// 返回 `IMessageChatLinkPreviewView` 在指定建议尺寸下所需的大小。
    ///
    /// - Parameter size: 父视图提供的建议尺寸。
    /// - Returns: 当前内容对应的适配尺寸。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        updateFonts()
        let maximumWidth = max(1, size.width)
        let iconSpace: CGFloat = hasSiteIcon && !hasCover ? 44 : 0
        let removeSpace: CGFloat = showsRemoveButton && !hasCover ? 36 : 0
        let naturalWidth = max(titleLabel.intrinsicContentSize.width, domainLabel.intrinsicContentSize.width)
            + 24 + iconSpace + removeSpace
        let width = hasCover ? maximumWidth : min(maximumWidth, max(110, ceil(naturalWidth)))
        let textWidth = max(1, width - 24 - iconSpace - removeSpace)
        let titleHeight = ceil(titleLabel.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        let textHeight = titleHeight + 2 + ceil(domainLabel.font.lineHeight)
        return CGSize(width: width, height: hasCover
            ? coverHeight(width: width) + textHeight + 16
            : max(54, textHeight + 16))
    }
    /// 根据当前边界更新 `IMessageChatLinkPreviewView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        updateFonts()
        let headerHeight = hasCover ? coverHeight(width: bounds.width) : 0
        coverView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        var content = CGRect(x: 12, y: headerHeight + 8, width: max(1, bounds.width - 24),
                             height: max(1, bounds.height - headerHeight - 16))
        if showsRemoveButton && !hasCover { content.size.width = max(1, content.width - 36) }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        if hasSiteIcon && !hasCover {
            siteIconView.frame = CGRect(x: rtl ? content.minX : content.maxX - 34,
                y: content.midY - 17, width: 34, height: 34)
            if rtl { content.origin.x += 44 }
            content.size.width = max(1, content.width - 44)
        }
        let titleHeight = min(ceil(titleLabel.sizeThatFits(CGSize(width: content.width,
            height: CGFloat.greatestFiniteMagnitude)).height), content.height)
        titleLabel.textAlignment = rtl ? .right : .left
        domainLabel.textAlignment = titleLabel.textAlignment
        titleLabel.frame = CGRect(x: content.minX, y: content.minY, width: content.width, height: titleHeight)
        domainLabel.frame = CGRect(x: content.minX, y: titleLabel.frame.maxY + 2, width: content.width,
                                  height: ceil(domainLabel.font.lineHeight))
    }
}

/// 内层沿实际图片边缘裁剪并描边，外层绘制阴影，避免圆角裁掉阴影。
@available(iOS 26.0, *)
final class IMessageChatAttachmentThumbnailView: UIView {
    /// 显示当前媒体图像的图像视图。
    private let imageView = UIImageView()

    /// 缩略图视图显示的图像；设置后同步到内层图像视图。
    var image: UIImage? {
        didSet {
            imageView.image = image
            setNeedsLayout()
        }
    }

    /// 缩略图的内容缩放模式；变化时同步到内层图像视图。
    override var contentMode: UIView.ContentMode {
        didSet { setNeedsLayout() }
    }

    /// 使用指定初始边框创建 `IMessageChatAttachmentThumbnailView`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = IMessageChatAttachmentCardStyle.thumbnailCornerRadius
        imageView.layer.borderWidth = 0.5
        addSubview(imageView)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 2)
        updateBorderColor()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (view: IMessageChatAttachmentThumbnailView, _: UITraitCollection) in
            view.updateBorderColor()
        }
    }

    /// 不支持从归档创建 `IMessageChatAttachmentThumbnailView`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 根据当前外观解析动态描边颜色并更新缩略图边框。
    private func updateBorderColor() {
        imageView.layer.borderColor = UIColor.label.withAlphaComponent(0.24)
            .resolvedColor(with: traitCollection).cgColor
    }

    /// 根据当前边界更新 `IMessageChatAttachmentThumbnailView` 的子视图布局与图层几何。
    override func layoutSubviews() {
        super.layoutSubviews()
        var imageRect = bounds
        if contentMode == .scaleAspectFit, let image, !image.isSymbolImage,
           image.size.width > 0, image.size.height > 0 {
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageRect = CGRect(
                x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                width: size.width, height: size.height
            )
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.frame = imageRect
        imageView.contentMode = image?.isSymbolImage == true ? .center : contentMode
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        imageView.backgroundColor = image?.isSymbolImage == true ? .secondarySystemGroupedBackground : .clear
        imageView.isHidden = image == nil
        layer.shadowPath = image == nil ? nil
            : UIBezierPath(roundedRect: imageRect,
                           cornerRadius: IMessageChatAttachmentCardStyle.thumbnailCornerRadius).cgPath
        CATransaction.commit()
    }
}

/// 链接按封面和图标内容测量，文件与单项媒体共用带独立删除区的附件卡片。
@available(iOS 26.0, *)
final class IMessageChatAttachmentCard: QuickLayoutView, UIGestureRecognizerDelegate {
    /// 显示文件图标或媒体缩略图的带边框视图。
    private let icon = IMessageChatAttachmentThumbnailView()
    /// 叠加在视频缩略图上的播放标记。
    private let playBadge = UIImageView()
    /// 显示文件名称或链接标题的多行标签。
    private let titleLabel = UILabel()
    /// 显示文件大小、导入状态或链接地址的详情标签。
    private let detailLabel = UILabel()
    /// 编辑器模式下删除当前草稿的按钮。
    private let removeButton = IMessageChatDraftRemoveButton(frame: .zero)
    /// 触发附件打开操作的轻点手势。
    private let openGesture = UITapGestureRecognizer()
    /// 使用缓存网页元数据的链接预览视图。
    private var linkView = IMessageChatLinkPreviewView()
    /// 最近一次测量的宽度约束与结果，用于判断内容更新是否改变尺寸。
    private var lastMeasurement: (width: CGFloat, size: CGSize)?
    /// 卡片首选尺寸确实变化时调用的闭包。
    var preferredSizeDidChange: (() -> Void)?
    /// 指示当前草稿是否采用链接卡片布局的布尔值。
    private var isLink = false
    /// 指示当前媒体缩略图是否需要视频播放标记的布尔值。
    private var isVideo = false
    /// 最近一次应用的草稿值，用于避免相同内容重复配置。
    private var configuredDraft: IMessageChatDocumentDraft?
    /// 发送气泡和 TextKit 附件共用测量，保留大封面与紧凑卡的差异。
    func preferredSize(maximumWidth: CGFloat) -> CGSize {
        let width = max(1, maximumWidth)
        let size: CGSize
        if isLink && !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            let fitted = linkView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            size = CGSize(
                width: min(width, max(44, ceil(fitted.width.isFinite ? fitted.width : width))),
                height: max(44, ceil(fitted.height.isFinite ? fitted.height : 84))
            )
        } else {
            // 最大宽度只作为上限；短文件名不应把剩余空间留在文字右侧。
            let textWidth = max(0, titleLabel.intrinsicContentSize.width, detailLabel.intrinsicContentSize.width)
            let iconWidth = isLink ? 0 : IMessageChatAttachmentCardStyle.thumbnailSize
                + IMessageChatAttachmentCardStyle.iconTextSpacing
            let naturalWidth = ceil(textWidth + iconWidth
                + IMessageChatAttachmentCardStyle.contentInset * 2
                + (remove == nil ? 0 : IMessageChatAttachmentCardStyle.removeReservedWidth))
            size = CGSize(width: min(width, max(44, naturalWidth)),
                          height: IMessageChatTextAttachment.height(for: traitCollection))
        }
        lastMeasurement = (width, size)
        return size
    }

    /// 按上次宽度重新测量链接卡片，仅在结果变化时通知布局更新。
    private func linkPreferredSizeDidChange() {
        guard let previous = lastMeasurement else { return }
        let size = preferredSize(maximumWidth: previous.width)
        guard size != previous.size else { return }
        setNeedsQuickLayout()
        invalidateIntrinsicContentSize()
        preferredSizeDidChange?()
    }
    /// 打开当前附件的回调；变化时重新生成辅助功能动作。
    var open: (() -> Void)? { didSet { refreshAccessibilityActions() } }
    /// 删除当前附件的回调；为 `nil` 时隐藏删除按钮并收回预留空间。
    var remove: (() -> Void)? {
        didSet {
            linkView.showsRemoveButton = remove != nil
            removeButton.isHidden = remove == nil
            removeButton.isEnabled = remove != nil
            refreshAccessibilityActions()
            setNeedsQuickLayout()
        }
    }

    /// 定义 `IMessageChatAttachmentCard` 的布局层级、间距和对齐方式。
    @LayoutBuilder override var body: Layout {
        if isLink && !traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            // 封面和文字背景覆盖整张卡片；删除按钮叠放，不添加异色侧栏。
            ZStack(alignment: effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? .topLeading : .topTrailing) {
                linkView.resizable().frame(maxWidth: .infinity, maxHeight: .infinity)
                if remove != nil {
                    removeButton.resizable().frame(width: 44, height: 44)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // 点击区与内容右内边距共用空间，文字仍停在点击区之外。
            ZStack(alignment: effectiveUserInterfaceLayoutDirection == .rightToLeft
                ? .topLeading : .topTrailing) {
                cardContent.frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(effectiveUserInterfaceLayoutDirection == .rightToLeft ? .leading : .trailing,
                             remove == nil ? 0 : IMessageChatAttachmentCardStyle.removeReservedWidth)
                if remove != nil {
                    removeButton.resizable().frame(width: 44, height: 44)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 组织缩略图、标题和详情的标准文件卡片布局。
    @LayoutBuilder private var cardContent: Layout {
        HStack(alignment: .center, spacing: IMessageChatAttachmentCardStyle.iconTextSpacing) {
            if !isLink {
                ZStack {
                    icon.resizable().frame(
                        width: IMessageChatAttachmentCardStyle.thumbnailSize,
                        height: IMessageChatAttachmentCardStyle.thumbnailSize
                    )
                    if isVideo { playBadge.resizable().frame(width: 28, height: 28) }
                }
            }
            VStack(alignment: .leading, spacing: IMessageChatAttachmentCardStyle.textSpacing) {
                titleLabel.resizable(axis: .horizontal).fixedSize(axis: .vertical)
                detailLabel.resizable(axis: .horizontal).fixedSize(axis: .vertical)
            }
        }.padding(IMessageChatAttachmentCardStyle.contentInset)
    }

    /// 使用指定初始边框创建 `IMessageChatAttachmentCard`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemFill
        layer.cornerRadius = 20
        clipsToBounds = true
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .secondaryLabel
        playBadge.image = UIImage(systemName: "play.circle.fill")?.applyingSymbolConfiguration(
            UIImage.SymbolConfiguration(paletteColors: [.white, .black.withAlphaComponent(0.7)])
        )
        playBadge.contentMode = .scaleAspectFit
        titleLabel.numberOfLines = 2
        detailLabel.numberOfLines = 1
        detailLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.adjustsFontForContentSizeCategory = true
        // 20 点卡片圆角需要比照片缩略图更多留白，避免圆形按钮贴住弧线。
        removeButton.visualInset = 8
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
            DispatchQueue.main.async { [weak card] in card?.linkPreferredSizeDidChange() }
        }
    }
    /// 不支持从归档创建 `IMessageChatAttachmentCard`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 按附件类型和导入状态配置卡片内容，保留相同草稿对应的已有视图。
    func configure(_ draft: IMessageChatDocumentDraft) {
        titleLabel.font = IMessageChatAttachmentCardStyle.titleFont(for: traitCollection)
        detailLabel.font = IMessageChatAttachmentCardStyle.detailFont(for: traitCollection)
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
                ? Localization.text("imessage.audio.attachment.recording")
                : file.fileURL.pathExtension.uppercased()
            detailLabel.text = "\(typeName) · \(ByteCountFormatter.string(fromByteCount: file.byteCount, countStyle: .file))"
            let symbol = type?.conforms(to: .audio) == true ? "music.note"
                : type?.conforms(to: .pdf) == true ? "doc.richtext" : "doc.text"
            icon.image = file.thumbnailURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(systemName: symbol)
            accessibilityIdentifier = "imessage.attachment.file.card"
        case .link(let link):
            isLink = true
            if configuredDraft != draft {
                linkView = IMessageChatLinkPreviewView(link: link)
                linkView.showsRemoveButton = remove != nil
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
                titleLabel.text = Localization.text(isVideo ? "imessage.media.video"
                    : media.isAnimatedImage ? "imessage.media.animatedImage" : "imessage.media.image")
                if let duration = media.kind.duration {
                    detailLabel.text = IMessageAudioBubbleView.durationText(duration)
                } else {
                    detailLabel.text = "\(Int(media.pixelSize.width)) × \(Int(media.pixelSize.height))"
                }
            } else {
                titleLabel.text = Localization.text("imessage.media.image")
                icon.image = UIImage(systemName: "photo")
            }
        case .audio(let audio):
            titleLabel.text = Localization.text("imessage.audio.attachment.recording")
            detailLabel.text = IMessageAudioBubbleView.durationText(audio.duration)
            icon.image = UIImage(systemName: "waveform")
            accessibilityIdentifier = "imessage.attachment.audio.card"
        }
        configuredDraft = draft
        if draft.status != .ready {
            detailLabel.text = Localization.text(draft.status == .importing
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

    /// 根据当前打开与删除回调重建可用的辅助功能动作。
    private func refreshAccessibilityActions() {
        let canOpen = configuredDraft?.status == .ready && open != nil
        openGesture.isEnabled = canOpen
        accessibilityTraits = canOpen ? .button : .staticText
        var actions: [UIAccessibilityCustomAction] = []
        if canOpen {
            actions.append(UIAccessibilityCustomAction(
                name: Localization.text("imessage.media.openPreview"), target: self, selector: #selector(accessibleOpen)
            ))
        }
        removeButton.accessibilityLabel = Localization.text("imessage.media.remove")
        if remove != nil {
            actions.append(UIAccessibilityCustomAction(
                name: Localization.text("imessage.media.remove"), target: self, selector: #selector(accessibleRemove)
            ))
        }
        accessibilityCustomActions = actions.isEmpty ? nil : actions
    }

    /// 按钮及其内部视图的整个 44pt 区域都不参与打开手势。
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return false }
        return touchedView !== removeButton && !touchedView.isDescendant(of: removeButton)
    }

    /// 将轻点手势转交到统一附件打开动作。
    @objc private func openAttachment() { _ = accessibleOpen() }
    /// 将删除按钮事件转交到统一附件删除动作。
    @objc private func removeAttachment() { _ = accessibleRemove() }
    /// 通过辅助功能激活当前附件的打开操作。
    override func accessibilityActivate() -> Bool { accessibleOpen() }
    /// 执行附件打开回调；没有可用回调时返回 `false`。
    @objc private func accessibleOpen() -> Bool {
        guard configuredDraft?.status == .ready, let open else { return false }
        open()
        return true
    }
    /// 执行附件删除回调；没有可用回调时返回 `false`。
    @objc private func accessibleRemove() -> Bool {
        guard let remove else { return false }
        remove()
        return true
    }
}

/// 在时间线中呈现文件或链接卡片、发送状态和保存入口的单元格。
@available(iOS 26.0, *)
final class IMessageChatDocumentBubbleCell: QuickLayoutCollectionViewCell {
    /// 与编辑器共用内容配置和测量规则的附件卡片。
    let card = IMessageChatAttachmentCard(frame: .zero)
    /// 显示发送进度、失败入口及送达文本的状态视图。
    let deliveryStatusView = IMessageChatDeliveryStatusView()
    /// 状态视图中用于显示本地化送达文本的标签。
    var deliveryLabel: UILabel { deliveryStatusView.label }
    /// 用于将收到的附件保存到系统位置的按钮。
    let saveButton = IMessageChatAttachmentSaveButton()
    /// 用户请求保存当前附件时调用的闭包。
    var saveRequested: (() -> Void)?
    /// 指示当前布局是否为附件保存入口保留空间的布尔值。
    private var showsSaveButton = false
    /// 当前绑定的消息展示模型；未配置或复用清理后为 `nil`。
    private var message: IMessageChatMessagePresentation?
    /// 当前布局允许的消息气泡最大宽度，单位为点。
    private var maximumBubbleWidth: CGFloat = 300
    /// 用户打开当前消息附件时调用的闭包。
    var open: ((IMessageChatAttachment) -> Void)?
    /// 需要随单元格同步更新布局方向的内容视图。
    override var quickLayoutDirectionViews: [UIView] { super.quickLayoutDirectionViews + [card] }
    /// 定义 `IMessageChatDocumentBubbleCell` 的布局层级、间距和对齐方式。
    @LayoutBuilder override var body: Layout {
        let cardSize = card.preferredSize(maximumWidth: maximumBubbleWidth)
        HStack(spacing: 0) {
            if message?.direction == .outgoing { Spacer() }
            VStack(alignment: message?.direction == .outgoing ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 8) {
                    card.frame(width: cardSize.width, height: cardSize.height)
                    if showsSaveButton { saveButton.frame(width: 44, height: 44) }
                }
                if message?.deliveryText != nil { deliveryStatusView }
            }
            if message?.direction != .outgoing { Spacer() }
        }.frame(maxWidth: .infinity).padding(.horizontal, 12).padding(.vertical, 2)
    }
    /// 使用指定初始边框创建 `IMessageChatDocumentBubbleCell`，并配置其子视图和默认外观。
    ///
    /// - Parameter frame: 在父视图坐标系中指定的初始边框。
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fullyFlexible
        saveButton.addAction(UIAction { [weak self] _ in self?.saveRequested?() }, for: .touchUpInside)
        deliveryLabel.font = .preferredFont(forTextStyle: .caption2)
        deliveryLabel.adjustsFontForContentSizeCategory = true
        deliveryLabel.textColor = .secondaryLabel
        card.preferredSizeDidChange = { [weak self] in
            guard let self else { return }
            setNeedsQuickLayout()
            var ancestor = superview
            while let view = ancestor {
                if let collection = view as? UICollectionView {
                    collection.collectionViewLayout.invalidateLayout()
                    break
                }
                ancestor = view.superview
            }
        }
    }
    /// 不支持从归档创建 `IMessageChatDocumentBubbleCell`。
    ///
    /// 请使用代码初始化方法创建此对象。
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// 根据列表提供的宽度更新内容宽度限制，并返回自适应高度的布局属性。
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        maximumBubbleWidth = max(1, min(attributes.size.width - 24 - (showsSaveButton ? 52 : 0), attributes.size.width * 0.70))
        setNeedsQuickLayout()
        return super.preferredLayoutAttributesFitting(attributes)
    }
    /// 绑定文档消息，配置卡片打开动作、发送状态与附件保存入口。
    func configure(_ message: IMessageChatMessagePresentation, saveState: IMessageChatAttachmentSaveState = .available) {
        guard case .attachment(let attachment) = message.content else { return }
        self.message = message
        showsSaveButton = IMessageChatAttachmentSavePolicy.showsButton(for: message)
        saveButton.configure(saveState, isMedia: false)
        card.remove = nil
        card.configure(.init(attachment: attachment))
        card.open = { [weak self] in self?.open?(attachment) }
        deliveryStatusView.configure(message)
        deliveryLabel.text = message.deliveryText
        setNeedsQuickLayout()
    }
    /// 为复用清理 `IMessageChatDocumentBubbleCell` 的内容与临时状态。
    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        showsSaveButton = false
        saveRequested = nil
        open = nil
        card.open = nil
        deliveryStatusView.configure(nil)
        deliveryStatusView.retryRequested = nil
        deliveryLabel.text = nil
        saveButton.configure(.hidden, isMedia: false)
        setNeedsQuickLayout()
    }
}

#if DEBUG
import QuickLayout
import QuickLayoutKit
import UIKit

/// 创建文档输入栏预览，支持布局方向、大字体、媒体粘贴及文字附件交错场景。
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
