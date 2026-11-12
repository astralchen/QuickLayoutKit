#if DEBUG
import SwiftUI

/// 使用同一分栏、标签栏与页面内边距，单独对照几何画布的嵌套滚动。
struct GeometryScrollReference: View {
    @State private var fraction = 0.8
    @State private var margin = 16.0

    static func makeController() -> UIViewController {
        let host = UIHostingController(rootView: Self())
        host.title = Localization.text("demo.geometry.title")
        return host
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Slider(value: $fraction, in: 0.35...1)
                    .accessibilityIdentifier("geometry.width")
                Slider(value: $margin, in: 0...48)
                    .accessibilityIdentifier("geometry.margin")
                GeometryReader { available in
                    canvas(width: available.size.width * fraction)
                }
                .frame(height: 260)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func canvas(width: CGFloat) -> some View {
        GeometryReader { canvas in
            ScrollView(.horizontal) {
                Rectangle().fill(.teal)
                    .frame(width: max(100, canvas.size.width * fraction * 1.6), height: 200)
                    .accessibilityElement()
                    .accessibilityIdentifier("geometry.sample")
                    .padding(.horizontal, margin)
            }
            .accessibilityIdentifier("geometry.horizontal")
            .frame(height: 200)
            .frame(maxHeight: .infinity)
        }
        .background {
            Rectangle().fill(Color(uiColor: .secondarySystemGroupedBackground))
                .accessibilityElement().accessibilityIdentifier("geometry.canvas")
        }
        .frame(width: width)
    }
}
#endif
