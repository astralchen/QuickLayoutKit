import UIKit

/// 让普通 UIView 作为浮层背景。实现三个类方法提供箭头尺寸和内容边距，
/// 并在方向或偏移变化时更新绘制。填充、描边、裁剪和阴影由视图自行决定。
@MainActor
public protocol PopoverBackgroundDrawing: UIPopoverBackgroundViewMethods where Self: UIView {
    var arrowDirection: UIPopoverArrowDirection { get set }
    var arrowOffset: CGFloat { get set }
}

extension UIPopoverBackgroundView: PopoverBackgroundDrawing {
    /// UIKit 通过类创建背景视图。按呈现容器匹配当前实例，避免从另一个浮层取色。
    fileprivate var owningNativePopover: UIPopoverPresentationController? {
        var presented = window?.rootViewController?.presentedViewController
        var owner: UIPresentationController?
        while let controller = presented {
            if let presentation = controller.presentationController,
               let container = presentation.containerView, isDescendant(of: container) {
                owner = presentation
            }
            presented = controller.presentedViewController
        }
        guard let popover = owner as? UIPopoverPresentationController,
              popover.popoverBackgroundViewClass == type(of: self),
              popover.presentedViewController.viewIfLoaded.map({ !isDescendant(of: $0) }) ?? true else { return nil }
        return popover
    }
}

/// 原生浮层改变颜色时不会要求自定义背景重新布局；按当前呈现实例同步颜色。
@MainActor
final class NativePopoverFill {
    private(set) weak var controller: UIPopoverPresentationController?
    private var observation: NSKeyValueObservation?
    private var opaqueShadowOpacity: Float?

    /// UIKit 给背景层提供实心阴影路径；透明或半透明填色时避免阴影透过主体。
    func updateShadow(of view: UIPopoverBackgroundView, fill: UIColor?) {
        if (fill?.resolvedColor(with: view.traitCollection).cgColor.alpha ?? 0) < 1 {
            if view.layer.shadowOpacity > 0 {
                opaqueShadowOpacity = view.layer.shadowOpacity
                view.layer.shadowOpacity = 0
            }
        } else if let opacity = opaqueShadowOpacity {
            view.layer.shadowOpacity = opacity
            opaqueShadowOpacity = nil
        }
    }

    func bind(to view: UIPopoverBackgroundView, apply: @escaping @MainActor (UIPopoverPresentationController) -> Void) {
        let owner = view.owningNativePopover
        guard owner !== controller else { return }
        observation = nil
        controller = owner
        guard let owner else { return }
        apply(owner)
        observation = owner.observe(\.backgroundColor) { [weak self, weak owner] _, _ in
            Task { @MainActor in
                guard let owner, self?.controller === owner else { return }
                apply(owner)
            }
        }
    }
}

/// 自定义背景可以在这里读取箭头颜色、圆角和材质样式，并更新自身绘制。
@MainActor
public protocol PopoverBackgroundAppearanceProviding: AnyObject {
    func applyPopoverAppearance(from controller: PopoverPresentationController)
}

@MainActor
public protocol PopoverPresentationControllerDelegate: UIAdaptivePresentationControllerDelegate {
    func prepareForPopoverPresentation(_ popover: PopoverPresentationController)
    func popoverPresentationController(_ popover: PopoverPresentationController, willRepositionTo rect: inout CGRect, in view: inout UIView)
}

public extension PopoverPresentationControllerDelegate {
    func prepareForPopoverPresentation(_ popover: PopoverPresentationController) {}
    func popoverPresentationController(_ popover: PopoverPresentationController, willRepositionTo rect: inout CGRect, in view: inout UIView) {}
}

/// 使用 presentPopover 展示。紧凑窗口复用同一个自适应 Sheet，业务可提前配置档位。
@MainActor
open class PopoverPresentationController: UIPresentationController {
    public var popoverDelegate: (any PopoverPresentationControllerDelegate)? {
        get { delegate as? any PopoverPresentationControllerDelegate }
        set { delegate = newValue }
    }
    open var sourceView: UIView? { didSet { invalidate() } }
    open var sourceRect: CGRect = .null { didSet { invalidate() } }
    open var barButtonItem: UIBarButtonItem? {
        get { item as? UIBarButtonItem }
        set { item = newValue }
    }
    @available(iOS 16, *)
    open var sourceItem: (any UIPopoverPresentationControllerSourceItem)? {
        get { item as? any UIPopoverPresentationControllerSourceItem }
        set { item = newValue }
    }
    open var permittedArrowDirections: UIPopoverArrowDirection = .any { didSet { invalidate() } }
    open var canOverlapSourceViewRect = false { didSet { invalidate() } }
    /// 隐藏箭头时仍按候选方向放置外框，原箭头区域可用于显示内容。
    open var shouldHideArrow: Bool {
        get { hiddenArrow ?? replacingItem }
        set { hiddenArrow = newValue; invalidate() }
    }
    private var hiddenArrow: Bool?

    /// 相对于背景边缘中点的偏移。首次布局和锚点重新定位时由控制器计算。
    open var arrowOffset: CGFloat {
        get { displayedOffset }
        set {
            displayedOffset = newValue
            if let placement { bubble.apply(placement, controller: self) }
        }
    }
    private var displayedOffset: CGFloat = 0
    /// 从容器顶部向下量取，专用于背景遮罩。
    open var dimmingViewTopEdgeInset: CGFloat = 0 { didSet { invalidate() } }

    /// 单独指定箭头颜色；为空时继承主体材质和颜色。
    @NSCopying open var arrowBackgroundColor: UIColor? { didSet { invalidate() } }
    /// 浮层的背景样式。保留原始编号，供自定义背景或系统外观对照使用。
    public struct BackgroundStyle: RawRepresentable, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }

        /// 使用浮层的默认背景样式。
        public static let automatic = Self(rawValue: 0)
    }

    open var popoverBackgroundStyle: BackgroundStyle = .automatic { didSet { invalidate() } }
    #if os(iOS) && !targetEnvironment(macCatalyst)
    /// 由 UIKit 保存效果；自定义呈现负责在浮层轮廓内更新材质。
    @available(iOS 26.1, *)
    open override var backgroundEffect: UIVisualEffect? {
        didSet { invalidate() }
    }
    #endif
    /// 显式指定背景颜色时使用的模糊样式。backgroundEffect 优先。
    open var backgroundBlurEffectStyle: UIBlurEffect.Style? { didSet { invalidate() } }
    /// 隐藏模糊背景及其着色层。系统默认的玻璃背景和自定义背景类各自绘制。
    open var backgroundBlurDisabled = false { didSet { invalidate() } }

    private var explicitRadius: CGFloat = -1
    private var configuredCorners: Any?
    var hasExplicitCornerConfiguration: Bool { configuredCorners != nil }

    func backgroundRadii(for direction: UIPopoverArrowDirection) -> [CGFloat]? {
        bubble.configuredRadii(for: self, direction: direction)
    }
    /// 负值使用默认圆角。显式半径替换之前设置的逐角配置。
    open var cornerRadius: CGFloat {
        get { explicitRadius }
        set { explicitRadius = newValue; configuredCorners = nil; invalidate() }
    }
    @available(iOS 26, *)
    open var cornerConfiguration: UICornerConfiguration? {
        get { configuredCorners as? UICornerConfiguration ?? .corners(radius: .fixed(explicitRadius >= 0 ? explicitRadius : 34)) }
        set { configuredCorners = newValue; explicitRadius = -1; invalidate() }
    }

    open var passthroughViews: [UIView]? { didSet { if installed && !showsSheet { surface.accessibilityViewIsModal = passthroughViews?.isEmpty ?? true } } }
    @NSCopying open var backgroundColor: UIColor? { didSet { invalidate() } }
    open var popoverLayoutMargins: UIEdgeInsets = .zero { didSet { invalidate() } }
    /// 接受 UIKit 背景子类或遵循 PopoverBackgroundDrawing 的 UIView 类型。nil 使用默认浮层背景。
    open var popoverBackgroundViewClass: (any UIPopoverBackgroundViewMethods.Type)? { didSet { invalidate() } }
    var backgroundViewType: (any PopoverBackgroundDrawing.Type)? {
        popoverBackgroundViewClass as? any PopoverBackgroundDrawing.Type
    }
    public private(set) var arrowDirection: UIPopoverArrowDirection = .unknown
    public var adaptiveSheetPresentationController: SheetPresentationController { sheet }

    private lazy var sheet: PopoverAdaptiveSheet = {
        let controller = PopoverAdaptiveSheet(presentedViewController: presentedViewController, presenting: presentingViewController)
        controller.owner = self
        return controller
    }()
    // UIKit 在适配前后持有同一个 presentedView，内容视图在浮层和 Sheet 内部重新挂载。
    private var surface: UIView { sheet.presentedView! }
    private let bubble = PopoverSurface()
    private let backdrop = PopoverBackdrop()
    private var item: AnyObject? { didSet { invalidate() } }
    private var placement: PopoverLayout?
    private var suppliedInsets: UIEdgeInsets = .zero
    private var watcher: CADisplayLink?
    private var previousContainerBounds: CGRect?
    private var transitioning = false
    private var userDismissal = false
    private var installed = false
    private(set) var showsSheet = false
    private weak var hiddenSource: UIView?
    private var originalSourceAlpha: CGFloat = 1
    private var sourceSnapshot: UIView?
    private let keyboard = PopoverKeyboardFrame()
    private var replacingItem: Bool {
        if #available(iOS 26, *) { return item is UIBarButtonItem || item is UITabBarItem }
        return false
    }

    public override var presentedView: UIView? { surface }
    public override var frameOfPresentedViewInContainerView: CGRect {
        if showsSheet { return sheet.frameOfPresentedViewInContainerView }
        return placement?.frame ?? containerView.flatMap(makeLayout)?.frame ?? .zero
    }

    // UIKit 保留当前自定义 presentation controller，实际形态由本对象按容器环境切换。
    public override var adaptivePresentationStyle: UIModalPresentationStyle { .none }
    public override func adaptivePresentationStyle(for traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    private func wantsSheet(in container: UIView) -> Bool {
        let traits = container.traitCollection
        let style = delegate?.adaptivePresentationStyle?(for: self, traitCollection: traits)
            ?? delegate?.adaptivePresentationStyle?(for: self) ?? .automatic
        switch style {
        case .none, .popover: return false
        case .automatic: return traits.horizontalSizeClass == .compact
        default: return true
        }
    }

    private func invalidate() { containerView?.setNeedsLayout() }

    private func rect(for view: UIView, in container: UIView, rect: CGRect = .null) -> CGRect? {
        guard view.window != nil, view.window === container.window else { return nil }
        return view.convert(rect.isNull ? view.bounds : rect, to: container)
    }

    func anchor(in container: UIView) -> CGRect? {
        if #available(iOS 17, *), let frame = sourceItem?.frame(in: container),
           !frame.isNull, !frame.isInfinite, !frame.isEmpty {
            return frame
        }
        if let view = (item as? UIBarButtonItem)?.customView ?? item as? UIView,
           let frame = rect(for: view, in: container) { return frame }
        if let guide = item as? UILayoutGuide, let host = guide.owningView,
           let frame = rect(for: host, in: container, rect: guide.layoutFrame) { return frame }
        return sourceView.flatMap { rect(for: $0, in: container, rect: sourceRect) }
    }

    private func makeLayout(in container: UIView) -> PopoverLayout? {
        guard let anchor = anchor(in: container) else { return nil }
        // 常规窗口在安全区内保留水平空间；Duo 的系统侧栏单独占用窗口区域。
        var margins = popoverLayoutMargins
        margins.left = max(10, margins.left)
        margins.right = max(10, margins.right)
        var area = container.safeAreaLayoutGuide.layoutFrame.inset(by: margins)
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // 有系统侧栏时，使用侧栏内侧和窗口圆角之间的区域。收拢后的窗口边距不同。
            let bounds = container.bounds
            let sideRail = container.reservedRegions(kind: .occlusion).map(\.frame).first {
                $0.height > $0.width && $0.height < bounds.height &&
                ($0.minX <= bounds.minX || $0.maxX >= bounds.maxX) && $0.width < bounds.width / 2
            }
            if let rail = sideRail {
                let wide = bounds.width > bounds.height
                let side: CGFloat = wide ? 21 : 8
                let end: CGFloat = wide ? 21 : 25
                let left = rail.minX <= bounds.minX ? rail.maxX - bounds.minX : side
                let right = rail.maxX >= bounds.maxX ? bounds.maxX - rail.minX : side
                area = bounds.inset(by: UIEdgeInsets(top: end, left: left, bottom: end, right: right))
                    .inset(by: popoverLayoutMargins)
                // 锚点触及侧栏边界时，检查侧栏上、下方能完整容纳锚点的通宽区域。
                let meetsRail = rail.minX <= bounds.minX ? anchor.minX <= rail.maxX : anchor.maxX >= rail.minX
                if meetsRail {
                    let outer = bounds.insetBy(dx: side, dy: end)
                    for (top, bottom) in [(outer.minY, rail.minY), (rail.maxY, outer.maxY)] where bottom > top {
                        let clear = CGRect(x: outer.minX, y: top, width: outer.width, height: bottom - top)
                            .inset(by: popoverLayoutMargins)
                        if clear.contains(anchor) { area = clear; break }
                    }
                }
            }
        }
        #endif
        var keyboardTop: CGFloat?
        if let keyboardFrame = keyboard.rect(in: container), keyboardFrame.maxY >= area.maxY,
           keyboardFrame.width >= area.width * 0.8 {
            area.size.height = max(0, min(area.maxY, keyboardFrame.minY) - area.minY)
            keyboardTop = area.maxY
        }
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let divisions = container.reservedRegions(kind: .division).map { $0.frame.inset(by: $0.margins) }
            let regions = SheetRegionGeometry.regions(in: area, divisions: divisions)
            area = regions.first { $0.contains(CGPoint(x: anchor.midX, y: anchor.midY)) } ?? area
        }
        #endif
        let custom = backgroundViewType
        var layoutInsets = UIEdgeInsets.zero
        var extendsContent = false
        var usesClassicPhonePlacement = false
        if #unavailable(iOS 27) {
            extendsContent = custom == nil
            if #available(iOS 26, *), container.traitCollection.userInterfaceIdiom == .phone {
                // iOS 26 的 iPhone 四边各留 10 点，水平留白已计入上面的 margins。
                layoutInsets = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
                usesClassicPhonePlacement = true
            } else {
                layoutInsets = UIEdgeInsets(top: 30, left: 9, bottom: 10, right: 9)
            }
        }
        let preferred = presentedViewController.preferredContentSize
        return PopoverLayout(anchor: anchor, keyboardTop: keyboardTop, region: area, preferred: CGSize(width: preferred.width > 0 ? preferred.width : 320,
                                                                              height: preferred.height > 0 ? preferred.height : 320),
                             directions: replacingItem ? [] : permittedArrowDirections, overlap: canOverlapSourceViewRect,
                             hidesArrow: shouldHideArrow, extendsContent: extendsContent, usesClassicPhonePlacement: usesClassicPhonePlacement, layoutInsets: layoutInsets,
                             insets: custom?.contentViewInsets() ?? .zero,
                             arrowHeight: max(0, custom?.arrowHeight() ?? PopoverOutline.height),
                             scale: max(1, container.traitCollection.displayScale))
    }

    public override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        transitioning = true
        installed = true
        keyboard.start(owner: self)
        showsSheet = wantsSheet(in: container)
        if showsSheet { installSheet() } else { installBubble(in: container) }
    }

    private func installSheet() {
        if sheet.delegate == nil { sheet.delegate = delegate }
        delegate?.presentationController?(self, prepare: sheet)
        sheet.presentationTransitionWillBegin()
    }

    private func installBubble(in container: UIView) {
        if #available(iOS 26, *) { surface.cornerConfiguration = .corners(radius: .fixed(0)) }
        surface.clipsToBounds = false
        surface.layer.mask = nil
        surface.layer.cornerRadius = 0
        surface.backgroundColor = .clear
        surface.accessibilityViewIsModal = passthroughViews?.isEmpty ?? true
        backdrop.owner = self
        backdrop.update(in: container, topInset: dimmingViewTopEdgeInset)
        backdrop.addTarget(self, action: #selector(tapOutside), for: .touchUpInside)
        container.addSubview(backdrop)
        surface.addSubview(bubble)
        updateBubble(in: container)
    }

    private func updateBubble(in container: UIView) {
        guard let next = makeLayout(in: container) else { return }
        if placement?.offset != next.offset || placement?.anchor != next.anchor {
            displayedOffset = next.offset
        }
        placement = next
        arrowDirection = next.direction
        bubble.install(presentedViewController.view, background: backgroundViewType)
        surface.bounds = CGRect(origin: .zero, size: next.frame.size)
        surface.center = CGPoint(x: next.frame.midX, y: next.frame.midY)
        bubble.frame = surface.bounds
        bubble.apply(next, controller: self)
        // 浮层拥有独立的内容安全区，窗口侧栏和底部手势区不应再次挤压内容。
        let content = next.content.offsetBy(dx: next.frame.minX, dy: next.frame.minY)
        let safe = container.safeAreaLayoutGuide.layoutFrame
        var insets = next.contentSafeArea
        insets.top -= min(content.height, max(0, safe.minY - content.minY))
        insets.bottom -= min(content.height, max(0, content.maxY - safe.maxY))
        insets.left -= min(content.width, max(0, safe.minX - content.minX))
        insets.right -= min(content.width, max(0, content.maxX - safe.maxX))
        updateContentSafeArea(insets)
    }

    public override func presentationTransitionDidEnd(_ completed: Bool) {
        transitioning = false
        if showsSheet { sheet.presentationTransitionDidEnd(completed) }
        else if completed { hideSource() }
        guard completed else { finish(); return }
        let link = CADisplayLink(target: PopoverAnchorObserver(self), selector: #selector(PopoverAnchorObserver.tick))
        link.add(to: .main, forMode: .common)
        watcher = link
        previousContainerBounds = containerView?.bounds
        invalidate()
    }

    fileprivate func checkAnchor() {
        guard !transitioning, !showsSheet, let container = containerView else { return }
        if let rect = anchor(in: container), rect != placement?.anchor { invalidate() }
    }

    public override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        invalidate()
    }

    public override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        guard installed, !transitioning, let container = containerView else { return }
        if let previousContainerBounds, previousContainerBounds != container.bounds, var view = sourceView {
            var rect = sourceRect
            popoverDelegate?.popoverPresentationController(self, willRepositionTo: &rect, in: &view)
            if sourceView !== view { sourceView = view }
            if sourceRect != rect { sourceRect = rect }
        }
        previousContainerBounds = container.bounds
        let adapt = wantsSheet(in: container)
        if adapt != showsSheet {
            if showsSheet {
                sheet.tearDown()
                showsSheet = false
                installBubble(in: container)
            } else {
                restoreSource()
                removeBubble()
                showsSheet = true
                arrowDirection = .unknown
                installSheet()
                sheet.presentationTransitionDidEnd(true)
            }
            container.addSubview(surface)
            if !showsSheet { hideSource() }
        }
        if showsSheet { sheet.containerViewWillLayoutSubviews() }
        else { backdrop.update(in: container, topInset: dimmingViewTopEdgeInset); updateBubble(in: container) }
    }

    @objc private func tapOutside() {
        guard !transitioning, !userDismissal else { return }
        guard !presentedViewController.isModalInPresentation, delegate?.presentationControllerShouldDismiss?(self) ?? true else {
            delegate?.presentationControllerDidAttemptToDismiss?(self)
            return
        }
        userDismissal = true
        delegate?.presentationControllerWillDismiss?(self)
        presentedViewController.dismiss(animated: true)
    }

    public override func dismissalTransitionWillBegin() {
        transitioning = true
        if showsSheet { sheet.dismissalTransitionWillBegin() }
    }

    public override func dismissalTransitionDidEnd(_ completed: Bool) {
        if showsSheet { sheet.dismissalTransitionDidEnd(completed) }
        transitioning = false
        if completed {
            finish()
            if userDismissal { delegate?.presentationControllerDidDismiss?(self) }
        } else { invalidate() }
        userDismissal = false
    }

    // 只撤销本控制器提供的安全区，保留内容控制器在展示期间自行设置的边距。
    private func updateContentSafeArea(_ next: UIEdgeInsets) {
        guard next != suppliedInsets else { return }
        var current = presentedViewController.additionalSafeAreaInsets
        current.top += next.top - suppliedInsets.top
        current.left += next.left - suppliedInsets.left
        current.bottom += next.bottom - suppliedInsets.bottom
        current.right += next.right - suppliedInsets.right
        suppliedInsets = next
        presentedViewController.additionalSafeAreaInsets = current
    }

    private func removeBubble() {
        placement = nil
        updateContentSafeArea(.zero)
        backdrop.removeTarget(self, action: #selector(tapOutside), for: .touchUpInside)
        backdrop.removeFromSuperview()
        bubble.removeFromSuperview()
    }

    private func finish() {
        installed = false
        watcher?.invalidate()
        watcher = nil
        keyboard.stop()
        restoreSource()
        sourceSnapshot?.removeFromSuperview()
        sourceSnapshot = nil
        removeBubble()
        presentedViewController.viewIfLoaded?.removeFromSuperview()
        surface.removeFromSuperview()
        arrowDirection = .unknown
        presentedViewController.releasePopoverTransition(self)
    }

    private var sourceVisual: UIView? {
        guard replacingItem else { return nil }
        if let custom = (item as? UIBarButtonItem)?.customView { return custom }
        guard let sourceView, sourceRect.isNull, let container = containerView,
              let fallback = rect(for: sourceView, in: container), fallback == placement?.anchor,
              !(sourceView is UINavigationBar), !(sourceView is UIToolbar), !(sourceView is UITabBar) else { return nil }
        return sourceView
    }

    private func hideSource() {
        guard hiddenSource == nil, let view = sourceVisual, view.window != nil,
              view !== presentingViewController.view, !presentingViewController.view.isDescendant(of: view) else { return }
        originalSourceAlpha = view.alpha
        hiddenSource = view
        view.alpha = 0
    }

    private func restoreSource() {
        hiddenSource?.alpha = originalSourceAlpha
        hiddenSource = nil
    }

    func duration(presenting: Bool) -> TimeInterval {
        if showsSheet { return SheetAnimator.duration }
        return presenting ? 0.5 : 0.25
    }

    func animate(using context: any UIViewControllerContextTransitioning, presenting: Bool) {
        if showsSheet { sheet.animate(using: context, presenting: presenting); return }
        let container = context.containerView
        if presenting {
            container.addSubview(surface)
            updateBubble(in: container)
            surface.layoutIfNeeded()
        }
        guard let placement else { context.completeTransition(false); return }
        let source = anchor(in: container) ?? placement.anchor
        let visibleCenter = surface.center
        let reduced = UIAccessibility.isReduceMotionEnabled
        let scaleX = replacingItem ? min(1, max(0.02, source.width / max(1, placement.frame.width))) : 0.01
        let scaleY = replacingItem ? min(1, max(0.02, source.height / max(1, placement.frame.height))) : 0.01
        var pivot = CGPoint(x: source.midX, y: source.midY)
        switch placement.direction {
        case .up: pivot.y = placement.frame.minY
        case .down: pivot.y = placement.frame.maxY
        case .left: pivot.x = placement.frame.minX
        case .right: pivot.x = placement.frame.maxX
        default: break
        }
        let amountX = replacingItem ? 1 : 1-scaleX, amountY = replacingItem ? 1 : 1-scaleY
        let collapsed = CGPoint(x: visibleCenter.x + (pivot.x-visibleCenter.x)*amountX,
                                y: visibleCenter.y + (pivot.y-visibleCenter.y)*amountY)
        func apply(visible: Bool) {
            surface.alpha = visible ? 1 : 0
            surface.center = visible || reduced ? visibleCenter : collapsed
            surface.transform = visible || reduced ? .identity : CGAffineTransform(scaleX: scaleX, y: scaleY)
        }
        // 标准栏按钮仅公开位置时，从呈现视图截取该区域；自定义按钮优先使用自身快照。
        if replacingItem && context.isAnimated && !reduced {
            if presenting {
                let host = presentingViewController.view!
                sourceSnapshot = sourceVisual?.snapshotView(afterScreenUpdates: false)
                    ?? host.resizableSnapshotView(from: host.convert(source, from: container),
                                                  afterScreenUpdates: false, withCapInsets: .zero)
                sourceSnapshot?.isUserInteractionEnabled = false
                sourceSnapshot?.accessibilityElementsHidden = true
            }
            if let snapshot = sourceSnapshot {
                snapshot.frame = source
                snapshot.alpha = presenting ? 1 : 0
                container.addSubview(snapshot)
            }
        }
        if presenting { apply(visible: false); hideSource() }
        func change() {
            apply(visible: presenting)
            sourceSnapshot?.alpha = presenting ? 0 : 1
        }
        let completion: (Bool) -> Void = { [self] _ in
            sourceSnapshot?.removeFromSuperview()
            let success = !context.transitionWasCancelled
            if !presenting && success || presenting && !success { restoreSource() }
            surface.transform = .identity
            surface.center = visibleCenter
            surface.alpha = 1
            context.completeTransition(success)
        }
        guard context.isAnimated else { apply(visible: presenting); completion(true); return }
        if presenting && !reduced {
            UIView.animate(withDuration: duration(presenting: true), delay: 0, usingSpringWithDamping: 0.81,
                           initialSpringVelocity: 0, options: [.allowUserInteraction],
                           animations: change, completion: completion)
            return
        }
        UIView.animate(withDuration: duration(presenting: presenting), delay: 0,
                       options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                       animations: change, completion: completion)
    }
}

@MainActor
private final class PopoverAdaptiveSheet: SheetPresentationController {
    weak var owner: PopoverPresentationController?
    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 26.1, *)
    override var backgroundEffect: UIVisualEffect? {
        get { super.backgroundEffect ?? owner?.backgroundEffect }
        set { super.backgroundEffect = newValue }
    }
    #endif
    override var containerView: UIView? {
        guard let owner, owner.showsSheet else { return nil }
        return owner.containerView
    }
}

@MainActor
private final class PopoverAnchorObserver: NSObject {
    weak var popover: PopoverPresentationController?
    init(_ popover: PopoverPresentationController) { self.popover = popover }
    @objc func tick(_ link: CADisplayLink) {
        guard let popover else { link.invalidate(); return }
        popover.checkAnchor()
    }
}

@MainActor
private final class PopoverKeyboardFrame: NSObject {
    private weak var owner: PopoverPresentationController?
    private var frame: CGRect?
    func start(owner: PopoverPresentationController) {
        self.owner = owner
        NotificationCenter.default.addObserver(self, selector: #selector(change(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(change(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    @objc private func change(_ note: Notification) {
        if let screen = note.object as? UIScreen, screen !== owner?.containerView?.window?.screen { return }
        frame = note.name == UIResponder.keyboardWillHideNotification ? nil : note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        owner?.containerView?.setNeedsLayout()
    }
    func rect(in container: UIView) -> CGRect? {
        guard let frame, let screen = container.window?.screen else { return nil }
        return container.convert(frame, from: screen.coordinateSpace)
    }
    func stop() { NotificationCenter.default.removeObserver(self) }
}
