import UIKit

@MainActor private var sheetTransitionAssociationKey: UInt8 = 0

@MainActor
public extension UIViewController {
    var customSheetPresentationController: SheetPresentationController? {
        presentationController as? SheetPresentationController
    }

    /// 配置接口对齐系统 Sheet，transitioning delegate 由框架自动持有。
    func presentSheet(
        _ viewController: UIViewController,
        animated: Bool = true,
        configure: @escaping @MainActor (SheetPresentationController) -> Void = { _ in },
        completion: (() -> Void)? = nil
    ) {
        let transition = SheetTransitioningDelegate(configure: configure)
        objc_setAssociatedObject(
            viewController,
            &sheetTransitionAssociationKey,
            transition,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        viewController.modalPresentationStyle = .custom
        viewController.transitioningDelegate = transition
        present(viewController, animated: animated, completion: completion)
    }
}

@MainActor
extension UIViewController {
    func releaseSheetTransition(for sheet: SheetPresentationController) {
        guard let owner = objc_getAssociatedObject(self, &sheetTransitionAssociationKey) as? SheetTransitioningDelegate,
              owner.sheet === sheet else { return }
        if transitioningDelegate === owner { transitioningDelegate = nil }
        objc_setAssociatedObject(self, &sheetTransitionAssociationKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
