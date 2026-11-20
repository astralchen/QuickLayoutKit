import UIKit

@MainActor
final class SheetTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    let configure: @MainActor (SheetPresentationController) -> Void
    weak var sheet: SheetPresentationController?

    init(configure: @escaping @MainActor (SheetPresentationController) -> Void) { self.configure = configure }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        let sheet = SheetPresentationController(presentedViewController: presented, presenting: presenting)
        configure(sheet)
        self.sheet = sheet
        return sheet
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        SheetAnimator(transition: self, presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        SheetAnimator(transition: self, presenting: false)
    }

    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? {
        sheet?.interactionController
    }
}

@MainActor
final class SheetAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    static let duration = 0.5
    let transition: SheetTransitioningDelegate
    let presenting: Bool

    init(transition: SheetTransitioningDelegate, presenting: Bool) {
        self.transition = transition
        self.presenting = presenting
    }

    func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval { Self.duration }
    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let sheet = transition.sheet else { context.completeTransition(false); return }
        sheet.animate(using: context, presenting: presenting)
    }
}

/// 手势直接更新可见位置。松手时从最后一帧起步，回弹时间独立于已经拖过的比例。
@MainActor
final class SheetDismissalInteraction: NSObject, UIViewControllerInteractiveTransitioning {
    let surface: UIView
    let dimming: SheetDimming
    private var context: (any UIViewControllerContextTransitioning)?
    private var origin = CGRect.zero
    private var travel: CGFloat = 0
    private var initialDimming: CGFloat = 1
    private var progress: CGFloat = 0
    private var pendingFinish: Bool?

    let updatePresenter: (CGRect) -> Void

    init(surface: UIView, dimming: SheetDimming, updatePresenter: @escaping (CGRect) -> Void) {
        self.updatePresenter = updatePresenter
        self.surface = surface
        self.dimming = dimming
    }

    func startInteractiveTransition(_ transitionContext: any UIViewControllerContextTransitioning) {
        context = transitionContext
        initialDimming = dimming.amount
        origin = surface.frame
        travel = transitionContext.containerView.bounds.maxY - origin.minY
        update(progress)
        if let pendingFinish { end(finishing: pendingFinish) }
    }

    func update(_ fraction: CGFloat) {
        progress = fraction
        guard let context else { return }
        context.updateInteractiveTransition(fraction)
        surface.frame = origin.offsetBy(dx: 0, dy: travel * fraction)
        updatePresenter(surface.frame)
        dimming.amount = initialDimming * (1 - fraction)
    }

    func end(finishing: Bool) {
        guard let context else { pendingFinish = finishing; return }
        if finishing {
            context.finishInteractiveTransition()
        } else {
            context.cancelInteractiveTransition()
        }
        UIView.animate(withDuration: SheetAnimator.duration, delay: 0, usingSpringWithDamping: 1,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.surface.frame = finishing ? self.origin.offsetBy(dx: 0, dy: self.travel) : self.origin
            self.updatePresenter(self.surface.frame)
            self.dimming.amount = finishing ? 0 : self.initialDimming
        } completion: { _ in
            self.context = nil
            context.completeTransition(finishing)
        }
    }
}
