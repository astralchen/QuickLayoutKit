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

    private func content() -> Layout { UIView().frame(width: 20, height: 30) }
    private func inset() -> Layout { UIView().frame(width: 12, height: 12) }
}
