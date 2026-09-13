import QuickLayout
import QuickLayoutKitCore
import Testing
import UIKit

@MainActor
@Suite(.serialized)
struct StackFixedSizeTests {
    private let proposal = CGSize(width: 300, height: 420)

    @Test func horizontalStackOnlyNeedsFixedSizeToEqualizeFlexibleChildren() {
        let stack = horizontalStack()
        let natural = stack.quick_layoutThatFits(CGSize(width: 300, height: CGFloat.infinity))
        #expect(natural.children.map(\.layout.size.height) == [80, 140])
        let fill = stack.quick_layoutThatFits(proposal)
        #expect(fill.children.map(\.layout.size.height) == [420, 420])
        let equal = stack.fixedSize(axis: .vertical).quick_layoutThatFits(proposal)
        #expect(equal.size == CGSize(width: 216, height: 140))
        #expect(equal.children.map(\.layout.size.height) == [140, 140])
        #expect(equal.children.map(\.position.y) == [0, 0])
    }

    @Test func verticalStackEqualizesWidthsAndPreservesSpacing() {
        let stack = VStack(alignment: .leading, spacing: 16) {
            SizeProbe(size: CGSize(width: 80, height: 100), flexible: .horizontal)
            SizeProbe(size: CGSize(width: 140, height: 100), flexible: .horizontal)
        }
        let layout = stack.fixedSize(axis: .horizontal).quick_layoutThatFits(proposal)
        #expect(layout.size == CGSize(width: 140, height: 216))
        #expect(layout.children.map(\.layout.size.width) == [140, 140])
        #expect(layout.children.map(\.position.y) == [0, 116])
    }

    @Test func axesAndExistingIdealLayoutKeepTheirContracts() {
        let stack = horizontalStack()
        for element in [stack.fixedSize(), stack.fixedSize(axis: [.horizontal, .vertical]),
                        stack.idealLayout().fixedSize(axis: .vertical)] {
            let layout = element.quick_layoutThatFits(proposal)
            #expect(layout.children.map(\.layout.size.height) == [140, 140])
        }
        let axisSets: [AxisSet] = [[], .horizontal]
        for axes in axisSets {
            let layout = stack.fixedSize(axis: axes).quick_layoutThatFits(proposal)
            #expect(layout.children.map(\.layout.size.height) == [420, 420])
        }
        let explicitIdeal = stack.idealLayout().fixedSize(axis: [])
            .quick_layoutThatFits(proposal)
        #expect(explicitIdeal.children.map(\.layout.size.height) == [140, 140])
        #expect(stack.fixedSize(axis: .vertical).quick_flexibility(for: .vertical) == .fixedSize)
    }

    @Test func fixedChildKeepsItsSizeAndBottomAlignment() {
        let stack = HStack(alignment: .bottom, spacing: 16) {
            SizeProbe(size: CGSize(width: 100, height: 80), flexible: [])
            SizeProbe(size: CGSize(width: 100, height: 140), flexible: .vertical)
        }
        let result = stack.fixedSize(axis: .vertical).quick_layoutThatFits(proposal)
        #expect(result.children.map(\.layout.size.height) == [80, 140])
        #expect(result.children.map(\.position.y) == [60, 0])
    }

    @Test func wrappingAndTypeErasureUseTheUpstreamOverload() {
        let stack = horizontalStack()
        let erased: any Element = stack
        let erasedLayout: any Layout = stack
        for element in [erased.fixedSize(axis: .vertical),
                        erasedLayout.fixedSize(axis: .vertical),
                        stack.padding(0).fixedSize(axis: .vertical)] {
            let result = element.quick_layoutThatFits(proposal)
            #expect(leafHeights(result) == [80, 140])
        }
        let paddingAfter = stack.fixedSize(axis: .vertical).padding(20)
            .quick_layoutThatFits(proposal)
        #expect(paddingAfter.size == CGSize(width: 256, height: 180))
        #expect(leafHeights(paddingAfter) == [140, 140])
    }

    @Test func remeasurementIsBoundedAndRepeatedLayoutsAreStable() {
        let counter = ProposalCounter()
        let stack = HStack(alignment: .top, spacing: 16) {
            SizeProbe(size: CGSize(width: 100, height: 80), flexible: .vertical, counter: counter)
            SizeProbe(size: CGSize(width: 100, height: 140), flexible: .vertical, counter: counter)
        }
        let element = stack.fixedSize(axis: .vertical)
        let first = element.quick_layoutThatFits(proposal)
        // Fixed main-axis sizes require one measurement per child in each of two passes.
        #expect(counter.proposals.count == 4)
        #expect(counter.proposals.filter { $0.height.isInfinite }.count == 2)
        #expect(counter.proposals.filter { $0.height == 140 }.count == 2)
        counter.proposals.removeAll()
        let second = element.quick_layoutThatFits(proposal)
        #expect(second.size == first.size)
        #expect(counter.proposals.count == 4)
        counter.proposals.removeAll()
        _ = stack.idealLayout().fixedSize(axis: .vertical).quick_layoutThatFits(proposal)
        #expect(counter.proposals.count == 4)
    }

    @Test func emptyStackSpacerAndRTLRemainWellDefined() {
        let empty = HStack {}.fixedSize().quick_layoutThatFits(proposal)
        #expect(empty.size == .zero)
        let stack = HStack(alignment: .top, spacing: 0) {
            SizeProbe(size: CGSize(width: 50, height: 80), flexible: .vertical)
            Spacer()
            SizeProbe(size: CGSize(width: 50, height: 140), flexible: .vertical)
        }
        let result = stack.fixedSize(axis: .vertical).quick_layoutThatFits(proposal)
        #expect(result.size == CGSize(width: 300, height: 140))
        #expect(result.children.first?.layout.size == CGSize(width: 50, height: 140))
        #expect(result.children.last?.position.x == 250)
        let rtl = stack.fixedSize(axis: .vertical).layoutDirection(.rightToLeft)
            .quick_layoutThatFits(proposal)
        #expect(rtl.size == result.size)
        #expect(rtl.children.first?.position.x == 250)
        #expect(rtl.children.last?.position.x == 0)
    }

    @Test func nestedStackAndMultilineTextKeepTheirNaturalContent() {
        let short = UILabel()
        let long = UILabel()
        [short, long].forEach {
            $0.numberOfLines = 0
            $0.font = .systemFont(ofSize: 17)
        }
        short.text = "Short"
        long.text = String(repeating: "Text wraps at its fixed width. ", count: 8)
        let natural = long.sizeThatFits(CGSize(width: 120, height: CGFloat.infinity)).height
        let row = HStack(alignment: .top, spacing: 16) {
            short.frame(width: 120).frame(maxHeight: .infinity, alignment: .topLeading)
            long.frame(width: 120).frame(maxHeight: .infinity, alignment: .topLeading)
        }.fixedSize(axis: .vertical)
        let layout = VStack(spacing: 10) {
            row
            SizeProbe(size: CGSize(width: 20, height: 10), flexible: [])
        }.quick_layoutThatFits(proposal)
        #expect(abs(layout.children[0].layout.size.height - natural) < 1)
        #expect(layout.children[0].layout.children.allSatisfy { abs($0.layout.size.height - natural) < 1 })
    }

    @Test func crossAxisFixPreservesMainAxisPriorityAllocation() {
        let stack = HStack(alignment: .top, spacing: 16) {
            SizeProbe(size: CGSize(width: 100, height: 80), flexible: [.horizontal, .vertical])
                .layoutPriority(1)
            SizeProbe(size: CGSize(width: 100, height: 140), flexible: [.horizontal, .vertical])
        }
        let natural = stack.quick_layoutThatFits(CGSize(width: 300, height: CGFloat.infinity))
        let equal = stack.fixedSize(axis: .vertical).quick_layoutThatFits(proposal)
        #expect(equal.size.width == natural.size.width)
        #expect(equal.children.map(\.layout.size.width) == natural.children.map(\.layout.size.width))
        #expect(equal.children.map(\.position.x) == natural.children.map(\.position.x))
        #expect(equal.children.map(\.layout.size.height) == [140, 140])
    }

    private func horizontalStack() -> StackElement {
        HStack(alignment: .top, spacing: 16) {
            SizeProbe(size: CGSize(width: 100, height: 80), flexible: .vertical)
            SizeProbe(size: CGSize(width: 100, height: 140), flexible: .vertical)
        }
    }

    private func leafHeights(_ layout: LayoutNode) -> [CGFloat] {
        if layout.children.isEmpty { return [layout.size.height] }
        return layout.children.flatMap { leafHeights($0.layout) }
    }
}

private final class ProposalCounter {
    var proposals: [CGSize] = []
}

private struct SizeProbe: Layout {
    let size: CGSize
    let flexible: AxisSet
    var counter: ProposalCounter? = nil

    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        counter?.proposals.append(proposedSize)
        return LayoutNode(view: nil, dimensions: ElementDimensions(CGSize(
            width: flexible.contains(.horizontal) && proposedSize.width.isFinite ? proposedSize.width : size.width,
            height: flexible.contains(.vertical) && proposedSize.height.isFinite ? proposedSize.height : size.height
        )))
    }

    func quick_flexibility(for axis: Axis) -> Flexibility {
        let expands = axis == .horizontal ? flexible.contains(.horizontal) : flexible.contains(.vertical)
        return expands ? .fullyFlexible : .fixedSize
    }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) {}
}
