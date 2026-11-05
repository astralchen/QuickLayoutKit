import QuickLayout
import UIKit

/// 水平排列内容，并在容器边界合并参考线。间距默认保持 QuickLayout 的 0。
public func HStack(
    alignment: VerticalAlignment = .center,
    spacing: CGFloat = 0,
    @FastArrayBuilder<Element> children: () -> [Element]
) -> StackElement {
    containerStack(children: children(), axis: .horizontal, spacing: spacing, alignment: alignment.alignmentID,
                   alignmentValue: { $0.dimensions[alignment] })
}

/// 垂直排列内容，并在容器边界合并参考线。间距默认保持 QuickLayout 的 0。
public func VStack(
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat = 0,
    @FastArrayBuilder<Element> children: () -> [Element]
) -> StackElement {
    containerStack(children: children(), axis: .vertical, spacing: spacing, alignment: alignment.alignmentID,
                   alignmentValue: { physicalHorizontalGuide(alignment, in: $0) },
                   normalizesMultipleChildren: !isBuiltInHorizontalGuide(alignment))
}

private func containerStack(children: [Element], axis: Axis, spacing: CGFloat, alignment: AnyAlignmentID,
                            alignmentValue: @escaping @Sendable (LayoutNode) -> CGFloat,
                            normalizesMultipleChildren: Bool = false) -> StackElement {
    let contents: [Element]
    if let child = children.first, children.count == 1 {
        contents = [SingleChildStackContainer(child: child, axis: axis, alignmentValue: alignmentValue)]
    } else if normalizesMultipleChildren && children.count > 1 {
        // 私有放置参考线只参与排布。默认值不合成为用户的显式参考线，
        // 避免父容器在聚合时把使用默认值的元素也计入平均值。
        let guide = HorizontalAlignment(StackHorizontalPlacementGuide.self)
        var normalized: [Element] = children.map {
            StackAlignedChild(child: $0, guide: guide, alignmentValue: alignmentValue)
        }
        // 对齐原点也属于容器边界。参考线越过全部子元素时，仍需保留这段空间；
        // 零尺寸 spacer 不插入间距，不参与用户参考线聚合或 idealLayout 的等宽判断。
        normalized.append(StackAlignmentOrigin())
        return StackElement(children: normalized, mainAxis: axis, spacing: spacing, alignmentID: guide.alignmentID)
    } else {
        contents = children
    }
    return StackElement(children: contents, mainAxis: axis, spacing: spacing, alignmentID: alignment)
}

/// 上游单元素快捷路径采用包装器的参考线传播规则。通过零尺寸原点参与布局，
/// 使用其完整容器路径处理尺寸、放置和参考线合并，而不更改 QuickLayout 依赖。
/// 原点不提供显式参考线，因此不会干扰自定义参考线的聚合。
private struct SingleChildStackContainer: Layout {
    let child: Element
    let axis: Axis
    let alignmentValue: @Sendable (LayoutNode) -> CGFloat

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let node = child.quick_layoutThatFits(proposedSize)
        let value = alignmentValue(node)
        let measured = StackMeasuredNode(node: node)
        // 私有参考线让原点的默认值始终为 0；用户自定义 ID 可以有非零默认值。
        // 用户参考线仍由原节点提供，不把原点计入自定义参考线的平均值。
        let aligned: Element
        let id: AnyAlignmentID
        if axis == .horizontal {
            let guide = VerticalAlignment(StackVerticalPlacementGuide.self)
            id = guide.alignmentID
            aligned = AlignmentGuideElement(child: measured, verticalAlignment: guide) { _ in value }
        } else {
            let guide = HorizontalAlignment(StackHorizontalPlacementGuide.self)
            id = guide.alignmentID
            aligned = AlignmentGuideElement(child: measured, horizontalAlignment: guide) { _ in value }
        }
        return StackElement(children: [aligned, StackAlignmentOrigin()], mainAxis: axis,
                            spacing: 0, alignmentID: id).quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
    func quickInternal_isSpacer() -> Bool { child.quickInternal_isSpacer() }
}

/// 无视图、无间距的布局原点；只参与容器的边界计算。
private struct StackAlignmentOrigin: Layout {
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { .empty }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
    func quickInternal_isSpacer() -> Bool { true }
}

private enum StackHorizontalPlacementGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 0 }
}

private struct StackMeasuredNode: Layout {
    let node: LayoutNode
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private enum StackVerticalPlacementGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 0 }
}

/// 保留原有子元素的弹性、优先级与测量次数，仅规范父栈读取的放置坐标。
private struct StackAlignedChild: Layout {
    let child: Element
    let guide: HorizontalAlignment
    let alignmentValue: @Sendable (LayoutNode) -> CGFloat

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let node = child.quick_layoutThatFits(proposedSize)
        let value = alignmentValue(node)
        return AlignmentGuideElement(child: StackMeasuredNode(node: node), horizontalAlignment: guide) { _ in value }
            .quick_layoutThatFits(proposedSize)
    }
    func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
    func quickInternal_isSpacer() -> Bool { child.quickInternal_isSpacer() }
}
