import UIKit

@MainActor private var popoverTransitionKey: UInt8 = 0

@MainActor
public extension UIViewController {
    var customPopoverPresentationController: PopoverPresentationController? {
        presentationController as? PopoverPresentationController
    }

    /// 返回 false 表示宿主当前无法呈现，或指定的锚点无法定位。
    @discardableResult
    func presentPopover(
        _ viewController: UIViewController,
        animated: Bool = true,
        configure: @MainActor (PopoverPresentationController) -> Void,
        completion: (() -> Void)? = nil
    ) -> Bool {
        guard viewIfLoaded?.window != nil, presentedViewController == nil,
              viewController !== self, viewController.parent == nil, viewController.presentingViewController == nil else { return false }
        let controller = PopoverPresentationController(presentedViewController: viewController, presenting: self)
        configure(controller)
        controller.popoverDelegate?.prepareForPopoverPresentation(controller)
        guard controller.anchor(in: view) != nil,
              controller.popoverBackgroundViewClass == nil || controller.backgroundViewType != nil else { return false }
        let transition = PopoverTransition(controller)
        objc_setAssociatedObject(viewController, &popoverTransitionKey, transition, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        viewController.modalPresentationStyle = .custom
        viewController.transitioningDelegate = transition
        present(viewController, animated: animated, completion: completion)
        return true
    }
}

@MainActor
extension UIViewController {
    func releasePopoverTransition(_ popover: PopoverPresentationController) {
        guard let owner = objc_getAssociatedObject(self, &popoverTransitionKey) as? PopoverTransition,
              owner.controller === popover else { return }
        if transitioningDelegate === owner { transitioningDelegate = nil }
        objc_setAssociatedObject(self, &popoverTransitionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

@MainActor
private final class PopoverTransition: NSObject, UIViewControllerTransitioningDelegate {
    weak var controller: PopoverPresentationController?
    init(_ controller: PopoverPresentationController) { self.controller = controller }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? { controller }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        controller.map { PopoverAnimator($0, presenting: true) }
    }

    func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        controller.map { PopoverAnimator($0, presenting: false) }
    }

    func interactionControllerForDismissal(using animator: any UIViewControllerAnimatedTransitioning)
        -> (any UIViewControllerInteractiveTransitioning)? {
        guard let controller, controller.showsSheet else { return nil }
        return controller.adaptiveSheetPresentationController.interactionController
    }
}

@MainActor
private final class PopoverAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let controller: PopoverPresentationController
    let presenting: Bool
    init(_ controller: PopoverPresentationController, presenting: Bool) {
        self.controller = controller
        self.presenting = presenting
    }

    func transitionDuration(using context: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        controller.duration(presenting: presenting)
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        controller.animate(using: context, presenting: presenting)
    }
}
