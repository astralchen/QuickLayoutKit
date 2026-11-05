import AppLocalization
import QuickLayoutKit
import UIKit

/// 交互检查网格尺寸规则、填充方向、容器变化与 RTL 的示例页面。
final class DirectionalGridViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.directionalGrid.title" }

    private let scrollView = QuickLayoutScrollView()
    private let introduction = UILabel()
    private let axisControl = UISegmentedControl(items: ["VGrid", "HGrid"])
    private let sizingControl = UISegmentedControl(items: ["fixed", "flexible", "adaptive", "mixed"])
    private let alignmentControl = UISegmentedControl(items: ["leading", "center", "trailing"])
    private let widthLabel = UILabel()
    private let widthHint = UILabel()
    private let widthSlider = UISlider()
    private let directionControl = UISegmentedControl(items: ["LTR", "RTL"])
    private let codeLabel = UILabel()
    let preview = DirectionalGridPreviewView()

    override func viewDidLoad() {
        // 基类会立即刷新本地化文案，先准备文案依赖的选中状态。
        axisControl.selectedSegmentIndex = 0
        sizingControl.selectedSegmentIndex = 2
        alignmentControl.selectedSegmentIndex = 1
        directionControl.selectedSegmentIndex = 0
        widthSlider.minimumValue = 0.45
        widthSlider.maximumValue = 1
        widthSlider.value = 1
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        introduction.numberOfLines = 0
        introduction.font = .preferredFont(forTextStyle: .body)
        introduction.adjustsFontForContentSizeCategory = true
        widthLabel.font = .preferredFont(forTextStyle: .subheadline)
        widthLabel.numberOfLines = 0
        widthHint.font = .preferredFont(forTextStyle: .caption1)
        widthHint.textColor = .secondaryLabel
        widthHint.numberOfLines = 0
        widthHint.adjustsFontForContentSizeCategory = true
        preview.onViewportSizeChange = { [weak self] _ in
            self?.updateAvailableSpaceText()
        }
        codeLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byWordWrapping
        codeLabel.semanticContentAttribute = .forceLeftToRight
        codeLabel.textAlignment = .left
        codeLabel.textColor = .secondaryLabel
        for control in [axisControl, sizingControl, alignmentControl, directionControl] {
            control.addTarget(self, action: #selector(updatePreview), for: .valueChanged)
        }
        widthSlider.addTarget(self, action: #selector(updatePreview), for: .valueChanged)
        axisControl.accessibilityIdentifier = "directionalGrid.axis"
        sizingControl.accessibilityIdentifier = "directionalGrid.sizing"
        alignmentControl.accessibilityIdentifier = "directionalGrid.alignment"
        directionControl.accessibilityIdentifier = "directionalGrid.direction"
        widthSlider.accessibilityIdentifier = "directionalGrid.width"
        widthLabel.accessibilityIdentifier = "directionalGrid.availableSpace"
        widthHint.accessibilityIdentifier = "directionalGrid.availableSpaceHint"
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        updatePreview()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 16) {
                introduction
                axisControl.resizable(axis: .horizontal)
                sizingControl.resizable(axis: .horizontal)
                alignmentControl.resizable(axis: .horizontal)
                directionControl.resizable(axis: .horizontal)
                widthLabel
                widthHint
                widthSlider.resizable(axis: .horizontal)
                preview.resizable().frame(height: 420)
                codeLabel
            }
            .padding(.vertical, 20)
        }
        // 滚动内容边距会补足 Duo 侧栏等横向安全区域，并参与网格可用宽度计算。
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    @objc private func updatePreview() {
        preview.isHorizontal = axisControl.selectedSegmentIndex == 1
        preview.sizing = sizingControl.selectedSegmentIndex
        preview.alignmentIndex = alignmentControl.selectedSegmentIndex
        preview.availableFraction = CGFloat(widthSlider.value)
        preview.semanticContentAttribute = directionControl.selectedSegmentIndex == 1 ? .forceRightToLeft : .forceLeftToRight
        let alignmentTitles = preview.isHorizontal
            ? ["top", "center", "bottom"]
            : ["leading", "center", "trailing"]
        for (index, title) in alignmentTitles.enumerated() {
            alignmentControl.setTitle(title, forSegmentAt: index)
        }
        introduction.text = Localization.text(preview.isHorizontal
            ? "directionalGrid.horizontalIntroduction" : "directionalGrid.verticalIntroduction")
        updateAvailableSpaceText()
        let rules = [
            ["GridItem(.fixed(76), spacing: 12)", "GridItem(.fixed(96), spacing: 12)"],
            ["GridItem(spacing: 12)", "GridItem(spacing: 12)"],
            ["GridItem(.adaptive(minimum: 72), spacing: 12)"],
            ["GridItem(.fixed(56), spacing: 12)", "GridItem(.adaptive(minimum: 64), spacing: 12)"]
        ][preview.sizing].joined(separator: ",\n    ")
        codeLabel.text = """
        \(preview.isHorizontal ? "HGrid(rows" : "VGrid(columns"): [
            \(rules)
        ], alignment: .\(alignmentTitles[preview.alignmentIndex]), spacing: 12)
        """
        preview.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }

    private func updateAvailableSpaceText() {
        let title = Localization.text(preview.isHorizontal
            ? "directionalGrid.availableHeight" : "directionalGrid.availableWidth")
        let length = preview.isHorizontal ? preview.viewportSize.height : preview.viewportSize.width
        let percentage = Int((preview.availableFraction * 100).rounded())
        let value = length > 0 ? String(format: "%.0f pt · %d%%", length, percentage) : "\(percentage)%"
        let text = "\(title) · \(value)"
        widthSlider.accessibilityLabel = title
        widthSlider.accessibilityValue = value
        widthHint.text = Localization.text(preview.isHorizontal
            ? "directionalGrid.heightHint" : "directionalGrid.widthHint")
        if widthLabel.text != text {
            widthLabel.text = text
            setNeedsQuickLayout()
        }
    }
}

/// 子视图身份稳定，切换配置和尺寸只重新排列现有卡片。
final class DirectionalGridPreviewView: QuickLayoutView {
    var isHorizontal = false
    var sizing = 2
    var alignmentIndex = 1
    var availableFraction: CGFloat = 1
    var onViewportSizeChange: ((CGSize) -> Void)?
    var viewportSize: CGSize { scrollView.bounds.size }
    private var reportedViewportSize: CGSize = .zero
    let cards: [UILabel] = (0..<11).map { index in
        let label = UILabel()
        label.text = String(format: "%02d", index + 1)
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.backgroundColor = [UIColor.systemBlue, .systemTeal, .systemOrange][index % 3].withAlphaComponent(0.18)
        label.textColor = .label
        label.layer.cornerRadius = 10
        label.clipsToBounds = true
        label.accessibilityIdentifier = "directionalGrid.card.\(index)"
        return label
    }
    private let scrollView = QuickLayoutScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        clipsToBounds = true
        accessibilityIdentifier = "directionalGrid.preview"
        scrollView.accessibilityIdentifier = "directionalGrid.viewport"
        scrollView.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.05)
        scrollView.layer.borderColor = UIColor.systemIndigo.cgColor
        scrollView.layer.borderWidth = 1.5
        scrollView.layer.cornerRadius = 8
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = viewportSize
        guard size != reportedViewportSize, size.width > 0, size.height > 0 else { return }
        reportedViewportSize = size
        onViewportSizeChange?(size)
    }

    private var items: [GridItem] {
        switch sizing {
        case 0: [.init(.fixed(76), spacing: 12), .init(.fixed(96), spacing: 12)]
        case 1: [.init(spacing: 12), .init(spacing: 12)]
        case 3: [.init(.fixed(56), spacing: 12), .init(.adaptive(minimum: 64), spacing: 12)]
        default: [.init(.adaptive(minimum: 72), spacing: 12)]
        }
    }

    override var body: Layout {
        let isHorizontal = isHorizontal
        let items = items
        let alignmentIndex = alignmentIndex
        let availableFraction = availableFraction
        let fixedCellCross: CGFloat? = sizing == 0 ? 48 : nil
        scrollView.semanticContentAttribute = semanticContentAttribute
        return GeometryReader { [cards, scrollView] proxy in
            if isHorizontal {
                ScrollView(scrollView, .horizontal) {
                    HGrid(rows: items, alignment: [.top, .center, .bottom][alignmentIndex], spacing: 12) {
                        for (index, card) in cards.enumerated() {
                            card.resizable().frame(width: CGFloat(56 + index % 3 * 12), height: fixedCellCross)
                        }
                    }
                }
                .frame(height: max(0, proxy.size.height * availableFraction))
                .frame(width: proxy.size.width, height: proxy.size.height,
                       alignment: Alignment(horizontal: .leading, vertical: [.top, .center, .bottom][alignmentIndex]))
            } else {
                ScrollView(scrollView) {
                    VGrid(columns: items, alignment: [.leading, .center, .trailing][alignmentIndex], spacing: 12) {
                        for (index, card) in cards.enumerated() {
                            card.resizable().frame(width: fixedCellCross, height: CGFloat(44 + index % 3 * 10))
                        }
                    }
                }
                .frame(width: max(0, proxy.size.width * availableFraction))
                // 缩小视口时也按所选方向放置，避免 trailing 落在全宽白底的中间。
                .frame(width: proxy.size.width, height: proxy.size.height,
                       alignment: Alignment(horizontal: [.leading, .center, .trailing][alignmentIndex], vertical: .top))
            }
        }
        .padding(12)
    }
}

@available(iOS 17.0, *)
#Preview { UINavigationController(rootViewController: DirectionalGridViewController()) }
