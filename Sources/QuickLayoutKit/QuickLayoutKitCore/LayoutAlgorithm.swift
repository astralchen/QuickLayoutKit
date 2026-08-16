import Foundation
import QuickLayout
import UIKit

/// A type that measures and places a collection of elements.
///
/// Conforming types implement the same two-phase layout model as SwiftUI's
/// `Layout`: first report a container size, then place every subview inside
/// the resulting bounds.
public protocol LayoutAlgorithm {

    associatedtype Cache = Void
    typealias Subviews = LayoutSubviews

    /// Creates storage shared by the measurement and placement phases.
    func makeCache(subviews: Subviews) -> Cache

    /// Refreshes an existing cache before a new layout pass.
    func updateCache(_ cache: inout Cache, subviews: Subviews)

    /// Returns the size of the composite element for a proposed size.
    func sizeThatFits(
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize

    /// Assigns a position and proposal to each subview.
    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedSize,
        subviews: Subviews,
        cache: inout Cache
    )
}

public extension LayoutAlgorithm where Cache == Void {

    func makeCache(subviews: Subviews) {}
}

public extension LayoutAlgorithm {

    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    /// Builds a QuickLayout element using this layout algorithm.
    func callAsFunction(
        @FastArrayBuilder<Element> content: () -> [Element]
    ) -> some Element & Layout {
        LayoutAlgorithmElement(
            algorithm: self,
            children: content()
        )
    }
}

/// A random-access collection of proxies for a custom layout's children.
public struct LayoutSubviews: RandomAccessCollection {

    public typealias Index = Int
    public typealias Element = LayoutSubview

    private let subviews: [LayoutSubview]

    init(children: [QuickLayout.Element]) {
        subviews = children.map { child in
            LayoutSubview(storage: LayoutSubviewStorage(element: child))
        }
    }

    public var startIndex: Int { subviews.startIndex }
    public var endIndex: Int { subviews.endIndex }

    public subscript(position: Int) -> LayoutSubview {
        subviews[position]
    }

    func resetPlacements() {
        subviews.forEach { $0.storage.placement = nil }
    }
}

/// A proxy that a `LayoutAlgorithm` uses to measure and place one child.
public struct LayoutSubview: Equatable {

    fileprivate let storage: LayoutSubviewStorage

    /// The child's QuickLayout layout priority.
    public var priority: Double {
        Double(storage.element.quick_layoutPriority())
    }

    /// Returns the child's custom value for a layout key.
    public subscript<Key: LayoutValueKey>(key: Key.Type) -> Key.Value {
        storage.element._layoutValue(for: key)
    }

    /// Asks the child to choose a size for a proposal.
    public func sizeThatFits(_ proposal: ProposedSize) -> CGSize {
        let dimensions = dimensions(in: proposal)
        return CGSize(width: dimensions.width, height: dimensions.height)
    }

    /// Asks the child for its dimensions and alignment guides.
    public func dimensions(in proposal: ProposedSize) -> ElementDimensions {
        storage.element.quick_layoutThatFits(proposal.quickLayoutProposal).dimensions
    }

    /// Places the child at a point in the layout container.
    ///
    /// The anchor uses unit coordinates where `(0, 0)` is the child's top-left
    /// and `(1, 1)` is its bottom-right.
    public func place(
        at position: CGPoint,
        anchor: UnitPoint = UnitPoint(x: 0, y: 0),
        proposal: ProposedSize = .unspecified
    ) {
        storage.placement = LayoutSubviewPlacement(
            position: sanitize(position),
            anchor: UnitPoint(
                x: sanitize(anchor.x),
                y: sanitize(anchor.y)
            ),
            proposal: proposal
        )
    }

    public static func == (lhs: LayoutSubview, rhs: LayoutSubview) -> Bool {
        lhs.storage === rhs.storage
    }
}

private final class LayoutSubviewStorage {
    let element: Element
    var placement: LayoutSubviewPlacement?

    init(element: Element) {
        self.element = element
    }
}

private struct LayoutSubviewPlacement {
    let position: CGPoint
    let anchor: UnitPoint
    let proposal: ProposedSize
}

private final class LayoutAlgorithmCacheBox<Cache> {
    private let lock = NSRecursiveLock()
    private var cache: Cache?

    func withCache<Result>(
        make: () -> Cache,
        update: (inout Cache) -> Void,
        operation: (inout Cache) -> Result
    ) -> Result {
        lock.lock()
        defer { lock.unlock() }

        if cache == nil {
            cache = make()
        } else {
            update(&cache!)
        }
        return operation(&cache!)
    }
}

private struct LayoutAlgorithmElement<Algorithm: LayoutAlgorithm>: Layout {

    let algorithm: Algorithm
    let children: [Element]
    let cacheBox: LayoutAlgorithmCacheBox<Algorithm.Cache>

    init(algorithm: Algorithm, children: [Element]) {
        self.algorithm = algorithm
        self.children = children
        cacheBox = LayoutAlgorithmCacheBox()
    }

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        let proposal = ProposedSize(quickLayoutProposal: proposedSize)
        let subviews = LayoutSubviews(children: children)

        return cacheBox.withCache(
            make: { algorithm.makeCache(subviews: subviews) },
            update: { algorithm.updateCache(&$0, subviews: subviews) }
        ) { cache in
            let size = sanitize(
                algorithm.sizeThatFits(
                    proposal: proposal,
                    subviews: subviews,
                    cache: &cache
                )
            )

            subviews.resetPlacements()
            algorithm.placeSubviews(
                in: CGRect(origin: .zero, size: size),
                proposal: proposal,
                subviews: subviews,
                cache: &cache
            )

            return layoutNode(size: size, subviews: subviews)
        }
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        children.reduce(.fixedSize) { result, child in
            max(result, child.quick_flexibility(for: axis))
        }
    }

    func quick_layoutPriority() -> CGFloat {
        children.map { $0.quick_layoutPriority() }.max() ?? 0
    }

    func quick_extractViewsIntoArray(_ views: inout [UIView]) {
        orderedSubviews(LayoutSubviews(children: children)).forEach { subview in
            subview.storage.element.quick_extractViewsIntoArray(&views)
        }
    }

    private func layoutNode(size: CGSize, subviews: LayoutSubviews) -> LayoutNode {
        let layers: [Element] = orderedSubviews(subviews).map { subview in
            let placement = subview.storage.placement ?? LayoutSubviewPlacement(
                position: .zero,
                anchor: UnitPoint(x: 0, y: 0),
                proposal: .unspecified
            )
            let childLayout = subview.storage.element.quick_layoutThatFits(
                placement.proposal.quickLayoutProposal
            )
            let origin = CGPoint(
                x: placement.position.x - placement.anchor.x * childLayout.size.width,
                y: placement.position.y - placement.anchor.y * childLayout.size.height
            )
            return positioned(
                childLayout,
                at: origin,
                in: size
            )
        }

        guard !layers.isEmpty else {
            return FixedFrameElement(
                child: EmptyElement(),
                width: size.width,
                height: size.height,
                alignment: .topLeading
            ).quick_layoutThatFits(size)
        }

        return ZStackElement(children: layers, alignment: .topLeading)
            .quick_layoutThatFits(size)
    }

    private func orderedSubviews(_ subviews: LayoutSubviews) -> [LayoutSubview] {
        subviews.enumerated()
            .sorted { lhs, rhs in
                let lhsZIndex = lhs.element[_ZIndexLayoutValueKey.self]
                let rhsZIndex = rhs.element[_ZIndexLayoutValueKey.self]
                return lhsZIndex == rhsZIndex
                    ? lhs.offset < rhs.offset
                    : lhsZIndex < rhsZIndex
            }
            .map(\.element)
    }
}

private struct PrecomputedLayoutElement: Layout {
    let layout: LayoutNode

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { layout }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}

private func positioned(
    _ layout: LayoutNode,
    at origin: CGPoint,
    in containerSize: CGSize
) -> Element {
    let horizontalOffset: CGFloat
    if LayoutContext.layoutDirection == .rightToLeft {
        let leadingOrigin = containerSize.width - layout.size.width
        horizontalOffset = leadingOrigin - origin.x
    } else {
        horizontalOffset = origin.x
    }

    let offsetChild = OffsetElement(
        child: PrecomputedLayoutElement(layout: layout),
        offset: CGPoint(x: horizontalOffset, y: origin.y)
    )
        // Keep child guides from changing this physical placement when the
        // enclosing fixed frame resolves its top-leading alignment.
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }

    let positionedChild = FixedFrameElement(
        child: offsetChild,
        width: containerSize.width,
        height: containerSize.height,
        alignment: .topLeading
    )
    return positionedChild
        // Resolve the wrapper's guides in its parent's direction so a local
        // layout-direction override can't leak its physical compensation out.
        .alignmentGuide(HorizontalAlignment.leading) { dimensions in
            dimensions[HorizontalAlignment.leading]
        }
        .alignmentGuide(VerticalAlignment.top) { dimensions in
            dimensions[VerticalAlignment.top]
        }
}

private func sanitize(_ value: CGFloat) -> CGFloat {
    value.isFinite ? value : 0
}

private func sanitize(_ point: CGPoint) -> CGPoint {
    CGPoint(x: sanitize(point.x), y: sanitize(point.y))
}

private func sanitize(_ size: CGSize) -> CGSize {
    CGSize(
        width: max(0, sanitize(size.width)),
        height: max(0, sanitize(size.height))
    )
}
