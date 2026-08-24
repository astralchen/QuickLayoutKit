import QuickLayout
import UIKit

/// The part of a supported container that receives content margins.
public struct ContentMarginPlacement: Hashable, Sendable {

    fileprivate enum Kind: Hashable, Sendable {
        case automatic
        case scrollContent
        case scrollIndicators
    }

    fileprivate let kind: Kind

    /// Applies margins to every placement supported by the container.
    public static var automatic: ContentMarginPlacement {
        ContentMarginPlacement(kind: .automatic)
    }

    /// Applies margins to scrollable content without moving scroll indicators.
    public static var scrollContent: ContentMarginPlacement {
        ContentMarginPlacement(kind: .scrollContent)
    }

    /// Applies margins to scroll indicators without moving scrollable content.
    public static var scrollIndicators: ContentMarginPlacement {
        ContentMarginPlacement(kind: .scrollIndicators)
    }
}

public extension Element {

    /// Configures directional content margins for supported containers.
    ///
    /// `QuickLayoutScrollView` supports all placements. The automatic
    /// placement applies the margins to both its content and indicators.
    @MainActor
    func contentMargins(
        _ edges: EdgeSet = .all,
        _ insets: EdgeInsets,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        ContentMarginsElement(
            child: self,
            edges: edges,
            insets: insets.sanitizedContentMargins,
            placement: placement
        )
    }

    /// Configures equal content margins on selected edges.
    ///
    /// Passing `nil` leaves the selected edges unspecified, matching SwiftUI.
    /// An earlier margin for the same placement or the container's default
    /// therefore remains in effect.
    @MainActor
    func contentMargins(
        _ edges: EdgeSet = .all,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        guard let length else {
            return ContentMarginsElement(
                child: self,
                edges: [],
                insets: .zero,
                placement: placement
            )
        }
        let sanitizedLength = sanitizedContentMargin(length)
        return contentMargins(
            edges,
            EdgeInsets(
                top: edges.contains(.top) ? sanitizedLength : 0,
                leading: edges.contains(.leading) ? sanitizedLength : 0,
                bottom: edges.contains(.bottom) ? sanitizedLength : 0,
                trailing: edges.contains(.trailing) ? sanitizedLength : 0
            ),
            for: placement
        )
    }

    /// Configures the same content margin on every edge.
    @MainActor
    func contentMargins(
        _ length: CGFloat,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        contentMargins(.all, length, for: placement)
    }
}

@MainActor
private struct ContentMarginsElement: @MainActor Layout {

    let child: Element
    let scrollViews: [QuickLayoutScrollView]
    let edges: EdgeSet
    let insets: EdgeInsets
    let placement: ContentMarginPlacement

    init(
        child: Element,
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement
    ) {
        self.child = child
        self.edges = edges
        self.insets = insets
        self.placement = placement

        var views: [UIView] = []
        child.quick_extractViewsIntoArray(&views)
        scrollViews = views.compactMap { $0 as? QuickLayoutScrollView }
        applyMargins()
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        child.quick_flexibility(for: axis)
    }

    func quick_layoutPriority() -> CGFloat {
        child.quick_layoutPriority()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let node = child.quick_layoutThatFits(proposedSize)
        applyMargins()
        return node
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        child.quick_extractViewsIntoArray(&views)
        applyMargins()
    }

    private func applyMargins() {
        for scrollView in scrollViews {
            scrollView.quickLayoutSetContentMargins(
                edges: edges,
                insets: insets,
                placement: placement
            )
        }
    }
}

final class QuickLayoutContentMarginState {

    private struct Overrides {
        var top: CGFloat?
        var leading: CGFloat?
        var bottom: CGFloat?
        var trailing: CGFloat?

        mutating func set(_ edges: EdgeSet, to insets: EdgeInsets) {
            if edges.contains(.top) { top = insets.top }
            if edges.contains(.leading) { leading = insets.leading }
            if edges.contains(.bottom) { bottom = insets.bottom }
            if edges.contains(.trailing) { trailing = insets.trailing }
        }

        func overriding(_ fallback: Overrides) -> Overrides {
            Overrides(
                top: top ?? fallback.top,
                leading: leading ?? fallback.leading,
                bottom: bottom ?? fallback.bottom,
                trailing: trailing ?? fallback.trailing
            )
        }

        var resolved: EdgeInsets {
            EdgeInsets(
                top: top ?? 0,
                leading: leading ?? 0,
                bottom: bottom ?? 0,
                trailing: trailing ?? 0
            )
        }

        var specified: EdgeInsets {
            EdgeInsets(
                top: top == nil ? 0 : 1,
                leading: leading == nil ? 0 : 1,
                bottom: bottom == nil ? 0 : 1,
                trailing: trailing == nil ? 0 : 1
            )
        }
    }

    private var automatic = Overrides()
    private var scrollContent = Overrides()
    private var scrollIndicators = Overrides()

    private(set) var appliedContentInsets: UIEdgeInsets = .zero
    private(set) var appliedVerticalIndicatorInsets: UIEdgeInsets = .zero
    private(set) var appliedHorizontalIndicatorInsets: UIEdgeInsets = .zero
    private var appliedLayoutDirection: UIUserInterfaceLayoutDirection?
    private var appliedSafeAreaInsets: UIEdgeInsets?
    private var appliedAutomaticAdjustmentInsets: UIEdgeInsets?

    @MainActor
    func reset(on scrollView: UIScrollView) {
        automatic = Overrides()
        scrollContent = Overrides()
        scrollIndicators = Overrides()
        updateInsets(on: scrollView)
    }

    @MainActor
    func set(
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement,
        on scrollView: UIScrollView
    ) {
        switch placement.kind {
        case .automatic:
            automatic.set(edges, to: insets)
        case .scrollContent:
            scrollContent.set(edges, to: insets)
        case .scrollIndicators:
            scrollIndicators.set(edges, to: insets)
        }
        updateInsets(on: scrollView)
    }

    @MainActor
    func updateLayoutDirectionIfNeeded(on scrollView: UIScrollView) {
        let automaticAdjustmentInsets = scrollView
            .quickLayoutAutomaticContentInsetAdjustment
        guard appliedLayoutDirection
                != scrollView.effectiveUserInterfaceLayoutDirection
                || appliedSafeAreaInsets != scrollView.safeAreaInsets
                || appliedAutomaticAdjustmentInsets
                    != automaticAdjustmentInsets else {
            return
        }

        updateInsets(on: scrollView, keepsContentAtStart: false)
    }

    @MainActor
    func updateSafeArea(
        on scrollView: UIScrollView,
        keepsContentAtStart: Bool
    ) {
        updateInsets(
            on: scrollView,
            keepsContentAtStart: keepsContentAtStart
        )
    }

    @MainActor
    func updateAxis(on scrollView: UIScrollView) {
        updateInsets(on: scrollView, keepsContentAtStart: false)
    }

    @MainActor
    private func updateInsets(
        on scrollView: UIScrollView,
        keepsContentAtStart: Bool = true
    ) {
        let previousContentMargins = appliedContentInsets
        let baseContentInsets = scrollView.contentInset
            .subtracting(appliedContentInsets)
        let baseVerticalIndicatorInsets = scrollView.verticalScrollIndicatorInsets
            .subtracting(appliedVerticalIndicatorInsets)
        let baseHorizontalIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
            .subtracting(appliedHorizontalIndicatorInsets)
        let layoutDirection = scrollView.effectiveUserInterfaceLayoutDirection

        let contentOverrides = scrollContent.overriding(automatic)
        let indicatorOverrides = scrollIndicators.overriding(automatic)
        let automaticAdjustmentInsets = scrollView
            .quickLayoutAutomaticContentInsetAdjustment
        let contentMargins = contentOverrides.resolved
            .uiInsets(for: layoutDirection)
            .adding(
                scrollView.quickLayoutMissingSafeAreaInsets(
                    specified: contentOverrides.specified
                        .uiInsets(for: layoutDirection),
                    automaticAdjustment: automaticAdjustmentInsets
                )
            )
        let indicatorMargins = indicatorOverrides.resolved
            .uiInsets(for: layoutDirection)
            .adding(
                scrollView.quickLayoutMissingSafeAreaInsets(
                    specified: indicatorOverrides.specified
                        .uiInsets(for: layoutDirection),
                    automaticAdjustment: automaticAdjustmentInsets
                )
            )
        let verticalIndicatorMargins: UIEdgeInsets
        let horizontalIndicatorMargins: UIEdgeInsets
        if let quickLayoutScrollView = scrollView as? QuickLayoutScrollView {
            verticalIndicatorMargins = quickLayoutScrollView.axis == .vertical
                ? indicatorMargins
                : .zero
            horizontalIndicatorMargins = quickLayoutScrollView.axis == .horizontal
                ? indicatorMargins
                : .zero
        } else {
            verticalIndicatorMargins = indicatorMargins
            horizontalIndicatorMargins = indicatorMargins
        }
        let shouldKeepContentAtStart = keepsContentAtStart
            && contentMargins != previousContentMargins
            && (scrollView as? QuickLayoutScrollView)?
                .quickLayoutIsAtContentStart() == true

        appliedLayoutDirection = layoutDirection
        appliedSafeAreaInsets = scrollView.safeAreaInsets
        appliedAutomaticAdjustmentInsets = automaticAdjustmentInsets
        appliedContentInsets = contentMargins
        appliedVerticalIndicatorInsets = verticalIndicatorMargins
        appliedHorizontalIndicatorInsets = horizontalIndicatorMargins

        scrollView.contentInset = baseContentInsets.adding(contentMargins)
        scrollView.verticalScrollIndicatorInsets = baseVerticalIndicatorInsets
            .adding(verticalIndicatorMargins)
        scrollView.horizontalScrollIndicatorInsets = baseHorizontalIndicatorInsets
            .adding(horizontalIndicatorMargins)

        if shouldKeepContentAtStart {
            (scrollView as? QuickLayoutScrollView)?
                .quickLayoutKeepContentAtStartAfterMarginChange()
        }
    }
}

extension QuickLayoutScrollView {

    @MainActor
    func quickLayoutResetContentMargins() {
        quickLayoutContentMarginState.reset(on: self)
    }

    @MainActor
    func quickLayoutUpdateContentMarginDirectionIfNeeded() {
        quickLayoutContentMarginState.updateLayoutDirectionIfNeeded(on: self)
    }

    @MainActor
    func quickLayoutUpdateContentMarginAxis() {
        quickLayoutContentMarginState.updateAxis(on: self)
    }

    @MainActor
    fileprivate func quickLayoutSetContentMargins(
        edges: EdgeSet,
        insets: EdgeInsets,
        placement: ContentMarginPlacement
    ) {
        quickLayoutContentMarginState.set(
            edges: edges,
            insets: insets,
            placement: placement,
            on: self
        )
    }
}

extension UIScrollView {

    var quickLayoutAppliedContentMarginInsets: UIEdgeInsets {
        (self as? QuickLayoutScrollView)?
            .quickLayoutContentMarginState.appliedContentInsets ?? .zero
    }

    var quickLayoutAppliedIndicatorMarginInsets: UIEdgeInsets {
        guard let scrollView = self as? QuickLayoutScrollView else {
            return .zero
        }
        switch scrollView.axis {
        case .vertical:
            return scrollView.quickLayoutContentMarginState
                .appliedVerticalIndicatorInsets
        case .horizontal:
            return scrollView.quickLayoutContentMarginState
                .appliedHorizontalIndicatorInsets
        }
    }
}

private extension EdgeInsets {

    var sanitizedContentMargins: EdgeInsets {
        EdgeInsets(
            top: sanitizedContentMargin(top),
            leading: sanitizedContentMargin(leading),
            bottom: sanitizedContentMargin(bottom),
            trailing: sanitizedContentMargin(trailing)
        )
    }

    func uiInsets(
        for direction: UIUserInterfaceLayoutDirection
    ) -> UIEdgeInsets {
        switch direction {
        case .rightToLeft:
            UIEdgeInsets(
                top: top,
                left: trailing,
                bottom: bottom,
                right: leading
            )
        case .leftToRight:
            UIEdgeInsets(
                top: top,
                left: leading,
                bottom: bottom,
                right: trailing
            )
        @unknown default:
            UIEdgeInsets(
                top: top,
                left: leading,
                bottom: bottom,
                right: trailing
            )
        }
    }
}

extension UIEdgeInsets {

    func adding(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top + other.top,
            left: left + other.left,
            bottom: bottom + other.bottom,
            right: right + other.right
        )
    }

    func subtracting(_ other: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: top - other.top,
            left: left - other.left,
            bottom: bottom - other.bottom,
            right: right - other.right
        )
    }
}

private extension UIScrollView {

    var quickLayoutAutomaticContentInsetAdjustment: UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, adjustedContentInset.top - contentInset.top),
            left: max(0, adjustedContentInset.left - contentInset.left),
            bottom: max(0, adjustedContentInset.bottom - contentInset.bottom),
            right: max(0, adjustedContentInset.right - contentInset.right)
        )
    }

    func quickLayoutMissingSafeAreaInsets(
        specified: UIEdgeInsets,
        automaticAdjustment: UIEdgeInsets
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: specified.top == 0
                ? 0
                : max(0, safeAreaInsets.top - automaticAdjustment.top),
            left: specified.left == 0
                ? 0
                : max(0, safeAreaInsets.left - automaticAdjustment.left),
            bottom: specified.bottom == 0
                ? 0
                : max(0, safeAreaInsets.bottom - automaticAdjustment.bottom),
            right: specified.right == 0
                ? 0
                : max(0, safeAreaInsets.right - automaticAdjustment.right)
        )
    }
}

private func sanitizedContentMargin(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}
