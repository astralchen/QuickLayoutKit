import QuickLayout
import UIKit

public extension Layout {
    /// 以逻辑坐标计算水平参考线，转换为父布局所需的 LTR / RTL 物理坐标。
    /// 连续组合参考线时，不会在传播过程中重复执行 `computeValue`。
    func alignmentGuide(_ alignment: HorizontalAlignment,
                        computeValue: @escaping @Sendable (ElementDimensions) -> CGFloat) -> some Layout {
        ResolvedAlignmentGuide(child: self, guide: .horizontal(alignment), computeValue: computeValue)
    }

    /// 在本次测量中计算垂直参考线，向父布局传播已计算的值。
    func alignmentGuide(_ alignment: VerticalAlignment,
                        computeValue: @escaping @Sendable (ElementDimensions) -> CGFloat) -> some Layout {
        ResolvedAlignmentGuide(child: self, guide: .vertical(alignment), computeValue: computeValue)
    }
}

public extension LeafElement {
    /// 为叶元素计算水平参考线，保持与布局元素相同的传播语义。
    func alignmentGuide(_ alignment: HorizontalAlignment,
                        computeValue: @escaping @Sendable (ElementDimensions) -> CGFloat) -> some Layout {
        ResolvedAlignmentGuide(child: self, guide: .horizontal(alignment), computeValue: computeValue)
    }

    /// 为叶元素计算垂直参考线，保持与布局元素相同的传播语义。
    func alignmentGuide(_ alignment: VerticalAlignment,
                        computeValue: @escaping @Sendable (ElementDimensions) -> CGFloat) -> some Layout {
        ResolvedAlignmentGuide(child: self, guide: .vertical(alignment), computeValue: computeValue)
    }
}

extension Layout {
    /// 物理定位容器的边缘参考线随父布局方向解析，不捕获子树局部的 LTR / RTL。
    /// 这属于容器内部的默认边缘规则，与用户参考线的按次测量求值不同。
    func defaultPlacementGuides() -> some Layout {
        AlignmentGuideElement(
            child: AlignmentGuideElement(child: self, horizontalAlignment: .leading) {
                ElementDimensions(CGSize(width: $0.width, height: $0.height))[HorizontalAlignment.leading]
            },
            verticalAlignment: .top
        ) { _ in 0 }
    }
}

/// 上游会在包装节点传播参考线时再次调用闭包，并传入包含该参考线的 dimensions。
/// 将闭包求值与传播分开，避免 `d[guide] + offset` 的 offset 被重复累计。
private struct ResolvedAlignmentGuide: Layout {
    enum Guide {
        case horizontal(HorizontalAlignment)
        case vertical(VerticalAlignment)
    }

    let child: Element
    let guide: Guide
    let computeValue: @Sendable (ElementDimensions) -> CGFloat

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let node = child.quick_layoutThatFits(proposedSize)
        let context = AlignmentGuideEvaluation(dimensions: node.dimensions, direction: LayoutContext.layoutDirection)
        let logicalDimensions = logicalGuideDimensions(of: node)
        let value = AlignmentGuideEvaluation.$current.withValue(context) {
            computeValue(logicalDimensions)
        }
        let measured = AlignmentGuideMeasuredNode(node: node)
        switch guide {
        case let .horizontal(alignment):
            let width = node.size.width
            let result = AlignmentGuideElement(child: measured, horizontalAlignment: alignment) { _ in
                if let evaluation = AlignmentGuideEvaluation.current {
                    // 上游传播器在闭包返回后加上祖先物理偏移。先扣除这段偏移，
                    // 使最外层 dimensions 的查询最终得到其自身坐标系的逻辑值。
                    let physical = AlignmentGuideEvaluation.$current.withValue(nil) {
                        LayoutContext.$layoutDirection.withValue(evaluation.direction) {
                            evaluation.dimensions[alignment]
                        }
                    }
                    let local = evaluation.direction == .rightToLeft ? width - value : value
                    let logical = evaluation.direction == .rightToLeft ? evaluation.dimensions.width - physical : physical
                    return logical - (physical - local)
                }
                return LayoutContext.layoutDirection == .rightToLeft ? width - value : value
            }
                .quick_layoutThatFits(proposedSize)
            return HorizontalGuideMetadata.attaching(alignment, to: result)
        case let .vertical(alignment):
            return AlignmentGuideElement(child: measured, verticalAlignment: alignment) { _ in value }
                .quick_layoutThatFits(proposedSize)
        }
    }

    func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
}

/// 每次闭包求值只作用于当前子树，不重复测量内容，也不修改全局布局方向。
private struct AlignmentGuideEvaluation: Sendable {
    @TaskLocal static var current: AlignmentGuideEvaluation?
    let dimensions: ElementDimensions
    let direction: LayoutDirection
}

private struct AlignmentGuideMeasuredNode: Layout {
    let node: LayoutNode
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 从最终节点恢复水平参考线；不依赖构建、测量或缓存命中的执行路径。
/// 私有垂直参考线只携带标记，沿上游的自定义参考线传播规则保留，
/// 不增加视图或布局空间。网格消费参考线时也会消费该标记。
enum HorizontalGuideMetadata {
    private static let marker = VerticalAlignment(Marker.self)
    @TaskLocal private static var reading: ReadContext?

    static func attaching(_ alignment: HorizontalAlignment, to node: LayoutNode) -> LayoutNode {
        // 内置参考线始终按节点尺寸转换，不需要额外标记。
        guard !isBuiltInHorizontalGuide(alignment) else { return node }
        return AlignmentGuideElement(child: AlignmentGuideMeasuredNode(node: node), verticalAlignment: marker) { _ in
            reading?.record(alignment)
            return 0
        }.quick_layoutThatFits(node.size)
    }

    static func alignments(in node: LayoutNode) -> [HorizontalAlignment] {
        var result: [AnyAlignmentID: HorizontalAlignment] = [:]
        collect(node, into: &result)
        return Array(result.values)
    }

    private static func collect(_ node: LayoutNode, into result: inout [AnyAlignmentID: HorizontalAlignment]) {
        let context = ReadContext()
        $reading.withValue(context) { _ = node.dimensions[marker] }
        let snapshot = context.snapshot
        // 默认值被读取意味着此节点没有显式标记，整条分支已消费或未提供参考线。
        guard !snapshot.absent else { return }
        for alignment in snapshot.alignments { result[alignment.alignmentID] = alignment }
        // 多元素容器会将标记闭包聚合成常量；实际标记仍保存在它保留的子节点中。
        for child in node.children { collect(child.layout, into: &result) }
    }

    private enum Marker: AlignmentID {
        static func defaultValue(in context: ElementDimensions) -> CGFloat {
            reading?.markAbsent()
            return 0
        }
    }

    /// 查询上下文只在读取标记时存在；不用数值判断标记是否存在，避免位置偏移干扰。
    private final class ReadContext: @unchecked Sendable {
        private let lock = NSLock()
        private var absent = false
        private var values: [AnyAlignmentID: HorizontalAlignment] = [:]

        var snapshot: (absent: Bool, alignments: [HorizontalAlignment]) {
            lock.lock()
            defer { lock.unlock() }
            return (absent, Array(values.values))
        }
        func markAbsent() {
            lock.lock()
            defer { lock.unlock() }
            absent = true
        }
        func record(_ alignment: HorizontalAlignment) {
            lock.lock()
            defer { lock.unlock() }
            values[alignment.alignmentID] = alignment
        }
    }
}

/// 用户闭包始终读取逻辑坐标。显式自定义参考线从最终布局树读取，默认值保留其语义。
private func logicalGuideDimensions(of node: LayoutNode,
                                    explicit: [HorizontalAlignment]? = nil) -> ElementDimensions {
    guard LayoutContext.layoutDirection == .rightToLeft else { return node.dimensions }
    var alignments: [AnyAlignmentID: HorizontalAlignment] = [:]
    for alignment in [HorizontalAlignment.leading, .center, .trailing]
        + (explicit ?? HorizontalGuideMetadata.alignments(in: node)) {
        alignments[alignment.alignmentID] = alignment
    }
    var logicalNode = node
    for alignment in alignments.values {
        let logical = node.size.width - node.dimensions[alignment]
        logicalNode = AlignmentGuideElement(child: AlignmentGuideMeasuredNode(node: logicalNode),
                                           horizontalAlignment: alignment) { _ in logical }
            .quick_layoutThatFits(node.size)
    }
    return logicalNode.dimensions
}

/// 自定义默认值来自逻辑坐标；显式值与内置参考线已由节点提供物理坐标。
func physicalHorizontalGuide(_ alignment: HorizontalAlignment, in node: LayoutNode) -> CGFloat {
    guard LayoutContext.layoutDirection == .rightToLeft, !isBuiltInHorizontalGuide(alignment) else {
        return node.dimensions[alignment]
    }
    let explicit = HorizontalGuideMetadata.alignments(in: node)
    guard !explicit.contains(where: { $0.alignmentID == alignment.alignmentID }) else {
        return node.dimensions[alignment]
    }
    return node.size.width - logicalGuideDimensions(of: node, explicit: explicit)[alignment]
}

func isBuiltInHorizontalGuide(_ alignment: HorizontalAlignment) -> Bool {
    [HorizontalAlignment.leading, .center, .trailing].contains { $0.alignmentID == alignment.alignmentID }
}
