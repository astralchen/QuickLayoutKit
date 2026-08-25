//
//  ContentMarginsDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/25.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 交互验证 `contentMargins` 不同 placement 与修饰器组合的页面。
final class ContentMarginsDemoViewController: DemoQuickLayoutHostingController {

    enum Scenario: Int, CaseIterable, Sendable {
        case automaticAll
        case scrollContentHorizontal
        case scrollIndicatorsHorizontal
        case separateContentAndIndicators
        case explicitContentWithAutomaticBottom
        case sameScrollContentPlacement
        case explicitContentReplacesAutomatic
        case explicitIndicatorsReplaceAutomatic
        case nilPreservesEarlierValue

        var title: String {
            switch self {
            case .automaticAll:
                ".automatic · all 16"
            case .scrollContentHorizontal:
                ".scrollContent · horizontal 16"
            case .scrollIndicatorsHorizontal:
                ".scrollIndicators · horizontal 36"
            case .separateContentAndIndicators:
                "content 16 + indicators 36"
            case .explicitContentWithAutomaticBottom:
                "content horizontal 16 + automatic bottom 24"
            case .sameScrollContentPlacement:
                "same scrollContent placement"
            case .explicitContentReplacesAutomatic:
                "scrollContent replaces automatic"
            case .explicitIndicatorsReplaceAutomatic:
                "scrollIndicators replaces automatic"
            case .nilPreservesEarlierValue:
                "nil preserves earlier value"
            }
        }

        var code: String {
            switch self {
            case .automaticAll:
                ".contentMargins(16)"
            case .scrollContentHorizontal:
                ".contentMargins(.horizontal, 16, for: .scrollContent)"
            case .scrollIndicatorsHorizontal:
                ".contentMargins(.horizontal, 36, for: .scrollIndicators)"
            case .separateContentAndIndicators:
                """
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.horizontal, 36, for: .scrollIndicators)
                """
            case .explicitContentWithAutomaticBottom:
                """
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 24)
                """
            case .sameScrollContentPlacement:
                """
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                """
            case .explicitContentReplacesAutomatic:
                """
                .contentMargins(.horizontal, 24)
                .contentMargins(.leading, 8, for: .scrollContent)
                """
            case .explicitIndicatorsReplaceAutomatic:
                """
                .contentMargins(.horizontal, 24)
                .contentMargins(.bottom, 12, for: .scrollIndicators)
                """
            case .nilPreservesEarlierValue:
                """
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.leading, nil, for: .scrollContent)
                """
            }
        }

        var expected: String {
            switch self {
            case .automaticAll:
                "content: all 16 · indicators: all 16"
            case .scrollContentHorizontal:
                "content: horizontal 16 · indicators: 0"
            case .scrollIndicatorsHorizontal:
                "content: 0 · indicators: horizontal 36"
            case .separateContentAndIndicators:
                "content: horizontal 16 · indicators: horizontal 36"
            case .explicitContentWithAutomaticBottom:
                "content: horizontal 16 · indicators: bottom 24"
            case .sameScrollContentPlacement:
                "content: horizontal 16 + bottom 24 · indicators: 0"
            case .explicitContentReplacesAutomatic:
                "content: leading 8 · indicators: horizontal 24"
            case .explicitIndicatorsReplaceAutomatic:
                "content: horizontal 24 · indicators: bottom 12"
            case .nilPreservesEarlierValue:
                "content: horizontal 20 · indicators: 0"
            }
        }
    }

    override var localizedTitleKey: String? {
        "demo.contentMargins.title"
    }

    let previewScrollView = QuickLayoutScrollView(.vertical)
    private let pageScrollView = QuickLayoutScrollView(
        .vertical,
        showsIndicators: false
    )
    private let introLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let scenarioButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let codeLabel = UILabel()
    private let expectedLabel = UILabel()
    let metricsLabel = UILabel()
    private let contentRows: [ContentMarginDemoRowView]

    private(set) var selectedScenario = Scenario.automaticAll
    private var shouldFlashIndicators = true

    override init(
        nibName nibNameOrNil: String?,
        bundle nibBundleOrNil: Bundle?
    ) {
        contentRows = (1...10).map { ContentMarginDemoRowView(index: $0) }
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        contentRows = (1...10).map { ContentMarginDemoRowView(index: $0) }
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        updateScenarioPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateObservedMetrics()

        if shouldFlashIndicators {
            shouldFlashIndicators = false
            previewScrollView.flashScrollIndicators()
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        introLabel.text = DemoLocalization.text("contentMargins.intro")
        previousButton.accessibilityLabel = DemoLocalization.text(
            "contentMargins.previous"
        )
        nextButton.accessibilityLabel = DemoLocalization.text(
            "contentMargins.next"
        )
        updateScenarioPresentation()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        [pageScrollView, previewScrollView].forEach {
            $0.semanticContentAttribute = semanticAttribute
            $0.setNeedsLayout()
        }
        contentRows.forEach {
            $0.semanticContentAttribute = semanticAttribute
            $0.setNeedsQuickLayout()
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(pageScrollView) {
            VStack(alignment: .leading, spacing: 12) {
                introLabel

                HStack(spacing: 8) {
                    previousButton.frame(width: 44, height: 44)
                    scenarioButton
                        .resizable(axis: .horizontal)
                        .frame(height: 44)
                    nextButton.frame(width: 44, height: 44)
                }

                codeLabel
                expectedLabel
                metricsLabel

                configuredPreview
            }
            .safeAreaPadding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    var scenarioCount: Int {
        Scenario.allCases.count
    }

    func selectScenario(at index: Int) {
        let scenarios = Scenario.allCases
        guard scenarios.indices.contains(index) else { return }
        selectScenario(scenarios[index])
    }

    private var configuredPreview: Layout {
        let preview = ScrollView(previewScrollView, .vertical) {
            VStack(spacing: 12) {
                ForEach(contentRows) { row in
                    row.resizable(axis: .horizontal)
                }
            }
            .padding(.vertical, 12)
        }
        .resizable(axis: .horizontal)
        .frame(height: 360)

        switch selectedScenario {
        case .automaticAll:
            return preview.contentMargins(16)
        case .scrollContentHorizontal:
            return preview.contentMargins(
                .horizontal,
                16,
                for: .scrollContent
            )
        case .scrollIndicatorsHorizontal:
            return preview.contentMargins(
                .horizontal,
                36,
                for: .scrollIndicators
            )
        case .separateContentAndIndicators:
            return preview
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.horizontal, 36, for: .scrollIndicators)
        case .explicitContentWithAutomaticBottom:
            return preview
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 24)
        case .sameScrollContentPlacement:
            return preview
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
        case .explicitContentReplacesAutomatic:
            return preview
                .contentMargins(.horizontal, 24)
                .contentMargins(.leading, 8, for: .scrollContent)
        case .explicitIndicatorsReplaceAutomatic:
            return preview
                .contentMargins(.horizontal, 24)
                .contentMargins(.bottom, 12, for: .scrollIndicators)
        case .nilPreservesEarlierValue:
            return preview
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .contentMargins(.leading, nil, for: .scrollContent)
        }
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        pageScrollView.backgroundColor = .systemGroupedBackground
        pageScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        previewScrollView.backgroundColor = .systemOrange.withAlphaComponent(
            0.12
        )
        previewScrollView.layer.cornerRadius = 18
        previewScrollView.layer.cornerCurve = .continuous
        previewScrollView.clipsToBounds = true
        previewScrollView.indicatorStyle = .black
        previewScrollView.accessibilityIdentifier = "contentMargins.preview"
        previewScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        introLabel.font = .preferredFont(forTextStyle: .body)
        introLabel.textColor = .secondaryLabel
        introLabel.adjustsFontForContentSizeCategory = true
        introLabel.numberOfLines = 0

        configureNavigationButton(
            previousButton,
            symbolName: "chevron.backward"
        )
        configureNavigationButton(
            nextButton,
            symbolName: "chevron.forward"
        )
        previousButton.addTarget(
            self,
            action: #selector(showPreviousScenario),
            for: .touchUpInside
        )
        nextButton.addTarget(
            self,
            action: #selector(showNextScenario),
            for: .touchUpInside
        )

        var scenarioConfiguration = UIButton.Configuration.tinted()
        scenarioConfiguration.cornerStyle = .medium
        scenarioConfiguration.image = UIImage(
            systemName: "chevron.up.chevron.down"
        )
        scenarioConfiguration.imagePlacement = .trailing
        scenarioConfiguration.imagePadding = 8
        scenarioButton.configuration = scenarioConfiguration
        scenarioButton.showsMenuAsPrimaryAction = true
        scenarioButton.accessibilityIdentifier = "contentMargins.scenario"

        [codeLabel, expectedLabel, metricsLabel].forEach {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        codeLabel.textColor = .systemIndigo
        expectedLabel.textColor = .label
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.accessibilityIdentifier = "contentMargins.metrics"
    }

    private func configureNavigationButton(
        _ button: UIButton,
        symbolName: String
    ) {
        var configuration = UIButton.Configuration.tinted()
        configuration.cornerStyle = .medium
        configuration.image = UIImage(systemName: symbolName)
        button.configuration = configuration
    }

    private func selectScenario(_ scenario: Scenario) {
        guard selectedScenario != scenario else { return }
        selectedScenario = scenario
        previewScrollView.setContentOffset(.zero, animated: false)
        shouldFlashIndicators = true
        updateScenarioPresentation()
        setNeedsQuickLayout()
    }

    private func updateScenarioPresentation() {
        codeLabel.text = selectedScenario.code
        expectedLabel.text = "SwiftUI → \(selectedScenario.expected)"

        var configuration = scenarioButton.configuration
            ?? UIButton.Configuration.tinted()
        let position = "\(selectedScenario.rawValue + 1)/\(scenarioCount)"
        configuration.title = "\(position)  \(selectedScenario.title)"
        scenarioButton.configuration = configuration
        scenarioButton.menu = UIMenu(
            children: Scenario.allCases.map { scenario in
                UIAction(
                    title: scenario.title,
                    state: scenario == selectedScenario ? .on : .off
                ) { [weak self] _ in
                    self?.selectScenario(scenario)
                }
            }
        )
    }

    private func updateObservedMetrics() {
        let content = previewScrollView.contentInset
        let adjusted = previewScrollView.adjustedContentInset
        let indicators = previewScrollView.verticalScrollIndicatorInsets
        let text = """
        contentInset       \(format(content))
        adjustedContentInset \(format(adjusted))
        indicatorInsets   \(format(indicators))
        """
        guard metricsLabel.text != text else { return }
        metricsLabel.text = text
        setNeedsQuickLayout()
    }

    private func format(_ insets: UIEdgeInsets) -> String {
        String(
            format: "T%.0f L%.0f B%.0f R%.0f",
            insets.top,
            insets.left,
            insets.bottom,
            insets.right
        )
    }

    @objc private func showPreviousScenario() {
        let previousIndex = (
            selectedScenario.rawValue - 1 + scenarioCount
        ) % scenarioCount
        selectScenario(at: previousIndex)
    }

    @objc private func showNextScenario() {
        selectScenario(at: (selectedScenario.rawValue + 1) % scenarioCount)
    }
}

private final class ContentMarginDemoRowView: QuickLayoutView {

    private let index: Int
    private let titleLabel = UILabel()
    private let backgroundView = UIView()

    init(index: Int) {
        self.index = index
        super.init(frame: .zero)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.text = "Content \(index)"
        titleLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        backgroundView.backgroundColor = index.isMultiple(of: 2)
            ? .systemBlue
            : .systemTeal
        backgroundView.layer.cornerRadius = 14
        backgroundView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var body: Layout {
        titleLabel
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 72)
            .background { backgroundView }
    }
}

#Preview {
    UINavigationController(
        rootViewController: ContentMarginsDemoViewController()
    )
}
