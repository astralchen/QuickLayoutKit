//
//  ScrollView.swift
//  QuickLayoutKit
//
//  Created by Sondra on 2025/12/24.
//

import UIKit
import QuickLayout

// MARK: - ScrollView Container

/// Creates a layout element backed by a scroll view.
///
/// Use this function inside a layout builder to declare scrollable QuickLayout
/// content while reusing a specific `QuickLayoutScrollView` instance.
///
/// The explicit scroll view parameter supplies the stable UIKit identity that
/// SwiftUI normally manages for its value-typed `ScrollView`.
///
/// - Parameters:
///   - scrollView: The scroll view to use as the backing view.
///   - axis: The single axis along which the scroll view scrolls.
///   - showsIndicators: Whether to show the indicator for that axis.
///   - content: A builder closure that returns the elements to display.
/// - Returns: A layout element that renders the scroll view.
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
        child.quick_layoutThatFits(proposedSize)
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
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
