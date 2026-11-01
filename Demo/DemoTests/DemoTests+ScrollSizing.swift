import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit

extension DemoTests {
    /// QuickLayout's infinite proposal requests the ideal size (SwiftUI nil).
    /// Compare the layout subview directly, rather than UIHostingController's
    /// own unspecified-size conversion or a window's safe-area adjustments.
    @Test func scrollSizingMatchesSwiftUIProposalsAndContainers() {
        var comparisons = 0
        for horizontal in [false, true] {
            for content in ScrollSizingContent.allCases {
                for container in ScrollSizingContainer.allCases {
                    let reference = scrollSizingReference(horizontal, content, container)
                    let actual = scrollSizingElement(horizontal, content, container)
                    for proposal in scrollSizingProposals {
                        let expected = scrollSizingMeasure(reference, proposal)
                        let size = actual.quick_layoutThatFits(proposal).size
                        #expect(abs(size.width - expected.width) < 0.5,
                                "width: horizontal=\(horizontal), \(content), \(container), \(proposal): \(size) != \(expected)")
                        #expect(abs(size.height - expected.height) < 0.5,
                                "height: horizontal=\(horizontal), \(content), \(container), \(proposal): \(size) != \(expected)")
                        comparisons += 1
                    }
                }
            }
        }
        print("SCROLL_PARITY: \(comparisons) comparisons; iOS \(UIDevice.current.systemVersion)")
    }

    @Test func scrollSizingPublicAndBuilderPathsAgreeWithoutPriorLayout() {
        for horizontal in [false, true] {
            for content in ScrollSizingContent.allCases {
                let scroll = QuickLayoutScrollView(horizontal ? .horizontal : .vertical) {
                    scrollSizingContent(content)
                }
                let builderScroll = QuickLayoutScrollView()
                let element = ScrollView(builderScroll, horizontal ? .horizontal : .vertical) {
                    scrollSizingContent(content)
                }
                for bounds in [CGSize.zero, CGSize(width: 17, height: 29), CGSize(width: 700, height: 900)] {
                    scroll.bounds.size = bounds
                    builderScroll.bounds.size = bounds
                    // A stale scroll range must not become an ideal viewport size.
                    scroll.contentSize = CGSize(width: 999, height: 888)
                    for proposal in scrollSizingProposals {
                        let expected = scrollSizingMeasure(scrollSizingReference(horizontal, content, .direct), proposal)
                        #expect(scroll.sizeThatFits(proposal) == expected)
                        #expect(scroll.quick_layoutThatFits(proposal).size == expected)
                        #expect(element.quick_layoutThatFits(proposal).size == expected)
                        #expect(scroll.bounds.size == bounds)
                        #expect(scroll.contentSize == CGSize(width: 999, height: 888))
                    }
                }
                for axis: QuickLayout.Axis in [.horizontal, .vertical] {
                    #expect(scroll.quick_flexibility(for: axis) == element.quick_flexibility(for: axis))
                }
            }
        }
    }

    @Test func scrollSizingContentMarginsMatchSwiftUI() {
        if #available(iOS 17.0, *) {
            for horizontal in [false, true] {
                for content in ScrollSizingContent.allCases {
                    let scroll = QuickLayoutScrollView()
                    scroll.contentInsetAdjustmentBehavior = .never
                    let element = ScrollView(scroll, horizontal ? .horizontal : .vertical) {
                        scrollSizingContent(content)
                    }.contentMargins(12, for: .scrollContent)
                    let reference = scrollSizingReference(horizontal, content, .direct)
                        .contentMargins(12, for: .scrollContent)
                    for proposal in scrollSizingProposals {
                        let expected = scrollSizingMeasure(reference, proposal)
                        #expect(element.quick_layoutThatFits(proposal).size == expected,
                                "margins: horizontal=\(horizontal), \(content), \(proposal), expected \(expected)")
                    }
                }
            }
        }
    }

    @Test func scrollSizingChangesWithAxisContentAndInsets() {
        let scroll = QuickLayoutScrollView(.vertical) { UIView().frame(width: 80, height: 60) }
        let proposal = CGSize(width: 300, height: 200)
        #expect(scroll.sizeThatFits(proposal) == CGSize(width: 80, height: 200))
        scroll.axis = .horizontal
        #expect(scroll.sizeThatFits(proposal) == CGSize(width: 300, height: 60))
        _ = ScrollView(scroll, .vertical) { UIView().frame(width: 140, height: 90) }
        #expect(scroll.sizeThatFits(proposal) == CGSize(width: 140, height: 200))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 3, left: 5, bottom: 7, right: 11)
        #expect(scroll.sizeThatFits(proposal) == CGSize(width: 156, height: 200))
        #expect(scroll.sizeThatFits(CGSize(width: CGFloat.infinity, height: CGFloat.infinity)) == CGSize(width: 156, height: 100))
    }
}

private let scrollSizingProposals = [
    CGSize(width: 300, height: 200), .zero,
    CGSize(width: 30, height: 20),
    CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
    CGSize(width: 300, height: CGFloat.infinity),
    CGSize(width: CGFloat.infinity, height: 200),
]

private enum ScrollSizingContent: CaseIterable {
    case small, large, flexible, empty, padded, flexibleFrame
}

private enum ScrollSizingContainer: CaseIterable {
    case direct, vstack, hstack, zstack, padding, fixedFrame, flexibleFrame
    case fixedSize, fixedWidth, fixedHeight, nestedSameAxis, nestedOppositeAxis
    case vstackSibling, hstackSibling, vstackFlexibleSibling, hstackFlexibleSibling
}

@MainActor
private func scrollSizingContent(_ content: ScrollSizingContent) -> any Element {
    switch content {
    case .small: UIView().frame(width: 80, height: 60)
    case .large: UIView().frame(width: 500, height: 400)
    case .flexible: UIView()
    case .empty: EmptyLayout()
    case .padded: UIView().frame(width: 80, height: 60).padding(12)
    case .flexibleFrame: UIView().frame(width: 80, height: 60).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private func scrollSizingElement(_ horizontal: Bool, _ content: ScrollSizingContent, _ container: ScrollSizingContainer) -> any Element {
    let axis: QuickLayout.Axis = horizontal ? .horizontal : .vertical
    let child = QuickLayoutScrollView(axis) { scrollSizingContent(content) }
    child.contentInsetAdjustmentBehavior = .never
    switch container {
    case .direct: return child
    case .vstack: return VStack(spacing: 0) { child }
    case .hstack: return HStack(spacing: 0) { child }
    case .zstack: return ZStack { child }
    case .padding: return child.padding(12)
    case .fixedFrame: return child.frame(width: 180, height: 120)
    case .flexibleFrame: return child.frame(maxWidth: .infinity, maxHeight: .infinity)
    case .fixedSize: return child.fixedSize()
    case .fixedWidth: return child.fixedSize(axis: .horizontal)
    case .fixedHeight: return child.fixedSize(axis: .vertical)
    case .nestedSameAxis: return QuickLayoutScrollView(axis) { child }
    case .nestedOppositeAxis: return QuickLayoutScrollView(horizontal ? .vertical : .horizontal) { child }
    case .vstackSibling: return VStack(spacing: 8) { child; UIView().frame(width: 20, height: 30) }
    case .hstackSibling: return HStack(spacing: 8) { child; UIView().frame(width: 20, height: 30) }
    case .vstackFlexibleSibling: return VStack(spacing: 8) { child; UIView() }
    case .hstackFlexibleSibling: return HStack(spacing: 8) { child; UIView() }
    }
}

@MainActor
private func scrollSizingReference(_ horizontal: Bool, _ content: ScrollSizingContent, _ container: ScrollSizingContainer) -> AnyView {
    let child = SwiftUI.ScrollView(horizontal ? .horizontal : .vertical) {
        switch content {
        case .small: SwiftUI.Color.red.frame(width: 80, height: 60)
        case .large: SwiftUI.Color.red.frame(width: 500, height: 400)
        case .flexible: SwiftUI.Color.red
        case .empty: SwiftUI.EmptyView()
        case .padded: SwiftUI.Color.red.frame(width: 80, height: 60).padding(12)
        case .flexibleFrame: SwiftUI.Color.red.frame(width: 80, height: 60).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    switch container {
    case .direct: return AnyView(child)
    case .vstack: return AnyView(SwiftUI.VStack(spacing: 0) { child })
    case .hstack: return AnyView(SwiftUI.HStack(spacing: 0) { child })
    case .zstack: return AnyView(SwiftUI.ZStack { child })
    case .padding: return AnyView(child.padding(12))
    case .fixedFrame: return AnyView(child.frame(width: 180, height: 120))
    case .flexibleFrame: return AnyView(child.frame(maxWidth: .infinity, maxHeight: .infinity))
    case .fixedSize: return AnyView(child.fixedSize())
    case .fixedWidth: return AnyView(child.fixedSize(horizontal: true, vertical: false))
    case .fixedHeight: return AnyView(child.fixedSize(horizontal: false, vertical: true))
    case .nestedSameAxis: return AnyView(SwiftUI.ScrollView(horizontal ? .horizontal : .vertical) { child })
    case .nestedOppositeAxis: return AnyView(SwiftUI.ScrollView(horizontal ? .vertical : .horizontal) { child })
    case .vstackSibling: return AnyView(SwiftUI.VStack(spacing: 8) { child; SwiftUI.Color.blue.frame(width: 20, height: 30) })
    case .hstackSibling: return AnyView(SwiftUI.HStack(spacing: 8) { child; SwiftUI.Color.blue.frame(width: 20, height: 30) })
    case .vstackFlexibleSibling: return AnyView(SwiftUI.VStack(spacing: 8) { child; SwiftUI.Color.blue })
    case .hstackFlexibleSibling: return AnyView(SwiftUI.HStack(spacing: 8) { child; SwiftUI.Color.blue })
    }
}

@MainActor
private func scrollSizingMeasure(_ view: some SwiftUI.View, _ proposal: CGSize) -> CGSize {
    let requested = ProposedViewSize(
        width: proposal.width.isFinite ? proposal.width : nil,
        height: proposal.height.isFinite ? proposal.height : nil
    )
    return autoreleasepool {
        let host = UIHostingController(rootView: ScrollSizingProposal(requested: requested) { view })
        return host.sizeThatFits(in: CGSize(width: 300, height: 200))
    }
}

private struct ScrollSizingProposal: SwiftUI.Layout {
    let requested: ProposedViewSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(requested)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}
