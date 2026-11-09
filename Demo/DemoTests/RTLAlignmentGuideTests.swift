import QuickLayout
import QuickLayoutKitCore
import SwiftUI
import Testing
import UIKit

private typealias QLHorizontal = QuickLayout.HorizontalAlignment
private typealias QLVertical = QuickLayout.VerticalAlignment

@MainActor
@Suite(.serialized)
struct RTLAlignmentGuideTests {
    @Test func parentStackFramesMatchSwiftUI() async {
        for rtl in [false, true] {
            for alignmentIndex in 0..<4 {
                for offset: CGFloat in [-17, 0, 17] {
                    for mode in 0..<5 {
                        await compare(rtl: rtl, alignmentIndex: alignmentIndex, offset: offset, mode: mode)
                    }
                }
            }
        }
    }

    @Test func singleChildStackGuidesMatchSwiftUI() async {
        for rtl in [false, true] {
            for alignmentIndex in 0..<4 {
                for offset: CGFloat in [-80, -17, 0, 17, 80] {
                    await compare(rtl: rtl, alignmentIndex: alignmentIndex, offset: offset, mode: 5)
                    await compareHorizontal(rtl: rtl, alignmentIndex: alignmentIndex, offset: offset)
                }
            }
        }
    }

    @Test func customDefaultParentStackMatchesSwiftUI() async {
        for rtl in [false, true] {
            for offset: CGFloat in [-80, -17, 0, 17, 80] {
                for mode in 0...5 {
                    await compare(rtl: rtl, alignmentIndex: 4, offset: offset, mode: mode)
                }
            }
        }
    }

    @Test func chainedAndCrossAxisQueriesReadLogicalValues() {
        let layout = UIView().resizable().frame(width: 40, height: 20)
            .alignmentGuide(QLHorizontal.center) { $0[QLHorizontal.center] + 12 }
            .alignmentGuide(QLVertical.center) { $0[QLHorizontal.center] + 3 }
            .alignmentGuide(QLHorizontal.center) { $0[QLHorizontal.center] + 3 }
        for rtl in [false, true] {
            let node = layout.layoutThatFits(CGSize(width: 100, height: 100),
                                            layoutDirection: rtl ? .rightToLeft : .leftToRight)
            LayoutContext.$layoutDirection.withValue(rtl ? .rightToLeft : .leftToRight) {
                #expect(node.dimensions[QLHorizontal.center] == (rtl ? 5 : 35))
                #expect(node.dimensions[QLVertical.center] == 35)
            }
        }
    }

    @Test func guideClosureKeepsActualLayoutDirection() {
        let layout = UIView().resizable().frame(width: 40, height: 20)
            .alignmentGuide(QLHorizontal.leading) {
                $0[QLHorizontal.leading] + (LayoutContext.layoutDirection == .rightToLeft ? 10 : 20)
            }
        for rtl in [false, true] {
            let node = layout.layoutThatFits(CGSize(width: 100, height: 100),
                                            layoutDirection: rtl ? .rightToLeft : .leftToRight)
            LayoutContext.$layoutDirection.withValue(rtl ? .rightToLeft : .leftToRight) {
                #expect(node.dimensions[QLHorizontal.leading] == (rtl ? 30 : 20))
                #expect(LayoutContext.layoutDirection == (rtl ? .rightToLeft : .leftToRight))
            }
        }
    }

    private func compareHorizontal(rtl: Bool, alignmentIndex: Int, offset: CGFloat) async {
        let nativeAlignment: SwiftUI.VerticalAlignment = [.top, .center, .bottom, .init(VerticalCustomGuide.self)][alignmentIndex]
        let actualAlignment: QLVertical = [.top, .center, .bottom, .init(VerticalCustomGuide.self)][alignmentIndex]
        let references = [UIView(), UIView()]
        let views = [UIView(), UIView()]
        let bounds = UIView()
        var native = AnyView(SwiftUI.Color.blue.frame(width: 40, height: 20)
            .background(RTLGuideProbe(view: references[0]))
            .alignmentGuide(nativeAlignment) { $0[nativeAlignment] + offset })
        native = AnyView(SwiftUI.HStack(alignment: nativeAlignment, spacing: 23) { native })
        native = AnyView(native
            .alignmentGuide(SwiftUI.HorizontalAlignment.center) { $0[nativeAlignment] / 2 }
            .alignmentGuide(nativeAlignment) { $0[nativeAlignment] + 3 })
        let actual = QuickLayoutKitCore.HStack(alignment: actualAlignment, spacing: 23) {
            views[0].resizable().frame(width: 40, height: 20)
                .alignmentGuide(actualAlignment) { $0[actualAlignment] + offset }
        }
        .alignmentGuide(QLHorizontal.center) { $0[actualAlignment] / 2 }
        .alignmentGuide(actualAlignment) { $0[actualAlignment] + 3 }
        let root = SwiftUI.HStack(alignment: nativeAlignment, spacing: 0) {
            native
            SwiftUI.Color.red.frame(width: 70, height: 30).background(RTLGuideProbe(view: references[1]))
        }
        let host = UIHostingController(rootView: root.background(RTLGuideProbe(view: bounds))
            .frame(width: 200, height: 200, alignment: .topLeading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<3 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        let stack = QuickLayoutKitCore.HStack(alignment: actualAlignment) {
            actual
            views[1].resizable().frame(width: 70, height: 30)
        }
        let direction: QuickLayout.LayoutDirection = rtl ? .rightToLeft : .leftToRight
        let node = stack.layoutThatFits(CGSize(width: 200, height: 200), layoutDirection: direction)
        stack._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading,
                          layoutDirection: direction, cachedLayout: node)
        let context = "HStack RTL=\(rtl), alignment=\(alignmentIndex), offset=\(offset)"
        #expect(abs(node.size.width - bounds.bounds.width) < 0.6 && abs(node.size.height - bounds.bounds.height) < 0.6,
                "\(context): size \(node.size) vs \(bounds.bounds.size)")
        for index in views.indices {
            #expect(references[index].superview != nil)
            let expected = references[index].convert(references[index].bounds, to: bounds)
            #expect(abs(views[index].frame.minX - expected.minX) < 0.6
                    && abs(views[index].frame.minY - expected.minY) < 0.6,
                    "\(context), item=\(index): \(views[index].frame) vs \(expected)")
        }
    }

    private func compare(rtl: Bool, alignmentIndex: Int, offset: CGFloat, mode: Int) async {
        let nativeAlignment: SwiftUI.HorizontalAlignment = [.leading, .center, .trailing, .init(RTLCustomGuide.self), .init(ConstantCustomGuide.self)][alignmentIndex]
        let actualAlignment: QLHorizontal = [.leading, .center, .trailing, .init(RTLCustomGuide.self), .init(ConstantCustomGuide.self)][alignmentIndex]
        let references = [UIView(), UIView()]
        let views = [UIView(), UIView()]
        let bounds = UIView()
        var native = AnyView(SwiftUI.Color.blue.frame(width: 40, height: 20)
            .background(RTLGuideProbe(view: references[0])))
        var actual: any QuickLayout.Layout = views[0].resizable().frame(width: 40, height: 20)
        if mode == 3 {
            // 参考线应用到整个嵌套栈，验证父栈接收到的值及后续修饰器求值。
            native = AnyView(SwiftUI.VStack(alignment: nativeAlignment, spacing: 0) { native })
            actual = QuickLayoutKitCore.VStack(alignment: actualAlignment) { actual }
        }
        native = AnyView(native.alignmentGuide(nativeAlignment) { mode == 4 ? offset : $0[nativeAlignment] + offset })
        actual = actual.alignmentGuide(actualAlignment) { mode == 4 ? offset : $0[actualAlignment] + offset }
        if mode == 5 {
            // 与 mode 3 区分：这里把参考线应用到栈内部的单个元素。
            native = AnyView(SwiftUI.VStack(alignment: nativeAlignment, spacing: 0) { native })
            actual = QuickLayoutKitCore.VStack(alignment: actualAlignment) { actual }
        }
        if mode == 2 {
            native = AnyView(native.frame(width: 80, height: 40, alignment: .bottomTrailing).padding(.leading, 7))
            actual = actual.frame(width: 80, height: 40, alignment: .bottomTrailing).padding(.leading, 7)
        }
        if mode > 0 && mode != 4 {
            native = AnyView(native
                .alignmentGuide(SwiftUI.VerticalAlignment.center) { $0[nativeAlignment] / 2 }
                .alignmentGuide(nativeAlignment) { $0[nativeAlignment] + 3 })
            actual = actual
                .alignmentGuide(QLVertical.center) { $0[actualAlignment] / 2 }
                .alignmentGuide(actualAlignment) { $0[actualAlignment] + 3 }
        }
        let root = SwiftUI.VStack(alignment: nativeAlignment, spacing: 0) {
            native
            SwiftUI.Color.red.frame(width: 70, height: 30).background(RTLGuideProbe(view: references[1]))
        }
        let host = UIHostingController(rootView: root.background(RTLGuideProbe(view: bounds))
            .frame(width: 200, height: 200, alignment: .topLeading)
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<3 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
        let stack = QuickLayoutKitCore.VStack(alignment: actualAlignment) {
            actual
            views[1].resizable().frame(width: 70, height: 30)
        }
        let direction: QuickLayout.LayoutDirection = rtl ? .rightToLeft : .leftToRight
        let node = stack.layoutThatFits(CGSize(width: 200, height: 200), layoutDirection: direction)
        stack._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading,
                          layoutDirection: direction, cachedLayout: node)
        let context = "RTL=\(rtl), alignment=\(alignmentIndex), offset=\(offset), mode=\(mode)"
        #expect(abs(node.size.width - bounds.bounds.width) < 0.6 && abs(node.size.height - bounds.bounds.height) < 0.6,
                "\(context): size \(node.size) vs \(bounds.bounds.size)")
        for index in views.indices {
            #expect(references[index].superview != nil)
            let expected = references[index].convert(references[index].bounds, to: bounds)
            #expect(abs(views[index].frame.minX - expected.minX) < 0.6
                    && abs(views[index].frame.minY - expected.minY) < 0.6,
                    "\(context), item=\(index): \(views[index].frame) vs \(expected)")
        }
    }
}

private enum RTLCustomGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context.width / 2 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { context.width / 2 }
}

private struct RTLGuideProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private enum VerticalCustomGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { context.height / 2 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { context.height / 2 }
}

private enum ConstantCustomGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { 42 }
}
