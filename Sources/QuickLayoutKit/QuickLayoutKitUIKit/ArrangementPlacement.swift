import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 布局结果使用宿主的物理坐标，RTL 仅影响水平方向的逻辑边缘。
struct ArrangementPlacement {
    let primary: CGRect
    let secondary: CGRect?
    let axis: Axis?
    let overlay: Bool

    @MainActor
    static func resolve(panes: ArrangementViewStyleConfiguration, style: ArrangementKind,
                        axes: AxisSet, rect: CGRect, divisions: [CGRect],
                        horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass,
                        rtl: Bool, scale: CGFloat = 1) -> Self {
        let single = Self(primary: rect, secondary: nil, axis: nil, overlay: false)
        let floating = Self(primary: rect, secondary: rect, axis: nil, overlay: true)

        // 只有贯穿当前容器、在两侧均留下空间的活动分隔区才参与排列。
        for division in divisions {
            let cut = rect.intersection(division)
            guard !cut.isNull else { continue }
            let across = cut.height >= rect.height && cut.minX > rect.minX && cut.maxX < rect.maxX
            let down = cut.width >= rect.width && cut.minY > rect.minY && cut.maxY < rect.maxY
            guard across || down else { continue }
            let axis: Axis = across ? .horizontal : .vertical
            guard axes.contains(across ? .horizontal : .vertical) else {
                return style == .overlay ? floating : single
            }
            let first = across ? rect.divided(atDistance: cut.minX - rect.minX, from: .minXEdge).slice
                               : rect.divided(atDistance: cut.minY - rect.minY, from: .minYEdge).slice
            let last = across ? rect.divided(atDistance: cut.maxX - rect.minX, from: .minXEdge).remainder
                              : rect.divided(atDistance: cut.maxY - rect.minY, from: .minYEdge).remainder
            var reverse = across && rtl
            if style == .overlay {
                if across {
                    let edge = panes.primary._layoutValue(for: OverlayHorizontalEdgeKey.self)
                    let other = panes.secondary._layoutValue(for: OverlayHorizontalEdgeKey.self)
                    if edge.map({ $0 == .trailing }) ?? (other == .leading) { reverse.toggle() }
                } else {
                    let edge = panes.primary._layoutValue(for: OverlayVerticalEdgeKey.self)
                    let other = panes.secondary._layoutValue(for: OverlayVerticalEdgeKey.self)
                    reverse = edge.map { $0 == .bottom } ?? (other == .top)
                }
            }
            return Self(primary: reverse ? last : first, secondary: reverse ? first : last,
                        axis: style == .split ? axis : nil, overlay: false)
        }

        guard style == .split else { return floating }
        let canRow = horizontal != .compact
        let canColumn = vertical != .compact
        guard canRow || canColumn else { return single }
        let row = canRow && (!canColumn || rect.width > rect.height)
        let axis: Axis = row ? .horizontal : .vertical
        guard axes.contains(row ? .horizontal : .vertical) else { return single }
        let available = row ? rect.width : rect.height
        return ArrangementLayoutContext.measure(axis: axis) {
            let p = panes.primary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let s = panes.secondary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let lower = p.min ?? 0, upper = available - (s.min ?? 0)
            guard lower <= upper else { return single }
            // 与同窗口 SwiftUI 对照：双方都有理想比例时，以主区为准；
            // 主区未声明偏好，才由辅助区反推边界。
            let ideal = p.ideal ?? s.ideal.map { available - $0 } ?? available / 2
            let snapped = scale > 0 ? (ideal * scale).rounded() / scale : ideal
            let length = min(upper, p.max ?? available, max(lower, available - (s.max ?? available), snapped))
            let edge: CGRectEdge = row ? (rtl ? .maxXEdge : .minXEdge) : .minYEdge
            let parts = rect.divided(atDistance: length, from: edge)
            let remaining = parts.remainder.divided(atDistance: min(available - length, s.max ?? available), from: edge).slice
            return Self(primary: parts.slice, secondary: remaining, axis: axis, overlay: false)
        }
    }
}
