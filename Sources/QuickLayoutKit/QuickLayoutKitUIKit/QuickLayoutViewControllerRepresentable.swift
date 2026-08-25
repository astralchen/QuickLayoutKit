import UIKit

/// 在 QuickLayout `body` 中嵌入子视图控制器的 UIKit 视图。
///
/// `QuickLayoutViewControllerRepresentable` 沿用 SwiftUI representable 的命名方式，
/// 但采用 UIKit 优先的契约：调用方传入已经创建的子视图控制器。该视图进入视图层级时，
/// 会从 UIKit 响应者链解析父视图控制器。需要延迟创建时，应使用 QuickLayout 的
/// `LazyView` 包装该视图。
@MainActor
public final class QuickLayoutViewControllerRepresentable: UIView, QuickLayoutUpdating {

    /// representable 视图发出的包含关系和布局事件。
    public enum Event: Equatable {
        /// representable 视图移入或移出父视图。
        case didMoveToSuperview
        /// 捕获或替换了父视图控制器引用。
        case didCaptureParent
        /// 子视图控制器即将附加到父视图控制器。
        case willAttach
        /// 子视图控制器已经附加到父视图控制器。
        case didAttach
        /// 子视图控制器即将从父视图控制器移除。
        case willDetach
        /// 子视图控制器已经从父视图控制器移除。
        case didDetach
        /// 宿主视图控制器即将被替换。
        case willReplaceViewController
        /// 宿主视图控制器已经被替换。
        case didReplaceViewController
        /// 宿主视图控制器即将被拆除。
        case willDismantleViewController
        /// 宿主视图控制器已经被拆除。
        case didDismantleViewController
        /// representable 视图缺少附加子控制器所需的父控制器。
        case missingParent
        /// 子视图控制器已属于其他父控制器。
        case viewControllerAlreadyParented
        /// 子控制器视图已在 representable 视图内完成布局。
        case didLayoutSubviews
        /// 宿主子控制器布局已失效。
        case didInvalidateChildLayout

        /// 用于日志和测试的稳定字符串名称。
        public var name: String {
            switch self {
            case .didMoveToSuperview:
                return "didMoveToSuperview"
            case .didCaptureParent:
                return "didCaptureParent"
            case .willAttach:
                return "willAttach"
            case .didAttach:
                return "didAttach"
            case .willDetach:
                return "willDetach"
            case .didDetach:
                return "didDetach"
            case .willReplaceViewController:
                return "willReplaceViewController"
            case .didReplaceViewController:
                return "didReplaceViewController"
            case .willDismantleViewController:
                return "willDismantleViewController"
            case .didDismantleViewController:
                return "didDismantleViewController"
            case .missingParent:
                return "missingParent"
            case .viewControllerAlreadyParented:
                return "viewControllerAlreadyParented"
            case .didLayoutSubviews:
                return "didLayoutSubviews"
            case .didInvalidateChildLayout:
                return "didInvalidateChildLayout"
            }
        }
    }

    /// 详细事件使用的稳定事件类型。
    public typealias EventKind = Event

    /// 包含相关控制器引用的包含关系或布局事件。
    public struct DetailedEvent {

        /// 事件类型。
        public let kind: EventKind

        /// 事件涉及的父视图控制器；当前事件不涉及父控制器时为 `nil`。
        public let parent: UIViewController?

        /// 事件涉及的主要子视图控制器；当前没有子控制器时为 `nil`。
        public let viewController: UIViewController?

        /// 替换宿主控制器时的旧子视图控制器；事件不是替换或此前为空时为 `nil`。
        public let oldViewController: UIViewController?

        /// 替换宿主控制器时的新子视图控制器；事件不是替换或移除控制器时为 `nil`。
        public let newViewController: UIViewController?

        /// 可选的诊断上下文；事件没有附加原因时为 `nil`。
        public let reason: String?
    }

    /// 当前承载的子视图控制器；未设置或已移除时为 `nil`。
    public private(set) var viewController: UIViewController?

    /// 接收包含关系和布局事件的闭包。设置为 `nil` 时不发送该应用回调。
    public var eventHandler: ((Event) -> Void)?

    /// 接收包含父子控制器上下文的包含关系和布局事件闭包。设置为 `nil` 时不发送该应用回调。
    public var detailedEventHandler: ((DetailedEvent) -> Void)?

    /// 指示测量期间是否检测首选内容尺寸变化。
    public var observesPreferredContentSizeChanges = true

    private weak var parentViewController: UIViewController?
    private var isAttached = false
    private var usesExplicitParent = false
    private var lastPreferredContentSize: CGSize = .zero

    /// 为子视图控制器创建 representable 视图。
    ///
    /// representable 视图进入控制器拥有的视图层级时，会自动从 UIKit 响应者链解析父视图控制器。
    ///
    /// - Parameter viewController: 要嵌入的子视图控制器。
    public init(_ viewController: UIViewController) {
        self.viewController = viewController
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false
    }

    /// 使用明确指定的父控制器，为子视图控制器创建 representable 视图。
    ///
    /// - Parameters:
    ///   - viewController: 要嵌入的子视图控制器。
    ///   - parent: 负责包含关系的父视图控制器。
    public init(_ viewController: UIViewController, parent: UIViewController) {
        self.viewController = viewController
        self.parentViewController = parent
        self.usesExplicitParent = true
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = false
    }

    /// 从 Interface Builder 归档创建 representable 视图。
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = false
    }

    /// 替换当前承载的子视图控制器。
    ///
    /// representable 视图当前位于 QuickLayout 层级中时，会先移除旧子控制器，再附加新子控制器。
    ///
    /// - Parameter viewController: 新的子视图控制器；传入 `nil` 表示移除当前子控制器。
    public func setViewController(_ viewController: UIViewController?) {
        guard self.viewController !== viewController else {
            attachIfNeeded()
            return
        }

        let oldViewController = self.viewController
        emit(
            .willReplaceViewController,
            viewController: oldViewController,
            oldViewController: oldViewController,
            newViewController: viewController
        )
        detachIfNeeded()
        removeCurrentChildViewIfNeeded()
        self.viewController = viewController
        lastPreferredContentSize = viewController?.preferredContentSize ?? .zero
        attachIfNeeded()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        emit(
            .didReplaceViewController,
            viewController: viewController,
            oldViewController: oldViewController,
            newViewController: viewController
        )
    }

    /// 移除并释放当前承载的子视图控制器。
    public func dismantleViewController() {
        emit(.willDismantleViewController)
        detachIfNeeded()
        removeCurrentChildViewIfNeeded()
        viewController = nil
        lastPreferredContentSize = .zero
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        emit(.didDismantleViewController)
    }

    /// 捕获或替换负责包含关系的父视图控制器。
    ///
    /// representable 视图已经附加到其他父控制器时，会移除旧包含关系，并在视图可见时将
    /// 子控制器附加到新的父控制器。
    ///
    /// - Parameter parent: 新的父视图控制器。
    public func captureParent(_ parent: UIViewController) {
        guard parentViewController !== parent else {
            usesExplicitParent = true
            emit(.didCaptureParent)
            attachIfNeeded()
            return
        }

        detachIfNeeded()
        parentViewController = parent
        usesExplicitParent = true
        emit(.didCaptureParent)
        attachIfNeeded()
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        emit(.didMoveToSuperview)

        if superview == nil {
            detachIfNeeded()
        } else {
            attachIfNeeded()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
        if let childView = viewController?.view {
            childView.frame = bounds
        }
        emit(.didLayoutSubviews)
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let viewController else {
            return .zero
        }

        let preferredSize = viewController.preferredContentSize
        updatePreferredContentSizeIfNeeded(preferredSize)
        if preferredSize != .zero {
            return clamped(preferredSize, to: size)
        }

        let targetSize = CGSize(
            width: size.width.isFinite ? size.width : UIView.layoutFittingCompressedSize.width,
            height: size.height.isFinite ? size.height : UIView.layoutFittingCompressedSize.height
        )
        let horizontalPriority: UILayoutPriority = size.width.isFinite ? .required : .fittingSizeLevel
        let verticalPriority: UILayoutPriority = size.height.isFinite ? .required : .fittingSizeLevel
        viewController.loadViewIfNeeded()
        guard let childView = viewController.view else {
            return .zero
        }

        let measuredSize = childView.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: horizontalPriority,
            verticalFittingPriority: verticalPriority
        )

        return clamped(measuredSize, to: size)
    }

    /// 将宿主控制器布局标记为需要更新。
    public func setNeedsQuickLayout() {
        setNeedsLayout()
        viewController?.view?.setNeedsLayout()
    }

    /// 根据需要立即布局宿主控制器视图。
    public func quickLayoutIfNeeded() {
        layoutIfNeeded()
        viewController?.view?.layoutIfNeeded()
    }

    /// 使宿主子控制器布局和 representable 视图尺寸失效。
    public func invalidateChildLayout() {
        viewController?.view?.setNeedsLayout()
        viewController?.view?.invalidateIntrinsicContentSize()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        emit(.didInvalidateChildLayout)
    }
}

private extension QuickLayoutViewControllerRepresentable {

    func attachIfNeeded() {
        guard superview != nil else {
            return
        }
        guard let viewController else {
            return
        }
        resolveParentIfNeeded()
        guard !isAttached else {
            return
        }
        guard let parentViewController else {
            emit(.missingParent, viewController: viewController, reason: "No parent view controller in responder chain.")
            return
        }
        if let existingParent = viewController.parent, existingParent !== parentViewController {
            emit(
                .viewControllerAlreadyParented,
                parent: existingParent,
                viewController: viewController,
                reason: "The child already belongs to another parent."
            )
            return
        }

        emit(.willAttach, parent: parentViewController, viewController: viewController)

        if viewController.parent == nil {
            parentViewController.addChild(viewController)
        }

        viewController.loadViewIfNeeded()
        guard let childView = viewController.view else {
            return
        }

        if childView.superview !== self {
            childView.removeFromSuperview()
            childView.frame = bounds
            childView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(childView)
        }

        viewController.didMove(toParent: parentViewController)
        isAttached = true
        setNeedsLayout()

        lastPreferredContentSize = viewController.preferredContentSize
        emit(.didAttach, parent: parentViewController, viewController: viewController)
    }

    func resolveParentIfNeeded() {
        guard !usesExplicitParent, let resolvedParent = nearestOwningViewController() else {
            return
        }
        guard parentViewController !== resolvedParent else {
            return
        }

        detachIfNeeded()
        parentViewController = resolvedParent
        emit(.didCaptureParent, parent: resolvedParent, viewController: viewController)
    }

    func nearestOwningViewController() -> UIViewController? {
        var responder = next
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }

    func detachIfNeeded() {
        guard isAttached, let viewController else {
            return
        }

        let parentViewController = viewController.parent ?? parentViewController
        emit(.willDetach, parent: parentViewController, viewController: viewController)

        viewController.willMove(toParent: nil)
        viewController.view?.removeFromSuperview()
        viewController.removeFromParent()
        isAttached = false

        emit(.didDetach, parent: parentViewController, viewController: viewController)
    }

    func removeCurrentChildViewIfNeeded() {
        viewController?.view?.removeFromSuperview()
    }

    func emit(
        _ event: Event,
        parent: UIViewController? = nil,
        viewController: UIViewController? = nil,
        oldViewController: UIViewController? = nil,
        newViewController: UIViewController? = nil,
        reason: String? = nil
    ) {
        eventHandler?(event)
        detailedEventHandler?(
            DetailedEvent(
                kind: event,
                parent: parent ?? parentViewController,
                viewController: viewController ?? self.viewController,
                oldViewController: oldViewController,
                newViewController: newViewController,
                reason: reason
            )
        )
    }

    func clamped(_ measuredSize: CGSize, to maximumSize: CGSize) -> CGSize {
        CGSize(
            width: maximumSize.width.isFinite ? min(measuredSize.width, maximumSize.width) : measuredSize.width,
            height: maximumSize.height.isFinite ? min(measuredSize.height, maximumSize.height) : measuredSize.height
        )
    }

    func updatePreferredContentSizeIfNeeded(_ preferredContentSize: CGSize) {
        guard observesPreferredContentSizeChanges,
              preferredContentSize != lastPreferredContentSize else {
            return
        }

        lastPreferredContentSize = preferredContentSize
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }
}
