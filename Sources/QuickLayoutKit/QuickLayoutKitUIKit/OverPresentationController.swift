import UIKit

/// 解析侧栏宽度档位时，呈现容器与内容控制器提供的布局信息。
@MainActor
@objc public protocol OverPresentationControllerDetentResolutionContext: NSObjectProtocol {
    var containerSize: CGSize { get }
    var containerTraitCollection: UITraitCollection { get }
    var safeAreaInsets: UIEdgeInsets { get }
    var preferredContentSize: CGSize { get }
    /// 当前呈现容器可提供的最大水平宽度，单位为点。
    var maximumDetentValue: CGFloat { get }
}

/// 保存本次解析开始时的容器环境。
private final class OverDetentContext: NSObject, OverPresentationControllerDetentResolutionContext {
    let containerSize: CGSize
    let containerTraitCollection: UITraitCollection
    let safeAreaInsets: UIEdgeInsets
    let preferredContentSize: CGSize
    var maximumDetentValue: CGFloat { containerSize.width }

    init(container: UIView, preferredContentSize: CGSize) {
        containerSize = container.bounds.size
        containerTraitCollection = container.traitCollection
        safeAreaInsets = container.safeAreaInsets
        self.preferredContentSize = preferredContentSize
    }
}

/// 沿水平逻辑边缘展开的全高模态呈现。
@MainActor
open class OverPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    public enum Edge: Sendable {
        case leading, trailing

        @MainActor func isRight(in view: UIView) -> Bool {
            (self == .trailing) == (view.effectiveUserInterfaceLayoutDirection == .leftToRight)
        }
    }

    /// 描述侧栏展开时的宽度档位，每次布局时根据当前容器重新解析。
    @MainActor
    open class Detent: NSObject {
        fileprivate private(set) var resolver: (@MainActor (any OverPresentationControllerDetentResolutionContext) -> CGFloat)?
        fileprivate static let effectChanged = Notification.Name("QuickLayoutKit.OverDetent.backgroundEffectChanged")

        /// 侧栏内容下方的背景材质，默认为 nil。修改后立即更新使用该档位的侧栏。
        open var backgroundEffect: UIVisualEffect? {
            didSet {
                guard oldValue !== backgroundEffect else { return }
                NotificationCenter.default.post(name: Self.effectChanged, object: self)
            }
        }

        /// 创建自动档位。工厂通过此初始化方法保留调用方的子类类型。
        public required override init() { super.init() }

        /// 根据容器尺寸类别与展示边所在的可用区域决定宽度。
        /// 有效的 preferredContentSize.width 优先，并受该区域宽度限制。
        open class func automatic() -> Self { self.init() }

        /// 使用以点为单位的宽度。
        open class func absolute(_ width: CGFloat) -> Self { custom { _ in width } }

        /// 按呈现容器完整宽度的比例计算。
        open class func fractional(_ fraction: CGFloat) -> Self {
            custom { $0.maximumDetentValue * fraction }
        }

        /// 由调用方根据当前容器环境计算宽度。
        public static func custom(
            resolver: @escaping @MainActor (any OverPresentationControllerDetentResolutionContext) -> CGFloat
        ) -> Self {
            let detent = self.init()
            detent.resolver = resolver
            return detent
        }
    }

    public enum PresentingViewEffect: Sendable {
        case overlay, push
        case parallax(factor: CGFloat)

        fileprivate var factor: CGFloat {
            switch self {
            case .overlay: 0
            case .push: 1
            case .parallax(let value): min(1, max(0, value))
            }
        }
    }

    open var edge: Edge { configuredEdge }
    open var detent: Detent = .automatic() {
        didSet {
            material.effect = detent.backgroundEffect
            invalidateDetent()
        }
    }
    open var presentingViewEffect: PresentingViewEffect = .push { didSet { invalidateDetent() } }
    open var backdropColor: UIColor = .black.withAlphaComponent(0.32) {
        didSet { backdrop.backgroundColor = backdropColor }
    }
    /// 单独控制拖动关闭；点击遮罩由 dismissesOnBackdropTap 控制。
    open var allowsInteractiveDismissal = true
    open var dismissesOnBackdropTap = true

    private let backdrop = UIView()
    private let material = UIVisualEffectView()
    private var configuredEdge: Edge = .trailing
    private var originalTransform = CGAffineTransform.identity
    private var isSettledOpen = false
    private var userDismissal = false
    private weak var source: UIViewController?
    private weak var transition: OverTransition?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))

    convenience init(presented: UIViewController, presenting: UIViewController?, source: UIViewController?,
                     edge: Edge, transition: OverTransition) {
        self.init(presentedViewController: presented, presenting: presenting)
        configuredEdge = edge
        self.source = source
        self.transition = transition
    }

    open override var shouldRemovePresentersView: Bool { false }
    open override var adaptivePresentationStyle: UIModalPresentationStyle { .none }
    open override func adaptivePresentationStyle(for traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }

    private var isRight: Bool {
        edge.isRight(in: source?.viewIfLoaded ?? presentingViewController.view)
    }

    open override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let bounds = containerView.bounds
        let maximum = bounds.width
        let preferred = presentedViewController.preferredContentSize
        let onRight = isRight
        let requested = detent.resolver?(OverDetentContext(container: containerView, preferredContentSize: preferred))
        let width: CGFloat
        if let requested, requested.isFinite {
            width = min(maximum, max(0, requested))
        } else {
            var divisions: [CGRect] = []
            #if compiler(>=6.4)
            if #available(iOS 27.1, *) {
                divisions = containerView.reservedRegions(kind: .division).map(\.frame)
            }
            #endif
            width = Self.automaticWidth(in: bounds, traits: containerView.traitCollection,
                                        divisions: divisions, onRight: onRight, preferred: preferred.width)
        }
        return CGRect(x: onRight ? bounds.maxX - width : bounds.minX, y: bounds.minY, width: width, height: bounds.height)
    }

    static func automaticWidth(in bounds: CGRect, traits: UITraitCollection, divisions: [CGRect],
                               onRight: Bool, preferred: CGFloat) -> CGFloat {
        let width = bounds.width
        // 全高侧栏只受竖向分隔带限制。使用系统给出的区域边界，保留折叠处的交互边距。
        let vertical = divisions.filter { $0.height > $0.width }
        if !vertical.isEmpty {
            let regions = SheetRegionGeometry.regions(in: bounds, divisions: vertical)
            let region = onRight ? regions.last : regions.first
            guard let region, onRight ? region.maxX == bounds.maxX : region.minX == bounds.minX else { return 0 }
            if region.width < width {
                return preferred.isFinite && preferred > 0 ? min(preferred, region.width) : region.width
            }
        }
        if preferred.isFinite && preferred > 0 { return min(preferred, width) }

        let compactWidth = width * 0.8
        let wideLayout = traits.horizontalSizeClass == .regular ||
            (traits.verticalSizeClass == .compact && width > bounds.height)
        guard wideLayout else { return compactWidth }
        // 宽布局取半宽；小窗口至少露出两成底页，大窗口限制侧栏的行长。
        return min(compactWidth, max(320, min(width / 2, 480)))
    }

    /// 自定义档位依赖的外部值变化时，在下一次布局重新计算侧栏宽度。
    open func invalidateDetent() { containerView?.setNeedsLayout() }

    open func animateChanges(_ changes: () -> Void) {
        containerView?.layoutIfNeeded()
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            changes()
            self.containerView?.layoutIfNeeded()
        }
    }

    open override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        invalidateDetent()
    }

    open override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        originalTransform = presentingViewController.view.transform
        backdrop.backgroundColor = backdropColor
        backdrop.frame = containerView.bounds
        backdrop.alpha = 0
        containerView.insertSubview(backdrop, at: 0)
        // 材质位于遮罩与侧栏内容之间。内容的透明区域可以透出材质，触摸仍由原有视图处理。
        material.isUserInteractionEnabled = false
        material.accessibilityElementsHidden = true
        material.effect = detent.backgroundEffect
        containerView.insertSubview(material, aboveSubview: backdrop)
        NotificationCenter.default.addObserver(self, selector: #selector(effectChanged(_:)), name: Detent.effectChanged, object: nil)
        if #available(iOS 17, *) {
            containerView.registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
                (container: UIView, _: UITraitCollection) in container.setNeedsLayout()
            }
        }
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // 半折叠时窗口尺寸可能保持不变，仍需重新读取当前生效的分隔区域。
            backdrop.addInteraction(UIHingeInteraction { [weak self] _, _ in self?.invalidateDetent() })
        }
        #endif
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapBackdrop))
        backdrop.addGestureRecognizer(tap)
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        containerView.addGestureRecognizer(pan)
        tap.require(toFail: pan)
    }

    open override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        backdrop.frame = containerView?.bounds ?? .zero
        if isSettledOpen { apply(open: true) }
    }

    /// 面板、底页和遮罩共用同一个可中断动画，取消手势时同步归位。
    func apply(open: Bool) {
        let frame = frameOfPresentedViewInContainerView
        let travel = (isRight ? 1 : -1) * frame.width
        let panelFrame = open ? frame : frame.offsetBy(dx: travel, dy: 0)
        presentedView?.frame = panelFrame
        material.frame = panelFrame
        var transform = originalTransform
        if open { transform.tx -= travel * presentingViewEffect.factor }
        presentingViewController.view.transform = transform
        backdrop.alpha = open ? 1 : 0
    }

    open override func presentationTransitionDidEnd(_ completed: Bool) {
        isSettledOpen = completed
        apply(open: completed)
        transition?.endInteraction()
        if !completed { tearDown() }
    }

    open override func dismissalTransitionWillBegin() { isSettledOpen = false }

    open override func dismissalTransitionDidEnd(_ completed: Bool) {
        isSettledOpen = !completed
        apply(open: !completed)
        transition?.endInteraction()
        if completed {
            if userDismissal { delegate?.presentationControllerDidDismiss?(self) }
            tearDown()
        }
        userDismissal = false
    }

    private func tearDown() {
        NotificationCenter.default.removeObserver(self, name: Detent.effectChanged, object: nil)
        material.removeFromSuperview()
        pan.view?.removeGestureRecognizer(pan)
        backdrop.removeFromSuperview()
        transition?.detach(from: presentedViewController)
    }

    @objc private func effectChanged(_ notification: Notification) {
        guard notification.object as? Detent === detent else { return }
        material.effect = detent.backgroundEffect
    }

    private func canDismiss() -> Bool {
        guard isSettledOpen, presentedViewController.presentedViewController == nil else { return false }
        if presentedViewController.isModalInPresentation || delegate?.presentationControllerShouldDismiss?(self) == false {
            delegate?.presentationControllerDidAttemptToDismiss?(self)
            return false
        }
        return true
    }

    private func dismissFromUser() {
        userDismissal = true
        delegate?.presentationControllerWillDismiss?(self)
        presentedViewController.dismiss(animated: true)
    }

    @objc private func tapBackdrop() {
        if dismissesOnBackdropTap, canDismiss() { dismissFromUser() }
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            guard let transition else { return }
            transition.beginInteraction(sign: isRight ? 1 : -1)
            dismissFromUser()
        } else {
            transition?.track(gesture)
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, transition != nil, allowsInteractiveDismissal, let containerView else { return false }
        let velocity = pan.velocity(in: containerView)
        guard abs(velocity.x) > abs(velocity.y), (isRight ? velocity.x : -velocity.x) > 0 else { return false }
        var view = containerView.hitTest(pan.location(in: containerView), with: nil)
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled {
                let left = -scroll.adjustedContentInset.left
                let right = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
                if right > left + 1, isRight ? scroll.contentOffset.x > left + 1 : scroll.contentOffset.x < right - 1 {
                    return false
                }
            }
            view = current.superview
        }
        return canDismiss()
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && (other.view as? UIScrollView)?.panGestureRecognizer === other
    }
}
