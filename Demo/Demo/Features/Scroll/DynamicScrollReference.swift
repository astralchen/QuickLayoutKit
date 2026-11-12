#if DEBUG
import SwiftUI

/// 动态滚动页的几何对照；保留相同的行数、行高和各自的内容与指示器边距。
@available(iOS 17.0, *)
struct DynamicScrollReference: View {
    let buttonHeight: CGFloat

    @MainActor static func makeController() -> UIViewController {
        let page = DynamicScrollViewController()
        page.loadViewIfNeeded()
        let host = UIHostingController(rootView: Self(buttonHeight: page.addButton.intrinsicContentSize.height))
        host.title = page.title
        host.installLanguageMenu()
        return host
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<10) { index in
                    let title = Localization.text("dynamic.item.title", index + 1)
                    Text(verbatim: title)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(Color(uiColor: .systemBackground), ignoresSafeAreaEdges: [])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: title))
                        .accessibilityIdentifier("reference.item.\(index)")
                }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .contentMargins(.top, buttonHeight + 8, for: .scrollContent)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .contentMargins(.top, buttonHeight + 8, for: .scrollIndicators)
        .contentMargins(.bottom, 8, for: .scrollIndicators)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            Text(verbatim: Localization.text("dynamic.addItem"))
                .frame(height: buttonHeight)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("reference.add")
        }
    }
}
#endif
