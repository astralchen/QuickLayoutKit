import CoreGraphics
import QuickLayout
import UIKit

/// 选择理想尺寸能够容纳在建议尺寸内的第一个备选布局。
///
/// 该函数按照声明顺序评估备选布局，并且只在 `axes` 指定的轴上检查是否能够容纳。
/// 如果此前的备选布局均无法容纳，则使用最后一个备选布局。
/// 当 `axes` 为空集合时，不执行尺寸检查，并始终使用第一个备选布局。
/// 内容构建器未生成任何元素时返回空布局。
/// Kit 宿主先测量候选，再仅挂载选中分支的视图；未选中分支独占的视图退出层级。
/// 共享视图按对象身份去重，纯测量不改变层级和业务隐藏状态。
///
/// - Parameters:
///   - axes: 执行尺寸检查的轴。
///   - content: 按优先顺序生成备选布局的构建器。
/// - Returns: 根据建议尺寸选择备选项的布局元素。
public func ViewThatFits(
    in axes: AxisSet = [.horizontal, .vertical],
    @FastArrayBuilder<Element> content: () -> [Element]
) -> Element & Layout {
    ViewThatFitsElement(children: content(), axes: axes)
}

/// 按声明顺序选择可容纳内容，将选择结果保存在本轮测量节点中。
private struct ViewThatFitsElement: Layout {

    /// 按优先级排列的备选元素；最后一个始终作为回退项。
    let children: [Element]
    /// 检查理想尺寸是否能够容纳的轴。
    let axes: AxisSet
    /// 身份随布局值复制而保留；不同测量结果独立保存选中的视图列表。
    private let identity = CandidateIdentity()

    init(children: [Element], axes: AxisSet) {
        self.children = children
        self.axes = axes
    }

    /// 采用所有备选元素中伸缩能力最强的弹性。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        children.reduce(.fixedSize) { result, child in
            let flexibility = child.quick_flexibility(for: axis)
            return flexibility.rawValue > result.rawValue ? flexibility : result
        }
    }

    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat {
        0
    }

    /// 选择第一个可容纳的备选项，全部不适合时用最后一项；空列表返回空节点。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        guard let fallback = children.last else {
            return .empty
        }

        for child in children.dropLast() {
            let idealLayout = child.quick_layoutThatFits(
                idealProposal(from: proposedSize)
            )
            if fits(idealLayout.size, in: proposedSize) {
                return layout(
                    selecting: child,
                    proposedSize: proposedSize
                )
            }
        }

        return layout(
            selecting: fallback,
            proposedSize: proposedSize
        )
    }

    /// 普通提取保留声明信息；宿主解析测量结果时只提取本轮选中的视图。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        if let selections = QuickLayoutCandidateSelection.current {
            views.append(contentsOf: selections[ObjectIdentifier(identity)] ?? [])
            return
        }
        var extractedViewIDs = Set(views.map(ObjectIdentifier.init))
        children.forEach { child in
            for view in extractedViews(from: child) {
                if extractedViewIDs.insert(ObjectIdentifier(view)).inserted {
                    views.append(view)
                }
            }
        }
    }

    /// 仅将待检查轴设为无界，以获取该轴上的理想尺寸。
    private func idealProposal(from proposedSize: CGSize) -> CGSize {
        CGSize(
            width: axes.contains(.horizontal) ? .infinity : proposedSize.width,
            height: axes.contains(.vertical) ? .infinity : proposedSize.height
        )
    }

    /// 比较所选轴的理想长度与建议长度；空轴集合始终可容纳。
    private func fits(_ idealSize: CGSize, in proposedSize: CGSize) -> Bool {
        if axes.contains(.horizontal), idealSize.width > proposedSize.width {
            return false
        }
        if axes.contains(.vertical), idealSize.height > proposedSize.height {
            return false
        }
        return true
    }

    /// 选择信息只附着于最终节点，理想尺寸试探产生的节点不会进入挂载列表。
    private func layout(selecting selectedChild: Element, proposedSize: CGSize) -> LayoutNode {
        let selectedLayout = selectedChild.quick_layoutThatFits(proposedSize)
        // 纯布局无需创建 UIKit 标记，仍支持后台测量。
        guard children.contains(where: { !extractedViews(from: $0).isEmpty }) else { return selectedLayout }
        let selectedViews = QuickLayoutCandidateSelection.views(of: selectedChild, measured: selectedLayout)
        let identity = identity
        let marker = MainActor.assumeIsolated {
            CandidateSelectionMarker(identity: identity, views: selectedViews)
        }
        // 使用覆盖层承载元数据，保留选中内容的尺寸和对齐参考线；标记不挂载到层级。
        return LayeringElement(
            target: QuickLayoutMeasuredLayout(node: selectedLayout, mountedViews: []),
            layer: QuickLayoutMeasuredLayout(
                node: LayoutNode(view: marker, dimensions: ElementDimensions(.zero)), mountedViews: []),
            type: .overlay
        ).quick_layoutThatFits(proposedSize)
    }
}

/// 候选身份不保存可变选择，避免不同建议尺寸和缓存节点互相覆盖。
final class CandidateIdentity: Sendable {}

/// 收集元素向 QuickLayout 暴露的 UIKit 视图。
private func extractedViews(from element: Element) -> [UIView] {
    var views: [UIView] = []
    element.quick_extractViewsIntoArray(&views)
    return views
}
