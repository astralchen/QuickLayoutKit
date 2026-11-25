import UIKit

@MainActor
extension UIViewController {
    @objc open var overPresentationController: OverPresentationController? {
        presentationController as? OverPresentationController
    }

    public func presentOver(_ viewController: UIViewController, from edge: OverPresentationController.Edge = .trailing,
                     animated: Bool = true, configure: @escaping @MainActor (OverPresentationController) -> Void = { _ in },
                     completion: (() -> Void)? = nil) {
        OverTransition(source: self, edge: edge, configure: configure)
            .present(viewController, animated: animated, completion: completion)
    }

    /// 由底页持有返回的交互对象，以持续响应边缘打开手势。
    public func installOverPresentationInteraction(
        from edge: OverPresentationController.Edge = .trailing,
        makeViewController: @escaping @MainActor () -> UIViewController,
        configure: @escaping @MainActor (OverPresentationController) -> Void = { _ in }
    ) -> OverPresentationInteraction {
        OverPresentationInteraction(source: self, edge: edge, makeViewController: makeViewController, configure: configure)
    }
}

@MainActor
public final class OverPresentationInteraction: NSObject, UIGestureRecognizerDelegate {
    private weak var source: UIViewController?
    private let edge: OverPresentationController.Edge
    private let makeViewController: @MainActor () -> UIViewController
    private let configure: @MainActor (OverPresentationController) -> Void
    private var recognizers: [UIScreenEdgePanGestureRecognizer] = []
    private weak var active: OverTransition?

    public var isEnabled = true {
        didSet { recognizers.forEach { $0.isEnabled = isEnabled } }
    }

    fileprivate init(source: UIViewController, edge: OverPresentationController.Edge,
                     makeViewController: @escaping @MainActor () -> UIViewController,
                     configure: @escaping @MainActor (OverPresentationController) -> Void) {
        self.source = source
        self.edge = edge
        self.makeViewController = makeViewController
        self.configure = configure
        super.init()
        // 分别监听两个物理边缘，在手势开始时判断当前逻辑方向，切换语言后即可沿新方向拖入。
        for side: UIRectEdge in [.left, .right] {
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(drag(_:)))
            pan.edges = side
            pan.delegate = self
            source.view.addGestureRecognizer(pan)
            recognizers.append(pan)
        }
    }

    isolated deinit { uninstall() }

    public func uninstall() {
        for pan in recognizers {
            pan.isEnabled = false
            pan.view?.removeGestureRecognizer(pan)
        }
        recognizers.removeAll()
    }

    public func present(animated: Bool = true, completion: (() -> Void)? = nil) {
        start(animated: animated, sign: nil, completion: completion)
    }

    private var canPresent: Bool {
        guard let source, source.viewIfLoaded?.window != nil else { return false }
        var current: UIViewController? = source
        while let controller = current {
            if controller.presentedViewController != nil || controller.isBeingDismissed { return false }
            current = controller.parent
        }
        return true
    }

    private func start(animated: Bool, sign: CGFloat?, completion: (() -> Void)?) {
        guard canPresent, let source else { return }
        let transition = OverTransition(source: source, edge: edge, configure: configure)
        if let sign { transition.beginInteraction(sign: sign) }
        active = transition
        transition.present(makeViewController(), animated: animated, completion: completion)
    }

    @objc private func drag(_ pan: UIScreenEdgePanGestureRecognizer) {
        if pan.state == .began {
            start(animated: true, sign: pan.edges == .right ? -1 : 1, completion: nil)
        } else {
            active?.track(pan)
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIScreenEdgePanGestureRecognizer, let view = pan.view else { return false }
        return canPresent && (pan.edges == .right) == edge.isRight(in: view)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        guard edge == .leading, let navigation = source?.navigationController else { return false }
        if #available(iOS 26.0, *), other === navigation.interactiveContentPopGestureRecognizer { return true }
        return other === navigation.interactivePopGestureRecognizer
    }
}
