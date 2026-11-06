import AppLocalization
import QuickLayoutKit
import UIKit

enum ArrangementExample: String, CaseIterable {
    case automatic, horizontal, vertical, ratio, range, size, fixed, overlay, custom

    var style: String {
        switch self {
        case .automatic: ".automatic"
        case .horizontal: ".split.axes(.horizontal)"
        case .vertical: ".split.axes(.vertical)"
        case .ratio, .range, .size, .fixed: ".split"
        case .overlay: ".overlay.axes([.horizontal, .vertical])"
        case .custom: "FloatingStyle()"
        }
    }

    private var primaryModifiers: [String] {
        switch self {
        case .ratio: [".splitArrangementLayoutRatio(0.65)"]
        case .range: ["""
            .splitArrangementLayoutRatio(
                minHorizontal: 0.4, idealHorizontal: 0.6, maxHorizontal: 0.8,
                minVertical: 0.2, idealVertical: 0.35, maxVertical: 0.5)
            """]
        case .size: ["""
            .splitArrangementLayoutSize(
                minWidth: 100, idealWidth: 160, maxWidth: 200,
                minHeight: 60, idealHeight: 100, maxHeight: 140)
            """]
        case .fixed: [".splitArrangementFixedLayoutSize(horizontal: true, vertical: true)"]
        case .overlay: [".overlayArrangementEdge(.trailing)", ".overlayArrangementEdge(.bottom)"]
        default: []
        }
    }

    func code(swiftUI: Bool) -> String {
        let pane = swiftUI ? "primary" : "primary.resizable()"
        let primary = ([pane] + primaryModifiers.map { "    " + $0 }).joined(separator: "\n")
            .replacingOccurrences(of: "\n", with: "\n    ")
        var code = """
        ArrangementView {
            \(primary)
        } secondary: {
            \(swiftUI ? "secondary" : "secondary.resizable()")
        }
        .arrangementViewStyle(\(style))
        """
        if self == .automatic || self == .overlay {
            code += swiftUI ? """


                @Environment(\\.splitArrangementAxis) var axis
                @Environment(\\.overlayArrangementZIndex) var zIndex
                """ : """


                let axis = paneView.splitArrangementAxis
                let zIndex = paneView.overlayArrangementZIndex
                """
        }
        if self == .custom {
            code += """


            struct FloatingStyle: ArrangementViewStyle {
                func makeBody(configuration: Configuration) -> some \(swiftUI ? "View" : "Layout") {
                    ArrangementView(configuration)
                        .arrangementViewStyle(.overlay.axes([]))
                }
            }
            """
        }
        return code
    }
}

private struct FloatingStyle: ArrangementViewStyle {
    func makeBody(configuration: Configuration) -> some Layout {
        ArrangementView(configuration).arrangementViewStyle(.overlay.axes([]))
    }
}

final class ArrangementPreview: QuickLayoutView {
    var example = ArrangementExample.automatic
    let primary = ArrangementExamplePane(primary: true)
    let secondary = ArrangementExamplePane(primary: false)

    override func layoutSubviews() {
        super.layoutSubviews()
        // 分界线切换方向时，单块内容可能保持原尺寸，但仍需刷新它显示的排列环境。
        primary.setNeedsLayout()
        secondary.setNeedsLayout()
    }

    override var body: Layout {
        let panes = ArrangementView { primaryContent } secondary: { secondary.resizable() }
        switch example {
        case .automatic: return panes.arrangementViewStyle(.automatic)
        case .horizontal: return panes.arrangementViewStyle(.split.axes(.horizontal))
        case .vertical: return panes.arrangementViewStyle(.split.axes(.vertical))
        case .overlay: return panes.arrangementViewStyle(.overlay.axes([.horizontal, .vertical]))
        case .custom: return panes.arrangementViewStyle(FloatingStyle())
        default: return panes.arrangementViewStyle(.split)
        }
    }

    private var primaryContent: Layout {
        let pane = primary.resizable()
        switch example {
        case .ratio: return pane.splitArrangementLayoutRatio(0.65)
        case .range: return pane.splitArrangementLayoutRatio(
            minHorizontal: 0.4, idealHorizontal: 0.6, maxHorizontal: 0.8,
            minVertical: 0.2, idealVertical: 0.35, maxVertical: 0.5)
        case .size: return pane.splitArrangementLayoutSize(
            minWidth: 100, idealWidth: 160, maxWidth: 200,
            minHeight: 60, idealHeight: 100, maxHeight: 140)
        case .fixed: return pane.splitArrangementFixedLayoutSize(horizontal: true, vertical: true)
        case .overlay: return pane.overlayArrangementEdge(.trailing).overlayArrangementEdge(.bottom)
        default: return pane
        }
    }
}

/// 两种预览使用相同的内容与理想尺寸，分别从自己的排列容器读取环境。
final class ArrangementExamplePane: UIView {
    private let isPrimary: Bool
    private let readout = UIView()
    private let label = UILabel()
    private enum Surface { case split, foreground, backdrop }
    private var surface: Surface = .split {
        didSet { if surface != oldValue { setNeedsDisplay() } }
    }
    private var accent: UIColor { isPrimary ? .systemIndigo : .systemOrange }
    var nativeContext: (axis: String, zIndex: Int)? { didSet { setNeedsLayout() } }

    init(primary: Bool) {
        isPrimary = primary
        super.init(frame: .zero)
        clipsToBounds = true
        isOpaque = false
        contentMode = .redraw
        readout.layer.cornerRadius = 8
        readout.layer.cornerCurve = .continuous
        readout.backgroundColor = .systemBackground
        readout.isAccessibilityElement = false
        addSubview(readout)
        label.numberOfLines = 0
        label.accessibilityIdentifier = primary ? "arrangement.primary" : "arrangement.secondary"
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 144, height: 78) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let axis = nativeContext?.axis ?? splitArrangementAxis.map { $0 == .horizontal ? "horizontal" : "vertical" } ?? "nil"
        let z = nativeContext?.zIndex ?? overlayArrangementZIndex
        let title = Localization.text(isPrimary ? "arrangement.primary" : "arrangement.secondary")
        let dimensions = "\(Int(bounds.width.rounded())) × \(Int(bounds.height.rounded())) pt"
        let layerInfo = "\(axis) · z = \(z)"
        let classes = traitCollection.arrangementSizeClasses
        label.accessibilityLabel = [title, dimensions, layerInfo, classes].joined(separator: "\n")

        surface = z > 0 ? .foreground : (!isPrimary && axis == "nil" ? .backdrop : .split)
        backgroundColor = surface == .foreground ? .clear : accent.withAlphaComponent(0.14)
        let inset: CGFloat = bounds.height < 100 || bounds.width < 160 ? 4 : 8
        let width = max(0, bounds.width - 2 * inset)
        // 分居折痕两侧时，主层的 axis 仍为 nil，但 z 已回到 0，可用整块区域显示读数。
        let readoutHeight = axis == "nil" && (!isPrimary || z > 0) ? bounds.height / 2 : bounds.height
        let height = max(0, readoutHeight - 2 * inset)
        let padX = min(8, width / 4), padY = min(4, height / 4)
        let limit = CGSize(width: max(0, width - 2 * padX), height: max(0, height - 2 * padY))

        let text = NSMutableAttributedString()
        func append(_ line: String, font: UIFont, color: UIColor) {
            let prefix = text.length == 0 ? "" : "\n"
            text.append(NSAttributedString(string: prefix + line, attributes: [.font: font, .foregroundColor: color]))
        }
        append(title, font: .preferredFont(forTextStyle: .headline), color: .label)
        let digits = UIFont.monospacedDigitSystemFont(ofSize: 19, weight: .semibold)
        append(dimensions, font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: digits), color: .label)
        let essentialLength = text.length
        let caption = UIFont.preferredFont(forTextStyle: .caption1)
        append(layerInfo, font: caption, color: .secondaryLabel)
        let detailLength = text.length
        append(classes, font: caption, color: .secondaryLabel)

        // 先收起尺寸类别，再收起轴和层级。VoiceOver 始终读取完整信息。
        label.attributedText = text
        for length in [detailLength, essentialLength] where label.sizeThatFits(limit).height > limit.height {
            label.attributedText = text.attributedSubstring(from: NSRange(location: 0, length: length))
        }
        let measured = label.sizeThatFits(limit)
        let size = CGSize(width: min(width, ceil(measured.width) + 2 * padX),
                          height: min(height, ceil(measured.height) + 2 * padY))
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let x = isPrimary != rtl ? bounds.minX + inset : bounds.maxX - inset - size.width
        let y = isPrimary ? bounds.minY + inset : bounds.maxY - inset - size.height
        readout.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        label.frame = readout.frame.insetBy(dx: padX, dy: padY)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard bounds.width > 8, bounds.height > 8 else { return }
        let path: UIBezierPath
        switch surface {
        case .foreground:
            // 只缩进示意色块，主视图仍占满实测 bounds。露出的底纹和透过前景的底纹连续。
            var sheet = bounds.insetBy(dx: 4, dy: 4)
            let reveal = min(64, sheet.width * 0.22)
            if effectiveUserInterfaceLayoutDirection == .rightToLeft { sheet.origin.x += reveal }
            sheet.size.width -= reveal
            // 底部为辅助层的读数留白，避免前景边线穿过尺寸文字。
            sheet.size.height -= min(100, sheet.height * 0.5)
            path = UIBezierPath(roundedRect: sheet, cornerRadius: 8)
            accent.withAlphaComponent(0.32).setFill()
            path.fill()
        case .backdrop:
            let stripes = UIBezierPath()
            for x in stride(from: bounds.minX - bounds.height, through: bounds.maxX, by: 20) {
                stripes.move(to: CGPoint(x: x, y: bounds.maxY))
                stripes.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
            }
            stripes.lineWidth = 4
            accent.withAlphaComponent(0.48).setStroke()
            stripes.stroke()
            path = UIBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        case .split:
            path = UIBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        }
        path.lineWidth = 2
        if !isPrimary { path.setLineDash([6, 4], count: 2, phase: 0) }
        accent.setStroke()
        path.stroke()
    }
}


extension UITraitCollection {
    @MainActor var arrangementSizeClasses: String {
        func name(_ sizeClass: UIUserInterfaceSizeClass) -> String {
            switch sizeClass {
            case .compact: "compact"
            case .regular: "regular"
            default: "unspecified"
            }
        }
        return Localization.text("arrangement.sizeClasses", name(horizontalSizeClass), name(verticalSizeClass))
    }
}
