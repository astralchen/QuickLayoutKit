import CoreGraphics
import QuickLayout
import UIKit

/// 选择理想尺寸能够容纳在建议尺寸内的第一个备选布局。
///
/// 该函数按照声明顺序评估备选布局，并且只在 `axes` 指定的轴上检查是否能够容纳。
/// 如果此前的备选布局均无法容纳，则使用最后一个备选布局。
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

private struct ViewThatFitsElement: Layout {

    let children: [Element]
    let axes: AxisSet

    func quick_flexibility(for axis: Axis) -> Flexibility {
        children.reduce(.fixedSize) { result, child in
            let flexibility = child.quick_flexibility(for: axis)
            return flexibility.rawValue > result.rawValue ? flexibility : result
        }
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

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

    private func idealProposal(from proposedSize: CGSize) -> CGSize {
        CGSize(
            width: axes.contains(.horizontal) ? .infinity : proposedSize.width,
            height: axes.contains(.vertical) ? .infinity : proposedSize.height
        )
    }

    private func fits(_ idealSize: CGSize, in proposedSize: CGSize) -> Bool {
        if axes.contains(.horizontal), idealSize.width > proposedSize.width {
            return false
        }
        if axes.contains(.vertical), idealSize.height > proposedSize.height {
            return false
        }
        return true
    }

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

private struct PrecomputedLayoutElement: Layout {

    let layout: LayoutNode

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fixedSize
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        layout
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private struct CollapsedViewElement: Layout {

    let view: UIView

    func quick_flexibility(for axis: Axis) -> Flexibility {
        .fixedSize
    }

    func quick_layoutPriority() -> CGFloat {
        0
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        LayoutNode(view: view, dimensions: ElementDimensions(.zero))
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func extractedViews(from element: Element) -> [UIView] {
    var views: [UIView] = []
    element.quick_extractViewsIntoArray(&views)
    return views
}
