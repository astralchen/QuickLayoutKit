import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

enum FixedSizeScenario: Int, CaseIterable {
    case natural, fill, equal

    var key: String {
        switch self {
        case .natural: "fixedSize.natural"
        case .fill: "fixedSize.fill"
        case .equal: "fixedSize.equal"
        }
    }

    var code: String {
        switch self {
        case .natural:
            "card.fixedSize(axis: .vertical)\n    .frame(width: cardWidth)"
        case .fill:
            "HStack {\n    card.frame(maxHeight: .infinity)\n}\n.frame(height: 420)"
        case .equal:
            "HStack(alignment: .top, spacing: 16) {\n    card.frame(maxHeight: .infinity)\n}\n.fixedSize(axis: .vertical)"
        }
    }
}

/// 组合介绍、实验区和说明面板，统一管理当前展示状态。
final class FixedSizeDemoView: QuickLayoutView {
    let pageScrollView = QuickLayoutScrollView(.vertical, showsIndicators: true)
    let stageView = FixedSizeStageView()
    private let introView = FixedSizeIntroView()
    private let scenarioControl = UISegmentedControl(items: ["", "", ""])
    private let explanationView = FixedSizeExplanationView()
    private(set) var selectedScenario = FixedSizeScenario.equal

    var onOpenSource: (() -> Void)? {
        get { explanationView.onOpenSource }
        set { explanationView.onOpenSource = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        pageScrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        pageScrollView.accessibilityIdentifier = "fixedSize.page"
        scenarioControl.selectedSegmentTintColor = .secondarySystemGroupedBackground
        scenarioControl.accessibilityIdentifier = "fixedSize.mode"
        scenarioControl.addTarget(self, action: #selector(scenarioChanged), for: .valueChanged)
        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        ScrollView(pageScrollView) {
            VStack(alignment: .leading, spacing: 24) {
                introView
                    .safeAreaPadding(.horizontal, 20)
                scenarioControl.resizable(axis: .horizontal).frame(height: 44)
                    .safeAreaPadding(.horizontal, 20)
                stageView
                explanationView
                    .safeAreaPadding(.horizontal, 20)
            }
            .padding(.vertical, 24)
        }
    }

    func selectScenario(_ scenario: FixedSizeScenario) {
        guard selectedScenario != scenario else { return }
        selectedScenario = scenario
        stageView.selectScenario(scenario)
        updateScenarioPresentation()
        setNeedsQuickLayout()
    }

    func reloadLocalizedContent() {
        introView.reloadLocalizedContent()
        stageView.reloadLocalizedContent()
        scenarioControl.accessibilityLabel = Localization.text("fixedSize.mode")
        for scenario in FixedSizeScenario.allCases {
            scenarioControl.setTitle(Localization.text(scenario.key), forSegmentAt: scenario.rawValue)
        }
        updateScenarioPresentation()
        setNeedsQuickLayout()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        semanticContentAttribute = direction.appLayoutDirection.semanticContentAttribute
        pageScrollView.semanticContentAttribute = semanticContentAttribute
        introView.semanticContentAttribute = semanticContentAttribute
        explanationView.semanticContentAttribute = semanticContentAttribute
        stageView.reloadLayoutDirection(direction)
        setNeedsQuickLayout()
    }

    private func updateScenarioPresentation() {
        scenarioControl.selectedSegmentIndex = selectedScenario.rawValue
        explanationView.configure(scenario: selectedScenario)
    }

    @objc private func scenarioChanged() {
        guard let scenario = FixedSizeScenario(rawValue: scenarioControl.selectedSegmentIndex) else { return }
        selectScenario(scenario)
    }
}

@MainActor
enum FixedSizeText {
    static func make(style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = color
        return label
    }
}

private final class FixedSizeIntroView: QuickLayoutView {
    private let eyebrowLabel = FixedSizeText.make(style: .caption1, color: .systemIndigo)
    private let headlineLabel = FixedSizeText.make(style: .largeTitle, color: .label)
    private let introLabel = FixedSizeText.make(style: .body, color: .secondaryLabel)

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        eyebrowLabel.text = "FIXED SIZE / QUICKLAYOUTKIT"
        headlineLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 34, weight: .bold)
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 10) {
            eyebrowLabel
            headlineLabel
            introLabel
        }
    }

    func reloadLocalizedContent() {
        headlineLabel.text = Localization.text("fixedSize.headline")
        introLabel.text = Localization.text("fixedSize.intro")
        setNeedsQuickLayout()
    }
}

private final class FixedSizeExplanationView: QuickLayoutView {
    private let explanationLabel = FixedSizeText.make(style: .headline, color: .label)
    private let codeLabel = FixedSizeText.make(style: .footnote, color: .systemIndigo)
    private let compatibilityLabel = FixedSizeText.make(style: .footnote, color: .secondaryLabel)
    private let sourceButton = UIButton(type: .system)
    var onOpenSource: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        codeLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .medium)
        )
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.up.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.contentInsets = .zero
        sourceButton.configuration = configuration
        sourceButton.accessibilityIdentifier = "fixedSize.source"
        sourceButton.addTarget(self, action: #selector(openSource), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 16) {
            explanationLabel
            codeLabel
            compatibilityLabel
            sourceButton.frame(minHeight: 44, alignment: .leading)
        }
        .padding(20)
    }

    func configure(scenario: FixedSizeScenario) {
        explanationLabel.text = Localization.text(scenario.key + ".explanation")
        codeLabel.text = scenario.code
        compatibilityLabel.text = Localization.text("fixedSize.compatibility")
        var configuration = sourceButton.configuration
        configuration?.title = Localization.text("fixedSize.source")
        sourceButton.configuration = configuration
        setNeedsQuickLayout()
    }

    @objc private func openSource() {
        onOpenSource?()
    }
}
