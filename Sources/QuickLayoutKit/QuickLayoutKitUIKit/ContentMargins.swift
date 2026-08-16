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
    /// Passing `nil` uses QuickLayoutKit's default margin of 16 points.
    @MainActor
    func contentMargins(
        _ edges: EdgeSet = .all,
        _ length: CGFloat?,
        for placement: ContentMarginPlacement = .automatic
    ) -> Element & Layout {
        let length = sanitizedContentMargin(length ?? 16)
        return contentMargins(
            edges,
            EdgeInsets(
                top: edges.contains(.top) ? length : 0,
                leading: edges.contains(.leading) ? length : 0,
                bottom: edges.contains(.bottom) ? length : 0,
                trailing: edges.contains(.trailing) ? length : 0
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
    }

    private var automatic = Overrides()
    private var scrollContent = Overrides()
    private var scrollIndicators = Overrides()

    private(set) var appliedContentInsets: UIEdgeInsets = .zero
    private(set) var appliedIndicatorInsets: UIEdgeInsets = .zero
    private var appliedLayoutDirection: UIUserInterfaceLayoutDirection?

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
        guard appliedLayoutDirection
                != scrollView.effectiveUserInterfaceLayoutDirection else {
            return
        }

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
            .subtracting(appliedIndicatorInsets)
        let baseHorizontalIndicatorInsets = scrollView.horizontalScrollIndicatorInsets
            .subtracting(appliedIndicatorInsets)
        let layoutDirection = scrollView.effectiveUserInterfaceLayoutDirection

        let contentMargins = scrollContent
            .overriding(automatic)
            .resolved
            .uiInsets(for: layoutDirection)
        let indicatorMargins = scrollIndicators
            .overriding(automatic)
            .resolved
            .uiInsets(for: layoutDirection)
        let shouldKeepContentAtStart = keepsContentAtStart
            && contentMargins != previousContentMargins
            && (scrollView as? QuickLayoutScrollView)?
                .quickLayoutIsAtContentStart() == true

        appliedLayoutDirection = layoutDirection
        appliedContentInsets = contentMargins
        appliedIndicatorInsets = indicatorMargins

        scrollView.contentInset = baseContentInsets.adding(contentMargins)
        scrollView.verticalScrollIndicatorInsets = baseVerticalIndicatorInsets
            .adding(indicatorMargins)
        scrollView.horizontalScrollIndicatorInsets = baseHorizontalIndicatorInsets
            .adding(indicatorMargins)

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
        (self as? QuickLayoutScrollView)?
            .quickLayoutContentMarginState.appliedIndicatorInsets ?? .zero
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

private func sanitizedContentMargin(_ value: CGFloat) -> CGFloat {
    value.isFinite ? max(0, value) : 0
}
