import UIKit
import QuickLayout

/// 指定宿主将 QuickLayout 内容的理想尺寸发布给哪些 UIKit 接口。
public struct QuickLayoutHostingControllerSizingOptions: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// 内容尺寸变化时更新控制器的 `preferredContentSize`。
    public static let preferredContentSize = Self(rawValue: 1 << 0)

    /// 通过根视图的 `intrinsicContentSize` 向 Auto Layout 提供内容尺寸。
    public static let intrinsicContentSize = Self(rawValue: 1 << 1)
}

/// 用于承载 QuickLayout 内容的视图控制器。
///
/// 可以创建子类并重写 ``body``，为控制器根视图提供 QuickLayout 层级；也可以使用
/// ``init(content:)`` 创建实例并以内联方式提供内容。
open class QuickLayoutHostingController: UIViewController, QuickLayoutUpdating {

    // MARK: - 属性

    /// 将控制器的 `body` 转交给通用 QuickLayout 宿主的根视图。
    private final class ContainerView: QuickLayoutView {
        /// 提供布局内容的控制器弱引用，避免根视图与控制器循环持有。
        weak var hostingController: QuickLayoutHostingController?

        private var options: QuickLayoutHostingControllerSizingOptions = []
        private var idealSize: CGSize?
        private var publishedIntrinsicSize: CGSize?
        private var isMeasuringIdealSize = false

        /// 读取所属控制器的布局；控制器不存在时返回空布局。
        override var body: Layout {
            hostingController?.body ?? EmptyLayout()
        }

        func applySizingOptions(_ newOptions: QuickLayoutHostingControllerSizingOptions) {
            options = newOptions.intersection([.preferredContentSize, .intrinsicContentSize])
            updateSizing()
        }

        override var intrinsicContentSize: CGSize {
            if options.contains(.intrinsicContentSize) {
                updateSizingIfNeeded()
            }
            return publishedIntrinsicSize ?? super.intrinsicContentSize
        }

        override func setNeedsQuickLayout() {
            super.setNeedsQuickLayout()
            guard idealSize != nil else { return }
            idealSize = nil
            // 零尺寸或尚未显示的宿主也需要把内容更新通知父容器。
            DispatchQueue.main.async { [weak self] in self?.updateSizingIfNeeded() }
        }

        override func layoutSubviews() {
            updateSizingIfNeeded()
            super.layoutSubviews()
        }

        private func updateSizingIfNeeded() {
            if !options.isEmpty && idealSize == nil { updateSizing() }
        }

        private func updateSizing() {
            guard !isMeasuringIdealSize else { return }
            if options.isEmpty {
                idealSize = nil
            } else if idealSize == nil {
                isMeasuringIdealSize = true
                let measured = QuickLayoutIdealSizeMeasurement.$isActive.withValue(true) {
                    sizeThatFits(CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
                }
                isMeasuringIdealSize = false
                if !options.isEmpty { idealSize = measured }
            }

            let intrinsic = options.contains(.intrinsicContentSize)
                ? idealSize?.replacingUndefinedLengths(with: UIView.noIntrinsicMetric)
                : nil
            if intrinsic != publishedIntrinsicSize {
                publishedIntrinsicSize = intrinsic
                invalidateIntrinsicContentSize()
            }
            if options.contains(.preferredContentSize), let idealSize, let hostingController {
                let preferred = idealSize.replacingUndefinedLengths(with: 0)
                if hostingController.preferredContentSize != preferred {
                    hostingController.preferredContentSize = preferred
                }
            }
        }
    }

    /// 以内联初始化方式提供内容的构建闭包；未设置时由 `body` 的默认实现返回空布局。
    private var contentProvider: (() -> Layout)?

    /// 自动跟踪内容理想尺寸的方式，默认值为 `[]`。可在加载视图之前设置。
    public var sizingOptions: QuickLayoutHostingControllerSizingOptions = [] {
        didSet {
            guard sizingOptions != oldValue else { return }
            (viewIfLoaded as? ContainerView)?.applySizingOptions(sizingOptions)
        }
    }

    /// 首次访问时创建的根宿主，负责布局、测量与键盘安全区域发布。
    private lazy var containerView: ContainerView = {
        let view = ContainerView()
        view.hostingController = self
        return view
    }()

    /// 根 QuickLayout 宿主自动发布键盘安全区域的方式。
    open var quickLayoutKeyboardSafeAreaBehavior:
        QuickLayoutKeyboardSafeAreaBehavior {
        get { containerView.quickLayoutKeyboardSafeAreaBehavior }
        set { containerView.quickLayoutKeyboardSafeAreaBehavior = newValue }
    }

    /// 当前根宿主向 QuickLayout 层级发布的物理键盘安全区域边距。
    public var quickLayoutKeyboardSafeAreaInsets: UIEdgeInsets {
        containerView.quickLayoutKeyboardSafeAreaInsets
    }

    /// 键盘上方可提前开始滚动收起手势的区域高度。
    ///
    /// 该属性只影响 `UIScrollView` 的键盘收起交互，不改变 QuickLayout 键盘安全区域。
    @available(iOS 17.0, *)
    open var quickLayoutKeyboardDismissPadding: CGFloat {
        get { containerView.quickLayoutKeyboardDismissPadding }
        set { containerView.quickLayoutKeyboardDismissPadding = newValue }
    }

    /// 替换根宿主的键盘事件源与 docked 判定器，仅供跨模块确定性测试使用。
    ///
    /// 该 SPI 会先停用现有协调器、注入依赖，再恢复原行为，确保测试覆盖公开行为属性
    /// 的完整启停链路，而不是直接写入发布的 safe-area 值。
    @_spi(Testing)
    public final func configureQuickLayoutKeyboardSafeAreaForTesting(
        notificationCenter: NotificationCenter,
        dockingResolver: @MainActor @escaping (
            QuickLayoutKeyboardContext,
            UIView
        ) -> Bool
    ) {
        let behavior = quickLayoutKeyboardSafeAreaBehavior
        quickLayoutKeyboardSafeAreaBehavior = .disabled
        containerView.configureQuickLayoutKeyboardSafeAreaForTesting(
            notificationCenter: notificationCenter,
            dockingResolver: dockingResolver
        )
        quickLayoutKeyboardSafeAreaBehavior = behavior
    }

    // MARK: - 初始化

    /// 创建以内联方式提供 QuickLayout 内容的宿主控制器。
    ///
    /// - Parameter content: 返回宿主内容的构建器闭包。
    public convenience init(@LayoutBuilder content: @escaping () -> Layout) {
        self.init(nibName: nil, bundle: nil)
        self.contentProvider = content
    }

    /// 创建内联宿主，并在首次加载根视图时开始跟踪指定的内容尺寸。
    public convenience init(
        sizingOptions: QuickLayoutHostingControllerSizingOptions,
        @LayoutBuilder content: @escaping () -> Layout
    ) {
        self.init(content: content)
        self.sizingOptions = sizingOptions
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

    /// 将 QuickLayout 宿主安装为根视图，并设置系统背景色。
    override open func loadView() {
        view = containerView
        view.backgroundColor = .systemBackground
        containerView.applySizingOptions(sizingOptions)
    }

    // MARK: - 布局更新

    /// 将宿主布局标记为需要更新。
    ///
    /// 更改影响 ``body`` 的状态后调用此方法。
    open func setNeedsQuickLayout() {
        containerView.setNeedsQuickLayout()
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

private extension CGSize {
    /// 自定义布局在某一轴没有理想长度时，向对应的 UIKit 接口提供该轴的缺省值。
    func replacingUndefinedLengths(with fallback: CGFloat) -> CGSize {
        func length(_ value: CGFloat) -> CGFloat {
            value >= 0 && value < .greatestFiniteMagnitude ? value : fallback
        }
        return CGSize(width: length(width), height: length(height))
    }
}
