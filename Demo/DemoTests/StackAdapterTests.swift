// 同时导入依赖和聚合模块，验证公开入口不会歧义并实际使用本库适配。
import QuickLayout
import QuickLayoutKit
import Testing
import UIKit

@MainActor
struct StackAdapterTests {
    private let proposal = CGSize(width: 200, height: 160)

    @Test func singleChildConsumesAllBuiltInGuides() {
        for rtl in [false, true] {
            func makeChild() -> any QuickLayout.Layout {
                UIView().resizable().frame(width: 40, height: 20)
                    .alignmentGuide(HorizontalAlignment.leading) { _ in -7 }
                    .alignmentGuide(HorizontalAlignment.center) { _ in 3 }
                    .alignmentGuide(HorizontalAlignment.trailing) { _ in 61 }
                    .alignmentGuide(VerticalAlignment.top) { _ in -9 }
                    .alignmentGuide(VerticalAlignment.center) { _ in 4 }
                    .alignmentGuide(VerticalAlignment.bottom) { _ in 37 }
            }
            for stack in [HStack { makeChild() }, VStack { makeChild() }] {
                LayoutContext.$layoutDirection.withValue(rtl ? .rightToLeft : .leftToRight) {
                    let node = stack.quick_layoutThatFits(proposal)
                    let defaults = ElementDimensions(node.size)
                    for guide: HorizontalAlignment in [.leading, .center, .trailing] {
                        #expect(node.dimensions[guide] == defaults[guide])
                    }
                    for guide: VerticalAlignment in [.top, .center, .bottom] {
                        #expect(node.dimensions[guide] == defaults[guide])
                    }
                }
            }
        }
    }

    @Test func singleChildKeepsSpacingMeasurementAndViewIdentity() {
        for axis: Axis in [.horizontal, .vertical] {
            let counter = StackMeasurementCounter()
            let view = UIView()
            var builds = 0
            func content() -> StackMeasurementProbe {
                builds += 1
                return StackMeasurementProbe(view: view, counter: counter)
            }
            let stack: StackElement = axis == .horizontal
                ? HStack(spacing: 23) { content() }
                : VStack(spacing: 23) { content() }
            #expect(builds == 1)
            #expect(stack.spacing == 23)
            #expect(stack.mainAxis == axis)
            #expect(stack.views().count == 1)
            #expect(stack.views().first === view)
            for _ in 0..<2 {
                counter.proposals.removeAll()
                #expect(stack.quick_layoutThatFits(proposal).size == CGSize(width: 40, height: 20))
                #expect(counter.proposals == [proposal])
            }
            #expect(builds == 1)
            #expect(stack.fixedSize().quick_layoutThatFits(proposal).size == CGSize(width: 40, height: 20))
            #expect(stack.idealLayout().quick_layoutThatFits(proposal).size == CGSize(width: 40, height: 20))
        }
    }

    @Test func customDefaultDoesNotAddAnAlignmentOriginOffset() {
        let horizontal = HorizontalAlignment(StackCustomGuide.self)
        let vertical = VerticalAlignment(StackVerticalCustomGuide.self)
        let view = UIView()
        func makeChild() -> any QuickLayout.Layout {
            view.resizable().frame(width: 40, height: 20)
                .alignmentGuide(horizontal) { _ in 12 }
                .alignmentGuide(vertical) { _ in 9 }
        }
        for stack in [VStack(alignment: horizontal) { makeChild() }, HStack(alignment: vertical) { makeChild() }] {
            let node = stack.layoutThatFits(proposal, layoutDirection: .leftToRight)
            stack._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading,
                              layoutDirection: .leftToRight, cachedLayout: node)
            #expect(node.size == CGSize(width: 40, height: 20))
            #expect(view.frame.origin == .zero)
            #expect(node.dimensions[horizontal] == 12)
            #expect(node.dimensions[vertical] == 9)
        }
    }

    @Test func customGuideSurvivesStackButDoesNotEscapeGrid() {
        let custom = HorizontalAlignment(StackCustomGuide.self)
        for rtl in [false, true] {
            func makeChild() -> any QuickLayout.Layout {
                UIView().resizable().frame(width: 40, height: 20)
                    .alignmentGuide(custom) { _ in 12 }
            }
            let stack = VStack(alignment: .leading) { makeChild() }
                .alignmentGuide(VerticalAlignment.top) { $0[custom] }
            let grid = VGrid(columns: [GridItem(.fixed(100))]) { makeChild() }
                .alignmentGuide(VerticalAlignment.top) { $0[custom] }
            let direction: LayoutDirection = rtl ? .rightToLeft : .leftToRight
            #expect(stack.layoutThatFits(proposal, layoutDirection: direction).dimensions[VerticalAlignment.top] == 12)
            // 网格消费 custom，外层闭包应读取 ID 默认值 42，而不是 RTL 镜像值。
            #expect(grid.layoutThatFits(proposal, layoutDirection: direction).dimensions[VerticalAlignment.top] == 42)
        }
    }

    @Test func customMultiStackKeepsFixedSizeMeasurementAndViewIdentity() {
        let guide = HorizontalAlignment(StackCustomGuide.self)
        let views = [UIView(), UIView()]
        let counter = StackMeasurementCounter()
        let stack: StackElement = VStack(alignment: guide, spacing: 12) {
            FlexibleStackProbe(view: views[0], preferredWidth: 80, counter: counter)
            FlexibleStackProbe(view: views[1], preferredWidth: 140, counter: counter)
        }
        #expect(stack.spacing == 12)
        #expect(stack.mainAxis == .vertical)
        #expect(stack.views().map(ObjectIdentifier.init) == views.map(ObjectIdentifier.init))
        for direction: LayoutDirection in [.leftToRight, .rightToLeft] {
            counter.proposals.removeAll()
            #expect(stack.layoutThatFits(proposal, layoutDirection: direction).size == CGSize(width: 200, height: 52))
            #expect(counter.proposals.count == 2)
            counter.proposals.removeAll()
            #expect(stack.fixedSize(axis: .horizontal).layoutThatFits(proposal, layoutDirection: direction).size
                    == CGSize(width: 140, height: 52))
            #expect(counter.proposals.count == 4)
            #expect(counter.proposals.filter { $0.width.isInfinite }.count == 2)
            #expect(counter.proposals.filter { $0.width == 140 }.count == 2)
        }
        let zero = VStack(alignment: guide) {
            views[0].resizable().frame(width: 80, height: 20)
            views[1].resizable().frame(width: 140, height: 20)
        }
        #expect(zero.spacing == 0)
        #expect(zero.layoutThatFits(proposal, layoutDirection: .rightToLeft).size == CGSize(width: 140, height: 40))
    }

    @Test func emptyAndMultipleChildrenKeepZeroSpacingDefault() {
        #expect(HStack {}.quick_layoutThatFits(proposal).size == .zero)
        #expect(VStack {}.quick_layoutThatFits(proposal).size == .zero)
        let first = UIView().resizable().frame(width: 40, height: 20)
        let second = UIView().resizable().frame(width: 30, height: 10)
        let horizontal: StackElement = HStack { first; second }
        let vertical: StackElement = VStack { first; second }
        #expect(horizontal.spacing == 0)
        #expect(vertical.spacing == 0)
        #expect(horizontal.quick_layoutThatFits(proposal).size == CGSize(width: 70, height: 20))
        #expect(vertical.quick_layoutThatFits(proposal).size == CGSize(width: 40, height: 30))
        #expect(HStack(spacing: 12) { first; second }.quick_layoutThatFits(proposal).size.width == 82)
        #expect(VStack(spacing: 12) { first; second }.quick_layoutThatFits(proposal).size.height == 42)
    }
}

private final class StackMeasurementCounter {
    var proposals: [CGSize] = []
}

private struct StackMeasurementProbe: QuickLayout.Layout {
    let view: UIView
    let counter: StackMeasurementCounter
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        counter.proposals.append(proposedSize)
        return LayoutNode(view: view, dimensions: ElementDimensions(CGSize(width: 40, height: 20)))
    }
    func quick_flexibility(for axis: Axis) -> Flexibility { .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { views.append(view) }
}

private enum StackCustomGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
}

private enum StackVerticalCustomGuide: AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
}

private struct FlexibleStackProbe: QuickLayout.Layout {
    let view: UIView
    let preferredWidth: CGFloat
    let counter: StackMeasurementCounter
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode {
        counter.proposals.append(proposedSize)
        return LayoutNode(view: view, dimensions: ElementDimensions(CGSize(
            width: proposedSize.width.isFinite ? proposedSize.width : preferredWidth, height: 20)))
    }
    func quick_flexibility(for axis: Axis) -> Flexibility { axis == .horizontal ? .fullyFlexible : .fixedSize }
    func quick_layoutPriority() -> CGFloat { 0 }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { views.append(view) }
}
