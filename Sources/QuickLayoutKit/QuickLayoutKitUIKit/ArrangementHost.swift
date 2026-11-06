import QuickLayout
import QuickLayoutKitCore
import UIKit

enum ArrangementKind { case split, overlay }

/// UIKit 只提供环境；区域尺寸和位置均由 QuickLayout 排版。
@MainActor
final class ArrangementHost: QuickLayoutView {
    private let primary = ArrangementPane()
    private let secondary = ArrangementPane()
    private var panes: ArrangementViewStyleConfiguration?
    private var style: ArrangementKind = .split
    private var axes: AxisSet = [.horizontal, .vertical]

    // 外层 body 可能每次测量都重新创建。复用同一组内容的宿主，避免打断输入与滚动。
    private static let hosts = NSMapTable<UIView, ArrangementHost>.weakToWeakObjects()

    static func make(panes: ArrangementViewStyleConfiguration, style: ArrangementKind, axes: AxisSet) -> ArrangementHost {
        var views: [UIView] = []
        panes.primary.quick_extractViewsIntoArray(&views)
        if views.isEmpty { panes.secondary.quick_extractViewsIntoArray(&views) }
        let host = views.first.flatMap { hosts.object(forKey: $0) } ?? ArrangementHost()
        if let key = views.first { hosts.setObject(host, forKey: key) }
        host.panes = panes
        host.primary.element = inheritingArrangementStyle(panes.primary)
        host.secondary.element = inheritingArrangementStyle(panes.secondary)
        host.axes = axes
        host.style = style
        host.setNeedsLayout()
        return host
    }

    override var body: Layout {
        guard let panes else { return EmptyLayout() }
        let rect = bounds.inset(by: safeAreaInsets)
        var divisions: [CGRect] = []
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            divisions = reservedRegions(kind: .division).map(\.frame)
        }
        #endif
        let placement = ArrangementPlacement.resolve(
            panes: panes, style: style, axes: axes, rect: rect, divisions: divisions,
            horizontal: traitCollection.horizontalSizeClass, vertical: traitCollection.verticalSizeClass,
            rtl: effectiveUserInterfaceLayoutDirection == .rightToLeft, scale: traitCollection.displayScale
        )
        return ZStack {
            if let frame = placement.secondary {
                secondary.placed(in: frame, axis: placement.axis, zIndex: 0)
            }
            primary.placed(in: placement.primary, axis: placement.axis, zIndex: placement.overlay ? 1 : 0)
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsLayout()
    }
}

private final class ArrangementPane: QuickLayoutView, ArrangementContextSource {
    var element: Layout = EmptyLayout() { didSet { setNeedsLayout() } }
    var arrangementAxis: Axis?
    var arrangementZIndex = 0

    override var body: Layout { element }

    func placed(in frame: CGRect, axis: Axis?, zIndex: Int) -> Layout {
        if axis != arrangementAxis || zIndex != arrangementZIndex {
            arrangementAxis = axis
            arrangementZIndex = zIndex
            setNeedsLayout()
        }
        return resizable().frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    override func layoutSubviews() {
        ArrangementLayoutContext.measure(axis: arrangementAxis, zIndex: arrangementZIndex) { super.layoutSubviews() }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        ArrangementLayoutContext.measure(axis: arrangementAxis, zIndex: arrangementZIndex) { super.sizeThatFits(size) }
    }
}
