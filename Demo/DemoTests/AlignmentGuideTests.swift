import QuickLayout
import QuickLayoutKitCore
import Testing
import UIKit

private typealias Horizontal = QuickLayout.HorizontalAlignment
private typealias Vertical = QuickLayout.VerticalAlignment

@MainActor
struct AlignmentGuideTests {
    @Test func chainedGuidesAreResolvedOnceAndRetainPreviousValues() {
        let view = UIView()
        let layout = view.resizable().frame(width: 40, height: 20)
            .alignmentGuide(Horizontal.center) { $0[Horizontal.center] + 12 }
            .alignmentGuide(Vertical.center) { $0[Vertical.center] - 9 }
            .alignmentGuide(Horizontal.center) { $0[Horizontal.center] + 3 }
        let node = layout.quick_layoutThatFits(CGSize(width: 200, height: 200))
        #expect(node.dimensions[Horizontal.center] == 35)
        #expect(node.dimensions[Vertical.center] == 1)
        #expect(layout.views().map(ObjectIdentifier.init) == [ObjectIdentifier(view)])

        let framed = layout.frame(width: 100, height: 100)
        framed.applyFrame(CGRect(x: 0, y: 0, width: 100, height: 100), alignment: .topLeading,
                          layoutDirection: .leftToRight)
        #expect(view.frame.origin == CGPoint(x: 15, y: 49))
    }

    @Test func leafGuidesAndCrossAxisReferencesSurviveWrappers() {
        let view = UIView()
        let layout = view
            .alignmentGuide(Horizontal.center) { _ in 12 }
            .alignmentGuide(Vertical.center) { $0[Horizontal.center] + 3 }
            .padding(5)
        let node = layout.quick_layoutThatFits(CGSize(width: 40, height: 20))
        #expect(node.dimensions[Horizontal.center] == 17)
        #expect(node.dimensions[Vertical.center] == 20)
        #expect(layout.views().map(ObjectIdentifier.init) == [ObjectIdentifier(view)])
    }

    @Test func physicalPlacementStillIgnoresChildGuides() {
        for outer: LayoutDirection in [.leftToRight, .rightToLeft] {
            for local: LayoutDirection in [.leftToRight, .rightToLeft] {
                let positioned = UIView()
                positioned.resizable().frame(width: 20, height: 10)
                    .alignmentGuide(Horizontal.leading) { _ in 7 }
                    .alignmentGuide(Vertical.top) { _ in 3 }
                    .position(x: 70, y: 30)
                    .layoutDirection(local)
                    .applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80),
                                alignment: .topLeading, layoutDirection: outer)
                #expect(positioned.frame == CGRect(x: 60, y: 25, width: 20, height: 10))

                let centered = UIView()
                let layout = GuideCenteredLayout() {
                    centered.resizable().frame(width: 20, height: 10)
                        .alignmentGuide(Horizontal.leading) { _ in 7 }
                        .alignmentGuide(Vertical.top) { _ in 3 }
                }
                layout.layoutDirection(local)
                    .applyFrame(CGRect(x: 0, y: 0, width: 100, height: 80),
                                alignment: .topLeading, layoutDirection: outer)
                #expect(centered.frame == CGRect(x: 40, y: 35, width: 20, height: 10))
            }
        }
    }
}

private struct GuideCenteredLayout: LayoutAlgorithm {
    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout Void) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedSize, subviews: Subviews, cache: inout Void) {
        for subview in subviews {
            subview.place(at: CGPoint(x: bounds.midX, y: bounds.midY),
                          anchor: .center, proposal: .unspecified)
        }
    }
}
