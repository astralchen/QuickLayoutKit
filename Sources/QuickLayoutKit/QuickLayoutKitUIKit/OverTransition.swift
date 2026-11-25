import UIKit

@MainActor private var overTransitionKey: UInt8 = 0

@MainActor
final class OverTransition: NSObject, UIViewControllerTransitioningDelegate {
    private let edge: OverPresentationController.Edge
    private weak var source: UIViewController?
    private var configure: ((OverPresentationController) -> Void)?
    private weak var presentation: OverPresentationController?
    private var driver: UIPercentDrivenInteractiveTransition?
    private var direction: CGFloat = 1

    init(source: UIViewController, edge: OverPresentationController.Edge,
         configure: @escaping (OverPresentationController) -> Void) {
        self.source = source
        self.edge = edge
        self.configure = configure
    }

    func present(_ content: UIViewController, animated: Bool, completion: (() -> Void)?) {
        guard let source else { return }
        // 从容器根控制器呈现，让导航栏和标签栏与底页一起平移。
        var host = source
        while let parent = host.parent { host = parent }
        guard host.presentedViewController == nil, content.presentingViewController == nil else { return }
        objc_setAssociatedObject(content, &overTransitionKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        content.modalPresentationStyle = .custom
        content.transitioningDelegate = self
        host.present(content, animated: animated, completion: completion)
    }

    func detach(from content: UIViewController) {
        guard content.transitioningDelegate === self else { return }
        content.transitioningDelegate = nil
        objc_setAssociatedObject(content, &overTransitionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func beginInteraction(sign: CGFloat) {
        direction = sign
        let driver = UIPercentDrivenInteractiveTransition()
        driver.completionCurve = .easeOut
        self.driver = driver
    }

    func endInteraction() { driver = nil }

    func track(_ gesture: UIPanGestureRecognizer) {
        guard let driver else { return }
        // 底页会随手势移动，因此在窗口坐标系中取位移，并按面板宽度换算本次转场的完成比例。
        let window = gesture.view?.window
        let width = max(1, presentation?.frameOfPresentedViewInContainerView.width ?? 1)
        let fraction = min(1, max(0, direction * gesture.translation(in: window).x / width))
        switch gesture.state {
        case .changed:
            driver.update(fraction)
        case .ended:
            let velocity = direction * gesture.velocity(in: window).x
            let projected = fraction + velocity * 0.18 / width
            if projected >= 0.5 { driver.finish() } else { driver.cancel() }
        case .cancelled, .failed:
            driver.cancel()
        default:
            break
        }
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        let controller = OverPresentationController(presented: presented, presenting: presenting,
                                                   source: self.source, edge: edge, transition: self)
        configure?(controller)
        configure = nil
        presentation = controller
        return controller
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        OverAnimator(opening: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        OverAnimator(opening: false)
    }

    func interactionControllerForPresentation(using animator: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? { driver }

    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? { driver }
}

@MainActor
private final class OverAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let opening: Bool
    private var animation: UIViewPropertyAnimator?

    init(opening: Bool) { self.opening = opening }

    func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.16 : 0.32
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        interruptibleAnimator(using: context).startAnimation()
    }

    func interruptibleAnimator(using context: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        if let animation { return animation }
        let key: UITransitionContextViewControllerKey = opening ? .to : .from
        let controller = context.viewController(forKey: key)?.overPresentationController
        if opening, let view = context.view(forKey: .to) {
            context.containerView.addSubview(view)
        }
        controller?.apply(open: !opening)
        controller?.presentedView?.layoutIfNeeded()
        let animation = UIViewPropertyAnimator(duration: transitionDuration(using: context), curve: .easeOut) {
            controller?.apply(open: self.opening)
        }
        animation.scrubsLinearly = true
        animation.addCompletion { [weak self] _ in
            self?.animation = nil
            context.completeTransition(!context.transitionWasCancelled)
        }
        self.animation = animation
        return animation
    }
}
