import QuickLayoutKit
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct SafeAreaInsetSpacingTests {
    private let proposal = CGSize(width: 200, height: 100)

    @Test func omittedSpacingEqualsExplicitZeroOnEveryEdge() {
        for edge: VerticalEdge in [.top, .bottom] {
            let implicit = content().safeAreaInset(edge: edge) { inset() }
            let explicit = content().safeAreaInset(edge: edge, spacing: 0) { inset() }
            #expect(implicit.sizeThatFits(proposal) == CGSize(width: 20, height: 42))
            #expect(implicit.sizeThatFits(proposal) == explicit.sizeThatFits(proposal))
        }
        for edge: HorizontalEdge in [.leading, .trailing] {
            let implicit = content().safeAreaInset(edge: edge) { inset() }
            let explicit = content().safeAreaInset(edge: edge, spacing: 0) { inset() }
            #expect(implicit.sizeThatFits(proposal) == CGSize(width: 32, height: 30))
            #expect(implicit.sizeThatFits(proposal) == explicit.sizeThatFits(proposal))
        }
    }

    @Test func explicitSpacingPreservesFiniteOverlapAndSanitizesNonfiniteValues() {
        let cases: [(CGFloat, CGFloat)] = [(0, 0), (8, 8), (-4, -4), (.infinity, 0), (-.infinity, 0), (.nan, 0)]
        for (spacing, resolved) in cases {
            let vertical = content().safeAreaInset(edge: .bottom, spacing: spacing) { inset() }
            let horizontal = content().safeAreaInset(edge: HorizontalEdge.leading, spacing: spacing) { inset() }
            #expect(vertical.sizeThatFits(proposal) == CGSize(width: 20, height: 42 + resolved))
            #expect(horizontal.sizeThatFits(proposal) == CGSize(width: 32 + resolved, height: 30))
        }
    }

    @Test func optionalContentStillAcceptsNilWithDefaultSpacing() {
        let vertical = content().safeAreaInset(edge: .bottom) { nil as UIView? }
        let horizontal = content().safeAreaInset(edge: HorizontalEdge.trailing) { nil as UIView? }
        #expect(vertical.sizeThatFits(proposal) == CGSize(width: 20, height: 30))
        #expect(horizontal.sizeThatFits(proposal) == CGSize(width: 20, height: 30))
    }

    @Test func conditionalAndOptionalLayoutsKeepEmptyContentSpacing() {
        for visible in [false, true] {
            let optional: Layout? = visible ? inset() : nil
            let conditionalVertical = content().safeAreaInset(edge: .bottom, spacing: 8) {
                if visible { inset() }
            }
            let optionalVertical = content().safeAreaInset(edge: .bottom, spacing: 8) { optional }
            let conditionalHorizontal = content().safeAreaInset(edge: HorizontalEdge.trailing, spacing: 8) {
                if visible { inset() }
            }
            let optionalHorizontal = content().safeAreaInset(edge: HorizontalEdge.trailing, spacing: 8) { optional }
            #expect(conditionalVertical.sizeThatFits(proposal) == CGSize(width: 20, height: visible ? 50 : 38))
            #expect(conditionalHorizontal.sizeThatFits(proposal) == CGSize(width: visible ? 40 : 28, height: 30))
            #expect(optionalVertical.sizeThatFits(proposal) == conditionalVertical.sizeThatFits(proposal))
            #expect(optionalHorizontal.sizeThatFits(proposal) == conditionalHorizontal.sizeThatFits(proposal))
        }
    }

    private func content() -> Layout { UIView().frame(width: 20, height: 30) }
    private func inset() -> Layout { UIView().frame(width: 12, height: 12) }
}
