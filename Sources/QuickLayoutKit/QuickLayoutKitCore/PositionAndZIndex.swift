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

/// 自定义布局排序时使用的显示层级键。
enum _ZIndexLayoutValueKey: LayoutValueKey {
    /// 未设置显示层级时使用零。
    static let defaultValue: Double = 0
}

/// 以物理中心坐标放置理想尺寸内容的包装器。
private struct PositionElement: Layout, _LayoutValueProvidingElement {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 子元素中心在父布局建议空间中的物理坐标。
    let position: CGPoint

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }

    /// 本层不提供布局值，交由查询器继续访问子元素。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? { nil }

    /// 测量理想尺寸，解析有限容器空间，再补偿布局方向放置内容。
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

    /// 允许父布局在指定轴上完整分配可用空间。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fullyFlexible
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }
}

/// 同时发布布局排序值并管理 UIKit 图层层级的包装器。
private struct ZIndexElement: Layout, _LayoutValueProvidingElement {

    /// 被当前修饰元素包装的布局内容。
    let child: Element
    /// 已归一化为有限数值的显示层级。
    let value: Double

    /// 继续向内查询自定义布局值时访问的子元素。
    var _layoutValueChild: Element { child }

    /// 仅为显示层级键提供值，其他键继续向子元素查询。
    func _layoutValue(for key: ObjectIdentifier) -> _AnyLayoutValue? {
        guard key == ObjectIdentifier(_ZIndexLayoutValueKey.self) else { return nil }
        return _AnyLayoutValue(value: value)
    }

    /// 原样传递尺寸建议并返回子元素的测量结果。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        child.quick_layoutThatFits(proposedSize)
    }

    /// 沿用子元素在指定轴上的尺寸弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 提取新增视图并在主线程应用层级；有宿主时记录可恢复的原始值。
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

/// 保存位置计算前的测量节点，防止包装层改变子元素尺寸。
private struct PositionPrecomputedLayoutElement: Layout {
    /// 已完成测量的布局节点，供包装层直接复用。
    let layout: LayoutNode

    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat { 0 }
    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 将物理原点转换为方向性偏移，并用固定容器维持外层尺寸。
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

/// 将非有限坐标转换为零，避免污染布局几何。
private func finite(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}
