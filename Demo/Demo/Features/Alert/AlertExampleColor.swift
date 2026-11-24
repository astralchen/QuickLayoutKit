import QuickLayoutKit
import UIKit

@MainActor
final class AlertExampleColor {
    private let hue = LocalizedSlider()
    private let saturation = LocalizedSlider()
    private let brightness = LocalizedSlider()
    private let swatch = UILabel()
    private var rows: [(label: UILabel, slider: LocalizedSlider)] = []
    private let report: (String) -> Void

    init(report: @escaping (String) -> Void) {
        self.report = report
        let initial = UIColor(red: 1, green: 45.0 / 255, blue: 198.0 / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        initial.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        swatch.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        swatch.textAlignment = .center
        swatch.accessibilityIdentifier = "alerts.color.hex"
        swatch.layer.cornerRadius = 8
        swatch.clipsToBounds = true
        addSlider(hue, id: "hue", value: h)
        addSlider(saturation, id: "saturation", value: s)
        addSlider(brightness, id: "brightness", value: b)
        updateColor(reportsChange: false)
    }

    func layout(idealWidth: CGFloat?) -> Layout {
        VStack(spacing: 6) {
            swatch.resizable().frame(height: 42)
            for row in rows {
                HStack(spacing: 8) {
                    row.label
                    row.slider.resizable(axis: .horizontal)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(idealWidth: idealWidth ?? 270)
    }

    private func addSlider(_ slider: LocalizedSlider, id: String, value: CGFloat) {
        let label = UILabel()
        let name = Localization.text("demo.alertExamples.color." + id)
        label.text = name
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        slider.value = Float(value)
        slider.accessibilityLabel = name
        slider.accessibilityIdentifier = "alerts.color." + id
        slider.addAction(UIAction { [weak self] _ in self?.updateColor(reportsChange: true) }, for: .valueChanged)
        rows.append((label, slider))
    }

    private func updateColor(reportsChange: Bool) {
        let color = UIColor(hue: CGFloat(hue.value), saturation: CGFloat(saturation.value),
                            brightness: CGFloat(brightness.value), alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        let hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()),
                         Int((b * 255).rounded()))
        swatch.text = hex
        swatch.backgroundColor = color
        swatch.textColor = 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.53 ? .black : .white
        if reportsChange { report(hex) }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("颜色选择器") {
    AlertExamplesViewController.preview(.color)
}
#endif
