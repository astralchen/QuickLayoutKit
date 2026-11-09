import QuickLayout
import QuickLayoutKitCore
import SwiftUI
import Testing
import UIKit

private typealias FitHorizontal = QuickLayout.HorizontalAlignment
private typealias FitVertical = QuickLayout.VerticalAlignment

@MainActor
@Suite(.serialized)
struct ViewThatFitsGuideTests {
    @Test func selectedGuidesMatchSwiftUIInParentStack() async {
        if #available(iOS 16.0, *) {
            for rtl in [false, true] {
                for width: CGFloat in [100, 300] {
                    for fallbackGuide: CGFloat? in [nil, 7] {
                        await compare(rtl: rtl, width: width, fallbackGuide: fallbackGuide)
                    }
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private func compare(rtl: Bool, width: CGFloat, fallbackGuide: CGFloat?) async {
        let nativeGuide = SwiftUI.HorizontalAlignment(FitGuide.self)
        let actualGuide = FitHorizontal(FitGuide.self)
        let references = [UIView(), UIView(), UIView()]
        let views = [UIView(), UIView(), UIView()]
        let bounds = UIView()
        var nativeFallback = AnyView(Color.blue.frame(width: 40, height: 20)
            .background(FitProbe(view: references[1])))
        if let fallbackGuide {
            nativeFallback = AnyView(nativeFallback.alignmentGuide(nativeGuide) { _ in fallbackGuide })
        }
        let native = SwiftUI.ViewThatFits(in: .horizontal) {
            Color.blue.frame(width: 200, height: 20)
                .background(FitProbe(view: references[0]))
                .alignmentGuide(nativeGuide) { _ in 12 }
            nativeFallback
        }.alignmentGuide(SwiftUI.VerticalAlignment.top) { $0[nativeGuide] }
        let actual = QuickLayoutKitCore.ViewThatFits(in: .horizontal) {
            views[0].resizable().frame(width: 200, height: 20)
                .alignmentGuide(actualGuide) { _ in 12 }
            if let fallbackGuide {
                views[1].resizable().frame(width: 40, height: 20)
                    .alignmentGuide(actualGuide) { _ in fallbackGuide }
            } else {
                views[1].resizable().frame(width: 40, height: 20)
            }
        }.alignmentGuide(FitVertical.top) { $0[actualGuide] }
        let root = SwiftUI.HStack(alignment: .top, spacing: 0) {
            native
            Color.red.frame(width: 20, height: 20).background(FitProbe(view: references[2]))
        }
        let host = UIHostingController(rootView: root.background(FitProbe(view: bounds))
            .frame(width: width, height: 200, alignment: .topLeading)
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
        let stack = QuickLayoutKitCore.HStack(alignment: .top) {
            actual
            views[2].resizable().frame(width: 20, height: 20)
        }
        let direction: QuickLayout.LayoutDirection = rtl ? .rightToLeft : .leftToRight
        let node = stack.layoutThatFits(CGSize(width: width, height: 200), layoutDirection: direction)
        stack._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading,
                          layoutDirection: direction, cachedLayout: node)
        let context = "RTL=\(rtl), width=\(width), fallback=\(String(describing: fallbackGuide))"
        #expect(abs(node.size.width - bounds.bounds.width) < 0.6 && abs(node.size.height - bounds.bounds.height) < 0.6,
                "\(context): size \(node.size) vs \(bounds.bounds.size)")
        for index in [width == 100 ? 1 : 0, 2] {
            #expect(references[index].superview != nil)
            let expected = references[index].convert(references[index].bounds, to: bounds)
            #expect(abs(views[index].frame.minX - expected.minX) < 0.6 && abs(views[index].frame.minY - expected.minY) < 0.6,
                    "\(context), item=\(index): \(views[index].frame) vs \(expected)")
        }
    }
}

private enum FitGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { 42 }
}
private struct FitProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
