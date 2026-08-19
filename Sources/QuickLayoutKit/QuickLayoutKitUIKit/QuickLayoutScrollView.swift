//
//  QuickLayoutScrollView.swift
//  QuickLayoutKit
//
//  Created by Sondra on 2025/12/26.
//

import QuartzCore
import QuickLayout
import UIKit

/// A scroll view that lays out QuickLayout elements along one scroll axis.
///
/// The primary initializer mirrors SwiftUI's `ScrollView`: choose an axis,
/// choose whether indicators are visible, and provide builder content. Unlike
/// SwiftUI, this type is a UIKit reference type and can also be created with
/// `init(frame:)` for use with ``ScrollView(_:_:showsIndicators:content:)``.
/// Runtime layout-direction changes relayout existing content without changing
/// the numeric scroll position, matching SwiftUI's `ScrollView` behavior.
open class QuickLayoutScrollView:
    UIScrollView,
    HasBody,
    QuickLayoutUpdating,
    QuickLayoutEnvironmentUpdating {

    /// An edge of the scrollable content.
    public enum Edge: Equatable, Sendable {
        /// The top edge of vertical content.
        case top

        /// The bottom edge of vertical content.
        case bottom

        /// The semantic leading edge of horizontal content.
        case leading

        /// The semantic trailing edge of horizontal content.
        case trailing

        fileprivate func isCompatible(with axis: QuickLayout.Axis) -> Bool {
            switch (self, axis) {
            case (.top, .vertical), (.bottom, .vertical),
                 (.leading, .horizontal), (.trailing, .horizontal):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Public Properties

    /// The axis along which the receiver scrolls.
    ///
    /// `QuickLayoutScrollView` intentionally supports one axis at a time. It
    /// uses the axis to choose the implicit `VStack` or `HStack` that contains
    /// builder-produced elements.
    open var axis: QuickLayout.Axis = .vertical {
        didSet {
            guard axis != oldValue else { return }
            if let pendingScroll, !pendingScroll.edge.isCompatible(with: axis) {
                self.pendingScroll = nil
            }
            configureAxisBehavior()
            setNeedsQuickLayout()
        }
    }

    /// Whether the indicator for the configured axis is visible.
    open var showsIndicators = true {
        didSet {
            guard showsIndicators != oldValue else { return }
            configureIndicators()
        }
    }

    /// The semantic role used to resolve the receiver's layout direction.
    ///
    /// App-level language switching commonly updates this property directly.
    /// Publish the new effective direction immediately, then invalidate the
    /// hosted content so the next layout pass remeasures and replaces it.
    open override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            quickLayoutEnvironmentState.update(self)
            setNeedsQuickLayout()
        }
    }

    private var contentElements: [Element] = [] {
        didSet {
            setNeedsQuickLayout()
        }
    }

    private let quickLayoutEnvironmentState = _QuickLayoutEnvironmentState()
    private var pendingScroll: (edge: Edge, animated: Bool)?
    private var needsContentMarginStartPosition = false
    let quickLayoutContentMarginState = QuickLayoutContentMarginState()

    // MARK: - Initialization

    /// Creates an empty, vertically scrolling view.
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureAxisBehavior()
    }

    /// Creates an empty scroll view for a single axis.
    ///
    /// - Parameters:
    ///   - axis: The single axis along which content scrolls.
    ///   - showsIndicators: Whether to show the indicator for that axis.
    public convenience init(
        _ axis: QuickLayout.Axis,
        showsIndicators: Bool = true
    ) {
        self.init(frame: .zero)
        configure(axis: axis, showsIndicators: showsIndicators, content: [])
    }

    /// Creates a scroll view with builder-produced content.
    ///
    /// - Parameters:
    ///   - axis: The single axis along which content scrolls.
    ///   - showsIndicators: Whether to show the indicator for that axis.
    ///   - content: The elements to place in the scroll view. Multiple root
    ///     elements use a zero-spacing stack and center on the cross axis.
    public convenience init(
        _ axis: QuickLayout.Axis = .vertical,
        showsIndicators: Bool = true,
        @FastArrayBuilder<Element> content: () -> [Element]
    ) {
        self.init(frame: .zero)
        configure(axis: axis, showsIndicators: showsIndicators, content: content())
    }

    /// Creates a scroll view from an archive or storyboard.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAxisBehavior()
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        quickLayoutEnvironmentState.update(self)
        setNeedsQuickLayout()
    }

    open override func traitCollectionDidChange(
        _ previousTraitCollection: UITraitCollection?
    ) {
        super.traitCollectionDidChange(previousTraitCollection)
        quickLayoutEnvironmentState.update(self)
        setNeedsQuickLayout()
    }

    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .safeArea)
    }

    open override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        quickLayoutEnvironmentState.update(self, explicitReason: .layoutMargins)
    }

    // MARK: - HasBody

    /// The QuickLayout content rendered by the scroll view.
    @LayoutBuilder
    open var body: Layout {
        if contentElements.isEmpty {
            EmptyLayout()
        } else {
            axisLayout
        }
    }

    @LayoutBuilder
    private var axisLayout: Layout {
        switch axis {
        case .vertical:
            VStack(alignment: .center, spacing: 0) {
                ForEach(contentElements)
            }
        case .horizontal:
            HStack(alignment: .center, spacing: 0) {
                ForEach(contentElements)
            }
        }
    }

    // MARK: - Layout

    override open func layoutSubviews() {
        super.layoutSubviews()

        quickLayoutEnvironmentState.update(self)
        quickLayoutUpdateContentMarginDirectionIfNeeded()
        let layoutDirection = quickLayoutDirection
        let layoutProposal = proposedContentSize
        let safeAreaRegionInsets = quickLayoutSafeAreaRegionInsets
        let measuredContentSize = withQuickLayoutContainerSize(
            bounds.size,
            insets: safeAreaRegionInsets.container,
            keyboardInsets: safeAreaRegionInsets.keyboard
        ) {
            _QuickLayoutViewImplementation.sizeThatFits(
                self,
                size: layoutProposal
            ) ?? .zero
        }
        let contentLayoutSize = resolvedContentLayoutSize(measuredContentSize)

        withQuickLayoutContainerSize(
            bounds.size,
            insets: safeAreaRegionInsets.container,
            keyboardInsets: safeAreaRegionInsets.keyboard
        ) {
            body.applyFrame(
                CGRect(origin: .zero, size: contentLayoutSize),
                alignment: contentAlignment,
                layoutDirection: layoutDirection
            )
        }

        if contentSize != contentLayoutSize {
            contentSize = contentLayoutSize
        }

        applyContentMarginStartPositionIfPossible()
        applyPendingScrollIfPossible()
    }

    /// Invalidates the hosted scroll content.
    ///
    /// Call this after localized content changes without changing layout
    /// direction, because UIKit has no notification for an app-specific locale.
    open func setNeedsQuickLayout() {
        setNeedsLayout()
    }

    /// Lays out the hosted scroll content immediately if needed.
    open func quickLayoutIfNeeded() {
        layoutIfNeeded()
    }

    /// Responds to UIKit environment changes that can affect scroll content.
    ///
    /// The default implementation invalidates measurement and placement while
    /// preserving the existing numeric content offset.
    open func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        setNeedsQuickLayout()
    }

    private var contentAlignment: Alignment {
        switch axis {
        case .vertical:
            return .top
        case .horizontal:
            return .leading
        }
    }

    private var proposedContentSize: CGSize {
        let viewportSize = contentMarginViewportSize
        switch axis {
        case .vertical:
            return CGSize(width: viewportSize.width, height: .infinity)
        case .horizontal:
            return CGSize(width: .infinity, height: viewportSize.height)
        }
    }

    private var contentMarginViewportSize: CGSize {
        let insets = quickLayoutAppliedContentMarginInsets
        return CGSize(
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    private var quickLayoutSafeAreaRegionInsets: (
        container: UIEdgeInsets,
        keyboard: UIEdgeInsets
    ) {
        let keyboardDelta = max(0, quickLayoutKeyboardInsetDelta)
        guard keyboardDelta > 0 else {
            return (adjustedContentInset, .zero)
        }

        var containerInsets = adjustedContentInset
        containerInsets.bottom = max(0, containerInsets.bottom - keyboardDelta)
        let keyboardInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: adjustedContentInset.bottom,
            right: 0
        )
        return (containerInsets, keyboardInsets)
    }

    private func resolvedContentLayoutSize(_ measuredSize: CGSize) -> CGSize {
        let viewportSize = contentMarginViewportSize
        switch axis {
        case .vertical:
            return CGSize(
                width: max(viewportSize.width, measuredSize.width),
                height: measuredSize.height
            )
        case .horizontal:
            return CGSize(
                width: measuredSize.width,
                height: max(viewportSize.height, measuredSize.height)
            )
        }
    }

    // MARK: - Scrolling

    /// Scrolls to an edge that belongs to the configured axis.
    ///
    /// A request made before the content has been measured is deferred until
    /// the next successful layout pass. A request for an edge on the other
    /// axis is ignored.
    ///
    /// - Parameters:
    ///   - edge: The content edge to reveal.
    ///   - animated: Pass `true` to animate the change.
    open func scrollTo(_ edge: Edge, animated: Bool = true) {
        guard edge.isCompatible(with: axis) else { return }

        layoutIfNeeded()
        guard canResolveScrollOffset(for: edge) else {
            pendingScroll = (edge, animated)
            return
        }

        setContentOffset(targetOffset(for: edge), requestedAnimated: animated)
    }

    // MARK: - Internal Configuration

    func configure(
        axis: QuickLayout.Axis,
        showsIndicators: Bool,
        content: [Element]
    ) {
        quickLayoutResetContentMargins()
        self.axis = axis
        self.showsIndicators = showsIndicators
        contentElements = content
    }

    func quickLayoutIsAtContentStart() -> Bool {
        let edge: Edge = axis == .vertical ? .top : .leading
        let target = targetOffset(for: edge)

        switch axis {
        case .vertical:
            return abs(contentOffset.y - target.y) < 0.5
        case .horizontal:
            return abs(contentOffset.x - target.x) < 0.5
        }
    }

    func quickLayoutKeepContentAtStartAfterMarginChange() {
        needsContentMarginStartPosition = true
        setNeedsQuickLayout()
    }

    // MARK: - Private Helpers

    private func configureAxisBehavior() {
        alwaysBounceVertical = axis == .vertical
        alwaysBounceHorizontal = axis == .horizontal
        configureIndicators()
    }

    private func configureIndicators() {
        showsVerticalScrollIndicator = showsIndicators && axis == .vertical
        showsHorizontalScrollIndicator = showsIndicators && axis == .horizontal
    }

    private func applyContentMarginStartPositionIfPossible() {
        guard needsContentMarginStartPosition else { return }

        let edge: Edge = axis == .vertical ? .top : .leading
        guard canResolveScrollOffset(for: edge) else { return }

        needsContentMarginStartPosition = false
        setContentOffset(
            targetOffset(for: edge),
            requestedAnimated: false
        )
    }

    private func applyPendingScrollIfPossible() {
        guard let pendingScroll,
              pendingScroll.edge.isCompatible(with: axis),
              canResolveScrollOffset(for: pendingScroll.edge) else {
            return
        }

        self.pendingScroll = nil
        setContentOffset(
            targetOffset(for: pendingScroll.edge),
            requestedAnimated: pendingScroll.animated
        )
    }

    private func canResolveScrollOffset(for edge: Edge) -> Bool {
        switch edge {
        case .top, .bottom:
            return bounds.height > 0 && contentSize.height > 0
        case .leading, .trailing:
            return bounds.width > 0 && contentSize.width > 0
        }
    }

    private func targetOffset(for edge: Edge) -> CGPoint {
        let inset = adjustedContentInset

        switch edge {
        case .top:
            return CGPoint(x: contentOffset.x, y: -inset.top)
        case .bottom:
            let maximumY = contentSize.height - bounds.height + inset.bottom
            return CGPoint(x: contentOffset.x, y: max(-inset.top, maximumY))
        case .leading:
            return CGPoint(x: horizontalOffset(for: .leading, inset: inset), y: contentOffset.y)
        case .trailing:
            return CGPoint(x: horizontalOffset(for: .trailing, inset: inset), y: contentOffset.y)
        }
    }

    private func horizontalOffset(for edge: Edge, inset: UIEdgeInsets) -> CGFloat {
        let minimumX = -inset.left
        let maximumX = max(minimumX, contentSize.width - bounds.width + inset.right)
        let isRightToLeft = quickLayoutDirection == .rightToLeft

        switch (edge, isRightToLeft) {
        case (.leading, false), (.trailing, true):
            return minimumX
        case (.leading, true), (.trailing, false):
            return maximumX
        default:
            return contentOffset.x
        }
    }

    private func setContentOffset(_ offset: CGPoint, requestedAnimated animated: Bool) {
        guard !animated else {
            setContentOffset(offset, animated: true)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            setContentOffset(offset, animated: false)
            layer.removeAnimation(forKey: "bounds")
            layer.removeAnimation(forKey: "position")
        }
        CATransaction.commit()
    }
}
