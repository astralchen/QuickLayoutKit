import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 可嵌入任意宿主区域的自适应非模态面板。
///
/// 使用 `show(in:containerView:animated:)` 建立父子控制器关系。宿主负责持有面板，
/// 面板负责内容控制器的生命周期、档位、手势及安全区布局。
@MainActor
public final class AdaptivePanelController: UIViewController {
    public typealias Detent = AdaptivePanelDetent
    public enum Placement: Sendable { case automatic, leading, center, trailing }
    public enum ChangeReason: Sendable { case programmatic, interaction, environment }
    public enum SafeAreaSource: Sendable { case container, window }

    public let contentViewController: UIViewController
    public var detents: [Detent] = [.large()] { didSet { invalidateDetents() } }
    public var selectedDetentIdentifier: Detent.Identifier? { didSet { invalidateDetents() } }
    /// nil 表示所有档位均可操作背景；设置标识后，仅该档位及更低档位允许操作背景。
    public var largestUndimmedDetentIdentifier: Detent.Identifier? { didSet { invalidateDetents() } }
    public var prefersScrollingExpandsWhenScrolledToEdge = true
    public var prefersGrabberVisible = true { didSet { invalidateDetents() } }
    public var preferredCornerRadius: CGFloat = 24 { didSet { invalidateDetents() } }
    public var preferredPlacement: Placement = .automatic { didSet { invalidateDetents() } }
    public weak var sourceView: UIView? { didSet { invalidateDetents() } }
    /// 默认尊重宿主安全区；覆盖导航栏或标签栏的页面浮层可选择窗口安全区。
    /// 窗口安全区仍会裁切到实际宿主 bounds，不会突破局部容器。
    public var safeAreaSource: SafeAreaSource = .container { didSet { invalidateDetents() } }
    /// 页面模式跟随宿主可读宽度；关闭后优先使用内容控制器声明的尺寸。
    public var prefersPageSizing = true { didSet { invalidateDetents() } }
    public var prefersEdgeAttachedInCompactHeight = true { didSet { invalidateDetents() } }
    public var widthFollowsPreferredContentSizeWhenEdgeAttached = false { didSet { invalidateDetents() } }
    public var allowsInteractiveDismissal = true
    public var dismissesOnBackdropTap = true
    public var avoidsKeyboard = true { didSet { invalidateDetents() } }
    /// 可显式指定需要联动的滚动视图；默认使用触摸位置最近的纵向滚动视图。
    public weak var trackingScrollView: UIScrollView?
    public var shouldDismiss: (() -> Bool)?
    public var onDismissAttempt: (() -> Void)?
    public var onDismiss: (() -> Void)?
    public var onSelectedDetentChange: ((Detent.Identifier, ChangeReason) -> Void)?
    public var onGeometryChange: ((CGRect, AdaptivePanelContext) -> Void)?
    public private(set) var context: AdaptivePanelContext?
    /// 面板的外部边界，使用宿主坐标，包含贴底时的安全区。
    public var panelFrame: CGRect { isViewLoaded ? surface.frame : .zero }

    let surface = AdaptivePanelSurface()
    let grabberArea = AdaptivePanelGrabber()
    let backdrop = UIControl()
    lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    var resolvedDetents: [(identifier: Detent.Identifier, height: CGFloat)] = []
    var interactiveHeight: CGFloat?
    var currentHeight: CGFloat = 0
    var draggingPanel = false
    weak var gestureScrollView: UIScrollView?
    var previousTranslation: CGFloat = 0
    var scrollStartOffset: CGFloat = 0
    var gestureStartIdentifier: Detent.Identifier?
    private var transition: UIViewPropertyAnimator?
    private(set) var isDismissing = false
    private var changeReason = ChangeReason.programmatic
    private var effectiveIdentifier: Detent.Identifier?
    private var didRotateWhilePresented = false
    private var keyboardFrameInScreen: CGRect?
    private var hingeAngle: CGFloat?
    private var hingeState = AdaptivePanelContext.HingeState.unavailable
    private var previousReportedFrame: CGRect?
    private var previousReportedAngle: CGFloat?
    private var previousReportedRegion: CGRect?
    // 浮层边缘留白属于外观参数，不是设备尺寸。新建 UIView 的默认边距会随环境变为 0，
    // 因此不从尚未入窗的临时视图读取；宽高仍由当前容器、安全区和可读区域求解。
    private let floatingMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    public init(contentViewController: UIViewController) {
        precondition(contentViewController.parent == nil, "面板内容已经属于其他父控制器")
        self.contentViewController = contentViewController
        super.init(nibName: nil, bundle: nil)
    }

    /// 普通视图也可作为面板内容，组件内部建立轻量控制器承载它。
    public convenience init(contentView: UIView) {
        let controller = UIViewController()
        controller.view = contentView
        self.init(contentViewController: controller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("请使用内容初始化器") }

    public override func loadView() {
        let overlay = AdaptivePanelOverlay()
        overlay.panel = self
        view = overlay
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        backdrop.addTarget(self, action: #selector(backdropTapped), for: .touchUpInside)
        view.addSubview(backdrop)
        surface.backgroundColor = .secondarySystemGroupedBackground
        surface.layer.cornerCurve = .continuous
        surface.clipsToBounds = true
        surface.accessibilityIdentifier = "adaptivePanel.surface"
        view.addSubview(surface)
        surface.grabber = grabberArea
        grabberArea.accessibilityLabel = NSLocalizedString("调整面板高度", comment: "面板把手的辅助功能名称")
        grabberArea.accessibilityIdentifier = "adaptivePanel.grabber"
        grabberArea.adjust = { [weak self] increase in self?.accessibilityAdjust(increase: increase) }
        addChild(contentViewController)
        surface.content = contentViewController.view
        surface.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)
        pan.delegate = self
        pan.cancelsTouchesInView = false
        surface.addGestureRecognizer(pan)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                hingeAngle = update.hinge?.angle
                if let hinge = update.hinge {
                    switch hinge.status {
                    case .closed: hingeState = .closed
                    case .partiallyOpen: hingeState = .partiallyOpen
                    case .fullyOpen: hingeState = .fullyOpen
                    case .unknown: hingeState = .unknown
                    @unknown default: hingeState = .unknown
                    }
                } else {
                    hingeState = .unavailable
                }
                environmentChanged()
            })
        }
        #endif
    }

    /// containerView 必须位于 parent 的视图层级中；省略时覆盖 parent.view。
    public func show(in parent: UIViewController, containerView: UIView? = nil, animated: Bool = true) {
        guard self.parent == nil else { return }
        let container = containerView ?? parent.view!
        precondition(container === parent.view || container.isDescendant(of: parent.view), "宿主区域必须属于父控制器")
        isDismissing = false
        didRotateWhilePresented = false
        parent.addChild(self)
        view.frame = container.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(view)
        didMove(toParent: parent)
        view.layoutIfNeeded()
        beginAppearanceTransition(true, animated: animated)
        if animated {
            surface.transform = CGAffineTransform(translationX: 0, y: view.bounds.maxY - surface.frame.minY)
            backdrop.alpha = 0
        }
        runTransition(animated: animated, animations: {
            self.surface.transform = .identity
            self.backdrop.alpha = 1
        }) { self.endAppearanceTransition() }
    }

    public override func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard parent != nil, !isDismissing else { completion?(); return }
        finishTransition()
        isDismissing = true
        pan.isEnabled = false
        view.endEditing(true)
        willMove(toParent: nil)
        beginAppearanceTransition(false, animated: animated)
        runTransition(animated: animated, animations: {
            self.surface.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height + 1)
            self.backdrop.alpha = 0
        }) {
            self.endAppearanceTransition()
            self.view.removeFromSuperview()
            self.removeFromParent()
            self.surface.transform = .identity
            self.interactiveHeight = nil
            self.keyboardFrameInScreen = nil
            self.isDismissing = false
            self.pan.isEnabled = true
            self.onDismiss?()
            completion?()
        }
    }

    public func invalidateDetents() { viewIfLoaded?.setNeedsLayout() }

    public func animateChanges(_ changes: () -> Void) {
        loadViewIfNeeded()
        view.layoutIfNeeded()
        changes()
        UIView.animate(withDuration: 0.3, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    public func selectDetent(_ identifier: Detent.Identifier, animated: Bool = true) {
        if animated {
            animateChanges {
                self.changeReason = .programmatic
                self.interactiveHeight = nil
                self.selectedDetentIdentifier = identifier
            }
        } else {
            changeReason = .programmatic
            interactiveHeight = nil
            selectedDetentIdentifier = identifier
            viewIfLoaded?.layoutIfNeeded()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPanel()
    }

    public override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // 旋转带有旋转变换，单纯拖动 iPad 窗口边角不会改变页面的呈现策略。
        let transform = coordinator.targetTransform
        guard parent != nil, abs(transform.b) > 0.5 || transform.a < 0 else { return }
        let previous = didRotateWhilePresented
        didRotateWhilePresented = true
        coordinator.animate(alongsideTransition: { _ in self.invalidateDetents() }) { context in
            if context.isCancelled { self.didRotateWhilePresented = previous }
            self.environmentChanged()
        }
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        environmentChanged()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        environmentChanged()
    }

    public override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        invalidateDetents()
    }

    private func environmentChanged() {
        changeReason = .environment
        invalidateDetents()
    }

    private func layoutPanel() {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        backdrop.frame = view.bounds
        var safe = view.bounds.inset(by: view.safeAreaInsets)
        if let window = view.window {
            if safeAreaSource == .window {
                safe = view.bounds.intersection(view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window))
            } else {
                safe = safe.intersection(view.convert(window.bounds, from: window))
            }
        }
        guard !safe.isNull, safe.width > 0, safe.height > 0 else { return }
        let compactHeight = traitCollection.verticalSizeClass == .compact
        let foldedPage = prefersPageSizing && hingeState == .closed
        let safeInsets = UIEdgeInsets(top: safe.minY - view.bounds.minY, left: safe.minX - view.bounds.minX,
                                      bottom: view.bounds.maxY - safe.maxY, right: view.bounds.maxX - safe.maxX)
        if foldedPage, safeAreaSource == .window {
            // 闭合外屏的页面浮层横向覆盖系统侧栏；局部宿主仍受自身 bounds 限制。
            // 仅窗口页面采用该策略，普通手机贴边面板与局部容器继续尊重完整安全区。
            let visible = view.window.map { view.bounds.intersection(view.convert($0.bounds, from: $0)) } ?? view.bounds
            safe.origin.x = visible.minX
            safe.size.width = visible.width
        }
        var divisions: [CGRect] = []
        var layoutDivisions: [CGRect] = []
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // 系统 frame 已包含交互内容边距。面板自身有边缘留白，分区只使用实际分隔范围，
            // 避免把铰链两侧的建议边距重复扣除；零宽或零高仍表示有效分隔线。
            let reserved = view.reservedRegions(kind: .division)
            // 展开纵屏的系统 medium 仍参考物理分隔位置；横向布局只使用当前活动分隔。
            divisions = view.reservedRegions(kind: .division, options: .includeInactive).map(\.frame)
            layoutDivisions = reserved.map { $0.frame.inset(by: $0.margins) }
            // 页面模式的横向折叠只限制 medium，large 和自定义档位仍可使用完整容器。
            // 竖向折叠则将整个面板放入单侧区域。
            if prefersPageSizing { layoutDivisions = layoutDivisions.filter { $0.height > $0.width } }
        }
        #endif
        var region = selectedRegion(AdaptivePanelContext.regions(in: safe, divisions: layoutDivisions)) ?? safe
        let originalBottom = region.maxY
        let floating = traitCollection.horizontalSizeClass == .regular && !compactHeight
        // Duo 内屏页面在编辑时沿用无键盘的档位上下文，仅将显示外框临时展开。
        let innerPhonePage = prefersPageSizing && floating && traitCollection.userInterfaceIdiom == .phone
            && (hingeState == .partiallyOpen || hingeState == .fullyOpen)
        var expandsForEditing = false
        if avoidsKeyboard, let keyboardFrameInScreen, let window = view.window {
            let keyboard = view.convert(window.convert(keyboardFrameInScreen, from: window.screen.coordinateSpace), from: window)
            let intersection = region.intersection(keyboard)
            if !intersection.isNull, intersection.width >= region.width * 0.5,
               keyboard.maxY >= region.maxY - 1 {
                if innerPhonePage, containsFirstResponder(contentViewController.view) {
                    expandsForEditing = true
                } else {
                    region.size.height = max(1, keyboard.minY - region.minY)
                }
            }
        }
        // readableContentGuide 表达的是正文宽度，页面外框还包含正文两侧边距。
        let readableWidth = view.readableContentGuide.layoutFrame.width
        let readablePageWidth = readableWidth > 0 ? readableWidth + view.layoutMargins.left + view.layoutMargins.right : region.width
        // regular/regular 的手机 Sheet 仍以底部为锚点，并包含底部安全区。
        let phonePage = (floating || foldedPage) && prefersPageSizing && traitCollection.userInterfaceIdiom == .phone
        let fillsRegion = traitCollection.verticalSizeClass == .regular && !phonePage
            && (!floating || (!phonePage && prefersPageSizing && readablePageWidth >= region.width))
        let insetPage: Bool
        if #available(iOS 27.0, *) { insetPage = fillsRegion } else { insetPage = false }
        let bottomInset = (!floating || phonePage || insetPage) && abs(region.maxY - safe.maxY) < 1 && region.maxY == originalBottom
            ? safeInsets.bottom : 0
        // 使用容器提供的布局边距，窗口、文字尺寸或容器变化后重新计算。
        // layoutMargins 可能已包含安全区，region 已扣除安全区，不能再次扣除它。
        let margin: CGFloat = insetPage ? 0 : phonePage ? floatingMargins.bottom : floating && !prefersPageSizing ? min(max(0, view.layoutMargins.left - view.safeAreaInsets.left),
                                            max(0, view.layoutMargins.right - view.safeAreaInsets.right)) : 0
        // 无顶部安全区的展开横屏需要浮层顶边留白；已有状态栏安全区时不再重复扣除。
        var maximum = max(1, region.height - (phonePage ? max(0, margin - safeInsets.top) : margin * 2))
        // iPadOS 27.2 的窗口级 page sheet 在打开后旋转会为最大档保留额外顶距。
        // 44 pt 是该呈现路径的实测留白，面板宽高仍由当前容器、档位和安全区求解。
        if #available(iOS 27.2, *), didRotateWhilePresented, prefersPageSizing, floating,
           traitCollection.userInterfaceIdiom == .pad, let window = view.window,
           view.convert(view.bounds, to: window).equalTo(window.bounds) {
            // 宿主可能已通过导航栏等安全区留出顶距，只扣除尚未包含的部分。
            let windowSafeTop = view.convert(window.safeAreaLayoutGuide.layoutFrame, from: window).minY
            let remainingClearance = max(0, windowSafeTop + 44 - region.minY)
            maximum = max(1, maximum - remainingClearance)
        }
        if floating, !prefersPageSizing, contentViewController.preferredContentSize.height > 0 {
            maximum = min(maximum, contentViewController.preferredContentSize.height)
        }
        var context = AdaptivePanelContext(containerBounds: view.bounds, availableRegion: region,
            divisionRegions: divisions, containerTraitCollection: traitCollection, maximumDetentValue: maximum,
            hingeAngle: hingeAngle, hingeState: hingeState)
        context.safeAreaInsets = safeInsets
        self.context = context
        var seen = Set<Detent.Identifier>()
        resolvedDetents = detents.compactMap { detent in
            guard seen.insert(detent.identifier).inserted, let height = detent.resolvedValue(in: context) else { return nil }
            return (detent.identifier, height)
        }.sorted { $0.height < $1.height }
        // 配置为空或全部停用时，提供可见的最大档位，确保用户仍可操作和关闭内容。
        if resolvedDetents.isEmpty { resolvedDetents = [(.large, maximum)] }
        let selected = resolvedDetents.first { $0.identifier == selectedDetentIdentifier } ?? resolvedDetents[0]
        let previous = effectiveIdentifier
        effectiveIdentifier = selected.identifier
        if selectedDetentIdentifier != selected.identifier { selectedDetentIdentifier = selected.identifier }
        var height = interactiveHeight ?? (expandsForEditing ? maximum : selected.height)
        if compactHeight && !prefersEdgeAttachedInCompactHeight { height = maximum }
        height = min(maximum, max(1, height))
        currentHeight = height
        var width = region.width
        if floating || phonePage || (widthFollowsPreferredContentSizeWhenEdgeAttached && compactHeight) {
            let preferredWidth = contentViewController.preferredContentSize.width
            var automaticWidth = readablePageWidth
            if phonePage {
                // 手机展开后可变成 regular/regular；页面宽度还需受容器短边限制。
                // 使用容器而非 UIScreen，支持子容器、旋转与窗口缩放。
                automaticWidth = foldedPage ? region.width - floatingMargins.left - floatingMargins.right
                    : min(automaticWidth, min(view.bounds.width, view.bounds.height) - floatingMargins.left - floatingMargins.right)
            }
            let target = preferredWidth > 0 && (!floating || !prefersPageSizing) ? preferredWidth : automaticWidth
            width = min(max(1, region.width - margin * 2), max(1, target))
        }
        var x = horizontalOrigin(width: width, region: region, margin: margin)
        if phonePage, sourceView == nil, preferredPlacement == .automatic || preferredPlacement == .center {
            x = min(region.maxX - margin - width, max(region.minX + margin, view.bounds.midX - width * 0.5))
        }
        // 浮动面板以最大档位的底边为锚点，切档时保持底边和两侧边缘稳定。
        var floatingCenterY = region.midY
        if floating, let sourceView, sourceView.window === view.window {
            let point = sourceView.convert(CGPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY), to: view)
            floatingCenterY = min(region.maxY - margin - maximum * 0.5,
                                  max(region.minY + margin + maximum * 0.5, point.y))
        }
        let mediumHeight = Detent.medium().resolvedValue(in: context) ?? maximum * 0.5
        let pageInsetFraction = min(1, max(0, (maximum - height) / max(1, maximum - mediumHeight)))
        var y = phonePage ? region.maxY - margin * pageInsetFraction - height
            : floating && !prefersPageSizing ? floatingCenterY + maximum * 0.5 - height : region.maxY - height
        var displayHeight = height + bottomInset
        if insetPage {
            // 小档位卡片保留容器边缘留白；升到最大档位时连续展开到容器宽度。
            // 档位解析仍使用逻辑内容高度，外框报告缩放后的实际显示尺寸。
            let inset = min(floatingMargins.left, width * 0.25) * pageInsetFraction
            let scale = max(0, (width - inset * 2) / width)
            x += inset
            width *= scale
            displayHeight *= scale
            y = region.maxY + bottomInset - inset - displayHeight
        } else if #available(iOS 27.0, *), compactHeight, !phonePage, prefersEdgeAttachedInCompactHeight {
            // 紧凑高度保持安全区宽度，小档位仍与底边分离，最大档位填满高度。
            let minimum = resolvedDetents.first?.height ?? maximum
            let fraction = min(1, max(0, (maximum - height) / max(1, maximum - minimum)))
            y -= floatingMargins.bottom * fraction
        }
        if phonePage {
            // 展开手机的浮层不进行整页缩放，按当前显示比例对齐物理像素。
            let scale = max(1, traitCollection.displayScale)
            x = (x * scale).rounded() / scale
            y = (y * scale).rounded() / scale
            width = (width * scale).rounded() / scale
            displayHeight = (displayHeight * scale).rounded() / scale
        }
        // 动画期间使用 bounds/center 更新，避免带 transform 的 frame 参与计算。
        surface.bounds = CGRect(x: 0, y: 0, width: width, height: displayHeight)
        surface.center = CGPoint(x: x + width * 0.5, y: y + displayHeight * 0.5)
        surface.layer.cornerRadius = max(0, preferredCornerRadius)
        surface.layer.borderWidth = 1 / max(1, traitCollection.displayScale)
        surface.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).withAlphaComponent(0.2).cgColor
        surface.layer.maskedCorners = floating || phonePage || insetPage ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let grabberHeight: CGFloat = prefersGrabberVisible ? min(24, height) : 0
        grabberArea.isHidden = !prefersGrabberVisible
        surface.grabberHeight = grabberHeight
        // 内屏的原生 Sheet 允许列表延伸至键盘背后，底部输入附件可使用内容视图的 keyboardLayoutGuide。
        surface.expandsForEditing = expandsForEditing
        grabberArea.accessibilityValue = selected.identifier.rawValue
        surface.setNeedsLayout()
        let threshold = resolvedDetents.first { $0.identifier == largestUndimmedDetentIdentifier }?.height
        let interactionHeight = expandsForEditing ? selected.height : height
        backdrop.isHidden = largestUndimmedDetentIdentifier == nil || (threshold.map { interactionHeight <= $0 + 0.5 } ?? false)
        surface.accessibilityViewIsModal = !backdrop.isHidden
        if previous != selected.identifier {
            onSelectedDetentChange?(selected.identifier, changeReason)
        }
        changeReason = .programmatic
        let frame = CGRect(x: x, y: y, width: width, height: displayHeight)
        if previousReportedFrame != frame || previousReportedAngle != hingeAngle || previousReportedRegion != region {
            previousReportedFrame = frame
            previousReportedAngle = hingeAngle
            previousReportedRegion = region
            onGeometryChange?(frame, context)
        }
    }

    private func selectedRegion(_ regions: [CGRect]) -> CGRect? {
        if let sourceView, sourceView.window === view.window {
            let point = sourceView.convert(CGPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY), to: view)
            if let region = regions.first(where: { $0.contains(point) }) { return region }
        }
        let leading = preferredPlacement != .trailing
        let preferLeft = leading != (view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        return regions.sorted {
            if abs($0.midY - $1.midY) > 1 { return $0.midY > $1.midY }
            // 自动位置优先容纳空间较大的单侧，避免被侧边系统栏压缩。
            if preferredPlacement == .automatic, abs($0.width - $1.width) > 1 { return $0.width > $1.width }
            return preferLeft ? $0.midX < $1.midX : $0.midX > $1.midX
        }.first
    }

    private func horizontalOrigin(width: CGFloat, region: CGRect, margin: CGFloat) -> CGFloat {
        if let sourceView, sourceView.window === view.window {
            let center = sourceView.convert(CGPoint(x: sourceView.bounds.midX, y: sourceView.bounds.midY), to: view)
            return min(region.maxX - margin - width, max(region.minX + margin, center.x - width * 0.5))
        }
        let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        switch preferredPlacement {
        case .leading: return rtl ? region.maxX - margin - width : region.minX + margin
        case .trailing: return rtl ? region.minX + margin : region.maxX - margin - width
        case .automatic, .center: return region.midX - width * 0.5
        }
    }

    private func containsFirstResponder(_ root: UIView) -> Bool {
        root.isFirstResponder || root.subviews.contains(where: containsFirstResponder)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard parent != nil, let info = notification.userInfo else { return }
        keyboardFrameInScreen = notification.name == UIResponder.keyboardWillHideNotification ? nil
            : (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        environmentChanged()
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, UIView.AnimationOptions(rawValue: curve << 16)]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func backdropTapped() {
        if dismissesOnBackdropTap { attemptDismiss() }
    }

    func attemptDismiss() {
        guard allowsInteractiveDismissal, shouldDismiss?() != false else {
            onDismissAttempt?()
            settle(to: selectedDetentIdentifier, reason: .interaction)
            return
        }
        dismiss()
    }

    func settle(to identifier: Detent.Identifier?, reason: ChangeReason) {
        animateChanges {
            self.changeReason = reason
            self.interactiveHeight = nil
            self.selectedDetentIdentifier = identifier
            self.invalidateDetents()
        }
    }

    public override func accessibilityPerformEscape() -> Bool {
        guard allowsInteractiveDismissal else { return false }
        attemptDismiss()
        return true
    }

    private func finishTransition() {
        guard let transition else { return }
        if transition.state == .active {
            transition.stopAnimation(false)
            transition.finishAnimation(at: .end)
        }
        self.transition = nil
    }

    private func runTransition(animated: Bool, animations: @escaping () -> Void, completion: @escaping () -> Void) {
        guard animated else { animations(); completion(); return }
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1, animations: animations)
        transition = animator
        animator.addCompletion { [weak self] _ in
            self?.transition = nil
            completion()
        }
        animator.startAnimation()
    }
}

/// 面板内部排版交由 QuickLayout；控制器仅提供交互求解后的外部几何。
final class AdaptivePanelSurface: QuickLayoutView {
    var grabber: UIView?
    var content: UIView?
    var grabberHeight: CGFloat = 24
    var expandsForEditing = false

    override var body: Layout {
        // 旋转途中键盘边界可能暂时改变；始终保持相同的子视图顺序，只更新内边距。
        // 编辑时把手叠放在顶端，普通状态为内容预留把手高度。
        return ZStack(alignment: .top) {
            if let content {
                content.resizable().padding(.top, expandsForEditing ? 0 : grabberHeight)
            }
            if let grabber {
                grabber.resizable().frame(width: expandsForEditing ? 44 : nil, height: grabberHeight)
            }
        }.ignoresSafeArea()
    }
}

private final class AdaptivePanelOverlay: UIView {
    weak var panel: AdaptivePanelController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let panel, !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        let surfacePoint = panel.surface.convert(point, from: self)
        if let hit = panel.surface.hitTest(surfacePoint, with: event) { return hit }
        return panel.backdrop.isHidden ? nil : panel.backdrop.hitTest(point, with: event)
    }
}

final class AdaptivePanelGrabber: UIView {
    var adjust: ((Bool) -> Void)?
    private let indicator = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = [.adjustable]
        indicator.backgroundColor = .tertiaryLabel
        indicator.layer.cornerRadius = 2.5
        addSubview(indicator)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("请使用 frame 初始化器") }
    override func layoutSubviews() {
        super.layoutSubviews()
        indicator.frame = CGRect(x: (bounds.width - 36) * 0.5, y: (bounds.height - 5) * 0.5, width: 36, height: 5)
    }
    override func accessibilityIncrement() { adjust?(true) }
    override func accessibilityDecrement() { adjust?(false) }
}
