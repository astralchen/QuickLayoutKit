import QuickLayout
import UIKit

/// 按列规则逐行排列全部内容的非懒加载网格。
///
/// `columns` 描述水平方向的尺寸和间距，`spacing` 描述相邻行的间距。
/// 内容在构建时全部创建，布局时全部测量；滚动由外层 `ScrollView` 提供。
///
/// - Parameters:
///   - columns: 列规则。空数组生成空布局。
///   - alignment: 轨道组在可用空间内的水平对齐方式，同时作为单元格的默认水平对齐。
///   - spacing: 行间距，默认为 0；负数和非有限值按 0 处理，与 QuickLayout Grid 一致。
///   - content: 按行优先顺序生成所有子元素。
public func VGrid(
    columns: [GridItem],
    alignment: HorizontalAlignment = .center,
    spacing: CGFloat = 0,
    @FastArrayBuilder<Element> content: () -> [Element]
) -> some Element & Layout {
    DirectionalGrid(items: columns, axis: .vertical,
                    alignment: Alignment(horizontal: alignment, vertical: .center),
                    spacing: gridSpacing(spacing), children: content())
}

/// 按行规则逐列排列全部内容的非懒加载网格。
///
/// `rows` 描述垂直方向的尺寸和间距，`spacing` 描述相邻列的间距。
/// 内容在构建时全部创建，布局时全部测量；滚动由外层 `ScrollView` 提供。
///
/// - Parameters:
///   - rows: 行规则。空数组生成空布局。
///   - alignment: 轨道组在可用空间内的垂直对齐方式，同时作为单元格的默认垂直对齐。
///   - spacing: 列间距，默认为 0；负数和非有限值按 0 处理，与 QuickLayout Grid 一致。
///   - content: 按列优先顺序生成所有子元素。
public func HGrid(
    rows: [GridItem],
    alignment: VerticalAlignment = .center,
    spacing: CGFloat = 0,
    @FastArrayBuilder<Element> content: () -> [Element]
) -> some Element & Layout {
    DirectionalGrid(items: rows, axis: .horizontal,
                    alignment: Alignment(horizontal: .center, vertical: alignment),
                    spacing: gridSpacing(spacing), children: content())
}

/// 两个方向共享同一套轨道分配和测量逻辑，坐标输出时再转换轴。
private struct DirectionalGrid: Layout {
    let items: [GridItem]
    let axis: Axis
    let alignment: Alignment
    let spacing: CGFloat
    let children: [Element]

    func quick_layoutPriority() -> CGFloat { 0 }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        guard !items.isEmpty else { return .fixedSize }
        if axis == self.axis { return .fixedSize }
        // 即使所有轨道都是固定尺寸，网格仍接受交叉轴的可用空间。
        return .fullyFlexible
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        guard !items.isEmpty else { return }
        children.forEach { $0.quick_extractViewsIntoArray(&views) }
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard !items.isEmpty else { return .empty }
        let proposedCross = crossLength(proposedSize)
        let measuredTracks = resolveTracks(proposedCross)
        let cross = proposedCross.isFinite ? max(measuredTracks.extent, proposedCross) : measuredTracks.extent
        // 空内容仍保留已声明轨道的交叉轴空间，增长轴长度为零。
        guard !children.isEmpty else {
            return LayoutNode(view: nil, dimensions: ElementDimensions(size(main: 0, cross: cross)))
        }
        // 报告阶段决定行列分组；放置阶段用报告的交叉轴尺寸重新分配轨道。
        // 内容按最终轨道测量，其最新尺寸同时用于报告分组与放置分组。
        // 两种分组必须分开，adaptive 展开后不能用放置行数覆盖报告行数。
        let reportedCount = measuredTracks.values.count
        let tracks = cross == proposedCross ? measuredTracks : resolveTracks(cross)
        let count = tracks.values.count
        var measured: [LayoutNode] = []
        var reportedLines = [CGFloat](repeating: 0, count: (children.count - 1) / reportedCount + 1)
        var lineLengths = [CGFloat](repeating: 0, count: (children.count - 1) / count + 1)
        for (index, child) in children.enumerated() {
            let node = child.quick_layoutThatFits(size(main: .infinity, cross: tracks.values[index % count].length))
            measured.append(node)
            let length = finiteLength(mainLength(node.size))
            reportedLines[index / reportedCount] = max(reportedLines[index / reportedCount], length)
            lineLengths[index / count] = max(lineLengths[index / count], length)
        }
        // LazyGrid 向上取整增长轴报告长度；放置仍保留子元素和行列的分数尺寸。
        let mainExtent = ceil(reportedLines.reduce(0, +) + CGFloat(reportedLines.count - 1) * spacing)
        // 再次溢出从逻辑起点延伸，RTL 以报告边界镜像，而非实际轨道或行列的范围。
        let container = size(main: max(0, mainExtent), cross: min(cross, tracks.extent))
        let resultSize = size(main: mainLength(container), cross: cross)
        let groupOrigin = frameOrigin(node: blankNode(container), size: resultSize, alignment: alignment)
        let rtl = LayoutContext.layoutDirection == .rightToLeft
        var mainOffset: CGFloat = 0
        var layers: [Element] = []
        for (index, node) in measured.enumerated() {
            let track = tracks.values[index % count]
            let cellSize = size(main: lineLengths[index / count], cross: track.length)
            let cellAlignment = track.alignment ?? alignment
            let defaultOrigin = frameOrigin(node: blankNode(node.size), size: cellSize, alignment: cellAlignment)
            // LazyGrid 以单元格中心放置内容；轨道 alignment 决定默认位置，
            // 显式 center 参考线的差值再加到位置上，与 frame 的减法语义不同。
            let cellOrigin = CGPoint(x: defaultOrigin.x + (rtl ? -1 : 1) * (node.dimensions[HorizontalAlignment.center] - node.size.width / 2),
                                     y: defaultOrigin.y + node.dimensions[VerticalAlignment.center] - node.size.height / 2)
            let logicalX = axis == .vertical ? track.offset : mainOffset
            let origin = CGPoint(x: groupOrigin.x + (rtl ? container.width - logicalX - cellSize.width : logicalX) + cellOrigin.x,
                                 y: groupOrigin.y + (axis == .vertical ? mainOffset : track.offset) + cellOrigin.y)
            appendViews(node, at: origin, in: resultSize, to: &layers)
            if index % count == count - 1 { mainOffset += lineLengths[index / count] + spacing }
        }
        // 网格消耗单元格参考线。只保留测量完成的视图及其物理坐标，不能把内部
        // 显式参考线传播到轨道组或外层栈；网格自身外加的 alignmentGuide 仍正常生效。
        guard !layers.isEmpty else { return blankNode(resultSize) }
        return ZStackElement(children: layers, alignment: .topLeading).quick_layoutThatFits(resultSize)
    }

    private func blankNode(_ size: CGSize) -> LayoutNode {
        LayoutNode(view: nil, dimensions: ElementDimensions(size))
    }

    private func frameOrigin(node: LayoutNode, size: CGSize, alignment: Alignment) -> CGPoint {
        let origin = LayoutContext.$layoutDirection.withValue(.leftToRight) {
            FixedFrameElement(child: GridMeasuredNode(node: node), width: size.width,
                              height: size.height, alignment: alignment)
                .quick_layoutThatFits(size).children[0].position
        }
        // SwiftUI 的自定义水平对齐值也以逻辑方向解释，不能只镜像内置 leading/trailing。
        return CGPoint(x: LayoutContext.layoutDirection == .rightToLeft ? size.width - node.size.width - origin.x : origin.x,
                       y: origin.y)
    }

    /// 当前 QuickLayout 的公开 LayoutNode 构造器只能创建叶节点，因此通过公开布局
    /// 原语重建已测量的视图位置，避免依赖内部参考线字典或重复测量用户内容。
    private func appendViews(_ node: LayoutNode, at origin: CGPoint, in size: CGSize, to layers: inout [Element]) {
        if let view = node.view {
            let leaf = LayoutNode(view: view, dimensions: ElementDimensions(node.size))
            let rtl = LayoutContext.layoutDirection == .rightToLeft
            let offset = CGPoint(x: rtl ? size.width - node.size.width - origin.x : origin.x, y: origin.y)
            layers.append(FixedFrameElement(
                child: OffsetElement(child: GridMeasuredNode(node: leaf), offset: offset),
                width: size.width, height: size.height, alignment: .topLeading))
        }
        for child in node.children {
            appendViews(child.layout, at: CGPoint(x: origin.x + child.position.x, y: origin.y + child.position.y),
                        in: size, to: &layers)
        }
    }

    /// 先扣除固定轨道及间距，再依声明顺序分配弹性与自适应轨道。
    private func resolveTracks(_ proposal: CGFloat) -> (values: [GridTrack], extent: CGFloat) {
        let gaps = items.map { gridSpacing($0.spacing) }
        var lengths = [CGFloat](repeating: 0, count: items.count)
        var remaining = proposal.isFinite ? max(0, proposal) - gaps.dropLast().reduce(0, +) : .infinity
        var flexibleCount = 0
        for (index, item) in items.enumerated() {
            if case let .fixed(value) = item.size {
                lengths[index] = finiteLength(value)
                remaining -= lengths[index]
            } else { flexibleCount += 1 }
        }
        for (index, item) in items.enumerated() {
            let share = remaining / CGFloat(max(1, flexibleCount))
            switch item.size {
            case .fixed: continue
            case let .flexible(minimum, maximum):
                let lower = finiteLength(minimum)
                lengths[index] = min(max(lower, share.isFinite ? share : 10), upperBound(maximum, minimum: lower))
            case .adaptive:
                // 与 SwiftUI 的未指定交叉轴建议一致，使用 10 点理想轨道；
                // adaptive 的 minimum 用于决定重复数量，不强制撑大可用空间。
                lengths[index] = share.isFinite ? max(0, share) : 10
            }
            remaining -= lengths[index]
            flexibleCount -= 1
        }
        var tracks: [GridTrack] = []
        var offset: CGFloat = 0
        for (index, item) in items.enumerated() {
            var length = lengths[index]
            var repetitions: CGFloat = 1
            if case let .adaptive(minimum, maximum) = item.size {
                let lower = finiteLength(minimum)
                let stride = lower + gaps[index]
                if stride > 0 {
                    repetitions = max(1, floor((length + gaps[index]) / stride))
                }
                if !repetitions.isFinite { repetitions = 1 }
                length = min(max(0, (length - (repetitions - 1) * gaps[index]) / repetitions),
                             upperBound(maximum, minimum: lower))
            }
            // 没有内容的虚拟轨道只计入总尺寸，避免极大建议尺寸引起无界内存分配。
            let visibleCount = Int(min(CGFloat(children.count), repetitions))
            for repetition in 0..<visibleCount {
                tracks.append(GridTrack(length: length, offset: offset + CGFloat(repetition) * (length + gaps[index]),
                                        alignment: item.alignment))
            }
            offset += repetitions * length + (repetitions - 1) * gaps[index]
            if index < items.count - 1 { offset += gaps[index] }
        }
        return (tracks, max(0, offset))
    }

    private func size(main: CGFloat, cross: CGFloat) -> CGSize {
        axis == .vertical ? CGSize(width: cross, height: main) : CGSize(width: main, height: cross)
    }
    private func mainLength(_ size: CGSize) -> CGFloat { axis == .vertical ? size.height : size.width }
    private func crossLength(_ size: CGSize) -> CGFloat { axis == .vertical ? size.width : size.height }
}

private struct GridTrack {
    let length: CGFloat
    let offset: CGFloat
    let alignment: Alignment?
}

/// 保留最终测量的结果，单元格包装和定位不会额外测量用户内容。
private struct GridMeasuredNode: Layout {
    let node: LayoutNode
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func gridSpacing(_ value: CGFloat) -> CGFloat {
    (value.isFinite && value > 0) ? value : 0
}

private func finiteLength(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }

private func upperBound(_ value: CGFloat, minimum: CGFloat) -> CGFloat {
    value.isNaN ? minimum : max(minimum, value)
}
