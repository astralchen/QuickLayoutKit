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
                        axes: AxisSet, rect: CGRect, divisions: [CGRect], windowBounds: CGRect? = nil,
                        horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass,
                        rtl: Bool, scale: CGFloat = 1) -> Self {
        func single(_ axis: Axis?) -> Self {
            Self(primary: rect, secondary: nil, axis: axis, overlay: false)
        }
        let floating = Self(primary: rect, secondary: rect, axis: nil, overlay: true)
        let canRow = horizontal != .compact
        let canColumn = vertical != .compact
        let row = canRow && (!canColumn || rect.width > rect.height)
        let splitAxis: Axis = row ? .horizontal : .vertical

        // 分隔区止于窗口边缘。滚动内容可以超出窗口，仅在可见范围判断是否贯穿。
        let visible = windowBounds.map(rect.intersection) ?? rect
        for division in divisions {
            guard !visible.intersection(division).isEmpty else { continue }
            let cut = rect.intersection(division)
            let across = cut.minY <= visible.minY && cut.maxY >= visible.maxY
                && cut.minX > rect.minX && cut.maxX < rect.maxX
            let down = cut.minX <= visible.minX && cut.maxX >= visible.maxX
                && cut.minY > rect.minY && cut.maxY < rect.maxY
            guard across || down else { continue }
            let axis: Axis = across ? .horizontal : .vertical
            // Split 先按容器选轴。滚动使另一方向的折痕进入预览时，不应改变分栏方向。
            if style == .split, canRow || canColumn, axis != splitAxis { continue }
            guard axes.contains(across ? .horizontal : .vertical) else {
                return style == .overlay ? floating : single(axis)
            }
            let edge: CGRectEdge = across ? .minXEdge : .minYEdge
            let origin = across ? rect.minX : rect.minY
            func pixelBoundary(_ point: CGFloat) -> CGFloat {
                scale > 0 ? (point * scale).rounded() / scale : point
            }
            let near = pixelBoundary(across ? cut.minX : cut.minY)
            let far = pixelBoundary(across ? cut.maxX : cut.maxY)
            let first = rect.divided(atDistance: near - origin, from: edge).slice
            let last = rect.divided(atDistance: far - origin, from: edge).remainder
            var reverse = across && rtl
            if style == .split {
                return splitAtDivision(panes: panes, rect: rect, axis: axis,
                    leading: reverse ? last : first, trailing: reverse ? first : last,
                    edge: reverse ? .maxXEdge : edge, gap: far - near, scale: scale)
            }
            if across {
                let edge = panes.primary._layoutValue(for: OverlayHorizontalEdgeKey.self)
                let other = panes.secondary._layoutValue(for: OverlayHorizontalEdgeKey.self)
                if edge.map({ $0 == .trailing }) ?? (other == .leading) { reverse.toggle() }
            } else {
                let edge = panes.primary._layoutValue(for: OverlayVerticalEdgeKey.self)
                let other = panes.secondary._layoutValue(for: OverlayVerticalEdgeKey.self)
                reverse = edge.map { $0 == .bottom } ?? (other == .top)
            }
            return Self(primary: reverse ? last : first, secondary: reverse ? first : last,
                        axis: axis, overlay: false)
        }

        guard style == .split else { return floating }
        guard canRow || canColumn else {
            return single(rect.width > rect.height ? .horizontal : .vertical)
        }
        let axis = splitAxis
        guard axes.contains(row ? .horizontal : .vertical) else {
            // SwiftUI 在此时收起辅助内容，主内容仍可读到环境选中的轴。
            return single(axis)
        }
        let available = row ? rect.width : rect.height
        return ArrangementLayoutContext.measure(axis: axis) {
            let p = panes.primary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let s = panes.secondary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let lower = p.min ?? 0, upper = available - (s.min ?? 0)
            guard lower <= upper else { return single(nil) }
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

    /// 比例以完整可用长度换算。折痕能满足内容约束时分居两侧，否则在一侧尝试相邻排列。
    @MainActor
    private static func splitAtDivision(panes: ArrangementViewStyleConfiguration, rect: CGRect,
                                        axis: Axis, leading: CGRect, trailing: CGRect,
                                        edge: CGRectEdge, gap: CGFloat, scale: CGFloat) -> Self {
        func length(_ frame: CGRect) -> CGFloat { axis == .horizontal ? frame.width : frame.height }
        return ArrangementLayoutContext.measure(axis: axis) {
            let available = length(rect)
            let p = panes.primary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let s = panes.secondary.arrangementRange(axis: axis, available: available, proposal: rect.size)
            let fixed = panes.primary._layoutValue(for: FixedKey.self).contains(axis == .horizontal ? .horizontal : .vertical)
            let maximum = fixed ? min(p.max ?? available, p.ideal ?? available) : p.max ?? available
            let secondaryMin = s.min ?? 0
            let useTrailing = length(leading) < (p.min ?? 0)
            let separated = Self(primary: leading, secondary: trailing, axis: axis, overlay: false)
            if !useTrailing && length(leading) <= maximum && length(trailing) >= secondaryMin { return separated }

            // 同窗口原生参考：改用尾侧的长度时，内容从逻辑起点偏移分隔带的厚度。
            let space: CGRect
            if useTrailing {
                space = rect.divided(atDistance: gap, from: edge).remainder
                    .divided(atDistance: length(trailing), from: edge).slice
            } else {
                space = leading
            }
            // 同侧排列时先预留辅助内容明确请求的理想长度，再应用主内容的范围。
            let ideal = s.ideal.map { available - $0 } ?? p.ideal ?? available / 2
            let snapped = scale > 0 ? (ideal * scale).rounded() / scale : ideal
            let primaryLength = min(maximum, max(p.min ?? 0, available - (s.max ?? available), snapped))
            guard primaryLength + secondaryMin <= length(space) else {
                if !useTrailing && length(trailing) >= secondaryMin { return separated }
                return Self(primary: space, secondary: nil, axis: axis, overlay: false)
            }
            let parts = space.divided(atDistance: primaryLength, from: edge)
            let rest = parts.remainder.divided(atDistance: min(length(parts.remainder), s.max ?? available), from: edge).slice
            return Self(primary: parts.slice, secondary: rest, axis: axis, overlay: false)
        }
    }
}
