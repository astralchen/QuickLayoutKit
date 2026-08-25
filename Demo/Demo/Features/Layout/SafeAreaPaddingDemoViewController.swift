//
//  SafeAreaPaddingDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/25.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 交互验证 `safeAreaPadding` 边缘选择、组合顺序和 QuickLayout `nil` 契约的页面。
final class SafeAreaPaddingDemoViewController: DemoQuickLayoutHostingController {

    enum Scenario: Int, CaseIterable, Sendable {
        case baseline
        case zeroAll
        case nilAll
        case allSixteen
        case horizontalSixteen
        case perEdgeInsets
        case separateEdges
        case repeatedLeading
        case leadingThenNil
        case negativeLeading

        var title: String {
            switch self {
            case .baseline:
                "No modifier"
            case .zeroAll:
                ".all · 0"
            case .nilAll:
                ".all · nil"
            case .allSixteen:
                ".all · 16"
            case .horizontalSixteen:
                ".horizontal · 16"
            case .perEdgeInsets:
                "EdgeInsets"
            case .separateEdges:
                "horizontal + bottom"
            case .repeatedLeading:
                "leading 8 + leading 12"
            case .leadingThenNil:
                "leading 8 + nil"
            case .negativeLeading:
                "negative leading"
            }
        }

        var code: String {
            switch self {
            case .baseline:
                "// No safeAreaPadding"
            case .zeroAll:
                ".safeAreaPadding(.all, 0)"
            case .nilAll:
                ".safeAreaPadding()"
            case .allSixteen:
                ".safeAreaPadding(16)"
            case .horizontalSixteen:
                ".safeAreaPadding(.horizontal, 16)"
            case .perEdgeInsets:
                """
                .safeAreaPadding(
                    EdgeInsets(top: 8, leading: 12,
                               bottom: 20, trailing: 24)
                )
                """
            case .separateEdges:
                """
                .safeAreaPadding(.horizontal, 16)
                .safeAreaPadding(.bottom, 24)
                """
            case .repeatedLeading:
                """
                .safeAreaPadding(.leading, 8)
                .safeAreaPadding(.leading, 12)
                """
            case .leadingThenNil:
                """
                .safeAreaPadding(.leading, 8)
                .safeAreaPadding(.leading, nil)
                """
            case .negativeLeading:
                ".safeAreaPadding(.leading, -8)"
            }
        }

        var expected: String {
            switch self {
            case .baseline:
                "Does not consume safe area; UIKit still adjusts scroll content"
            case .zeroAll:
                "Consumes every safe-area edge; additional spacing is 0"
            case .nilAll:
                "QuickLayout nil: consumes all edges; additional spacing is 0"
            case .allSixteen:
                "Adds 16 beyond every inherited safe-area edge"
            case .horizontalSixteen:
                "Consumes horizontal safe area and adds 16 on both sides"
            case .perEdgeInsets:
                "Adds top 8, leading 12, bottom 20, and trailing 24"
            case .separateEdges:
                "Consecutive calls on different edges combine independently"
            case .repeatedLeading:
                "Repeated leading calls accumulate to 20"
            case .leadingThenNil:
                "nil adds 0; the earlier leading 8 remains effective"
            case .negativeLeading:
                "Negative spacing clamps to 0 and stays inside the original safe area"
            }
        }
    }

    override var localizedTitleKey: String? {
        "demo.safeAreaPadding.title"
    }

    let pageScrollView = QuickLayoutScrollView(.vertical)
    let metricsLabel = UILabel()
    private let backdropView = UIView()
    private let safeAreaGuideView = SafeAreaPaddingGuideView()
    private let introLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let scenarioButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let codeLabel = UILabel()
    private let expectedLabel = UILabel()
    private let sampleViews: [SafeAreaPaddingSampleView]

    private(set) var selectedScenario = Scenario.baseline
    private var shouldScrollPageToTop = false

    override init(
        nibName nibNameOrNil: String?,
        bundle nibBundleOrNil: Bundle?
    ) {
        sampleViews = (1...8).map { SafeAreaPaddingSampleView(index: $0) }
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        sampleViews = (1...8).map { SafeAreaPaddingSampleView(index: $0) }
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        updateScenarioPresentation()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if shouldScrollPageToTop {
            shouldScrollPageToTop = false
            pageScrollView.scrollTo(.top, animated: false)
        }
        updateObservedMetrics()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        introLabel.text = DemoLocalization.text("safeAreaPadding.intro")
        previousButton.accessibilityLabel = DemoLocalization.text(
            "safeAreaPadding.previous"
        )
        nextButton.accessibilityLabel = DemoLocalization.text(
            "safeAreaPadding.next"
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
        [pageScrollView, safeAreaGuideView].forEach {
            $0.semanticContentAttribute = semanticAttribute
            $0.setNeedsLayout()
        }
        sampleViews.forEach {
            $0.semanticContentAttribute = semanticAttribute
            $0.setNeedsQuickLayout()
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ZStack {
            backdropView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            configuredPage

            safeAreaGuideView
                .resizable()
                .zIndex(10)
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

    private var configuredPage: Layout {
        let page = ScrollView(pageScrollView, .vertical) {
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

                VStack(spacing: 10) {
                    ForEach(sampleViews) { sample in
                        sample.resizable(axis: .horizontal)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }

        switch selectedScenario {
        case .baseline:
            return page
        case .zeroAll:
            return page.safeAreaPadding(.all, 0)
        case .nilAll:
            return page.safeAreaPadding()
        case .allSixteen:
            return page.safeAreaPadding(16)
        case .horizontalSixteen:
            return page.safeAreaPadding(.horizontal, 16)
        case .perEdgeInsets:
            return page.safeAreaPadding(
                EdgeInsets(
                    top: 8,
                    leading: 12,
                    bottom: 20,
                    trailing: 24
                )
            )
        case .separateEdges:
            return page
                .safeAreaPadding(.horizontal, 16)
                .safeAreaPadding(.bottom, 24)
        case .repeatedLeading:
            return page
                .safeAreaPadding(.leading, 8)
                .safeAreaPadding(.leading, 12)
        case .leadingThenNil:
            return page
                .safeAreaPadding(.leading, 8)
                .safeAreaPadding(.leading, nil)
        case .negativeLeading:
            return page.safeAreaPadding(.leading, -8)
        }
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        backdropView.backgroundColor = .systemIndigo.withAlphaComponent(0.12)

        pageScrollView.backgroundColor = .systemBackground
        pageScrollView.accessibilityIdentifier = "safeAreaPadding.page"
        pageScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        safeAreaGuideView.accessibilityIdentifier = "safeAreaPadding.guide"
        safeAreaGuideView.isUserInteractionEnabled = false

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
        scenarioButton.accessibilityIdentifier = "safeAreaPadding.scenario"

        [codeLabel, expectedLabel, metricsLabel].forEach {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        codeLabel.textColor = .systemIndigo
        expectedLabel.textColor = .label
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.accessibilityIdentifier = "safeAreaPadding.metrics"
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
        shouldScrollPageToTop = true
        updateScenarioPresentation()
        setNeedsQuickLayout()
    }

    private func updateScenarioPresentation() {
        codeLabel.text = selectedScenario.code
        expectedLabel.text = "Contract → \(selectedScenario.expected)"

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
        let frame = pageScrollView.convert(pageScrollView.bounds, to: view)
        let safeArea = view.safeAreaInsets
        let text = """
        safeAreaInsets \(format(safeArea))
        pageFrame      \(format(frame))
        direction      \(view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? "RTL" : "LTR")
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

    private func format(_ frame: CGRect) -> String {
        String(
            format: "x%.0f y%.0f w%.0f h%.0f",
            frame.minX,
            frame.minY,
            frame.width,
            frame.height
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

private final class SafeAreaPaddingGuideView: UIView {

    private let safeAreaLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        safeAreaLayer.fillColor = UIColor.clear.cgColor
        safeAreaLayer.strokeColor = UIColor.systemGreen.cgColor
        safeAreaLayer.lineWidth = 2
        safeAreaLayer.lineDashPattern = [6, 4]
        layer.addSublayer(safeAreaLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safeBounds = bounds.inset(by: safeAreaInsets)
        safeAreaLayer.frame = bounds
        safeAreaLayer.path = UIBezierPath(rect: safeBounds).cgPath
    }
}

private final class SafeAreaPaddingSampleView: QuickLayoutView {

    private let titleLabel = UILabel()
    private let backgroundView = UIView()

    init(index: Int) {
        super.init(frame: .zero)

        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.text = "Safe area content \(index)"
        titleLabel.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
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
            .frame(height: 64)
            .background { backgroundView }
    }
}

#Preview {
    UINavigationController(
        rootViewController: SafeAreaPaddingDemoViewController()
    )
}
