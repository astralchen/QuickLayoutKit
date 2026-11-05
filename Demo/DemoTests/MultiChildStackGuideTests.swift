import QuickLayout
import QuickLayoutKitCore
import SwiftUI
import Testing
import UIKit

private typealias MultiHorizontal = QuickLayout.HorizontalAlignment
private typealias MultiVertical = QuickLayout.VerticalAlignment

@MainActor
@Suite(.serialized)
struct MultiChildStackGuideTests {
    @Test func customDefaultsAndExplicitValuesMatchSwiftUI() async {
        for rtl in [false, true] {
            for guideIndex in 0..<4 {
                for explicitMode in 0..<3 {
                    for spacing: CGFloat in [0, 11] {
                        await compare(rtl: rtl, guideIndex: guideIndex, explicitMode: explicitMode,
                                      spacing: spacing, nested: false)
                    }
                }
            }
        }
    }

    @Test func cachedNestedStacksPreserveExplicitGuideAggregation() async {
        for rtl in [false, true] {
            for guideIndex in 0..<4 {
                for explicitMode in 0..<3 {
                    await compare(rtl: rtl, guideIndex: guideIndex, explicitMode: explicitMode,
                                  spacing: 7, nested: true)
                }
            }
        }
    }

    private func actualCell(view: UIView, index: Int, guide: MultiHorizontal,
                            explicitMode: Int) -> any QuickLayout.Layout {
        let child = view.resizable().frame(width: index == 0 ? 40 : 70, height: index == 0 ? 20 : 30)
        if explicitMode == 2 || (explicitMode == 1 && index == 0) {
            let offset: CGFloat = index == 0 ? -17 : 23
            return child.alignmentGuide(guide) { $0[guide] + offset }
        }
        return child
    }

    private func compare(rtl: Bool, guideIndex: Int, explicitMode: Int, spacing: CGFloat, nested: Bool) async {
        let nativeGuide: SwiftUI.HorizontalAlignment = [
            .init(MultiConstantGuide.self), .init(MultiNegativeGuide.self),
            .init(MultiOutsideGuide.self), .init(MultiDerivedGuide.self)
        ][guideIndex]
        let actualGuide: MultiHorizontal = [
            .init(MultiConstantGuide.self), .init(MultiNegativeGuide.self),
            .init(MultiOutsideGuide.self), .init(MultiDerivedGuide.self)
        ][guideIndex]
        let references = [UIView(), UIView(), UIView()]
        let views = [UIView(), UIView(), UIView()]
        let bounds = UIView()
        var natives: [AnyView] = []
        for index in 0..<2 {
            let width: CGFloat = index == 0 ? 40 : 70
            let height: CGFloat = index == 0 ? 20 : 30
            var native = AnyView(Color.blue.frame(width: width, height: height)
                .background(MultiStackProbe(view: references[index])))
            if explicitMode == 2 || (explicitMode == 1 && index == 0) {
                let offset: CGFloat = index == 0 ? -17 : 23
                native = AnyView(native.alignmentGuide(nativeGuide) { $0[nativeGuide] + offset })
            }
            natives.append(native)
        }
        var native = AnyView(SwiftUI.VStack(alignment: nativeGuide, spacing: spacing) {
            natives[0]
            natives[1]
        })
        var actual: any QuickLayout.Layout = QuickLayoutKitCore.VStack(alignment: actualGuide, spacing: spacing) {
            for index in 0..<2 {
                actualCell(view: views[index], index: index, guide: actualGuide, explicitMode: explicitMode)
            }
        }
        let direction: QuickLayout.LayoutDirection = rtl ? .rightToLeft : .leftToRight
        let proposal = CGSize(width: 400, height: 400)
        if nested {
            // 先缓存内层栈，再从外层读取自定义参考线；默认值不能混入显式值的平均数。
            actual = MultiStackCachedNode(child: actual,
                                          node: actual.layoutThatFits(proposal, layoutDirection: direction))
                .alignmentGuide(MultiVertical.top) { $0[actualGuide] }
            let first = actual
            actual = QuickLayoutKitCore.HStack(alignment: .top) {
                first
                views[2].resizable().frame(width: 13, height: 10)
            }
            let firstNative = AnyView(native.alignmentGuide(SwiftUI.VerticalAlignment.top) { $0[nativeGuide] })
            native = AnyView(SwiftUI.HStack(alignment: .top, spacing: 0) {
                firstNative
                Color.red.frame(width: 13, height: 10).background(MultiStackProbe(view: references[2]))
            })
        }
        let host = UIHostingController(rootView: native.background(MultiStackProbe(view: bounds))
            .frame(width: 400, height: 400, alignment: .topLeading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 700))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<3 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        let node = actual.layoutThatFits(proposal, layoutDirection: direction)
        actual._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading,
                           layoutDirection: direction, cachedLayout: node)
        let context = "RTL=\(rtl), guide=\(guideIndex), explicit=\(explicitMode), spacing=\(spacing), nested=\(nested)"
        #expect(abs(node.size.width - bounds.bounds.width) < 0.6 && abs(node.size.height - bounds.bounds.height) < 0.6,
                "\(context): size \(node.size) vs \(bounds.bounds.size)")
        for index in 0..<(nested ? 3 : 2) {
            #expect(references[index].superview != nil)
            let expected = references[index].convert(references[index].bounds, to: bounds)
            #expect(abs(views[index].frame.minX - expected.minX) < 0.6 && abs(views[index].frame.minY - expected.minY) < 0.6,
                    "\(context), item=\(index): \(views[index].frame) vs \(expected)")
        }
    }
}

private enum MultiConstantGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { 42 }
}
private enum MultiNegativeGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { -17 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { -17 }
}
private enum MultiOutsideGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 120 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { 120 }
}
private enum MultiDerivedGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context[MultiHorizontal.leading] + 5 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { context[SwiftUI.HorizontalAlignment.leading] + 5 }
}
private struct MultiStackProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
private struct MultiStackCachedNode: QuickLayout.Layout {
    let child: Element
    let node: LayoutNode
    func quick_layoutThatFits(_ proposedSize: CGSize) -> LayoutNode { node }
    func quick_flexibility(for axis: QuickLayout.Axis) -> Flexibility { child.quick_flexibility(for: axis) }
    func quick_layoutPriority() -> CGFloat { child.quick_layoutPriority() }
    func quick_extractViewsIntoArray(_ views: inout [UIView]) { child.quick_extractViewsIntoArray(&views) }
}
