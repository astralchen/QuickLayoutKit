import UIKit

@MainActor
open class AlertAction: NSObject, UIAccessibilityIdentification {
    /// 创建操作时使用的按钮外观。
    public struct Appearance {
        public var image: UIImage?
        public var titleColor: UIColor?
        public var cornerStyle: UIButton.Configuration.CornerStyle?

        public init(
            image: UIImage? = nil,
            titleColor: UIColor? = nil,
            cornerStyle: UIButton.Configuration.CornerStyle? = nil
        ) {
            self.image = image
            self.titleColor = titleColor
            self.cornerStyle = cornerStyle
        }
    }

    open private(set) var title: String?
    /// 通过 attributedTitle 初始化时使用的按钮标题。
    open private(set) var attributedTitle: AttributedString?
    open private(set) var style: UIAlertAction.Style
    open private(set) var image: UIImage?
    open private(set) var titleColor: UIColor?
    /// 覆盖当前系统版本对应的默认按钮圆角。
    open private(set) var cornerStyle: UIButton.Configuration.CornerStyle?
    /// 设置按钮标题的对齐方式。nil 时沿用按钮的默认对齐。
    public var titleTextAlignment: NSTextAlignment? {
        didSet { button?.setTitleAlignment(titleTextAlignment) }
    }
    open var isEnabled = true {
        didSet { button?.isEnabled = isEnabled }
    }
    open var accessibilityIdentifier: String? {
        didSet { button?.accessibilityIdentifier = accessibilityIdentifier }
    }

    private weak var button: AlertActionButton?
    fileprivate let handler: ((AlertAction) -> Void)?

    public init(
        title: String?,
        style: UIAlertAction.Style = .default,
        handler: ((AlertAction) -> Void)? = nil
    ) {
        self.title = title
        self.style = style
        self.handler = handler
    }

    public convenience init(
        title: String?,
        style: UIAlertAction.Style = .default,
        appearance: Appearance,
        handler: ((AlertAction) -> Void)? = nil
    ) {
        self.init(title: title, style: style, handler: handler)
        self.image = appearance.image
        self.titleColor = appearance.titleColor
        self.cornerStyle = appearance.cornerStyle
    }

    public convenience init(
        attributedTitle: AttributedString,
        style: UIAlertAction.Style = .default,
        appearance: Appearance = .init(),
        handler: ((AlertAction) -> Void)? = nil
    ) {
        self.init(title: nil, style: style, appearance: appearance, handler: handler)
        self.attributedTitle = attributedTitle
    }

    fileprivate func bind(to button: AlertActionButton) {
        self.button = button
        button.isEnabled = isEnabled
        button.accessibilityIdentifier = accessibilityIdentifier
        button.setTitleAlignment(titleTextAlignment)
    }

    /// 执行已启用操作的回调，可用于把同一个操作绑定到其他 UIKit 控件。
    public func perform() {
        guard isEnabled else { return }
        handler?(self)
    }
}

@MainActor
private final class AlertActionButton: UIButton {
    enum Appearance {
        case standard
        case grouped
        case modernStacked
    }

    private let appearance: Appearance
    private let usesPreferredFill: Bool
    private let usesPopoverMaterial: Bool
    private let actionIconView: UIImageView?
    private let titleLeadingInset: CGFloat
    static let edgeInset: CGFloat = 12

    init(configuration: UIButton.Configuration, appearance: Appearance, usesPreferredFill: Bool, usesPopoverMaterial: Bool) {
        self.usesPopoverMaterial = usesPopoverMaterial
        self.appearance = appearance
        self.usesPreferredFill = usesPreferredFill
        var configuration = configuration
        if appearance != .standard, let image = configuration.image {
            actionIconView = UIImageView(image: image)
            configuration.image = nil
        } else {
            actionIconView = nil
        }
        let size = actionIconView?.image?.size ?? .zero
        let scale = min(1, 24 / max(1, size.width, size.height))
        let imageSize = CGSize(width: size.width * scale, height: size.height * scale)
        let iconWidth = appearance == .grouped ? max(20, imageSize.width) : imageSize.width
        if appearance == .standard {
            titleLeadingInset = configuration.contentInsets.leading
        } else {
            titleLeadingInset = actionIconView == nil ? Self.edgeInset : Self.edgeInset * 2 + iconWidth
        }
        super.init(frame: .zero)
        if #available(iOS 26, *) {
            let transform = configuration.background.backgroundColorTransformer
            configuration.background.backgroundColorTransformer = UIConfigurationColorTransformer { [weak self] color in
                guard let self, !isEnabled, self.configuration?.baseBackgroundColor != .clear else {
                    return transform?(color) ?? color
                }
                return UIColor { traits in
                    if #available(iOS 27, *) {
                        if traits.userInterfaceStyle == .dark { return .white.withAlphaComponent(0.125) }
                        return .black.withAlphaComponent(usesPopoverMaterial ? 0.125 : 0.132)
                    }
                    return traits.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.11) : .black.withAlphaComponent(0.12)
                }
            }
        }
        let transform = configuration.titleTextAttributesTransformer
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { [weak self] input in
            var attributes = transform?(input) ?? input
            if let self, !isEnabled {
                attributes.foregroundColor = disabledTitleColor
            }
            return attributes
        }
        self.configuration = configuration
        if let actionIconView {
            // 图标固定在起始侧，标题按自己的对齐方式布局。
            actionIconView.translatesAutoresizingMaskIntoConstraints = false
            actionIconView.contentMode = .scaleAspectFit
            actionIconView.isAccessibilityElement = false
            addSubview(actionIconView)
            NSLayoutConstraint.activate([
                actionIconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.edgeInset),
                actionIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                actionIconView.widthAnchor.constraint(equalToConstant: imageSize.width),
                actionIconView.heightAnchor.constraint(equalToConstant: imageSize.height),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setTitleAlignment(_ alignment: NSTextAlignment?) {
        guard var configuration else { return }
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        switch alignment {
        case .left:
            contentHorizontalAlignment = .left
            configuration.titleAlignment = rtl ? .trailing : .leading
        case .right:
            contentHorizontalAlignment = .right
            configuration.titleAlignment = rtl ? .leading : .trailing
        case .natural:
            contentHorizontalAlignment = .leading
            configuration.titleAlignment = .leading
        case .justified:
            contentHorizontalAlignment = .fill
            configuration.titleAlignment = .leading
        case .center:
            contentHorizontalAlignment = .center
            configuration.titleAlignment = .center
        default:
            contentHorizontalAlignment = .center
            configuration.titleAlignment = appearance == .standard ? .automatic : .center
        }
        let centered = contentHorizontalAlignment == .center
        if appearance == .modernStacked && !usesPreferredFill {
            configuration.baseBackgroundColor = centered ? .secondarySystemFill : .clear
        }
        configuration.contentInsets.leading = titleLeadingInset
        configuration.contentInsets.trailing = centered || appearance == .standard ? titleLeadingInset : Self.edgeInset
        self.configuration = configuration
        if let alignment = alignment ?? (appearance == .standard ? nil : .center) {
            titleLabel?.textAlignment = alignment
        }
        setNeedsLayout()
        setNeedsUpdateConfiguration()
    }

    private var disabledTitleColor: UIColor {
        if #available(iOS 27, *) {
            let lightOpacity: CGFloat = usesPopoverMaterial ? 0.345 : 0.378
            return UIColor { traits in
                traits.userInterfaceStyle == .dark ? .white.withAlphaComponent(0.262) : .black.withAlphaComponent(lightOpacity)
            }
        }
        if #available(iOS 26, *) {
            return UIColor { traits in
                let label = UIColor.tertiaryLabel.resolvedColor(with: traits)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                guard label.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return label }
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                return UIColor(white: luminance, alpha: alpha * 0.8)
            }
        }
        // 旧版 UIKit 将中性灰以同一透明度叠在浅色或深色面板上。
        return UIColor(white: 0.485, alpha: 0.64)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        guard scale > 0, let label = titleLabel, configuration?.image == nil, let host = label.superview else { return }
        if host !== self {
            // 新版 UIButton 将标题放入内容视图，先完成该子树的布局再按按钮中心对齐。
            subviews.forEach { $0.layoutIfNeeded() }
        }
        // UIKit 居中标题遇到半个物理像素时向上取整。
        var frame = label.frame
        func centeredOffset(_ available: CGFloat, _ length: CGFloat) -> CGFloat {
            let freePixels = ((available - length) * scale).rounded()
            return (freePixels / 2).rounded() / scale
        }
        var column = bounds
        if appearance == .grouped, let stack = superview as? UIStackView, stack.axis == .horizontal {
            // 两列标题各自在半个面板内居中，分隔线只占按钮的点击区域。
            let halfWidth = stack.bounds.width / 2
            let x: CGFloat = self.frame.midX < stack.bounds.midX ? stack.bounds.minX : stack.bounds.midX
            column = convert(CGRect(x: x, y: bounds.minY, width: halfWidth, height: bounds.height), from: stack)
        }
        let origin = convert(CGPoint(x: column.minX + centeredOffset(column.width, frame.width),
                                     y: bounds.minY + centeredOffset(bounds.height, frame.height)), to: host)
        let pixel = 1 / scale
        if contentHorizontalAlignment == .center, abs(frame.minX - origin.x) <= pixel + 0.000_001 { frame.origin.x = origin.x }
        if abs(frame.minY - origin.y) <= pixel + 0.000_001 { frame.origin.y = origin.y }
        label.frame = frame
    }

    override func updateConfiguration() {
        super.updateConfiguration()
        if appearance == .grouped, var configuration {
            let highlighted = isHighlighted && isEnabled
            configuration.background.backgroundColorTransformer = UIConfigurationColorTransformer {
                _ in highlighted ? .tertiarySystemFill : .clear
            }
            self.configuration = configuration
        }
        guard let actionIconView else { return }
        actionIconView.tintColor = isEnabled ? configuration?.baseForegroundColor : .tertiaryLabel
        actionIconView.alpha = isHighlighted || (!isEnabled && actionIconView.image?.renderingMode == .alwaysOriginal) ? 0.45 : 1
    }
}

/// 支持嵌入子控制器、测量内容尺寸和使用原生 Popover 锚点的 UIKit 弹窗。
@MainActor
open class AlertController: UIViewController {
    public enum ContentSizing {
        /// 优先使用子控制器的首选高度。QuickLayout 宿主按实际宽度测量，其他控制器使用 Auto Layout。
        case automatic
        /// 优先使用子控制器的首选高度，否则在实际内容宽度下调用 sizeThatFits。
        case sizeThatFits
    }

    /// 自定义面板宽度时使用的容器环境与宽度（单位为点）。
    public struct PanelWidthContext {
        /// 扣除安全区、分区和呈现边距后，面板所在区域的宽度。
        public let availableWidth: CGFloat
        /// 当前呈现环境的默认面板宽度，尚未应用 maximumPanelWidth。
        public let automaticWidth: CGFloat
        /// 本次计算 automaticWidth 时使用的容器特征。
        public let containerTraitCollection: UITraitCollection
    }

    public enum PanelWidth {
        /// 按面板的呈现方式决定宽度。
        /// - iOS 26 及以上：居中呈现的 Alert 和 Action Sheet 基础宽度均为 320 pt。
        ///   Popover 在 iPad 上的基础宽度为 288 pt，其余设备为 240 pt。
        /// - iOS 26 之前：Alert 的基础宽度为 270 pt，Popover 为 304 pt。
        ///   底部呈现的 Action Sheet 使用所在区域的全部可用宽度。
        ///
        /// 上述基础宽度随 Dynamic Type 字号调整，缩放后最多为 416 pt。
        /// 最终宽度还受可用区域和 `maximumPanelWidth` 限制。
        case automatic
        /// 请求指定点数。非正数或非有限值回退到自动宽度。
        case points(CGFloat)
        /// 铺满面板所在的可用区域。
        case fill
        /// 容纳头部及正文子控制器声明的首选宽度。均未声明宽度时采用自动宽度。
        case content
        /// 根据当前呈现区域计算请求宽度。闭包可在布局期间多次执行。
        case custom(@MainActor (PanelWidthContext) -> CGFloat)
    }

    private final class EmbeddedContent {
        let controller: UIViewController
        var width: NSLayoutConstraint?
        var centerX: NSLayoutConstraint?

        init(_ controller: UIViewController) { self.controller = controller }
    }

    open private(set) var preferredStyle: UIAlertController.Style
    /// 控制自定义呈现时点击遮罩是否关闭弹窗。Action Sheet 默认开启，Alert 默认关闭。
    public var dismissesOnBackdropTap: Bool
    open private(set) var actions: [AlertAction] = []
    /// 首选操作必须已通过 addAction(_:) 添加。支持 Return 快捷键的 Alert 可提交显式指定的禁用操作。
    /// 未指定时，单个可用操作或可用操作中唯一的非取消项可作为默认提交项。
    /// iOS 26 起，Action Sheet 和 Popover 也会突出显示可见的首选操作。
    open var preferredAction: AlertAction? {
        willSet {
            precondition(newValue == nil || actions.contains { $0 === newValue },
                         "Add the preferred action to this alert before assigning it.")
        }
        didSet {
            guard isViewLoaded, oldValue !== preferredAction else { return }
            rebuildActions()
            if view.window != nil { focusForReturnKeyIfNeeded() }
        }
    }
    /// 按添加顺序返回输入框。尚未添加输入框时为 nil。
    open private(set) var textFields: [UITextField]?
    open var message: String? { didSet { updateHeader() } }
    /// 居中弹窗、底部 Action Sheet 和 iOS 26 及以上的 Popover 将补充说明放在主操作区下方。
    /// 旧版 Popover 将补充说明与正文一起滚动。旧版底部 Action Sheet 有独立取消区时不显示补充说明。
    public var detailMessage: String? { didSet { updateHeader() } }
    /// 设置为 nil 时恢复普通标题。
    public var attributedTitle: NSAttributedString? { didSet { updateHeader() } }
    /// 设置为 nil 时恢复普通正文。
    public var attributedMessage: NSAttributedString? { didSet { updateHeader() } }
    /// 设置为 nil 时恢复普通补充说明。
    public var attributedDetailMessage: NSAttributedString? { didSet { updateHeader() } }
    /// 标题的最大行数，0 表示不限行。
    public var titleMaximumLineCount = 0 { didSet { updateHeader() } }
    /// 显式设置时统一覆盖标题的换行方式。nil 时采用富文本段落样式或 UILabel 默认行为。
    public var titleLineBreakMode: NSLineBreakMode? { didSet { updateHeader() } }
    /// 面板宽度策略。实际布局受 maximumPanelWidth 和可用区域限制。
    public var panelWidth: PanelWidth = .automatic {
        didSet { invalidateContentSize() }
    }
    /// 对所有策略生效的宽度上限。非正数和非有限值等同于 nil。
    /// 有效请求和上限最低按 33 pt 处理，实际宽度仍受可用区域限制。
    public var maximumPanelWidth: CGFloat? {
        didSet {
            maximumPanelWidth = Self.validWidth(maximumPanelWidth)
            if maximumPanelWidth != oldValue { invalidateContentSize() }
        }
    }
    /// 标题、正文及内容布局参考线的左右内边距，以及面板的上下内边距。
    /// iOS 26 及以上默认单独为标题和正文预留 30 pt。显式设置后统一使用给定的左右值。
    /// 正文滚动条沿面板边缘显示，按钮的内边距独立计算。
    public var contentInsets: UIEdgeInsets {
        get {
            if let configuredContentInsets { return configuredContentInsets }
            if usesLegacyAlertLayout {
                return UIEdgeInsets(top: 20, left: 16, bottom: actions.isEmpty ? 20 : 0, right: 16)
            }
            if usesLegacySheetLayout {
                let top: CGFloat = attributedTitle == nil && attributedMessage == nil ? 14.5 : 12
                return UIEdgeInsets(top: top, left: 16, bottom: 0, right: 16)
            }
            return UIEdgeInsets(top: usesModernAppearance ? 22 : 16, left: 16, bottom: 16, right: 16)
        }
        set {
            guard configuredContentInsets != newValue else { return }
            configuredContentInsets = newValue
            invalidateContentSize()
        }
    }
    /// 头部与正文子控制器未指定首选高度时，共用此测量方式。
    public var contentSizing: ContentSizing = .automatic { didSet { invalidateContentSize() } }
    /// 启用后，嵌入视图使用面板的完整宽度进行测量和布局。
    /// 默认可使用面板全宽，也可通过子控制器的首选宽度将其居中。
    /// 显式设置内边距或将此属性设为 false 后，内容宽度受布局参考线限制。
    /// 显式赋值可覆盖默认行为。内容布局参考线始终提供内边距。
    public var contentExtendsToPanelEdges: Bool {
        get {
            if let configuredContentExtendsToPanelEdges { return configuredContentExtendsToPanelEdges }
            return (!usesPopover || usesModernAppearance)
                && configuredContentInsets == nil && preferredChildWidth == nil
        }
        set {
            guard configuredContentExtendsToPanelEdges != newValue else { return }
            configuredContentExtendsToPanelEdges = newValue
            invalidateContentSize()
        }
    }
    /// 嵌入在面板顶边、标题上方的子控制器，可与正文内容同时使用。
    /// 高度优先使用 `preferredContentSize.height`，否则按 `contentSizing` 测量。
    /// 正宽度居中并受面板宽度限制，默认铺满面板。
    public var headerContentViewController: UIViewController? {
        didSet { if isViewLoaded { installHeaderContent(replacing: oldValue) } }
    }

    public var contentViewController: UIViewController? {
        didSet { if isViewLoaded { installContent(replacing: oldValue) } }
    }

    /// 嵌入内容的内边距区域，可用于限制子控制器或其内部元素的宽度。
    public let contentViewControllerLayoutGuide = UILayoutGuide()

    /// 面板和内容的测量结果，单位为点。
    public struct LayoutSnapshot: Equatable {
        public let panelSize: CGSize
        public let contentSize: CGSize
        public let measurementWidth: CGFloat
    }

    /// 最近一次布局的测量结果。
    public private(set) var layoutSnapshot: LayoutSnapshot?
    /// 进场转场使用的布局结果。
    public private(set) var entranceLayoutSnapshot: LayoutSnapshot?

    open override var title: String? { didSet { updateHeader() } }

    fileprivate let panel = UIView()
    fileprivate let dimmingView = UIControl()
    private let panelMaterial = UIVisualEffectView()
    private let cancelBackground = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let titleHost = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    fileprivate let detailMessageLabel = UILabel()
    private let messageScrollView = UIScrollView()
    private let messageStack = UIStackView()
    private let actionStack = UIStackView()
    private let popoverActionsScrollView = UIScrollView()
    private let cancelStack = UIStackView()
    private let actionTopSeparator = UIView()
    private let headerContentHost = UIView()
    private let contentHost = UIView()
    private let textFieldsHost = UIView()
    private let textFieldStack = UIStackView()
    private var configuredContentInsets: UIEdgeInsets?
    private var configuredContentExtendsToPanelEdges: Bool?
    private var leftTextConstraints: [NSLayoutConstraint] = []
    private var rightTextConstraints: [NSLayoutConstraint] = []
    private var leftContentConstraint: NSLayoutConstraint!
    private var rightContentConstraint: NSLayoutConstraint!
    private var topContentConstraint: NSLayoutConstraint!
    private var bottomContentConstraint: NSLayoutConstraint!
    private var scrollBottomConstraint: NSLayoutConstraint!
    private var topMessageConstraint: NSLayoutConstraint!
    private var bottomMessageConstraint: NSLayoutConstraint!
    private var messageHeight: NSLayoutConstraint!
    private var headerContentHeight: NSLayoutConstraint!
    private var contentHeight: NSLayoutConstraint!
    private var embeddedHeader: EmbeddedContent?
    private var embeddedBody: EmbeddedContent?
    private var measuring = false
    private var isLayingOutPanel = false
    private var isClosing = false
    private var keyboardFrame: CGRect?
    private weak var sourceView: UIView?
    private weak var sourceItem: UIBarButtonItem?
    private var sourceRect = CGRect.null
    private var isUpdatingPopoverSize = false
    private var needsPopoverSizeUpdate = false
    private var popoverRegionSize = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    private var popoverTargetWidth: CGFloat = 0

    private static func validWidth(_ width: CGFloat?) -> CGFloat? {
        guard let width, width.isFinite, width > 0 else { return nil }
        return width
    }

    private var preferredChildWidth: CGFloat? {
        Self.validWidth(contentViewController?.preferredContentSize.width)
    }

    private var bodyWidthUsesGuide: Bool {
        !contentExtendsToPanelEdges && (configuredContentInsets != nil
            || configuredContentExtendsToPanelEdges == false || (usesPopover && !usesModernAppearance))
    }

    private var hasConfiguredPanelWidth: Bool {
        if maximumPanelWidth != nil { return true }
        switch panelWidth {
        case .automatic: return false
        case .points(let width): return Self.validWidth(width) != nil
        case .fill, .content, .custom: return true
        }
    }

    fileprivate var usesPopover: Bool { modalPresentationStyle == .popover }
    private var usesModernAlertLayout: Bool {
        if #available(iOS 26, *) { return !usesPopover }
        return false
    }
    private var usesModernAppearance: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }
    private var usesLegacyAlertLayout: Bool {
        if #available(iOS 26, *) { return false }
        return preferredStyle == .alert && !usesPopover
    }
    private var usesLegacySheetLayout: Bool { isBottomAligned }
    private var usesGroupedActions: Bool { usesLegacyAlertLayout || usesLegacySheetLayout }
    private var usesLegacyTextFieldLayout: Bool {
        usesLegacyAlertLayout && textFields?.isEmpty == false
    }
    private var usesDetailFooter: Bool { !usesPopover || usesModernAppearance }
    private var usesCompactPopoverHeaderSpacing: Bool {
        usesModernAppearance && usesPopover && embeddedHeader != nil && traitCollection.userInterfaceIdiom == .phone
    }
    private var hidesLegacySheetFooter: Bool {
        usesLegacySheetLayout && actions.contains { $0.style == .cancel }
    }
    private var separatorThickness: CGFloat {
        let scale = traitCollection.displayScale
        return scale > 0 ? 1 / scale : 0.5
    }
    private var actionSideInset: CGFloat {
        if #available(iOS 26, *) { return 16 }
        return 0
    }
    private let minimumPanelWidth: CGFloat = 32
    private let screenMargin: CGFloat = 12
    private let legacySheetGap: CGFloat = 8

    public init(title: String? = nil, message: String? = nil, preferredStyle: UIAlertController.Style) {
        self.message = message
        self.preferredStyle = preferredStyle
        dismissesOnBackdropTap = preferredStyle == .actionSheet
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("Use init(title:message:preferredStyle:)") }

    /// 在显示前配置锚点。省略矩形时采用锚点视图的 bounds。旧版 iPhone 使用系统的底部呈现方式。
    public func setPopoverAnchor(_ sourceView: UIView, sourceRect: CGRect? = nil) {
        guard preferredStyle == .actionSheet, presentingViewController == nil else { return }
        self.sourceView = sourceView
        sourceItem = nil
        self.sourceRect = sourceRect ?? .null
        configurePopover()
    }

    public func setPopoverAnchor(_ item: UIBarButtonItem) {
        guard preferredStyle == .actionSheet, presentingViewController == nil else { return }
        sourceView = nil
        sourceItem = item
        configurePopover()
    }

    open func addAction(_ action: AlertAction) {
        guard !actions.contains(where: { $0 === action }) else { return }
        guard action.style != .cancel || !actions.contains(where: { $0.style == .cancel }) else { return }
        actions.append(action)
        if isViewLoaded {
            rebuildActions()
            if hidesLegacySheetFooter { detailMessageLabel.isHidden = true }
        }
    }

    /// 向 .alert 添加一个输入框，并立即调用配置闭包。
    open func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        precondition(preferredStyle == .alert, "Text fields are supported only in the .alert style.")
        let field = UITextField()
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: usesModernAlertLayout ? .body : .footnote)
        field.adjustsFontForContentSizeCategory = true
        field.addTarget(self, action: #selector(handleTextFieldReturn(_:)), for: .editingDidEndOnExit)
        if textFields == nil { textFields = [] }
        textFields?.append(field)
        if isViewLoaded { installTextField(field) }
        configurationHandler?(field)
        invalidateContentSize()
    }

    /// 内容发生变化且未更新 preferredContentSize 时，可显式请求重新测量。
    public func invalidateContentSize() {
        guard isViewLoaded else { return }
        view.setNeedsLayout()
        if usesPopover, let presenter = presentingViewController {
            updatePopoverSize(in: presenter.view)
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        dimmingView.isAccessibilityElement = false
        dimmingView.addAction(UIAction { [weak self] _ in
            guard let self, self.dismissesOnBackdropTap else { return }
            self.close(using: self.cancelAction)
        }, for: .touchUpInside)
        view.addSubview(dimmingView)
        panel.bounds.size.width = minimumPanelWidth + 1
        view.addSubview(panel)
        panel.layer.cornerRadius = panelCornerRadius
        panel.layer.cornerCurve = .continuous
        panel.clipsToBounds = true
        dimmingView.isHidden = usesPopover

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.delaysContentTouches = false
        scrollView.contentInsetAdjustmentBehavior = .never
        panel.addSubview(scrollView)
        if usesLegacySheetLayout {
            scrollView.addSubview(panelMaterial)
            scrollView.addSubview(cancelBackground)
        } else {
            panel.insertSubview(panelMaterial, at: 0)
            panelMaterial.frame = panel.bounds
            panelMaterial.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        for material in [panelMaterial, cancelBackground] {
            material.isUserInteractionEnabled = false
            material.layer.cornerCurve = .continuous
        }
        updateSurface()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = usesLegacySheetLayout ? 0 : 12
        scrollView.addSubview(stack)
        headerContentHost.isHidden = true
        headerContentHost.clipsToBounds = true
        stack.addArrangedSubview(headerContentHost)
        headerContentHeight = headerContentHost.heightAnchor.constraint(equalToConstant: 0)

        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.accessibilityIdentifier = "AlertController.titleLabel"
        for label in [titleLabel, messageLabel, detailMessageLabel] {
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.accessibilityIdentifier = "AlertController.messageLabel"
        detailMessageLabel.accessibilityIdentifier = "AlertController.detailMessageLabel"
        messageScrollView.accessibilityIdentifier = "AlertController.messageScrollView"
        messageScrollView.contentInsetAdjustmentBehavior = .never
        messageScrollView.automaticallyAdjustsScrollIndicatorInsets = false
        messageStack.axis = .vertical
        messageStack.spacing = 8
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        if usesGroupedActions {
            messageStack.addArrangedSubview(titleLabel)
        } else {
            titleHost.addSubview(titleLabel)
            stack.addArrangedSubview(titleHost)
        }
        messageStack.addArrangedSubview(messageLabel)
        updateDetailPlacement()
        messageScrollView.addSubview(messageStack)
        messageHeight = messageScrollView.heightAnchor.constraint(equalToConstant: 0)
        stack.addArrangedSubview(messageScrollView)
        stack.addArrangedSubview(contentHost)
        contentHost.addLayoutGuide(contentViewControllerLayoutGuide)
        contentHeight = contentHost.heightAnchor.constraint(equalToConstant: 0)
        textFieldsHost.isHidden = true
        textFieldsHost.insetsLayoutMarginsFromSafeArea = false
        stack.addArrangedSubview(textFieldsHost)
        textFieldStack.axis = .vertical
        textFieldStack.translatesAutoresizingMaskIntoConstraints = false
        if usesModernAlertLayout {
            textFieldStack.backgroundColor = .secondarySystemFill
            textFieldStack.layer.cornerRadius = 24
            textFieldStack.layer.cornerCurve = .continuous
        }
        textFieldsHost.addSubview(textFieldStack)
        actionStack.axis = .vertical
        actionStack.isLayoutMarginsRelativeArrangement = true
        actionStack.insetsLayoutMarginsFromSafeArea = false
        actionStack.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0, leading: actionSideInset, bottom: 0, trailing: actionSideInset
        )
        actionTopSeparator.backgroundColor = .separator
        actionTopSeparator.isUserInteractionEnabled = false
        actionStack.addSubview(actionTopSeparator)
        stack.addArrangedSubview(actionStack)
        if usesLegacySheetLayout {
            cancelStack.axis = .vertical
            stack.addArrangedSubview(cancelStack)
        }

        leftTextConstraints = [
            messageStack.leftAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.leftAnchor),
        ]
        rightTextConstraints = [
            messageStack.rightAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.rightAnchor),
        ]
        if !usesGroupedActions {
            leftTextConstraints.append(titleLabel.leftAnchor.constraint(equalTo: titleHost.leftAnchor))
            rightTextConstraints.append(titleLabel.rightAnchor.constraint(equalTo: titleHost.rightAnchor))
            NSLayoutConstraint.activate([
                titleLabel.topAnchor.constraint(equalTo: titleHost.topAnchor),
                titleLabel.bottomAnchor.constraint(equalTo: titleHost.bottomAnchor),
            ])
        }
        leftContentConstraint = contentViewControllerLayoutGuide.leftAnchor.constraint(equalTo: contentHost.leftAnchor)
        rightContentConstraint = contentViewControllerLayoutGuide.rightAnchor.constraint(equalTo: contentHost.rightAnchor)
        topContentConstraint = stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor)
        bottomContentConstraint = stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor)
        topMessageConstraint = messageStack.topAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.topAnchor)
        bottomMessageConstraint = messageStack.bottomAnchor.constraint(equalTo: messageScrollView.contentLayoutGuide.bottomAnchor)
        scrollBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        let layoutConstraints: [NSLayoutConstraint] = [
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: panel.topAnchor),
            scrollBottomConstraint,
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            topContentConstraint,
            bottomContentConstraint,
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            messageHeight,
            headerContentHeight,
            messageScrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: messageScrollView.frameLayoutGuide.widthAnchor),
            topMessageConstraint,
            bottomMessageConstraint,
            contentHeight,
            leftContentConstraint,
            rightContentConstraint,
            contentViewControllerLayoutGuide.topAnchor.constraint(equalTo: contentHost.topAnchor),
            contentViewControllerLayoutGuide.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            textFieldStack.leadingAnchor.constraint(equalTo: textFieldsHost.layoutMarginsGuide.leadingAnchor),
            textFieldStack.trailingAnchor.constraint(equalTo: textFieldsHost.layoutMarginsGuide.trailingAnchor),
            textFieldStack.topAnchor.constraint(equalTo: textFieldsHost.topAnchor),
            textFieldStack.bottomAnchor.constraint(equalTo: textFieldsHost.bottomAnchor),
        ]
        NSLayoutConstraint.activate(layoutConstraints)
        NSLayoutConstraint.activate(leftTextConstraints + rightTextConstraints)
        textFields?.forEach(installTextField)
        updateHeader()
        rebuildActions()
        installHeaderContent(replacing: nil)
        installContent(replacing: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, _ in
                self?.invalidateContentSize()
            })
        }
        #endif
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isClosing = false
        if usesPopover, preferredContentSize == .zero || hasConfiguredPanelWidth || popoverTargetWidth > 0,
           let presenter = presentingViewController {
            updatePopoverSize(in: presenter.view)
        }
    }

    open override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard let textFields, !textFields.contains(where: \.isFirstResponder) else { return }
        textFields.first { $0.isEnabled && !$0.isHidden && $0.canBecomeFirstResponder }?.becomeFirstResponder()
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        focusForReturnKeyIfNeeded()
    }

    private var supportsReturnKeyCommand: Bool {
        // 从 iPadOS 27 起，Alert 交给焦点系统处理硬件按键，输入框仍可直接提交。
        if #available(iOS 27, *), traitCollection.userInterfaceIdiom == .pad { return false }
        return preferredStyle == .alert
    }

    open override var canBecomeFirstResponder: Bool {
        supportsReturnKeyCommand || super.canBecomeFirstResponder
    }

    private func focusForReturnKeyIfNeeded() {
        func containsFirstResponder(_ view: UIView) -> Bool {
            view.isFirstResponder || view.subviews.contains(where: containsFirstResponder)
        }
        guard supportsReturnKeyCommand, !isFirstResponder, !containsFirstResponder(view) else { return }
        becomeFirstResponder()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimmingView.frame = view.bounds
        if usesPopover {
            if popoverTargetWidth > 0, let presenter = presentingViewController {
                let region = availableRegion(in: presenter.view)
                if needsPopoverSizeUpdate || region.size != popoverRegionSize {
                    updatePopoverSize(in: presenter.view, region: region)
                }
            }
            let bounds = usesModernAppearance ? view.safeAreaLayoutGuide.layoutFrame : view.bounds
            guard bounds.width > minimumPanelWidth else { return }
            panel.frame = bounds
            let (result, footer) = measurePanel(width: bounds.width, heightLimit: popoverRegionSize.height,
                                                visibleHeight: bounds.height)
            layoutPanelContent(footer: footer)
            layoutSnapshot = LayoutSnapshot(panelSize: bounds.size, contentSize: result.contentSize,
                                            measurementWidth: result.measurementWidth)
            if view.window != nil, entranceLayoutSnapshot == nil { entranceLayoutSnapshot = layoutSnapshot }

            if view.window != nil, bounds.width < popoverTargetWidth - 0.5,
               abs(preferredContentSize.height - result.panelSize.height) > 0.5 {
                // 箭头与屏幕边缘可能压缩面板，只有宽度变化时才用实际宽度重新测量。
                preferredContentSize.height = result.panelSize.height
            }
        } else {
            let region = availableRegion(in: view)
            guard region.width > minimumPanelWidth, region.height > 0 else {
                panel.isHidden = true
                if usesDetailFooter { detailMessageLabel.frame = .zero }
                return
            }
            panel.isHidden = false
            let width = resolvedPanelWidth(in: region, traits: traitCollection)
            let (result, footer) = measurePanel(width: width, heightLimit: region.height)
            let outsideFooterHeight = usesModernAlertLayout ? 0 : footer.height
            let y = isBottomAligned ? region.maxY - outsideFooterHeight - result.panelSize.height / 2
                : region.midY - outsideFooterHeight / 2
            panel.bounds.size = result.panelSize
            if usesGroupedActions || usesModernAlertLayout {
                let halfHeight = result.panelSize.height / 2
                let pixel = separatorThickness
                let top = ((y - halfHeight) / pixel).rounded() * pixel
                let left = ((region.midX - width / 2) / pixel).rounded() * pixel
                panel.center = CGPoint(x: left + width / 2, y: top + halfHeight)
            } else {
                panel.center = CGPoint(x: region.midX, y: y)
            }
            layoutPanelContent(footer: footer)
            layoutSnapshot = result
        }
    }

    private var detailFooterSpacing: CGFloat { usesGroupedActions ? 7.5 : 6 - separatorThickness }
    private var detailFooterBottomInset: CGFloat { usesModernAppearance ? 12 : 0 }

    private func detailFooterSize(panelWidth: CGFloat, heightLimit: CGFloat) -> CGSize {
        guard usesDetailFooter, !detailMessageLabel.isHidden else { return .zero }
        let insets = resolvedTextInsets(panelWidth: panelWidth)
        let width = panelWidth - insets.left - insets.right
        let lineHeight: CGFloat = usesGroupedActions ? 16 : 18
        let naturalHeight = detailMessageLabel.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        let height = ((max(lineHeight, naturalHeight) / separatorThickness).rounded(.up)) * separatorThickness
        let paddedHeight = height + detailFooterSpacing + detailFooterBottomInset
        return CGSize(width: width, height: min(paddedHeight, heightLimit / 2))
    }

    private func measurePanel(width: CGFloat, heightLimit: CGFloat, visibleHeight: CGFloat? = nil) -> (LayoutSnapshot, CGSize) {
        let footer = detailFooterSize(panelWidth: width, heightLimit: min(visibleHeight ?? heightLimit, heightLimit))
        let result = measure(panelWidth: width, heightLimit: heightLimit - footer.height,
                             visibleHeight: visibleHeight.map { max(0, $0 - footer.height) })
        guard usesModernAppearance, footer.height > 0 else { return (result, footer) }

        let totalSize = CGSize(width: width, height: result.panelSize.height + footer.height)
        return (LayoutSnapshot(panelSize: totalSize, contentSize: result.contentSize,
                               measurementWidth: result.measurementWidth), footer)
    }

    private func layoutPanelContent(footer: CGSize) {
        let panelFooterHeight = usesModernAppearance ? footer.height : 0
        let inset = panelFooterHeight + popoverActionsScrollView.bounds.height
        if popoverActionsScrollView.superview != nil {
            popoverActionsScrollView.frame.origin = CGPoint(x: 0, y: panel.bounds.height - inset)
        }
        if scrollBottomConstraint.constant != -inset { scrollBottomConstraint.constant = -inset }
        if usesDetailFooter {
            if footer.height > 0 {
                let insets = resolvedTextInsets(panelWidth: panel.bounds.width)
                let footerOrigin = usesModernAppearance
                    ? CGPoint(x: 0, y: panel.bounds.height - panelFooterHeight)
                    : CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
                detailMessageLabel.frame = CGRect(x: footerOrigin.x + insets.left,
                                                  y: footerOrigin.y + detailFooterSpacing,
                                                  width: footer.width,
                                                  height: max(0, footer.height - detailFooterSpacing - detailFooterBottomInset))
            } else {
                detailMessageLabel.frame = .zero
            }
        }
        if usesLegacyTextFieldLayout {
            textFieldStack.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
        }
        isLayingOutPanel = true
        panel.layoutIfNeeded()
        isLayingOutPanel = false
        if usesGroupedActions {
            actionTopSeparator.frame = CGRect(x: 0, y: 0, width: actionStack.bounds.width,
                                              height: actionStack.directionalLayoutMargins.top)
        }
        if usesLegacySheetLayout {
            let cancelFrame = cancelStack.convert(cancelStack.bounds, to: scrollView)
            cancelBackground.isHidden = cancelStack.isHidden
            cancelBackground.frame = cancelFrame
            let height = cancelStack.isHidden ? scrollView.contentSize.height : cancelFrame.minY - legacySheetGap
            panelMaterial.frame = CGRect(x: 0, y: 0, width: panel.bounds.width, height: max(0, height))
        }
        let canScroll = scrollView.contentSize.height > scrollView.bounds.height + 0.5
        if scrollView.isScrollEnabled != canScroll { scrollView.isScrollEnabled = canScroll }
        let canScrollMessage = messageScrollView.contentSize.height > messageScrollView.bounds.height + 0.5
        if messageScrollView.isScrollEnabled != canScrollMessage {
            messageScrollView.isScrollEnabled = canScrollMessage
        }
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard let previousTraitCollection else { return }
        if case .custom = panelWidth {
            // 闭包可以读取任意 trait，即使容器尺寸没变也需要重新计算。
            invalidateContentSize()
        } else if previousTraitCollection.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            invalidateContentSize()
        }
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    open override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            guard let self else { return }
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }

    open override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        guard container === headerContentViewController || container === contentViewController else { return }
        invalidateContentSize()
    }

    open override func accessibilityPerformEscape() -> Bool {
        guard let cancelAction else { return false }
        close(using: cancelAction)
        return true
    }

    private var visiblePreferredAction: AlertAction? {
        guard preferredStyle == .alert || usesModernAppearance,
              !(usesPopover && preferredAction?.style == .cancel) else { return nil }
        return preferredAction
    }

    private var returnKeyAction: AlertAction? {
        guard preferredStyle == .alert else { return nil }
        if let preferredAction { return preferredAction }
        let enabled = actions.filter(\.isEnabled)
        if enabled.count == 1 { return enabled[0] }
        let choices = enabled.filter { $0.style != .cancel }
        return choices.count == 1 ? choices[0] : nil
    }

    open override var keyCommands: [UIKeyCommand]? {
        guard supportsReturnKeyCommand, returnKeyAction != nil else { return super.keyCommands }
        let submit = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(activateReturnKeyAction))
        return (super.keyCommands ?? []) + [submit]
    }

    @objc private func activateReturnKeyAction() {
        guard let action = returnKeyAction else { return }
        // UIKit 的键盘提交可以触发显式指定的禁用操作；点击和 perform() 仍检查 isEnabled。
        dismissAlert { action.handler?(action) }
    }

    fileprivate var isBottomAligned: Bool {
        guard preferredStyle == .actionSheet, !usesPopover else { return false }
        if #available(iOS 26, *) { return false }
        return true
    }

    /// 按展示控制器视图的可用区域预先测量并布局内容 guide。
    /// 原生 Popover 用结果设置首选尺寸，实际进场宽度在 entranceLayoutSnapshot 中记录。
    @discardableResult
    public func prepareForPresentation(from presenter: UIViewController) -> LayoutSnapshot? {
        if presentingViewController != nil { return layoutSnapshot }
        entranceLayoutSnapshot = nil
        let host = presenter.view!
        if usesPopover, sourceItem == nil,
           sourceView?.window == nil || sourceView?.window !== host.window {
            modalPresentationStyle = .custom
            transitioningDelegate = self
            if isViewLoaded { updatePresentationAppearance() }
        }
        loadViewIfNeeded()
        var footer = CGSize.zero
        if usesPopover {
            updatePopoverSize(in: host)
            if let layoutSnapshot {
                footer = detailFooterSize(panelWidth: layoutSnapshot.panelSize.width, heightLimit: popoverRegionSize.height)
            }
        } else {
            let region = availableRegion(in: host.window ?? host)
            if region.width > minimumPanelWidth, region.height > 0 {
                let width = resolvedPanelWidth(in: region, traits: host.traitCollection)
                let (result, measuredFooter) = measurePanel(width: width, heightLimit: region.height)
                layoutSnapshot = result
                footer = measuredFooter
            } else {
                layoutSnapshot = nil
            }
        }
        if let layoutSnapshot {
            panel.bounds.size = layoutSnapshot.panelSize
            layoutPanelContent(footer: footer)
        }
        return layoutSnapshot
    }

    fileprivate func recordEntranceLayout() {
        entranceLayoutSnapshot = layoutSnapshot
    }

    private var cancelAction: AlertAction? { actions.first { $0.style == .cancel && $0.isEnabled } }

    private func configurePopover() {
        // 紧凑手机上的旧版 UIKit 会将有来源的 Action Sheet 仍显示在底部。
        if #unavailable(iOS 26),
           (sourceView?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom) == .phone {
            return
        }
        modalPresentationStyle = .popover
        transitioningDelegate = nil
        let popover = popoverPresentationController
        popover?.delegate = self
        if #available(iOS 16, *) { popover?.sourceItem = sourceItem }
        else { popover?.barButtonItem = sourceItem }
        popover?.sourceView = sourceView
        popover?.sourceRect = sourceRect
        if isViewLoaded { updatePresentationAppearance() }
    }

    private var panelCornerRadius: CGFloat {
        if usesPopover || usesLegacySheetLayout { return 0 }
        if usesLegacyAlertLayout { return 13 }
        return 34
    }

    private func updateSurface() {
        let background: UIColor = usesPopover && !usesModernAppearance ? .secondarySystemBackground : .clear
        view.backgroundColor = background
        panel.backgroundColor = background
        panelMaterial.isHidden = usesPopover
        if #available(iOS 26, *), !usesPopover {
            panelMaterial.cornerConfiguration = .corners(radius: .fixed(Double(panelCornerRadius)))
            panelMaterial.effect = UIGlassEffect(style: .regular)
        } else {
            panelMaterial.effect = UIBlurEffect(style: .systemMaterial)
        }
        if usesLegacySheetLayout {
            panelMaterial.layer.cornerRadius = 13
            cancelBackground.layer.cornerRadius = 13
            cancelBackground.backgroundColor = .systemBackground
            panelMaterial.clipsToBounds = true
        }
    }

    private func updatePresentationAppearance() {
        dimmingView.isHidden = usesPopover
        panel.layer.cornerRadius = panelCornerRadius
        updateSurface()
        updateDetailPlacement()
        updateHeader()
        rebuildActions()
    }

    private func updateDetailPlacement() {
        let host = usesDetailFooter ? (usesModernAppearance ? panel : view!) : messageStack
        guard detailMessageLabel.superview !== host else { return }
        detailMessageLabel.removeFromSuperview()
        if !usesDetailFooter {
            messageStack.addArrangedSubview(detailMessageLabel)
        } else {
            host.addSubview(detailMessageLabel)
        }
    }

    private func updateHeader() {
        guard isViewLoaded else { return }
        let hasTitle = !(attributedTitle?.string ?? title ?? "").isEmpty
        applyText(message, attributedMessage, to: messageLabel,
                  style: usesModernAlertLayout && !hasTitle ? .body : .subheadline,
                  color: usesLegacyAlertLayout ? .label : .secondaryLabel)
        if usesLegacySheetLayout {
            applyText(attributedDetailMessage?.string ?? detailMessage, nil, to: detailMessageLabel,
                      style: .footnote, color: .secondaryLabel)
            detailMessageLabel.font = legacyFont(.footnote, size: 13)
        } else {
            applyText(detailMessage, attributedDetailMessage, to: detailMessageLabel, style: .footnote,
                      color: usesModernAppearance ? .label : .secondaryLabel)
        }
        messageLabel.isHidden = messageLabel.text?.isEmpty != false
        detailMessageLabel.isHidden = hidesLegacySheetFooter || detailMessageLabel.text?.isEmpty != false
        let hasMessage = !messageLabel.isHidden || (!usesDetailFooter && !detailMessageLabel.isHidden)
        if usesDetailFooter {
            if attributedDetailMessage == nil {
                detailMessageLabel.font = usesGroupedActions
                    ? legacyFont(.footnote, size: 13) : .preferredFont(forTextStyle: .subheadline)
            }
            if !usesPopover { detailMessageLabel.textAlignment = .center }
        }
        let standaloneTitle = usesModernAppearance && !hasMessage && attributedTitle == nil
        applyText(title, attributedTitle, to: titleLabel, style: standaloneTitle ? .body : .headline, color: .label)
        if usesLegacyAlertLayout {
            if attributedTitle == nil { titleLabel.font = legacyFont(.headline, size: 17, weight: .semibold) }
            if attributedMessage == nil {
                let font = legacyFont(.footnote, size: 13)
                messageLabel.font = font
                if let message, !message.isEmpty {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = messageLabel.textAlignment
                    paragraph.lineSpacing = ceil(font.lineHeight) - font.lineHeight
                    messageLabel.attributedText = NSAttributedString(
                        string: message, attributes: [.paragraphStyle: paragraph]
                    )
                }
            }
        }
        if standaloneTitle { titleLabel.textAlignment = .center }
        if usesLegacySheetLayout {
            let decorated = attributedTitle != nil || attributedMessage != nil
            if attributedTitle == nil {
                titleLabel.font = legacyFont(.footnote, size: 13, weight: hasMessage ? .semibold : .regular)
            }
            if attributedMessage == nil {
                messageLabel.font = legacyFont(.footnote, size: 13)
                if let message, !message.isEmpty {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = .center
                    paragraph.lineSpacing = 2.5
                    messageLabel.attributedText = NSAttributedString(
                        string: message, attributes: [.paragraphStyle: paragraph]
                    )
                }
            }
            if !decorated { titleLabel.textColor = .secondaryLabel }
        }
        titleLabel.numberOfLines = max(0, titleMaximumLineCount)
        if let titleLineBreakMode { titleLabel.lineBreakMode = titleLineBreakMode }
        titleHost.isHidden = !hasTitle
        titleLabel.isHidden = !hasTitle
        let hasScrollContent = hasMessage || (usesGroupedActions && hasTitle)
        if !hasScrollContent { messageHeight.constant = 0 }
        messageScrollView.isHidden = !hasScrollContent
        invalidateContentSize()
    }

    private func applyText(_ text: String?, _ attributedText: NSAttributedString?, to label: UILabel,
                           style: UIFont.TextStyle, color: UIColor) {
        // UILabel 会从富文本首字符更新默认样式，切回普通文本时先恢复默认值。
        label.attributedText = nil
        label.font = .preferredFont(forTextStyle: style)
        label.textColor = color
        if #available(iOS 26, *) {
            label.textAlignment = .natural
        } else {
            label.textAlignment = .center
        }
        label.lineBreakMode = .byTruncatingTail
        if let attributedText { label.attributedText = attributedText }
        else { label.text = text }
    }

    private func legacyFont(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let scaled = UIFontMetrics(forTextStyle: style).scaledFont(for: base, compatibleWith: traitCollection)
        return scaled.pointSize >= size ? scaled : base
    }

    private var horizontalActionTitleInset: CGFloat { usesModernAlertLayout ? 10 : AlertActionButton.edgeInset }

    private func attributedButtonTitle(for action: AlertAction) -> AttributedString? {
        guard let title = action.attributedTitle, action === visiblePreferredAction else { return action.attributedTitle }
        return title.mergingAttributes(AttributeContainer().font(actionFont(for: action)), mergePolicy: .keepCurrent)
    }

    private func usesHorizontalActions(panelWidth: CGFloat?) -> Bool {
        guard (preferredStyle == .alert || usesModernAlertLayout), actions.count == 2,
              !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else { return false }
        guard !usesPopover, let panelWidth else { return true }
        let spacing: CGFloat = usesLegacyAlertLayout ? separatorThickness : 8
        let slotWidth = (panelWidth - 2 * actionSideInset - spacing) / 2 - 2 * horizontalActionTitleInset
        return actions.allSatisfy { action in
            let title = attributedButtonTitle(for: action).map { NSAttributedString($0) }
                ?? NSAttributedString(string: action.title ?? "", attributes: [.font: actionFont(for: action)])
            let iconWidth = action.image.map { max(20, min(24, $0.size.width)) + AlertActionButton.edgeInset } ?? 0
            return title.size().width + iconWidth <= slotWidth
        }
    }

    private func rebuildActions(panelWidth: CGFloat? = nil) {
        actionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cancelStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let regular = actions.filter { $0.style != .cancel }
        let cancellation = usesPopover ? [] : actions.filter { $0.style == .cancel }
        let horizontal = usesHorizontalActions(panelWidth: panelWidth ?? layoutSnapshot?.panelSize.width)
        // 横排时取消操作占据起始侧，竖排时放在底部。
        let cancelFirst = horizontal && (usesModernAlertLayout || usesLegacyAlertLayout)
        let displayed = usesLegacySheetLayout ? regular : (cancelFirst ? cancellation + regular : regular + cancellation)
        let legacyHorizontal = usesLegacyAlertLayout && horizontal
        actionStack.isHidden = displayed.isEmpty
        actionStack.axis = horizontal ? .horizontal : .vertical
        actionStack.distribution = horizontal && !legacyHorizontal ? .fillEqually : .fill
        actionTopSeparator.isHidden = !usesGroupedActions
        cancelStack.isHidden = !usesLegacySheetLayout || cancellation.isEmpty
        let defaultCornerStyle: UIButton.Configuration.CornerStyle
        let minimumActionHeight: CGFloat
        if #available(iOS 26, *) {
            defaultCornerStyle = .capsule
            minimumActionHeight = 48
            actionStack.spacing = 8
        } else {
            // 旧版按钮共用面板外轮廓，各操作行之间留一个物理像素。
            defaultCornerStyle = .fixed
            minimumActionHeight = preferredStyle == .alert ? 44 : 57
            actionStack.spacing = usesGroupedActions ? 0 : separatorThickness
        }
        for action in displayed + (usesLegacySheetLayout ? cancellation : []) {
            var configuration = UIButton.Configuration.filled()
            let preferred = action === visiblePreferredAction
            let usesPreferredFill = usesModernAppearance && preferred && action.style != .destructive
            if let attributedTitle = attributedButtonTitle(for: action) {
                configuration.attributedTitle = attributedTitle
            } else {
                configuration.title = action.title
                let font = actionFont(for: action)
                configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                    var attributes = attributes
                    attributes.font = font
                    return attributes
                }
            }
            configuration.image = action.image
            configuration.imagePadding = 8
            configuration.cornerStyle = action.cornerStyle ?? defaultCornerStyle
            if defaultCornerStyle == .fixed { configuration.background.cornerRadius = 0 }
            let sideInset = horizontal ? horizontalActionTitleInset : AlertActionButton.edgeInset
            configuration.contentInsets.leading = sideInset
            configuration.contentInsets.trailing = sideInset
            if horizontal && !usesPopover { configuration.titleLineBreakMode = .byTruncatingTail }
            configuration.baseBackgroundColor = usesGroupedActions ? .clear : .secondarySystemFill
            var foreground = usesModernAppearance ? UIColor.label : view.tintColor
            if usesPreferredFill {
                configuration.baseBackgroundColor = .tintColor
                foreground = .white
            } else if action.style == .destructive {
                foreground = .systemRed
            }
            configuration.baseForegroundColor = action.titleColor ?? foreground
            let appearance: AlertActionButton.Appearance = usesGroupedActions ? .grouped
                : (usesModernAppearance && !horizontal ? .modernStacked : .standard)
            let button = AlertActionButton(configuration: configuration, appearance: appearance,
                                           usesPreferredFill: usesPreferredFill, usesPopoverMaterial: usesPopover)
            button.addAction(UIAction { [weak self, weak action] _ in
                guard let action else { return }
                self?.close(using: action)
            }, for: .touchUpInside)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumActionHeight).isActive = true
            let destination = usesLegacySheetLayout && action.style == .cancel ? cancelStack : actionStack
            if usesGroupedActions && !destination.arrangedSubviews.isEmpty {
                let divider = UIView()
                divider.backgroundColor = .separator
                divider.isUserInteractionEnabled = false
                if horizontal { divider.widthAnchor.constraint(equalToConstant: separatorThickness).isActive = true }
                else { divider.heightAnchor.constraint(equalToConstant: separatorThickness).isActive = true }
                destination.addArrangedSubview(divider)
            }
            destination.addArrangedSubview(button)
            action.bind(to: button)
        }
        if legacyHorizontal, let firstButton = actionStack.arrangedSubviews.first {
            // 起始侧占面板的一半，剩余一侧让出分隔线的宽度。
            firstButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor, multiplier: 0.5).isActive = true
        }
        if !measuring { invalidateContentSize() }
    }

    private func actionFont(for action: AlertAction) -> UIFont {
        let preferred = action === visiblePreferredAction
        if usesModernAppearance {
            let body = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body, compatibleWith: traitCollection)
            let weight: UIFont.Weight = preferred ? .semibold : .medium
            let descriptor = body.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
            return UIFont(descriptor: descriptor, size: 0)
        }
        let emphasized = preferred || (visiblePreferredAction == nil && action.style == .cancel)
        return legacyFont(
            .body, size: usesLegacyAlertLayout ? 17 : 20, weight: emphasized ? .semibold : .regular
        )
    }

    private func installTextField(_ field: UITextField) {
        textFieldsHost.isHidden = false
        if usesLegacyTextFieldLayout {
            installLegacyTextField(field)
            return
        }
        let row = textFieldRow(field, horizontalInset: 15, topInset: 7, bottomInset: 6, minimumHeight: 35)
        if !textFieldStack.arrangedSubviews.isEmpty {
            addTextFieldSeparator(to: row, leading: field.leadingAnchor, trailing: field.trailingAnchor)
        }
        textFieldStack.addArrangedSubview(row)
    }

    private func textFieldRow(_ field: UITextField, horizontalInset: CGFloat, topInset: CGFloat,
                              bottomInset: CGFloat, minimumHeight: CGFloat) -> UIControl {
        let row = UIControl()
        row.addAction(UIAction { [weak field] _ in field?.becomeFirstResponder() }, for: .touchUpInside)
        row.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        let leading = field.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: horizontalInset)
        let trailing = field.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -horizontalInset)
        leading.priority = UILayoutPriority(rawValue: 999)
        trailing.priority = leading.priority
        let height = field.heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            leading,
            trailing,
            field.topAnchor.constraint(equalTo: row.topAnchor, constant: topInset),
            field.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -bottomInset),
            height,
        ])
        return row
    }

    private func addTextFieldSeparator(to row: UIView, leading: NSLayoutXAxisAnchor, trailing: NSLayoutXAxisAnchor) {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.isUserInteractionEnabled = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(divider)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leading),
            divider.trailingAnchor.constraint(equalTo: trailing),
            divider.topAnchor.constraint(equalTo: row.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: separatorThickness),
        ])
    }

    private func installLegacyTextField(_ field: UITextField) {
        let isFirstRow = textFieldStack.arrangedSubviews.isEmpty
        let pixel = separatorThickness
        if isFirstRow {
            textFieldStack.isLayoutMarginsRelativeArrangement = true
            textFieldStack.insetsLayoutMarginsFromSafeArea = false
            textFieldStack.backgroundColor = .systemBackground
            textFieldStack.layer.cornerRadius = 7
            textFieldStack.layer.borderWidth = pixel
            textFieldStack.clipsToBounds = true
        }

        let row = textFieldRow(field, horizontalInset: 0, topInset: isFirstRow ? 7 : 6.5, bottomInset: 6.5,
                               minimumHeight: isFirstRow ? 16 : 15)
        textFieldStack.addArrangedSubview(row)
        if !isFirstRow {
            addTextFieldSeparator(to: row, leading: textFieldStack.leadingAnchor, trailing: textFieldStack.trailingAnchor)
        }
    }

    @objc private func handleTextFieldReturn(_ field: UITextField) {
        if field.returnKeyType == .next, let textFields, let index = textFields.firstIndex(of: field),
           let next = textFields.dropFirst(index + 1).first(where: { $0.isEnabled && !$0.isHidden && $0.canBecomeFirstResponder }) {
            next.becomeFirstResponder()
        } else {
            field.resignFirstResponder()
            activateReturnKeyAction()
        }
    }

    private func installHeaderContent(replacing previous: UIViewController?) {
        if let previous, previous === headerContentViewController, previous === embeddedHeader?.controller { return }
        embeddedHeader = installEmbeddedController(
            headerContentViewController, replacing: embeddedHeader, in: headerContentHost, height: headerContentHeight
        )
        invalidateContentSize()
    }

    private func installContent(replacing previous: UIViewController?) {
        if let previous, previous === contentViewController, previous === embeddedBody?.controller { return }
        embeddedBody = installEmbeddedController(
            contentViewController, replacing: embeddedBody, in: contentHost, height: contentHeight
        )
        invalidateContentSize()
    }

    private func installEmbeddedController(
        _ child: UIViewController?, replacing previous: EmbeddedContent?, in host: UIView, height: NSLayoutConstraint
    ) -> EmbeddedContent? {
        if let previous, previous.controller.parent === self {
            previous.controller.willMove(toParent: nil)
            previous.width?.isActive = false
            previous.controller.viewIfLoaded?.removeFromSuperview()
            previous.controller.removeFromParent()
        }
        height.constant = 0
        host.isHidden = true
        guard let child, child !== self, child.parent == nil else { return nil }
        addChild(child)
        return EmbeddedContent(child)
    }

    private func layoutEmbeddedContent(
        _ embedded: EmbeddedContent, in host: UIView, height: NSLayoutConstraint, width: CGFloat, centerOffset: CGFloat = 0
    ) -> CGSize {
        let child = embedded.controller
        let content = child.view!
        content.translatesAutoresizingMaskIntoConstraints = false
        let size = CGSize(width: width, height: embeddedContentHeight(for: child, width: width))
        if host.isHidden { host.isHidden = false }
        if height.constant != size.height { height.constant = size.height }
        if let widthConstraint = embedded.width, let centerX = embedded.centerX {
            if widthConstraint.constant != width { widthConstraint.constant = width }
            if centerX.constant != centerOffset { centerX.constant = centerOffset }
            return size
        }

        // 在挂载子视图前确定尺寸，避免占位约束与子视图的最小尺寸或内边距冲突。
        content.frame = CGRect(origin: .zero, size: size)
        host.addSubview(content)
        let widthConstraint = content.widthAnchor.constraint(equalToConstant: width)
        let centerX = content.centerXAnchor.constraint(equalTo: host.centerXAnchor, constant: centerOffset)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            centerX,
            widthConstraint,
        ])
        embedded.width = widthConstraint
        embedded.centerX = centerX
        child.didMove(toParent: self)
        return size
    }

    private func embeddedContentHeight(for child: UIViewController, width: CGFloat) -> CGFloat {
        let preferred = child.preferredContentSize.height
        if preferred.isFinite, preferred > 0 { return ceil(preferred) }
        let fitted: CGFloat
        switch contentSizing {
        case .automatic:
            if let host = child as? QuickLayoutHostingController {
                fitted = host.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
                break
            }
            if child.view.superview == nil {
                // 脱离层级的空白视图可能返回控制器初始的屏幕高度。
                child.view.bounds.size = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            }
            fitted = child.view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
        case .sizeThatFits:
            fitted = child.view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        }
        return fitted.isFinite && fitted > 0 ? ceil(fitted) : 100
    }

    private func availableRegion(in host: UIView) -> CGRect {
        var safe = host.bounds.inset(by: host.safeAreaInsets)
        if let window = host.window, host !== presentingViewController?.view {
            safe = safe.intersection(host.convert(window.safeAreaLayoutGuide.layoutFrame, from: window))
        }
        var area = safe.isEmpty || safe.isNull ? host.bounds : safe
        if host === view, let keyboardFrame, let window = host.window {
            let keyboard = window.convert(keyboardFrame, from: window.screen.coordinateSpace)
            let obstruction = host.convert(keyboard, from: window).intersection(area)
            if !obstruction.isNull, obstruction.width >= area.width / 2, obstruction.maxY >= area.maxY - 1 {
                area.size.height = max(0, obstruction.minY - area.minY)
            }
        }
        let verticalMargin = usesLegacyAlertLayout ? 2 * screenMargin : screenMargin
        let insets = usesLegacySheetLayout
            ? UIEdgeInsets(top: 4 * screenMargin, left: 8, bottom: 0, right: 8)
            : UIEdgeInsets(top: verticalMargin, left: screenMargin, bottom: verticalMargin, right: screenMargin)

        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let divisions = host.reservedRegions(kind: .division).map(\.frame)
            let occlusions = host.reservedRegions(kind: .occlusion).map(\.frame)
            let source = sourceView.flatMap { anchor -> CGPoint? in
                guard let window = host.window, anchor.window === window else { return nil }
                let rect = anchor.convert(sourceRect.isNull ? anchor.bounds : sourceRect, to: host)
                return CGPoint(x: rect.midX, y: rect.midY)
            }
            let rtl = host.effectiveUserInterfaceLayoutDirection == .rightToLeft
            return AlertLayout.availableRegion(area, divisions: divisions, occlusions: occlusions,
                                               insets: insets, anchor: source, rtl: rtl)
        }
        #endif
        let insetArea = area.inset(by: insets)
        return insetArea.isEmpty ? .zero : insetArea
    }

    private func resolvedPanelWidth(in region: CGRect, traits: UITraitCollection) -> CGFloat {
        let automatic = automaticPanelWidth(in: region, traits: traits)
        let requested: CGFloat?
        switch panelWidth {
        case .automatic: requested = automatic
        case .points(let width): requested = width
        case .fill: requested = region.width
        case .content:
            // 子控制器可能在 viewDidLoad 中声明首选宽度。
            embeddedHeader?.controller.loadViewIfNeeded()
            embeddedBody?.controller.loadViewIfNeeded()
            let header = Self.validWidth(embeddedHeader?.controller.preferredContentSize.width)
            var body = Self.validWidth(embeddedBody?.controller.preferredContentSize.width)
            if let width = body, bodyWidthUsesGuide {
                let (left, right) = fittedEdges(contentInsets.left, contentInsets.right, panelWidth: region.width)
                body = min(width, region.width) + left + right
            }
            requested = max(header ?? 0, body ?? 0)
        case .custom(let resolve):
            requested = resolve(PanelWidthContext(availableWidth: region.width, automaticWidth: automatic,
                                                  containerTraitCollection: traits))
        }
        let capped = min(Self.validWidth(requested) ?? automatic, maximumPanelWidth ?? region.width)
        return min(region.width, max(minimumPanelWidth + 1, capped))
    }

    private func automaticPanelWidth(in region: CGRect, traits: UITraitCollection) -> CGFloat {
        if isBottomAligned { return region.width }
        // 面板宽度随 Dynamic Type 缩放，并受实际可用区域限制。
        let baseWidth: CGFloat
        if usesLegacyAlertLayout { baseWidth = 270 }
        else if usesModernAlertLayout { baseWidth = 320 }
        else if usesModernAppearance { baseWidth = traits.userInterfaceIdiom == .pad ? 288 : 240 }
        else { baseWidth = 304 }
        let scaledWidth = UIFontMetrics(forTextStyle: .body).scaledValue(for: baseWidth, compatibleWith: traits)
        let maximum = min(416, usesLegacyAlertLayout ? max(baseWidth, scaledWidth) : scaledWidth)
        return min(region.width, maximum)
    }

    private func updatePopoverSize(in host: UIView, region: CGRect? = nil) {
        // 子控制器可在测量期间更新 preferredContentSize，留到下一次布局读取新值。
        guard !measuring, !isUpdatingPopoverSize, !isLayingOutPanel else {
            needsPopoverSizeUpdate = true
            return
        }
        needsPopoverSizeUpdate = false
        isUpdatingPopoverSize = true
        defer { isUpdatingPopoverSize = false }
        loadViewIfNeeded()
        let region = region ?? availableRegion(in: host)
        guard region.width > minimumPanelWidth, region.height > 0 else { return }
        let traits = view.window == nil ? host.traitCollection : traitCollection
        let targetWidth = resolvedPanelWidth(in: region, traits: traits)
        let actualWidth = view.window != nil && popoverTargetWidth == targetWidth ? panel.bounds.width : 0
        let sameRegion = popoverRegionSize == region.size
        popoverTargetWidth = targetWidth
        popoverRegionSize = region.size
        let width = actualWidth > minimumPanelWidth ? min(actualWidth, targetWidth) : targetWidth
        let (result, _) = measurePanel(width: width, heightLimit: region.height)
        let preferredSize = CGSize(width: targetWidth, height: result.panelSize.height)
        if view.window == nil { layoutSnapshot = result }
        guard preferredContentSize != preferredSize else { return }
        let visibleHeight = view.safeAreaLayoutGuide.layoutFrame.height
        if view.window != nil, sameRegion, visibleHeight > 0, preferredContentSize.width == targetWidth,
           min(preferredContentSize.height, preferredSize.height) > visibleHeight + separatorThickness {
            // UIKit 已压缩面板；此时提交另一个超高尺寸会让它反复尝试加宽。可见区域增大后再协商。
            needsPopoverSizeUpdate = true
            return
        }
        preferredContentSize = preferredSize
    }

    /// 自定义头部和正文共用上方的滚动区，操作在下方独立滚动。
    private func measurePopoverActions(width: CGFloat, bottomInset: CGFloat) -> CGFloat {
        guard usesModernAppearance, usesPopover, embeddedHeader != nil || embeddedBody != nil,
              !actionStack.isHidden else {
            if popoverActionsScrollView.superview != nil {
                actionStack.removeFromSuperview()
                stack.addArrangedSubview(actionStack)
                popoverActionsScrollView.removeFromSuperview()
                popoverActionsScrollView.bounds = .zero
            }
            return 0
        }
        if popoverActionsScrollView.superview == nil {
            actionStack.removeFromSuperview()
            actionStack.translatesAutoresizingMaskIntoConstraints = true
            popoverActionsScrollView.addSubview(actionStack)
            popoverActionsScrollView.contentInsetAdjustmentBehavior = .never
            panel.addSubview(popoverActionsScrollView)
        }
        let size = actionStack.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        actionStack.frame = CGRect(x: 0, y: actionSideInset, width: width, height: size.height)
        let height = actionStack.frame.maxY + bottomInset
        popoverActionsScrollView.contentSize = CGSize(width: width, height: height)
        return height
    }

    private func measure(panelWidth: CGFloat, heightLimit: CGFloat, visibleHeight: CGFloat? = nil) -> LayoutSnapshot {
        measuring = true
        defer { measuring = false }
        if !usesPopover || view.window == nil || layoutSnapshot == nil {
            if panel.bounds.width != panelWidth { panel.bounds.size.width = panelWidth }
        }
        if usesHorizontalActions(panelWidth: panelWidth) != (actionStack.axis == .horizontal) {
            rebuildActions(panelWidth: panelWidth)
        }
        if let embeddedHeader {
            let child = embeddedHeader.controller
            child.loadViewIfNeeded()
            let preferredWidth = child.preferredContentSize.width
            let width = preferredWidth.isFinite && preferredWidth > 0 ? min(preferredWidth, panelWidth) : panelWidth
            _ = layoutEmbeddedContent(embeddedHeader, in: headerContentHost, height: headerContentHeight, width: width)
        }
        embeddedBody?.controller.loadViewIfNeeded()
        let (insets, textWidth, naturalTop) = applyContentInsets(panelWidth: panelWidth)
        let available = panelWidth - insets.left - insets.right
        var size = CGSize.zero
        if let embeddedBody {
            let extendsToPanelEdges = contentExtendsToPanelEdges
            let width: CGFloat
            if extendsToPanelEdges { width = panelWidth }
            else if let preferredChildWidth { width = min(preferredChildWidth, bodyWidthUsesGuide ? available : panelWidth) }
            else { width = available }
            let centerOffset = extendsToPanelEdges ? 0 : (insets.left - insets.right) / 2
            size = layoutEmbeddedContent(embeddedBody, in: contentHost, height: contentHeight,
                                         width: width, centerOffset: centerOffset)
        }
        if usesModernAppearance {
            let hasContent = !contentHost.isHidden || !textFieldsHost.isHidden
            let multilineRichTitle = attributedTitle != nil && titleLabel.sizeThatFits(
                CGSize(width: textWidth, height: .greatestFiniteMagnitude)
            ).height > titleLabel.font.lineHeight + separatorThickness
            let titleSpacing: CGFloat
            if !messageScrollView.isHidden {
                if usesCompactPopoverHeaderSpacing { titleSpacing = separatorThickness }
                else {
                    titleSpacing = multilineRichTitle ? 6 - separatorThickness
                        : 8 - (usesPopover ? 1 : 2) * separatorThickness
                }
            } else {
                titleSpacing = hasContent ? (usesPopover ? 2 : 16) : 20
            }
            let messageSpacing: CGFloat = hasContent ? 16 : 20
            let contentSpacing: CGFloat = textFieldsHost.isHidden ? 24 : 12
            let titleHeight = titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
            let titleRounding = usesModernAlertLayout && !titleHost.isHidden ? ceil(titleHeight) - titleHeight : 0
            for (spacing, section) in [(titleSpacing + titleRounding, titleHost), (messageSpacing, messageScrollView as UIView),
                                       (contentSpacing, contentHost), (20, textFieldsHost)]
                where stack.customSpacing(after: section) != spacing {
                stack.setCustomSpacing(spacing, after: section)
            }
        } else if usesLegacyAlertLayout {
            updateLegacySectionSpacing()
        } else if usesLegacySheetLayout {
            updateLegacySheetSpacing(textWidth: textWidth)
        }
        let viewport = min(visibleHeight ?? heightLimit, heightLimit)
        let actionHeight = measurePopoverActions(width: panelWidth, bottomInset: insets.bottom)
        var bodyBottom = insets.bottom
        if actionHeight > 0, let lastSection = stack.arrangedSubviews.last(where: { !$0.isHidden }) {
            // 相邻两区的间距由正文末尾和操作区顶部共同提供。
            if lastSection === titleHost {
                bodyBottom = 2 - separatorThickness
            } else {
                let gap = lastSection === headerContentHost ? naturalTop : stack.customSpacing(after: lastSection)
                bodyBottom = max(0, (gap == UIStackView.spacingUseDefault ? stack.spacing : gap) - actionSideInset)
            }
        }
        if bottomContentConstraint.constant != -bodyBottom { bottomContentConstraint.constant = -bodyBottom }
        // 头部插在标题上方时，顶部留白位于两个 section 之间，已计入 stack 的测量高度。
        var topAdjustment = naturalTop
        if !headerContentHost.isHidden {
            let gap = stack.customSpacing(after: headerContentHost)
            let hasFollowingSection = stack.arrangedSubviews.dropFirst().contains { !$0.isHidden }
            topAdjustment = hasFollowingSection ? naturalTop - (gap == UIStackView.spacingUseDefault ? stack.spacing : gap) : 0
        }
        let heightWithoutMessage = stack.systemLayoutSizeFitting(
            CGSize(width: panelWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + topAdjustment + bodyBottom + actionHeight - messageHeight.constant

        var height = heightWithoutMessage
        if !messageScrollView.isHidden {
            let readingLabel = messageStack.arrangedSubviews.first { !$0.isHidden } as? UILabel
            let lineHeight = (messageLabel.isHidden ? readingLabel ?? detailMessageLabel : messageLabel).font.lineHeight
            let minimumReadingHeight = min(viewport, ceil(lineHeight * 3))
            let remaining = viewport - heightWithoutMessage
            let message: CGFloat
            let visibleMessage: CGFloat
            if usesLegacyAlertLayout {
                let availableHeight = max(minimumReadingHeight, (remaining / separatorThickness).rounded(.down) * separatorThickness)
                message = measureLegacyHeader(width: textWidth, availableHeight: availableHeight, topInset: insets.top)
                visibleMessage = min(message, availableHeight)
            } else {
                let visibleLabels = messageStack.arrangedSubviews.compactMap { $0 as? UILabel }.filter { !$0.isHidden }
                let proposal = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
                let roundingUnit = usesLegacySheetLayout ? separatorThickness : 1
                let labelHeight = visibleLabels.reduce(CGFloat.zero) { height, label in
                    let fitted = label.sizeThatFits(proposal).height
                    return height + (fitted / roundingUnit).rounded(.up) * roundingUnit
                }
                var spacing = visibleLabels.dropLast().reduce(CGFloat.zero) { spacing, label in
                    let gap = messageStack.customSpacing(after: label)
                    return spacing + (gap == UIStackView.spacingUseDefault ? messageStack.spacing : gap)
                }
                var top: CGFloat = 0
                if usesLegacySheetLayout {
                    top = insets.top
                    if configuredContentInsets == nil, labelHeight + spacing + top > remaining {
                        top = min(top, 4)
                        if visibleLabels.count > 1, visibleLabels.first === titleLabel {
                            spacing += separatorThickness - messageStack.customSpacing(after: titleLabel)
                            messageStack.setCustomSpacing(separatorThickness, after: titleLabel)
                        }
                    }
                    if topMessageConstraint.constant != top { topMessageConstraint.constant = top }
                }
                message = labelHeight + spacing + top
                let remainingHeight = (remaining / roundingUnit).rounded(.down) * roundingUnit
                visibleMessage = min(message, max(minimumReadingHeight, remainingHeight))
            }
            if messageHeight.constant != visibleMessage { messageHeight.constant = visibleMessage }
            height += message
        }
        var visibleTop = naturalTop
        if actionHeight > 0, configuredContentInsets == nil, !titleHost.isHidden {
            let overflow = max(0, heightWithoutMessage + messageHeight.constant - viewport)
            visibleTop -= min(overflow, max(0, naturalTop - 5))
        }
        if actionHeight > 0 {
            let bodyHeight = heightWithoutMessage - actionHeight + messageHeight.constant - (naturalTop - visibleTop)
            // 两区都需要滚动时，UIKit 将可见高度的 60% 给正文。短正文让出余量给操作区。
            let bodyLimit = (viewport * 0.6 / separatorThickness).rounded() * separatorThickness
            let visibleActions = min(actionHeight, max(0, viewport - min(bodyHeight, bodyLimit)))
            popoverActionsScrollView.bounds.size = CGSize(width: panelWidth, height: visibleActions)
            popoverActionsScrollView.isScrollEnabled = actionHeight > visibleActions + 0.5
        }
        let stackTop = headerContentHost.isHidden ? visibleTop : 0
        if topContentConstraint.constant != stackTop { topContentConstraint.constant = stackTop }
        if !headerContentHost.isHidden, stack.customSpacing(after: headerContentHost) != visibleTop {
            stack.setCustomSpacing(visibleTop, after: headerContentHost)
        }
        let roundingUnit = usesModernAppearance || usesGroupedActions ? separatorThickness : 1
        let fittedHeight = (height / roundingUnit - 0.000_001).rounded(.up) * roundingUnit
        return LayoutSnapshot(panelSize: CGSize(width: panelWidth, height: min(heightLimit, fittedHeight)),
                              contentSize: size, measurementWidth: size.width)
    }

    private func updateLegacySectionSpacing() {
        let visibleFieldCount = textFieldStack.arrangedSubviews.count { !$0.isHidden }
        let hasHeader = !messageScrollView.isHidden || !contentHost.isHidden || visibleFieldCount > 0
        var actionMargins = actionStack.directionalLayoutMargins
        let divider = hasHeader ? separatorThickness : 0
        if actionMargins.top != divider {
            actionMargins.top = divider
            actionStack.directionalLayoutMargins = actionMargins
        }

        let contentSpacing: CGFloat = visibleFieldCount > 0 ? 12 : 0
        let fieldSpacing: CGFloat = visibleFieldCount > 1 ? 12.5 : 12
        for (spacing, section) in [(0, messageScrollView as UIView),
                                   (contentSpacing, contentHost), (fieldSpacing, textFieldsHost)]
            where stack.customSpacing(after: section) != spacing {
            stack.setCustomSpacing(spacing, after: section)
        }
    }

    private func updateLegacySheetSpacing(textWidth: CGFloat) {
        let hasTitle = !titleLabel.isHidden
        let hasMessage = !messageLabel.isHidden
        let hasContent = !contentHost.isHidden
        let decorated = attributedTitle != nil || attributedMessage != nil
        let multiline = attributedTitle != nil && titleLabel.sizeThatFits(
            CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        ).height > titleLabel.font.lineHeight + separatorThickness
        let headingGap: CGFloat = decorated ? (multiline ? 2.5 : 4) : 6
        if messageStack.customSpacing(after: titleLabel) != headingGap {
            messageStack.setCustomSpacing(headingGap, after: titleLabel)
        }
        let hasHeader = hasTitle || hasMessage || hasContent
        var margins = actionStack.directionalLayoutMargins
        margins.top = hasHeader ? separatorThickness : 0
        if actionStack.directionalLayoutMargins != margins { actionStack.directionalLayoutMargins = margins }

        let headerSpacing: CGFloat = hasContent ? 13.5 : (hasMessage ? (multiline ? 23.5 : 24.5) : 20)
        let sections: [(CGFloat, UIView)] = [
            (headerSpacing, messageScrollView),
            (0, contentHost),
            (0, actionStack),
        ]
        let last = sections.last { !$0.1.isHidden }?.1
        for (defaultSpacing, section) in sections {
            let spacing = section === last ? (cancelStack.isHidden ? 0 : legacySheetGap) : defaultSpacing
            if stack.customSpacing(after: section) != spacing {
                stack.setCustomSpacing(spacing, after: section)
            }
        }
    }

    private func measureLegacyHeader(width: CGFloat, availableHeight: CGFloat, topInset: CGFloat) -> CGFloat {
        let proposedSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        let labels = [titleLabel, messageLabel].filter { !$0.isHidden }
        let labelHeight = labels.reduce(CGFloat.zero) { height, label in
            height + (label.sizeThatFits(proposedSize).height / separatorThickness).rounded(.up) * separatorThickness
        }
        let hasBody = !messageLabel.isHidden
        let richTitle = !titleLabel.isHidden && attributedTitle != nil
        let multiline = richTitle && titleLabel.sizeThatFits(proposedSize).height > titleLabel.font.lineHeight + separatorThickness
        let titleSpacing: CGFloat = !titleLabel.isHidden && hasBody
            ? (richTitle ? (multiline ? separatorThickness : 2) : 3.5) : 0
        let bottomInset: CGFloat = actionStack.isHidden && contentHost.isHidden && textFieldsHost.isHidden ? 0
            : (hasBody ? (multiline ? 20 : 20.5) : 19.5)
        let paddedTop = richTitle && configuredContentInsets == nil ? topInset + 1 : topInset
        let overflows = paddedTop + labelHeight + titleSpacing + bottomInset > availableHeight
        let topPadding = overflows && configuredContentInsets == nil ? min(paddedTop, 5) : paddedTop
        let headingGap = overflows ? 0 : titleSpacing
        if messageStack.customSpacing(after: titleLabel) != headingGap {
            messageStack.setCustomSpacing(headingGap, after: titleLabel)
        }
        if topMessageConstraint.constant != topPadding { topMessageConstraint.constant = topPadding }
        if bottomMessageConstraint.constant != -bottomInset { bottomMessageConstraint.constant = -bottomInset }
        return topPadding + labelHeight + headingGap + bottomInset
    }

    private func applyContentInsets(panelWidth: CGFloat) -> (UIEdgeInsets, CGFloat, CGFloat) {
        func valid(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }
        let requested = contentInsets
        let (left, right) = fittedEdges(requested.left, requested.right, panelWidth: panelWidth)
        let insets = UIEdgeInsets(top: valid(requested.top), left: left, bottom: valid(requested.bottom), right: right)
        let textInsets = resolvedTextInsets(panelWidth: panelWidth)
        let textLeft = textInsets.left
        let textRight = textInsets.right
        for constraint in leftTextConstraints where constraint.constant != textLeft {
            constraint.constant = textLeft
        }
        for constraint in rightTextConstraints where constraint.constant != -textRight {
            constraint.constant = -textRight
        }
        if leftContentConstraint.constant != left { leftContentConstraint.constant = left }
        if rightContentConstraint.constant != -right { rightContentConstraint.constant = -right }
        let (fieldLeft, fieldRight) = (usesLegacyTextFieldLayout || usesModernAlertLayout) && configuredContentInsets == nil
            ? fittedEdges(15, 15, panelWidth: panelWidth) : (left, right)
        let fieldMargins = UIEdgeInsets(top: 0, left: fieldLeft, bottom: 0, right: fieldRight)
        if textFieldsHost.layoutMargins != fieldMargins { textFieldsHost.layoutMargins = fieldMargins }
        if usesLegacyTextFieldLayout {
            let inset = min(7.5, max(0, (panelWidth - fieldLeft - fieldRight - 1) / 2))
            let rowMargins = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
            if textFieldStack.layoutMargins != rowMargins { textFieldStack.layoutMargins = rowMargins }
        }
        let top: CGFloat
        if usesLegacyAlertLayout && !messageScrollView.isHidden { top = 0 }
        else if usesLegacySheetLayout && (!messageScrollView.isHidden || configuredContentInsets == nil) { top = 0 }
        else if usesCompactPopoverHeaderSpacing && configuredContentInsets == nil && !titleHost.isHidden
            && (embeddedBody != nil || !messageScrollView.isHidden) { top = 5 }
        else if usesModernAlertLayout && configuredContentInsets == nil && !textFieldsHost.isHidden { top = insets.top - separatorThickness }
        else { top = insets.top }
        return (insets, panelWidth - textLeft - textRight, top)
    }

    private func resolvedTextInsets(panelWidth: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let requested = usesModernAppearance && configuredContentInsets == nil
            ? (CGFloat(30), CGFloat(30)) : (contentInsets.left, contentInsets.right)
        return fittedEdges(requested.0, requested.1, panelWidth: panelWidth)
    }

    private func fittedEdges(_ left: CGFloat, _ right: CGFloat, panelWidth: CGFloat) -> (CGFloat, CGFloat) {
        // 窄窗口等比缩减左右留白，内容宽度至少保留 1 pt。
        let left = left.isFinite ? min(max(0, left), panelWidth) : 0
        let right = right.isFinite ? min(max(0, right), panelWidth) : 0
        let scale = min(1, (panelWidth - 1) / max(1, left + right))
        return (left * scale, right * scale)
    }

    private func close(using action: AlertAction?) {
        guard action?.isEnabled != false else { return }
        dismissAlert { action?.perform() }
    }

    private func dismissAlert(completion: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        // 先结束编辑，让弹窗和键盘一起退场。
        view.endEditing(true)
        dismiss(animated: true, completion: completion)
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        relayoutForKeyboard(notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect, notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        relayoutForKeyboard(nil, notification)
    }

    private func relayoutForKeyboard(_ frame: CGRect?, _ notification: Notification) {
        guard isViewLoaded, view.window != nil, !usesPopover, !isClosing else { return }
        keyboardFrame = frame
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        view.setNeedsLayout()
        UIView.animate(withDuration: duration, delay: 0, options: .beginFromCurrentState) {
            self.view.layoutIfNeeded()
        }
    }
}

@MainActor
public extension UIViewController {
    /// 先测量内容，再发起 UIKit 转场。
    func presentAlert(_ alert: AlertController, animated: Bool = true, completion: (() -> Void)? = nil) {
        alert.prepareForPresentation(from: self)
        present(alert, animated: animated, completion: completion)
    }
}

extension AlertController: UIPopoverPresentationControllerDelegate {
    public func adaptivePresentationStyle(for controller: UIPresentationController,
                                          traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finishPopoverDismissal(presentationController)
    }

    public func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        finishPopoverDismissal(popoverPresentationController)
    }

    private func finishPopoverDismissal(_ presentationController: UIPresentationController) {
        guard usesPopover, presentationController.presentedViewController === self, !isClosing else { return }
        isClosing = true
        cancelAction?.perform()
    }

    public func popoverPresentationController(_ popoverPresentationController: UIPopoverPresentationController,
                                              willRepositionPopoverTo rect: UnsafeMutablePointer<CGRect>,
                                              in view: AutoreleasingUnsafeMutablePointer<UIView>) {
        // UIKit 重新定位锚点时，按更新后的可用区域计算尺寸。
        if let presenter = presentingViewController { updatePopoverSize(in: presenter.view) }
    }
}

extension AlertController: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController,
                                       presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        AlertPresentationController(presentedViewController: presented, presenting: presenting)
    }

    public func animationController(forPresented presented: UIViewController,
                                    presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        AlertAnimator(alert: self, presenting: true)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        AlertAnimator(alert: self, presenting: false)
    }
}

private final class AlertPresentationController: UIPresentationController {
    private var previousTintAdjustment: UIView.TintAdjustmentMode?

    override var shouldRemovePresentersView: Bool { false }

    override func presentationTransitionWillBegin() {
        let view = presentingViewController.view!
        previousTintAdjustment = view.tintAdjustmentMode
        view.tintAdjustmentMode = .dimmed
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        if !completed { restoreTint() }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed { restoreTint() }
    }

    private func restoreTint() {
        if let previousTintAdjustment {
            presentingViewController.view.tintAdjustmentMode = previousTintAdjustment
            self.previousTintAdjustment = nil
        }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        if let containerView { presentedView?.frame = containerView.bounds }
    }
}

@MainActor
private final class AlertAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let alert: AlertController
    let presenting: Bool

    init(alert: AlertController, presenting: Bool) {
        self.alert = alert
        self.presenting = presenting
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval { 0.4 }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        let panel = alert.panel
        let dimming = alert.dimmingView
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let view = context.view(forKey: presenting ? .to : .from) ?? alert.view!
        let detail = alert.detailMessageLabel.superview === view ? alert.detailMessageLabel : nil
        if presenting {
            view.frame = context.finalFrame(for: alert)
            context.containerView.addSubview(view)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            alert.recordEntranceLayout()
            panel.alpha = 0
            dimming.alpha = 0
            detail?.alpha = 0
            if !reduceMotion {
                if alert.isBottomAligned {
                    let slide = CGAffineTransform(translationX: 0, y: context.containerView.bounds.maxY - panel.frame.minY)
                    panel.transform = slide
                    detail?.transform = slide
                } else {
                    panel.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }
            }
        }
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0,
                       usingSpringWithDamping: 1, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            panel.alpha = self.presenting ? 1 : 0
            dimming.alpha = self.presenting ? 1 : 0
            detail?.alpha = self.presenting ? 1 : 0
            panel.transform = .identity
            detail?.transform = .identity
        } completion: { _ in
            let cancelled = context.transitionWasCancelled
            if (!self.presenting && !cancelled) || (self.presenting && cancelled) { view.removeFromSuperview() }
            if cancelled {
                panel.alpha = 1
                dimming.alpha = 1
                detail?.alpha = 1
                panel.transform = .identity
                detail?.transform = .identity
            }
            context.completeTransition(!cancelled)
        }
    }
}
