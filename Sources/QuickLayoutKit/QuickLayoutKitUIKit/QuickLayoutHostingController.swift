import UIKit
import QuickLayout

/// 用于承载 QuickLayout 内容的视图控制器。
///
/// 可以创建子类并重写 ``body``，为控制器根视图提供 QuickLayout 层级；也可以使用
/// ``init(content:)`` 创建实例并以内联方式提供内容。
open class QuickLayoutHostingController: UIViewController, QuickLayoutUpdating {

    // MARK: - 属性

    private final class ContainerView: QuickLayoutView {
        weak var hostingController: QuickLayoutHostingController?

        override var body: Layout {
            hostingController?.body ?? EmptyLayout()
        }
    }

    private var contentProvider: (() -> Layout)?

    private lazy var containerView: ContainerView = {
        let view = ContainerView()
        view.hostingController = self
        return view
    }()

    // MARK: - 初始化

    /// 创建以内联方式提供 QuickLayout 内容的宿主控制器。
    ///
    /// - Parameter content: 返回宿主内容的构建器闭包。
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(nibName: nil, bundle: nil)
        self.contentProvider = content
    }

    // MARK: - 布局内容

    /// 视图控制器承载的 QuickLayout 内容。
    ///
    /// 默认实现返回空布局。子类可以重写该属性以返回根布局。
    @LayoutBuilder
    open var body: Layout {
        if let contentProvider {
            contentProvider()
        } else {
            EmptyLayout()
        }
    }

    // MARK: - 生命周期

    override open func loadView() {
        view = containerView
        view.backgroundColor = .systemBackground
    }

    // MARK: - 布局更新

    /// 将宿主布局标记为需要更新。
    ///
    /// 更改影响 ``body`` 的状态后调用此方法。
    open func setNeedsQuickLayout() {
        containerView.setNeedsLayout()
    }

    /// 根据需要立即布局宿主内容。
    open func quickLayoutIfNeeded() {
        containerView.layoutIfNeeded()
    }

    /// 返回最适合指定约束的尺寸。
    ///
    /// - Parameter size: 宿主内容可使用的最大尺寸。
    /// - Returns: 适合宿主布局的尺寸。
    open func sizeThatFits(in size: CGSize) -> CGSize {
        return containerView.sizeThatFits(size)
    }
}
