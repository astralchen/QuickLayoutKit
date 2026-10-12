import CoreGraphics
import QuickLayout
import UIKit

/// 选择理想尺寸能够容纳在建议尺寸内的第一个备选布局。
///
/// 该函数按照声明顺序评估备选布局，并且只在 `axes` 指定的轴上检查是否能够容纳。
/// 如果此前的备选布局均无法容纳，则使用最后一个备选布局。
/// 当 `axes` 为空集合时，不执行尺寸检查，并始终使用第一个备选布局。
/// 内容构建器未生成任何元素时返回空布局。
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

/// 按声明顺序选择可容纳内容，并折叠其他视图的布局元素。
private struct ViewThatFitsElement: Layout {

    /// 按优先级排列的备选元素；最后一个始终作为回退项。
    let children: [Element]
    /// 检查理想尺寸是否能够容纳的轴。
    let axes: AxisSet

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

    /// 提取所有备选项的视图并按对象标识去重，保持稳定的宿主层级。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
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

    /// 布局选中内容，并将未被选中内容独占的视图压缩为零尺寸。
    private func layout(
        selecting selectedChild: Element,
        proposedSize: CGSize
    ) -> LayoutNode {
        let selectedLayout = selectedChild.quick_layoutThatFits(proposedSize)
        let selectedViewIDs = Set(extractedViews(from: selectedChild).map(ObjectIdentifier.init))
        var collapsedViewIDs = Set<ObjectIdentifier>()
        let collapsedViews = children.flatMap { child in
            extractedViews(from: child).compactMap { view -> UIView? in
                let identifier = ObjectIdentifier(view)
                guard
                    !selectedViewIDs.contains(identifier),
                    collapsedViewIDs.insert(identifier).inserted
                else {
                    return nil
                }
                return view
            }
        }

        let layers: [Element] = [PrecomputedLayoutElement(layout: selectedLayout)]
            + collapsedViews.map(CollapsedViewElement.init)
        return ZStackElement(children: layers, alignment: .topLeading)
            .quick_layoutThatFits(proposedSize)
    }
}

/// 复用已选内容的测量节点，不重复提取其视图。
private struct PrecomputedLayoutElement: Layout {

    /// 已完成测量的布局节点，供包装层直接复用。
    let layout: LayoutNode

    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fixedSize
    }

    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat {
        0
    }

    /// 直接返回已测量的节点，忽略包装层的新尺寸建议。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        layout
    }

    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 让未选中视图占据零尺寸，避免遗留上一轮布局矩形。
private struct CollapsedViewElement: Layout {

    /// 本轮需要折叠的未选中视图。
    let view: UIView

    /// 以固定尺寸参与父布局，不要求额外伸缩空间。
    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fixedSize
    }

    /// 使用默认布局优先级，不额外影响父布局的空间分配。
    func quick_layoutPriority() -> CGFloat {
        0
    }

    /// 生成零尺寸视图节点，由布局应用阶段收起其矩形。
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        LayoutNode(view: view, dimensions: ElementDimensions(.zero))
    }

    /// 不重复提取视图；实际视图由原内容或布局节点管理。
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

/// 收集元素向 QuickLayout 暴露的 UIKit 视图。
private func extractedViews(from element: Element) -> [UIView] {
    var views: [UIView] = []
    element.quick_extractViewsIntoArray(&views)
    return views
}
