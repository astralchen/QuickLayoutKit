import QuickLayout
import UIKit

public extension Element {

    /// 将元素的中心放置在父元素所建议空间内的指定点。
    ///
    /// - Parameter position: 元素中心在父元素坐标空间中的位置。
    /// - Returns: 中心位于指定位置的元素。
    func position(_ position: CGPoint) -> Element & Layout {
        PositionElement(child: self, position: position)
    }

    /// 将元素的中心放置在父元素所建议空间内的指定坐标。
    ///
    /// - Parameters:
    ///   - x: 元素中心的水平坐标。
    ///   - y: 元素中心的垂直坐标。
    /// - Returns: 中心位于指定坐标的元素。
    func position(x: CGFloat, y: CGFloat) -> Element & Layout {
        position(CGPoint(x: x, y: y))
    }

    /// 控制重叠元素的显示顺序。
    ///
    /// 值较大的元素显示在值较小的元素前面；值相同时保持源码中的声明顺序。
    /// 当移除此修饰符或视图移动到其他宿主时，QuickLayoutKit 宿主会恢复视图原有的
    /// `layer.zPosition`。在 QuickLayoutKit 宿主之外直接使用 QuickLayout 布局时，
    /// 仍保持一次性写入图层层级的行为。
    ///
    /// - Parameter value: 元素的显示层级。非有限值按 `0` 处理。
    /// - Returns: 应用指定显示层级后的元素。
    func zIndex(_ value: Double) -> Element & Layout {
        ZIndexElement(child: self, value: value.isFinite ? value : 0)
    }
}

enum _ZIndexLayoutValueKey: LayoutValueKey {
    static let defaultValue: Double = 0
}

private struct PositionElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let position: CGPoint

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let childLayout = child.quick_layoutThatFits(
            ProposedSize.unspecified.quickLayoutProposal
        )
        let size = CGSize(
            width: proposedSize.width.isFinite
                ? max(0, proposedSize.width)
                : childLayout.size.width,
            height: proposedSize.height.isFinite
                ? max(0, proposedSize.height)
                : childLayout.size.height
        )
        let origin = CGPoint(
            x: finite(position.x) - childLayout.size.width / 2,
            y: finite(position.y) - childLayout.size.height / 2
        )

        return positionedPositionElement(
            childLayout,
            at: origin,
            in: size
        ).quick_layoutThatFits(size)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

private struct ZIndexElement: Layout, _LayoutValueProvidingElement {

    let child: Element
    let value: Double

    var _layoutValueChild: Element { child }

    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? {
        guard key == ObjectIdentifier(_ZIndexLayoutValueKey.self) else { return nil }
        return _AnyLayoutValue(value: value)
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        let startIndex = views.endIndex
        child.quick_extractViewsIntoArray(&views)
        guard Thread.isMainThread else { return }
        let zPosition = CGFloat(value)
        MainActor.assumeIsolated {
            for view in views[startIndex...] {
                if let store = QuickLayoutManagedViewStateContext.current {
                    store.applyZIndex(zPosition, to: view)
                } else {
                    // 直接集成 QuickLayout 时不存在宿主渲染边界，因此保留原有的一次性写入行为。
                    view.layer.zPosition = zPosition
                }
            }
        }
    }
}

private struct PositionPrecomputedLayoutElement: Layout {
    let layout: LayoutNode

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func positionedPositionElement(
    _ layout: LayoutNode,
    at origin: CGPoint,
    in containerSize: CGSize
) -> Element & Layout {
    let horizontalOffset: CGFloat
    if LayoutContext.layoutDirection == .rightToLeft {
        let leadingOrigin = containerSize.width - layout.size.width
        horizontalOffset = leadingOrigin - origin.x
    } else {
        horizontalOffset = origin.x
    }

    let offsetChild = OffsetElement(
        child: PositionPrecomputedLayoutElement(layout: layout),
        offset: CGPoint(x: horizontalOffset, y: origin.y)
    )
        // 避免外层固定框架解析顶部前缘对齐时，子元素的对齐参考线改变此处的物理位置。
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }

    let positionedChild = FixedFrameElement(
        child: offsetChild,
        width: containerSize.width,
        height: containerSize.height,
        alignment: .topLeading
    )
    return positionedChild
        // 按父元素的布局方向解析包装层参考线，避免局部布局方向覆盖向外泄漏物理补偿。
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }
}

private func finite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}
