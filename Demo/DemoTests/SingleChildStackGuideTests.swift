import QuickLayout
import QuickLayoutKitCore
import SwiftUI
import Testing
import UIKit

private typealias NativeStackHorizontal = QuickLayout.HorizontalAlignment
private typealias NativeStackVertical = QuickLayout.VerticalAlignment

@MainActor
@Suite(.serialized)
struct SingleChildStackGuideTests {
    @Test func customNonCenterDefaultMatchesNativeSingleStack() async {
        for horizontal in [false, true] {
            for rtl in [false, true] {
                for explicit: CGFloat? in [nil, 12, -17, 80] {
                    await compare(horizontal: horizontal, rtl: rtl, explicit: explicit)
                }
            }
        }
    }

    private func compare(horizontal: Bool, rtl: Bool, explicit: CGFloat?) async {
        let reference = UIView()
        let bounds = UIView()
        let view = UIView()
        var native = AnyView(Color.blue.frame(width: 40, height: 20).background(NativeStackProbe(view: reference)))
        var actual: any QuickLayout.Layout = view.resizable().frame(width: 40, height: 20)
        if horizontal {
            let nativeGuide = SwiftUI.VerticalAlignment(NativeStackGuide.self)
            let actualGuide = NativeStackVertical(NativeStackGuide.self)
            if let explicit {
                native = AnyView(native.alignmentGuide(nativeGuide) { _ in explicit })
                actual = actual.alignmentGuide(actualGuide) { _ in explicit }
            }
            native = AnyView(SwiftUI.HStack(alignment: nativeGuide, spacing: 0) { native })
            actual = QuickLayoutKitCore.HStack(alignment: actualGuide) { actual }
        } else {
            let nativeGuide = SwiftUI.HorizontalAlignment(NativeStackGuide.self)
            let actualGuide = NativeStackHorizontal(NativeStackGuide.self)
            if let explicit {
                native = AnyView(native.alignmentGuide(nativeGuide) { _ in explicit })
                actual = actual.alignmentGuide(actualGuide) { _ in explicit }
            }
            native = AnyView(SwiftUI.VStack(alignment: nativeGuide, spacing: 0) { native })
            actual = QuickLayoutKitCore.VStack(alignment: actualGuide) { actual }
        }
        let host = UIHostingController(rootView: native.background(NativeStackProbe(view: bounds))
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
        let direction: QuickLayout.LayoutDirection = rtl ? .rightToLeft : .leftToRight
        let node = actual.layoutThatFits(CGSize(width: 200, height: 200), layoutDirection: direction)
        actual._applyFrame(CGRect(origin: .zero, size: node.size), alignment: .topLeading, layoutDirection: direction, cachedLayout: node)
        let frame = reference.convert(reference.bounds, to: bounds)
        let context = "horizontal=\(horizontal), RTL=\(rtl), explicit=\(String(describing: explicit))"
        #expect(reference.superview != nil && bounds.superview != nil)
        #expect(abs(node.size.width - bounds.bounds.width) < 0.6 && abs(node.size.height - bounds.bounds.height) < 0.6,
                "\(context): size \(node.size) vs \(bounds.bounds.size)")
        #expect(abs(view.frame.minX - frame.minX) < 0.6 && abs(view.frame.minY - frame.minY) < 0.6,
                "\(context): frame \(view.frame) vs \(frame)")
    }
}

private enum NativeStackGuide: QuickLayout.AlignmentID, SwiftUI.AlignmentID {
    static func defaultValue(in context: ElementDimensions) -> CGFloat { 42 }
    static func defaultValue(in context: SwiftUI.ViewDimensions) -> CGFloat { 42 }
}
private struct NativeStackProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
