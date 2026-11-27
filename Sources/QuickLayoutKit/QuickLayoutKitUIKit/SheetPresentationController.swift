import UIKit

/// 通过 UIViewController.presentSheet 展示，使用 UIKit 的 dismiss 关闭。
@MainActor
open class SheetPresentationController: UIPresentationController {
    /// 页式卡片在可用区域中的水平位置。leading 和 trailing 遵循布局方向。
    public enum Placement: Sendable { case automatic, leading, center, trailing }

    /// 与继承的弱 delegate 共用同一存储，Swift 协议提供 Sheet 专属回调。
    public var sheetDelegate: (any SheetPresentationControllerDelegate)? {
        get { delegate as? any SheetPresentationControllerDelegate }
        set { delegate = newValue }
    }

    open var sourceView: UIView? { didSet { invalidateDetents() } }
    open var preferredPlacement: Placement = .automatic { didSet { invalidateDetents() } }
    open var prefersPageSizing: Bool = {
        if #available(iOS 18, *) { return false }
        return true
    }() { didSet { invalidateDetents() } }
    open var prefersEdgeAttachedInCompactHeight = false { didSet { invalidateDetents() } }
    open var widthFollowsPreferredContentSizeWhenEdgeAttached = false { didSet { invalidateDetents() } }
    open var prefersGrabberVisible = false { didSet { invalidateDetents() } }
    open var detents: [Detent] = [.large()] { didSet { invalidateDetents() } }
    open var selectedDetentIdentifier: Detent.Identifier? { didSet { invalidateDetents() } }
    /// 保持背景透亮的最高档位。默认值 nil 在每一档都遮暗背景。
    open var largestUndimmedDetentIdentifier: Detent.Identifier? { didSet { invalidateDetents() } }
    open var prefersScrollingExpandsWhenScrolledToEdge = true
    open var preferredCornerRadius: CGFloat? { didSet { invalidateDetents() } }

    /// 页式卡片相对所选区域的单侧间距。普通 iPhone 竖屏在中档及以下使用此值，展开到大档时贴边。
    /// iOS 26 起默认为 8 pt，较早系统默认为 0。
    public var horizontalInset: CGFloat = SheetRegionGeometry.defaultPageInset { didSet { invalidateDetents() } }

    /// 页式卡片在中档及以下的底部留白，独立于内容安全区。默认值和 horizontalInset 相同。
    public var bottomInset: CGFloat = SheetRegionGeometry.defaultPageInset { didSet { invalidateDetents() } }

    private(set) var isAtMaximumDetent = false
    let presenterEffect = SheetPresenterEffect()
    private let surface = SheetSurface()
    private let material = UIVisualEffectView()
    private let grabber = UIView()
    private let backdrop = SheetBackdrop()
    private var suppliedBottomInset: CGFloat = 0
    private var transitioning = false
    private var dragLayout: SheetLayout?
    private var detentAnimator: UIViewPropertyAnimator?
    private var previousTint: UIView.TintAdjustmentMode = .automatic
    private(set) var hasHinge = false
    private(set) var hingeClosed = false
    private var userDismissal = false
    private var dragOrigin = CGRect.zero
    private weak var touchedScroll: UIScrollView?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    private(set) var interactionController: SheetDismissalInteraction?

    private var layout: SheetLayout? { containerView.map { SheetLayout(self, in: $0) } }
    public override var presentedView: UIView? { surface }
    public override var frameOfPresentedViewInContainerView: CGRect { layout?.selected.frame ?? .zero }

    open func invalidateDetents() { containerView?.setNeedsLayout() }

    public override func preferredContentSizeDidChange(forChildContentContainer container: any UIContentContainer) {
        super.preferredContentSizeDidChange(forChildContentContainer: container)
        invalidateDetents()
    }

    open func animateChanges(_ changes: () -> Void) {
        animateChanges(using: nil, changes)
    }

    private func animateChanges(using spring: UISpringTimingParameters?, _ changes: () -> Void) {
        stopSettling()
        changes()
        guard surface.window != nil, !transitioning, dragLayout == nil else { invalidateDetents(); return }
        let animator = if let spring {
            UIViewPropertyAnimator(duration: 0, timingParameters: spring)
        } else {
            UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1)
        }
        animator.addAnimations { self.layoutSheet() }
        detentAnimator = animator
        animator.addCompletion { [weak self] _ in
            self?.detentAnimator = nil
            self?.invalidateDetents()
        }
        animator.startAnimation()
    }

    private func stopSettling() {
        guard let animator = detentAnimator else { return }
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        detentAnimator = nil
    }

    public override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        transitioning = true
        presenterEffect.configure(presenter: presentingViewController)
        previousTint = presentingViewController.view.tintAdjustmentMode
        backdrop.frame = container.bounds
        if #available(iOS 26, *) { backdrop.cornerConfiguration = .corners(radius: .containerConcentric()) }
        backdrop.addTarget(self, action: #selector(tapBackground), for: .touchUpInside)
        container.addSubview(backdrop)
        presenterEffect.installDimming(in: backdrop, surface: surface)
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // 从 Popover 再次适配为 Sheet 时，重新读取本次窗口的铰链状态。
            hasHinge = false
            hingeClosed = false
            backdrop.addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                hasHinge = update.hinge != nil
                hingeClosed = update.hinge?.status == .closed
                invalidateDetents()
            })
        }
        #endif
        surface.backgroundColor = .systemBackground
        surface.clipsToBounds = true
        surface.layer.cornerCurve = .continuous
        material.frame = surface.bounds
        material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        material.isUserInteractionEnabled = false
        surface.addSubview(material)
        NotificationCenter.default.addObserver(self, selector: #selector(effectChanged(_:)), name: Detent.effectChanged, object: nil)
        let content = presentedViewController.view!
        surface.content = content
        grabber.backgroundColor = .tertiaryLabel
        grabber.layer.cornerRadius = 2.5
        grabber.isUserInteractionEnabled = false
        surface.addSubview(grabber)
        pan.delegate = self
        surface.addGestureRecognizer(pan)
        layoutSheet()
        presenterEffect.dimming.amount = 0
    }

    public override func presentationTransitionDidEnd(_ completed: Bool) {
        transitioning = false
        if completed { layoutSheet() } else { tearDown() }
    }

    public override func dismissalTransitionWillBegin() {
        stopSettling()
        dragLayout = nil
        transitioning = true
    }

    public override func dismissalTransitionDidEnd(_ completed: Bool) {
        transitioning = false
        interactionController = nil
        if completed {
            tearDown()
            if userDismissal { delegate?.presentationControllerDidDismiss?(self) }
        } else {
            layoutSheet()
        }
        userDismissal = false
    }

    public override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        backdrop.frame = containerView?.bounds ?? .zero
        if !transitioning && dragLayout == nil && detentAnimator == nil { layoutSheet() }
    }

    private func layoutSheet() {
        guard let layout else { return }
        let stop = layout.selected
        isAtMaximumDetent = abs(stop.height - layout.maximumHeight) < 0.5
        surface.logicalWidth = layout.logicalWidth
        guard let container = containerView else { return }
        let frame = presenterEffect.frameWhenCovered(stop.frame, minimumTop: layout.stops[0].frame.minY, in: container)
        surface.place(in: frame)
        if !transitioning { updatePresenter(for: frame, in: layout) }
        updateCorners(for: frame, in: layout)
        grabber.isHidden = !prefersGrabberVisible
        grabber.frame = CGRect(x: (surface.bounds.width - 58) / 2, y: 5, width: 58, height: 5)
        grabber.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        updateMaterial(stop.detent)
        applyDimming(stop.dimming)
        // 卡片浮起时，内容从窗口继承的底部安全区相应减少，只补回移出的距离。
        let lift = max(0, (containerView?.bounds.maxY ?? stop.frame.maxY) - stop.frame.maxY)
        setSuppliedBottomInset(min(lift, layout.contentBottomInset))
        if surface.window != nil { surface.layoutIfNeeded() }
    }

    private func updatePresenter(for frame: CGRect, in layout: SheetLayout) {
        guard let container = containerView else { return }
        let progress = layout.presenterFraction(at: frame.minY, bottom: container.bounds.maxY)
        presenterEffect.update(progress, in: container, frontFrame: frame, attachment: layout.attachment, interacting: dragLayout != nil)
    }

    private func updateCorners(for frame: CGRect, in layout: SheetLayout) {
        guard let container = containerView else { return }
        let fullscreen = container.traitCollection.verticalSizeClass == .compact && !prefersEdgeAttachedInCompactHeight
        SheetRegionGeometry.updateCorners(of: surface, relativeTo: backdrop, frame: frame, preferredRadius: preferredCornerRadius,
                                         fullScreen: fullscreen, logicalWidth: surface.logicalWidth, attachment: layout.attachment, isLifted: presenterEffect.isLifted)
    }

    private func setSuppliedBottomInset(_ value: CGFloat) {
        guard abs(value - suppliedBottomInset) > 0.1 else { return }
        let adjustment = value - suppliedBottomInset
        suppliedBottomInset = value
        presentedViewController.additionalSafeAreaInsets.bottom += adjustment
    }

    @objc private func effectChanged(_ notification: Notification) {
        if let changed = notification.object as? Detent, detents.contains(where: { $0 === changed }) { invalidateDetents() }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 26.1, *)
    open override var backgroundEffect: UIVisualEffect? {
        didSet { invalidateDetents() }
    }
    #endif

    private func updateMaterial(_ detent: Detent) {
        var effect = detent.backgroundEffect
        #if os(iOS) && !targetEnvironment(macCatalyst)
        // 档位未指定材质时，使用呈现控制器的背景。
        if #available(iOS 26.1, *), effect == nil { effect = backgroundEffect }
        #endif
        if material.effect !== effect { material.effect = effect }
        surface.backgroundColor = effect == nil ? .systemBackground : .clear
    }

    private func applyDimming(_ amount: CGFloat) {
        presenterEffect.dimming.amount = amount
        surface.accessibilityViewIsModal = amount > 0
        backdrop.passthroughView = amount == 0 ? presentingViewController.view : nil
        presentingViewController.view.tintAdjustmentMode = amount == 0 ? previousTint : .dimmed
    }

    func tearDown() {
        NotificationCenter.default.removeObserver(self, name: Detent.effectChanged, object: nil)
        backdrop.removeTarget(self, action: #selector(tapBackground), for: .touchUpInside)
        if #available(iOS 27.1, *) {
            #if compiler(>=6.4)
            for interaction in backdrop.interactions where interaction is UIHingeInteraction { backdrop.removeInteraction(interaction) }
            #endif
        }
        material.removeFromSuperview()
        grabber.removeFromSuperview()
        surface.removeGestureRecognizer(pan)
        surface.content = nil
        presenterEffect.reset()
        setSuppliedBottomInset(0)
        presentingViewController.view.tintAdjustmentMode = previousTint
        backdrop.removeFromSuperview()
        presentedViewController.viewIfLoaded?.removeFromSuperview()
        surface.removeFromSuperview()
        presentedViewController.releaseSheetTransition(for: self)
    }

    func animate(using context: any UIViewControllerContextTransitioning, presenting: Bool) {
        let visible = presenting ? frameOfPresentedViewInContainerView : surface.frame
        let hidden = visible.offsetBy(dx: 0, dy: context.containerView.bounds.maxY - visible.minY)
        if presenting {
            surface.frame = visible
            context.containerView.addSubview(surface)
            // 等内容进入窗口后，再按显示位置的安全区排版首帧。
            if surface.window != nil { surface.layoutIfNeeded() }
            surface.frame = hidden
        }
        let targetDimming = presenting ? layout?.selected.dimming ?? 1 : 0
        let change = {
            self.surface.frame = presenting ? visible : hidden
            self.presenterEffect.dimming.amount = targetDimming
            if presenting, let layout = self.layout { self.updatePresenter(for: visible, in: layout) }
            else { self.presenterEffect.restore() }
        }
        let complete: (Bool) -> Void = { _ in context.completeTransition(!context.transitionWasCancelled) }
        if !context.isAnimated {
            change()
            complete(true)
        } else {
            UIView.animate(withDuration: SheetAnimator.duration, delay: 0, usingSpringWithDamping: 1,
                           initialSpringVelocity: 0, options: [], animations: change, completion: complete)
        }
    }

    private func beginUserDismissal(interactive: Bool) {
        guard !presentedViewController.isModalInPresentation,
              delegate?.presentationControllerShouldDismiss?(self) ?? true else {
            delegate?.presentationControllerDidAttemptToDismiss?(self)
            return
        }
        userDismissal = true
        if interactive, let layout {
            interactionController = SheetDismissalInteraction(surface: surface, dimming: presenterEffect.dimming) { [weak self] frame in
                self?.updatePresenter(for: frame, in: layout)
            }
        }
        delegate?.presentationControllerWillDismiss?(self)
        presentedViewController.dismiss(animated: true)
    }

    @objc private func tapBackground() {
        if !transitioning { beginUserDismissal(interactive: false) }
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView else { return }
        let distance = gesture.translation(in: container).y
        let velocity = gesture.velocity(in: container).y
        switch gesture.state {
        case .began:
            stopSettling()
            guard let layout else { return }
            dragOrigin = surface.frame
            if velocity > 0, layout.selected.frame == layout.stops.first?.frame,
               dragOrigin.minY >= layout.largest.frame.minY {
                beginUserDismissal(interactive: true)
            } else {
                dragLayout = layout
            }
        case .changed:
            if let interactionController {
                interactionController.update(max(0, min(1, distance / max(1, container.bounds.maxY - dragOrigin.minY))))
            } else if let dragLayout {
                let sample = dragLayout.sample(from: dragOrigin.minY, translation: distance, allowsOverdrag: touchedScroll == nil)
                surface.place(in: sample.frame)
                updatePresenter(for: sample.frame, in: dragLayout)
                updateCorners(for: sample.frame, in: dragLayout)
                applyDimming(sample.dimming)
                if let scroll = touchedScroll { scroll.contentOffset.y = -scroll.adjustedContentInset.top }
            }
        case .ended, .cancelled, .failed:
            if let interactionController {
                interactionController.end(finishing: gesture.state == .ended && distance + velocity * 0.18 > dragOrigin.height * 0.35)
            } else if let dragLayout {
                self.dragLayout = nil
                let projected = surface.frame.minY + velocity * 0.18
                let largest = dragLayout.largest
                let overdrag = surface.frame.minY < largest.frame.minY
                let selected = dragLayout.selected
                let target: SheetLayout.Stop
                if gesture.state != .ended {
                    target = selected
                } else if overdrag {
                    target = selected.frame == largest.frame ? selected : largest
                } else {
                    target = dragLayout.stops.min {
                        abs($0.frame.minY - projected) < abs($1.frame.minY - projected)
                    } ?? selected
                }
                let changes = {
                    if target.id != selected.id { self.selectedDetentIdentifier = target.id }
                }
                if overdrag, target.frame == largest.frame {
                    animateChanges(using: SheetOverdrag.spring(velocity: gesture.state == .ended ? velocity : 0), changes)
                } else {
                    animateChanges(changes)
                }
                if target.id != selected.id {
                    sheetDelegate?.sheetPresentationControllerDidChangeSelectedDetentIdentifier(self)
                }
            }
        default: break
        }
    }
}

extension SheetPresentationController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, !transitioning, let layout else { return false }
        let velocity = pan.velocity(in: surface)
        guard abs(velocity.y) > abs(velocity.x) else { return false }
        var hit = surface.hitTest(pan.location(in: surface), with: nil)
        touchedScroll = nil
        while let view = hit, view !== surface {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                if velocity.y < 0 && (!prefersScrollingExpandsWhenScrolledToEdge || layout.selected.id == layout.stops.last?.id) {
                    return false
                }
                guard scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1 else { return false }
                touchedScroll = scroll
                break
            }
            hit = view.superview
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pan && other === touchedScroll?.panGestureRecognizer
    }
}
