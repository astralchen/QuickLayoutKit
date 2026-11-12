//
//  ScrollView.swift
//  QuickLayoutKit
//
//  由 Sondra 创建于 2025/12/24。
//

import UIKit
import QuickLayout
import QuickLayoutKitCore

// MARK: - 滚动视图容器

/// 创建由滚动视图承载的布局元素。
///
/// 在布局构建器中使用此函数声明可滚动的 QuickLayout 内容，并复用指定的
/// `QuickLayoutScrollView` 实例。
///
/// 显式传入滚动视图，可以提供稳定的 UIKit 对象标识；对于值类型的 `ScrollView`，
/// 该标识通常由 SwiftUI 管理。
///
/// 与 SwiftUI 的 `ScrollView` 一样，滚动轴接受建议长度，交叉轴按内容和建议尺寸测量。
/// UIKit 通过调整后的内容边距表示与滚动视图相交的安全区域，QuickLayout 会将这些值
/// 传递给滚动内容。
/// 内容默认避让安全区域，`safeAreaPadding` 添加额外安全边距；
/// `contentMargins` 可分别配置内容和滚动指示器的额外间距。
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
) -> QuickLayoutScrollElement {
    scrollView.configure(
        axis: axis,
        showsIndicators: showsIndicators,
        content: content()
    )
    return QuickLayoutScrollElement(scrollView)
}

/// 将稳定的滚动视图实例适配为 QuickLayout 叶子节点。
@MainActor
public struct QuickLayoutScrollElement: @MainActor Layout, @MainActor LeafElement, @MainActor QuickLayoutSafeAreaInsetTarget {

    /// 由调用方持有并复用的滚动宿主。
    private let child: UIScrollView
    private var resizableAxes: AxisSet = []

    /// 保存滚动宿主，不创建新的 UIKit 实例。
    init(_ scrollView: UIScrollView) {
        self.child = scrollView
    }

    /// 由 QuickLayout 的 UIScrollView 桥接调用宿主的 sizeThatFits。
    public func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        quick_layoutWithSafeAreaInset(proposedSize, reservation: .init())
    }

    package var quickLayoutAcceptsSafeAreaInset: Bool { true }

    package func quick_layoutWithSafeAreaInset(
        _ proposedSize: CGSize,
        reservation: QuickLayoutSafeAreaInsetReservation
    ) -> LayoutNode {
        // 空容器保留交叉轴零理想尺寸，系统区域不能单独撑出一条空白视口。
        let contentHost = child as? QuickLayoutScrollView
        let crossAxis: AxisSet = contentHost?.axis == .vertical ? .horizontal : .vertical
        if contentHost?.hasEmptyContent == true, !resizableAxes.contains(crossAxis),
           let values = QuickLayoutSafeAreaContext.current {
            let edges: EdgeSet = contentHost?.axis == .vertical ? .horizontal : .vertical
            return QuickLayoutSafeAreaContext.withValues(values.ignoring(.all, edges: edges)) {
                layoutViewport(proposedSize, reservation: reservation)
            }
        }
        return layoutViewport(proposedSize, reservation: reservation)
    }

    private func layoutViewport(_ proposedSize: CGSize, reservation: QuickLayoutSafeAreaInsetReservation) -> LayoutNode {
        let values = QuickLayoutSafeAreaContext.current
        let inherited = values?.expansion(ignoring: .all, edges: .all) ?? .zero
        // 无界内容轴没有视口远端边界，不能把外层安全区分配给每个自然尺寸轮播。
        let expandsWidth = proposedSize.width.isFinite && proposedSize.width >= (values?.containerSize.width ?? proposedSize.width)
        let expandsHeight = proposedSize.height.isFinite && proposedSize.height >= (values?.containerSize.height ?? proposedSize.height)
        let touching = values.map { QuickLayoutSafeAreaContext.touchingEdges(of: child, values: $0) } ?? []
        // 外层滚动内容沿主轴没有固定视口边界。即使内层 frame 提供了有限尺寸，
        // 也不能借此恢复外层的顶部／底部区域，否则会侵入相邻内容并重复增加 inset。
        let allowsVerticalExpansion = values?.scrollContentAxis != .vertical
        let allowsHorizontalExpansion = values?.scrollContentAxis != .horizontal
        let expansion = EdgeInsets(top: allowsVerticalExpansion && proposedSize.height.isFinite && (expandsHeight || touching.contains(.top)) ? inherited.top : 0,
                                   leading: allowsHorizontalExpansion && proposedSize.width.isFinite && (expandsWidth || touching.contains(.leading)) ? inherited.leading : 0,
                                   bottom: allowsVerticalExpansion && proposedSize.height.isFinite && (expandsHeight || touching.contains(.bottom)) ? inherited.bottom : 0,
                                   trailing: allowsHorizontalExpansion && proposedSize.width.isFinite && (expandsWidth || touching.contains(.trailing)) ? inherited.trailing : 0)
        let remaining = QuickLayoutSafeAreaContext.current?.effectiveInsets ?? .zero
        let rtl = LayoutContext.layoutDirection == .rightToLeft
        let safe = UIEdgeInsets(top: expansion.top + remaining.top,
                                left: rtl ? expansion.trailing + remaining.trailing : expansion.leading + remaining.leading,
                                bottom: expansion.bottom + remaining.bottom,
                                right: rtl ? expansion.leading + remaining.leading : expansion.trailing + remaining.trailing)
        var resolved = reservation
        resolved.ignoredContainerEdges = values?.ignoredPhysicalContainerEdges ?? .zero
        resolved.insets = UIEdgeInsets(top: safe.top + reservation.insets.top,
                                     left: safe.left + reservation.insets.left,
                                     bottom: safe.bottom + reservation.insets.bottom,
                                     right: safe.right + reservation.insets.right)
        resolved.selected = values == nil ? reservation.selected : UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        child.quickLayoutSetSafeAreaInsetReservation(resolved)
        child.quickLayoutScrollMarginState.updateLayoutDirectionIfNeeded(on: child)
        let viewport: Element = resizableAxes.isEmpty ? child : child.resizable(axis: resizableAxes)
        return QuickLayoutSafeAreaScrollViewport(child: viewport, expansion: expansion)
            .quick_layoutThatFits(proposedSize)
    }

    /// 在视口内部应用伸缩，避免上游叶子适配丢弃安全区包装节点。
    public func resizable(axis: AxisSet = [.horizontal, .vertical]) -> Self {
        var result = self
        result.resizableAxes = axis
        return result
    }

    /// 构建器与直接使用宿主视图时采用相同的轴弹性。
    public func quick_flexibility(for axis: Axis) -> Flexibility {
        resizableAxes.contains(axis == .horizontal ? .horizontal : .vertical)
            ? .fullyFlexible : child.quick_flexibility(for: axis)
    }

    /// 沿用子元素的布局优先级。
    public func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    /// 将视图提取转交给子元素，不引入额外 UIKit 视图。
    public func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
    }

    /// 返回该叶子节点使用的滚动宿主视图。
    public func backingView() -> UIView? {
        child
    }

}
