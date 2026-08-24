//
//  ScrollView.swift
//  QuickLayoutKit
//
//  由 Sondra 创建于 2025/12/24。
//

import UIKit
import QuickLayout

// MARK: - 滚动视图容器

/// 创建由滚动视图承载的布局元素。
///
/// 在布局构建器中使用此函数声明可滚动的 QuickLayout 内容，并复用指定的
/// `QuickLayoutScrollView` 实例。
///
/// 显式传入滚动视图，可以提供稳定的 UIKit 对象标识；对于值类型的 `ScrollView`，
/// 该标识通常由 SwiftUI 管理。
///
/// 与 SwiftUI 的 `ScrollView` 一样，该滚动视图占据完整的建议视口。UIKit 通过调整后的
/// 内容边距表示与滚动视图相交的安全区域，QuickLayout 会将这些值传递给滚动内容。
/// 对必须保持在安全区域内的非滚动内容使用 `safeAreaPadding`；需要让可滚动内容的起止
/// 边缘在安全区域内可达时，使用 `contentMargins`。
///
/// - Parameters:
///   - scrollView: 用作承载视图的滚动视图。
///   - axis: 滚动视图滚动的单一轴。
///   - showsIndicators: 是否显示相应轴的滚动指示器。
///   - content: 返回待显示元素的构建器闭包。
/// - Returns: 用于渲染滚动视图的布局元素。
@MainActor public func ScrollView(
    _ scrollView: QuickLayoutScrollView,
    _ axis: QuickLayout.Axis = .vertical,
    showsIndicators: Bool = true,
    @FastArrayBuilder<Element> content: () -> [Element]
) -> LeafElement & Layout {
    scrollView.configure(
        axis: axis,
        showsIndicators: showsIndicators,
        content: content()
    )
    return ScrollElement(scrollView)
}

@MainActor
private struct ScrollElement: @MainActor Layout, @MainActor LeafElement {

    private let child: QuickLayoutScrollView

    init(_ scrollView: QuickLayoutScrollView) {
        self.child = scrollView
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        if child.axis == .horizontal {
            return LayoutNode(
                view: child,
                dimensions: ElementDimensions(
                    child.quickLayoutViewportSizeThatFits(proposedSize)
                )
            )
        }
        return child.quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        if child.axis == .horizontal, axis == .vertical {
            return .fixedSize
        }
        return child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    func backingView() -> UIView? {
        child
    }

}
