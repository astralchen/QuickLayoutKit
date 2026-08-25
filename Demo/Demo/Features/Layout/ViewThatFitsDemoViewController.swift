//
//  ViewThatFitsDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/8/25.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 交互验证 `ViewThatFits` 候选顺序、约束轴与回退规则的页面。
final class ViewThatFitsDemoViewController: DemoQuickLayoutHostingController {

    enum Scenario: Int, CaseIterable, Sendable {
        case defaultBothAxes
        case horizontalOnly
        case verticalOnly
        case emptyAxes
        case firstMatchingCandidate
        case lastCandidateFallback

        var title: String {
            switch self {
            case .defaultBothAxes:
                "default · both axes"
            case .horizontalOnly:
                ".horizontal only"
            case .verticalOnly:
                ".vertical only"
            case .emptyAxes:
                "empty axes"
            case .firstMatchingCandidate:
                "first matching candidate"
            case .lastCandidateFallback:
                "last candidate fallback"
            }
        }

        var code: String {
            switch self {
            case .defaultBothAxes, .firstMatchingCandidate,
                    .lastCandidateFallback:
                "ViewThatFits { A; B; C }"
            case .horizontalOnly:
                "ViewThatFits(in: .horizontal) { A; B; C }"
            case .verticalOnly:
                "ViewThatFits(in: .vertical) { A; B; C }"
            case .emptyAxes:
                "ViewThatFits(in: []) { A; B; C }"
            }
        }

        var axes: AxisSet {
            switch self {
            case .horizontalOnly:
                [.horizontal]
            case .verticalOnly:
                [.vertical]
            case .emptyAxes:
                []
            case .defaultBothAxes, .firstMatchingCandidate,
                    .lastCandidateFallback:
                [.horizontal, .vertical]
            }
        }

        var candidates: [ViewThatFitsCandidate] {
            switch self {
            case .defaultBothAxes:
                [
                    .init(identifier: "A", size: CGSize(width: 260, height: 120)),
                    .init(identifier: "B", size: CGSize(width: 180, height: 90)),
                    .init(identifier: "C", size: CGSize(width: 100, height: 60)),
                ]
            case .horizontalOnly:
                [
                    .init(identifier: "A", size: CGSize(width: 180, height: 160)),
                    .init(identifier: "B", size: CGSize(width: 130, height: 80)),
                    .init(identifier: "C", size: CGSize(width: 90, height: 50)),
                ]
            case .verticalOnly:
                [
                    .init(identifier: "A", size: CGSize(width: 260, height: 80)),
                    .init(identifier: "B", size: CGSize(width: 180, height: 60)),
                    .init(identifier: "C", size: CGSize(width: 100, height: 40)),
                ]
            case .emptyAxes:
                [
                    .init(identifier: "A", size: CGSize(width: 280, height: 150)),
                    .init(identifier: "B", size: CGSize(width: 160, height: 80)),
                    .init(identifier: "C", size: CGSize(width: 90, height: 50)),
                ]
            case .firstMatchingCandidate:
                [
                    .init(identifier: "A", size: CGSize(width: 180, height: 80)),
                    .init(identifier: "B", size: CGSize(width: 160, height: 70)),
                    .init(identifier: "C", size: CGSize(width: 100, height: 50)),
                ]
            case .lastCandidateFallback:
                [
                    .init(identifier: "A", size: CGSize(width: 240, height: 120)),
                    .init(identifier: "B", size: CGSize(width: 180, height: 100)),
                    .init(identifier: "C", size: CGSize(width: 150, height: 90)),
                ]
            }
        }

        var proposedSize: CGSize {
            switch self {
            case .firstMatchingCandidate:
                CGSize(width: 240, height: 130)
            case .lastCandidateFallback:
                CGSize(width: 120, height: 70)
            case .defaultBothAxes, .horizontalOnly, .verticalOnly, .emptyAxes:
                CGSize(width: 200, height: 100)
            }
        }

        func expectedCandidate(
            for proposedSize: CGSize
        ) -> ViewThatFitsCandidate? {
            guard let fallback = candidates.last else { return nil }

            for candidate in candidates.dropLast() {
                if axes.contains(.horizontal),
                   candidate.size.width > proposedSize.width {
                    continue
                }
                if axes.contains(.vertical),
                   candidate.size.height > proposedSize.height {
                    continue
                }
                return candidate
            }

            return fallback
        }
    }

    override var localizedTitleKey: String? {
        "demo.viewThatFits.title"
    }

    let pageScrollView = QuickLayoutScrollView(
        .vertical,
        showsIndicators: true
    )
    let previewView = ViewThatFitsPreviewView()

    private let introLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let scenarioButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let codeLabel = UILabel()
    let expectedLabel = UILabel()
    private let widthTitleLabel = UILabel()
    private let widthValueLabel = UILabel()
    private let widthSlider = UISlider()
    private let heightTitleLabel = UILabel()
    private let heightValueLabel = UILabel()
    private let heightSlider = UISlider()
    let metricsLabel = UILabel()

    private(set) var selectedScenario = Scenario.defaultBothAxes
    private(set) var proposedSize = Scenario.defaultBothAxes.proposedSize

    var scenarioCount: Int {
        Scenario.allCases.count
    }

    var selectedCandidateIdentifier: String? {
        previewView.selectedCandidateIdentifier
    }

    var selectedCandidateSize: CGSize? {
        previewView.selectedCandidateSize
    }

    var expectedCandidateIdentifier: String? {
        selectedScenario.expectedCandidate(for: proposedSize)?.identifier
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        applySelectedScenario(resetProposedSize: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateObservedSelection()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        introLabel.text = DemoLocalization.text("viewThatFits.intro")
        previousButton.accessibilityLabel = DemoLocalization.text(
            "viewThatFits.previous"
        )
        nextButton.accessibilityLabel = DemoLocalization.text(
            "viewThatFits.next"
        )
        widthTitleLabel.text = DemoLocalization.text("viewThatFits.width")
        heightTitleLabel.text = DemoLocalization.text("viewThatFits.height")
        updateScenarioPresentation()
        updateObservedSelection()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        let semanticAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        pageScrollView.semanticContentAttribute = semanticAttribute
        previewView.semanticContentAttribute = semanticAttribute
        previewView.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(pageScrollView) {
            VStack(alignment: .leading, spacing: 14) {
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

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        widthTitleLabel
                        widthValueLabel
                    }
                    widthSlider
                        .resizable(axis: .horizontal)
                        .frame(height: 32)

                    HStack {
                        heightTitleLabel
                        heightValueLabel
                    }
                    heightSlider
                        .resizable(axis: .horizontal)
                        .frame(height: 32)
                }

                previewView
                    .resizable()
                    .frame(
                        width: proposedSize.width,
                        height: proposedSize.height
                    )
                    .frame(maxWidth: .infinity, alignment: .center)

                metricsLabel
            }
            .safeAreaPadding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    func selectScenario(at index: Int) {
        let scenarios = Scenario.allCases
        guard scenarios.indices.contains(index) else { return }
        let scenario = scenarios[index]
        guard selectedScenario != scenario else { return }
        selectedScenario = scenario
        applySelectedScenario(resetProposedSize: true)
    }

    func setProposedSize(_ size: CGSize) {
        let width = min(max(size.width, 90), 320)
        let height = min(max(size.height, 50), 200)
        proposedSize = CGSize(width: width, height: height)
        widthSlider.value = Float(width)
        heightSlider.value = Float(height)
        updateSizePresentation()
        updateExpectedPresentation()
        setNeedsQuickLayout()
    }

    private func configureViews() {
        view.backgroundColor = .systemGroupedBackground
        pageScrollView.backgroundColor = .systemGroupedBackground
        pageScrollView.quickLayoutSemanticDirectionBehavior =
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
        scenarioButton.accessibilityIdentifier = "viewThatFits.scenario"

        [codeLabel, expectedLabel, metricsLabel].forEach {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            $0.adjustsFontForContentSizeCategory = true
            $0.numberOfLines = 0
        }
        codeLabel.textColor = .systemIndigo
        expectedLabel.textColor = .label
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.accessibilityIdentifier = "viewThatFits.metrics"

        [widthTitleLabel, heightTitleLabel].forEach {
            $0.font = .preferredFont(forTextStyle: .subheadline)
            $0.adjustsFontForContentSizeCategory = true
        }
        [widthValueLabel, heightValueLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
            $0.textAlignment = .right
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        widthSlider.minimumValue = 90
        widthSlider.maximumValue = 320
        widthSlider.addTarget(
            self,
            action: #selector(proposedSizeDidChange),
            for: .valueChanged
        )
        widthSlider.accessibilityIdentifier = "viewThatFits.width"

        heightSlider.minimumValue = 50
        heightSlider.maximumValue = 200
        heightSlider.addTarget(
            self,
            action: #selector(proposedSizeDidChange),
            for: .valueChanged
        )
        heightSlider.accessibilityIdentifier = "viewThatFits.height"

        previewView.selectionDidChange = { [weak self] _ in
            self?.updateObservedSelection()
        }
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

    private func applySelectedScenario(resetProposedSize: Bool) {
        if resetProposedSize {
            setProposedSize(selectedScenario.proposedSize)
        }
        previewView.configure(
            axes: selectedScenario.axes,
            candidates: selectedScenario.candidates
        )
        updateScenarioPresentation()
        setNeedsQuickLayout()
    }

    private func updateScenarioPresentation() {
        codeLabel.text = selectedScenario.code
        updateExpectedPresentation()

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
                    self?.selectScenario(at: scenario.rawValue)
                }
            }
        )
    }

    private func updateExpectedPresentation() {
        expectedLabel.text = DemoLocalization.text(
            "viewThatFits.expected",
            expectedCandidateIdentifier ?? "—"
        )
    }

    private func updateSizePresentation() {
        widthValueLabel.text = String(format: "%.0f pt", proposedSize.width)
        heightValueLabel.text = String(format: "%.0f pt", proposedSize.height)
    }

    private func updateObservedSelection() {
        let selected = selectedCandidateIdentifier ?? "—"
        let text = DemoLocalization.text("viewThatFits.selected", selected)
        guard metricsLabel.text != text else { return }
        metricsLabel.text = text
        setNeedsQuickLayout()
    }

    @objc private func proposedSizeDidChange() {
        setProposedSize(
            CGSize(
                width: CGFloat(widthSlider.value.rounded()),
                height: CGFloat(heightSlider.value.rounded())
            )
        )
    }

    @objc private func showPreviousScenario() {
        let previousIndex = (
            selectedScenario.rawValue - 1 + scenarioCount
        ) % scenarioCount
        selectScenario(at: previousIndex)
    }

    @objc private func showNextScenario() {
        selectScenario(
            at: (selectedScenario.rawValue + 1) % scenarioCount
        )
    }
}

struct ViewThatFitsCandidate: Sendable {
    let identifier: String
    let size: CGSize
}

final class ViewThatFitsPreviewView: QuickLayoutView {

    private let candidateViews: [UILabel] = [UILabel(), UILabel(), UILabel()]
    private var axes: AxisSet = [.horizontal, .vertical]
    private var candidates: [ViewThatFitsCandidate] = []

    var selectionDidChange: ((String?) -> Void)?

    var selectedCandidateIdentifier: String? {
        zip(candidates, candidateViews).first { _, view in
            view.bounds.width > 0 && view.bounds.height > 0
        }?.0.identifier
    }

    var selectedCandidateSize: CGSize? {
        candidateViews.first { view in
            view.bounds.width > 0 && view.bounds.height > 0
        }?.bounds.size
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        selectionDidChange?(selectedCandidateIdentifier)
    }

    override var body: Layout {
        fittedContent
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
    }

    func configure(
        axes: AxisSet,
        candidates: [ViewThatFitsCandidate]
    ) {
        precondition(candidates.count == candidateViews.count)
        self.axes = axes
        self.candidates = candidates

        for (candidate, view) in zip(candidates, candidateViews) {
            view.text = "\(candidate.identifier)\n\(format(candidate.size))"
            view.accessibilityLabel = "Candidate \(candidate.identifier)"
            view.accessibilityValue = format(candidate.size)
        }
        setNeedsQuickLayout()
    }

    private var fittedContent: Layout {
        ViewThatFits(in: axes) {
            candidateLayout(at: 0)
            candidateLayout(at: 1)
            candidateLayout(at: 2)
        }
    }

    private func candidateLayout(at index: Int) -> Layout {
        let candidate = candidates.indices.contains(index)
            ? candidates[index]
            : ViewThatFitsCandidate(identifier: "—", size: .zero)
        return candidateViews[index]
            .resizable()
            .frame(width: candidate.size.width, height: candidate.size.height)
    }

    private func configureAppearance() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        clipsToBounds = true
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "viewThatFits.preview"

        let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen]
        for (index, view) in candidateViews.enumerated() {
            view.backgroundColor = colors[index]
            view.textColor = .white
            view.textAlignment = .center
            view.numberOfLines = 0
            view.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
            view.layer.cornerRadius = 14
            view.layer.cornerCurve = .continuous
            view.clipsToBounds = true
            view.isAccessibilityElement = true
        }
    }

    private func format(_ size: CGSize) -> String {
        String(format: "%.0f × %.0f", size.width, size.height)
    }
}

#Preview {
    UINavigationController(
        rootViewController: ViewThatFitsDemoViewController()
    )
}
