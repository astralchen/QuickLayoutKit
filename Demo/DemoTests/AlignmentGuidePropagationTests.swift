import QuickLayout
import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct AlignmentGuidePropagationTests {
    private let proposal = CGSize(width: 100, height: 100)

    @Test func rejectedViewThatFitsCandidateMustNotSupplyGuide() {
        let guide = HorizontalAlignment(PropagationGuide.self)
        let fallback = UIView().resizable().frame(width: 40, height: 20)
        let candidate = UIView().resizable().frame(width: 200, height: 20)
        let withoutGuide = ViewThatFits(in: .horizontal) {
            candidate
            fallback
        }.alignmentGuide(VerticalAlignment.top) { $0[guide] }
        let withGuide = ViewThatFits(in: .horizontal) {
            candidate.alignmentGuide(guide) { _ in 12 }
            fallback
        }.alignmentGuide(VerticalAlignment.top) { $0[guide] }
        let baseline = withoutGuide.layoutThatFits(proposal, layoutDirection: .rightToLeft)
        let actual = withGuide.layoutThatFits(proposal, layoutDirection: .rightToLeft)
        #expect(actual.size == baseline.size)
        #expect(actual.dimensions[VerticalAlignment.top] == baseline.dimensions[VerticalAlignment.top])
    }

    @Test func customGuideMustSurviveCachedNodeRemeasurement() {
        let guide = HorizontalAlignment(PropagationGuide.self)
        for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
            for prewarm in [false, true] {
                for container in 0..<3 {
                    for explicit: CGFloat in [-2, 12, 42] {
                        let child: any QuickLayout.Layout
                        switch container {
                        case 1:
                            child = VStack(alignment: .leading) {
                                UIView().resizable().frame(width: 40, height: 20)
                                    .alignmentGuide(guide) { _ in explicit }
                            }
                        case 2:
                            child = VGrid(columns: [GridItem(.fixed(100))]) {
                                UIView().resizable().frame(width: 40, height: 20)
                                    .alignmentGuide(guide) { _ in explicit }
                            }
                        default:
                            child = UIView().resizable().frame(width: 40, height: 20)
                                .alignmentGuide(guide) { _ in explicit }
                        }
                        let cache = PropagationCachingLayout(child: child)
                        if prewarm { _ = cache.layoutThatFits(proposal, layoutDirection: direction) }
                        let outer = cache.alignmentGuide(VerticalAlignment.top) { $0[guide] }
                        for _ in 0..<3 {
                            let node = outer.layoutThatFits(proposal, layoutDirection: direction)
                            #expect(node.dimensions[VerticalAlignment.top] == (container == 2 ? 42 : explicit))
                        }
                        #expect(cache.measurements == 1)
                    }
                }
            }
        }
    }

    @Test func changingViewThatFitsSelectionKeepsOnlyReturnedGuides() {
        let guide = HorizontalAlignment(PropagationGuide.self)
        let rejectedGuide = HorizontalAlignment(PropagationOtherGuide.self)
        for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
            let layout = ViewThatFits(in: .horizontal) {
                UIView().resizable().frame(width: 200, height: 20)
                    .alignmentGuide(guide) { _ in 12 }
                    .alignmentGuide(rejectedGuide) { _ in 17 }
                UIView().resizable().frame(width: 40, height: 20)
                    .alignmentGuide(guide) { _ in 7 }
            }
            .alignmentGuide(VerticalAlignment.top) { $0[guide] }
            .alignmentGuide(VerticalAlignment.bottom) { $0[rejectedGuide] }
            for width: CGFloat in [100, 300, 100, 300] {
                let node = layout.layoutThatFits(CGSize(width: width, height: 100), layoutDirection: direction)
                #expect(node.dimensions[VerticalAlignment.top] == (width == 100 ? 7 : 12))
                #expect(node.dimensions[VerticalAlignment.bottom] == (width == 100 ? 19 : 17))
            }
        }
    }

    @Test func cachedMultipleChildrenKeepAggregatedCustomGuide() {
        let guide = HorizontalAlignment(PropagationGuide.self)
        for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
            let child = VStack(alignment: .leading) {
                UIView().resizable().frame(width: 40, height: 20).alignmentGuide(guide) { _ in 12 }
                UIView().resizable().frame(width: 40, height: 20).alignmentGuide(guide) { _ in 24 }
            }.padding(5)
            let cache = PropagationCachingLayout(child: child)
            _ = cache.layoutThatFits(proposal, layoutDirection: direction)
            let outer = cache.alignmentGuide(VerticalAlignment.top) { $0[guide] }
            for _ in 0..<3 {
                #expect(outer.layoutThatFits(proposal, layoutDirection: direction).dimensions[VerticalAlignment.top] == 23)
            }
            #expect(cache.measurements == 1)
        }
    }

    @Test func rtlBuiltInCustomDefaultQueryIsLogical() {
        let guide = HorizontalAlignment(PropagationDerivedGuide.self)
        let child = UIView().resizable().frame(width: 40, height: 20)
            .alignmentGuide(guide) { $0[guide] }
            .alignmentGuide(VerticalAlignment.top) { $0[guide] }
        let actual = child.layoutThatFits(proposal, layoutDirection: .rightToLeft)
        #expect(actual.dimensions[VerticalAlignment.top] == 5)
    }
}

private enum PropagationGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
}
private enum PropagationDerivedGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context[HorizontalAlignment.leading] + 5 }
}
private final class PropagationCachingLayout: QuickLayout.Layout {
    let child: Element
    var cached: LayoutNode?
    var measurements = 0
    init(child: Element) { self.child = child }
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        if let cached { return cached }
        measurements += 1
        let node = child.quick_layoutThatFits(proposedSize)
        cached = node
        return node
    }
    func quick_flexibility(for axis: Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
}

private enum PropagationOtherGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 19 }
}
