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
    private let label = UILabel()
    var nativeContext: (axis: String, zIndex: Int)? { didSet { setNeedsLayout() } }

    init(primary: Bool) {
        isPrimary = primary
        super.init(frame: .zero)
        clipsToBounds = true
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = primary ? "arrangement.primary" : "arrangement.secondary"
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 144, height: 78) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let axis = nativeContext?.axis ?? splitArrangementAxis.map { $0 == .horizontal ? "horizontal" : "vertical" } ?? "nil"
        let z = nativeContext?.zIndex ?? overlayArrangementZIndex
        let title = Localization.text(isPrimary ? "arrangement.primary" : "arrangement.secondary")
        let summary = "\(title)\n\(Int(bounds.width.rounded())) × \(Int(bounds.height.rounded())) pt\n\(axis) · z = \(z)"
        let tint: UIColor = isPrimary ? .systemIndigo : .systemTeal
        backgroundColor = tint.withAlphaComponent(z > 0 ? 0.12 : 0.23)
        label.textAlignment = .center
        let inset = bounds.insetBy(dx: 4, dy: 4)
        let classes = traitCollection.arrangementSizeClasses
        label.text = summary + "\n" + classes
        // 固有尺寸示例优先保留尺寸和分割轴，VoiceOver 仍可读取尺寸类别。
        if label.sizeThatFits(inset.size).height > inset.height {
            label.text = summary
            label.accessibilityValue = classes
        } else {
            label.accessibilityValue = nil
        }
        let height = min(max(0, inset.height), label.sizeThatFits(inset.size).height)
        // 浮层保持透明，在两端标出主、辅内容，便于同时观察两个层级。
        let y = isPrimary ? inset.minY : inset.maxY - height
        label.frame = CGRect(x: inset.minX, y: y, width: max(0, inset.width), height: height)
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
