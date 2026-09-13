import QuickLayout
import QuickLayoutKit
import SwiftUI
import Testing
import UIKit
@testable import Demo

extension DemoTests {
    @Test func fixedSizeStackMatchesSwiftUIFrames() async throws {
        let shortBounds = UIView()
        let tallBounds = UIView()
        let rowBounds = UIView()
        let reference = SwiftUI.HStack(alignment: .top, spacing: 16) {
            SwiftUI.Color.blue.frame(width: 100, height: 80)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(FixedSizeBoundsProbe(view: shortBounds))
            SwiftUI.Color.orange.frame(width: 100, height: 140)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(FixedSizeBoundsProbe(view: tallBounds))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(FixedSizeBoundsProbe(view: rowBounds))
        .frame(width: 300, height: 420, alignment: .topLeading)
        let host = UIHostingController(rootView: reference)
        let window = try makeVisibleTestWindow(rootViewController: host, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        #expect(await waitForCondition {
            host.view.layoutIfNeeded()
            return rowBounds.bounds.height > 0 && shortBounds.bounds.height > 0
        })

        let row = makeFixedSizeQuickLayoutReference()
        let actual = row.quick_layoutThatFits(CGSize(width: 300, height: 420))
        #expect(abs(rowBounds.bounds.height - 140) < 1)
        #expect(abs(actual.size.height - rowBounds.bounds.height) < 1)
        #expect(abs(actual.children[0].layout.size.height - shortBounds.bounds.height) < 1)
        #expect(abs(actual.children[1].layout.size.height - tallBounds.bounds.height) < 1)
        #expect(abs(actual.size.width - rowBounds.bounds.width) < 1)
    }
}

private struct FixedSizeBoundsProbe: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
