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
open class QuickLayoutScrollView: UIScrollView, HasBody {

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
            setNeedsLayout()
        }
    }

    /// Whether the indicator for the configured axis is visible.
    open var showsIndicators = true {
        didSet {
            guard showsIndicators != oldValue else { return }
            configureIndicators()
        }
    }

    private var contentElements: [Element] = [] {
        didSet {
            setNeedsLayout()
        }
    }

    private var pendingScroll: (edge: Edge, animated: Bool)?

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
    ///   - content: The elements to place in the scroll view.
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
            VStack {
                ForEach(contentElements)
            }
        case .horizontal:
            HStack {
                ForEach(contentElements)
            }
        }
    }

    // MARK: - Layout

    override open func layoutSubviews() {
        super.layoutSubviews()

        let layoutProposal = proposedContentSize
        let measuredContentSize = _QuickLayoutViewImplementation.sizeThatFits(
            self,
            size: layoutProposal
        ) ?? .zero
        let contentLayoutSize = resolvedContentLayoutSize(measuredContentSize)

        body.applyFrame(
            CGRect(origin: .zero, size: contentLayoutSize),
            alignment: contentAlignment,
            layoutDirection: quickLayoutDirection
        )

        if contentSize != contentLayoutSize {
            contentSize = contentLayoutSize
        }

        applyPendingScrollIfPossible()
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
        switch axis {
        case .vertical:
            return CGSize(width: bounds.width, height: .infinity)
        case .horizontal:
            return CGSize(width: .infinity, height: bounds.height)
        }
    }

    private func resolvedContentLayoutSize(_ measuredSize: CGSize) -> CGSize {
        switch axis {
        case .vertical:
            return CGSize(
                width: max(bounds.width, measuredSize.width),
                height: measuredSize.height
            )
        case .horizontal:
            return CGSize(
                width: measuredSize.width,
                height: max(bounds.height, measuredSize.height)
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
        self.axis = axis
        self.showsIndicators = showsIndicators
        contentElements = content
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
