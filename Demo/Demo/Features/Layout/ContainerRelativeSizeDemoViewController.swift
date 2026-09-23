import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 演示共享尺寸上限、自然收紧、跨轴计算及嵌套作用域。
final class ContainerRelativeSizeDemoViewController: LocalizedQuickLayoutHostingController {
    enum Scenario: Int, CaseIterable, Sendable {
        case natural, proportional, crossAxis, nested

        var key: String {
            switch self {
            case .natural: "natural"
            case .proportional: "proportional"
            case .crossAxis: "crossAxis"
            case .nested: "nested"
            }
        }

        var code: String {
            switch self {
            case .natural:
                """
                ContainerRelativeSize(.horizontal) {
                  VStack(alignment: .leading, spacing: 12) {
                    shortText.containerRelativeSize(.horizontal)
                    longText.containerRelativeSize(.horizontal)
                  }
                }
                """
            case .proportional:
                """
                ContainerRelativeSize(.horizontal,
                  length: { width, _ in width * 0.7 }
                ) {
                  VStack(alignment: .leading, spacing: 12) {
                    marked.resizable()
                      .containerRelativeSize(.horizontal)
                      .frame(height: 64)
                    unmarked.resizable()
                      .frame(height: 64)
                  }
                }
                """
            case .crossAxis:
                """
                ContainerRelativeSize(.vertical,
                  maxSize: { container in
                    CGSize(width: .infinity,
                      height: min(container.height,
                        container.width * 9 / 16))
                  }
                ) {
                  panel.resizable().containerRelativeSize()
                }
                """
            case .nested:
                """
                ContainerRelativeSize(.horizontal,
                  length: { width, _ in width * 0.7 }
                ) {
                  VStack(alignment: .leading, spacing: 12) {
                    ContainerRelativeSize(.vertical,
                      length: { _, _ in 80 }
                    ) {
                      inner.resizable().containerRelativeSize()
                    }.frame(height: 100, alignment: .topLeading)
                    sibling.resizable().containerRelativeSize()
                      .frame(height: 120)
                  }
                }
                """
            }
        }
    }

    override var localizedTitleKey: String? { "demo.containerRelativeSize.title" }

    let pageScrollView = QuickLayoutScrollView(.vertical, showsIndicators: false)
    let previewView = ContainerRelativeSizePreviewView()
    let metricsLabel = UILabel()
    private let introLabel = UILabel()
    private let codeLabel = UILabel()
    private let expectedLabel = UILabel()
    private let widthLabel = UILabel()
    private let widthSlider = UISlider()
    private let previousButton = UIButton(type: .system)
    private let scenarioButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private lazy var previewStage = ContainerRelativeSizePreviewStage(preview: previewView)
    private(set) var selectedScenario = Scenario.natural
    private(set) var widthFraction: CGFloat = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        pageScrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        for label in [introLabel, expectedLabel, widthLabel, metricsLabel] {
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }
        introLabel.textColor = .secondaryLabel
        metricsLabel.textColor = .secondaryLabel
        metricsLabel.accessibilityIdentifier = "containerRelativeSize.metrics"
        codeLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .regular)
        )
        codeLabel.adjustsFontForContentSizeCategory = true
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byCharWrapping
        codeLabel.textColor = .systemIndigo
        codeLabel.textAlignment = .left
        codeLabel.semanticContentAttribute = .forceLeftToRight
        codeLabel.accessibilityIdentifier = "containerRelativeSize.code"

        for (button, symbol, action) in [
            (previousButton, "chevron.backward", #selector(previousScenario)),
            (nextButton, "chevron.forward", #selector(nextScenario)),
        ] {
            var configuration = UIButton.Configuration.tinted()
            configuration.image = UIImage(systemName: symbol)
            button.configuration = configuration
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        scenarioButton.configuration = .tinted()
        scenarioButton.showsMenuAsPrimaryAction = true
        scenarioButton.accessibilityIdentifier = "containerRelativeSize.scenario"
        previousButton.accessibilityIdentifier = "containerRelativeSize.previous"
        nextButton.accessibilityIdentifier = "containerRelativeSize.next"
        widthSlider.minimumValue = 0.5
        widthSlider.maximumValue = 1
        widthSlider.value = 1
        widthSlider.accessibilityIdentifier = "containerRelativeSize.width"
        widthSlider.addTarget(self, action: #selector(widthChanged), for: .valueChanged)
        previewView.didLayout = { [weak self] in self?.updateMetrics() }
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(pageScrollView) {
            VStack(alignment: .leading, spacing: 14) {
                introLabel
                HStack(spacing: 8) {
                    previousButton.frame(width: 44, height: 44)
                    scenarioButton.resizable(axis: .horizontal).frame(minHeight: 44)
                    nextButton.frame(width: 44, height: 44)
                }
                expectedLabel
                widthLabel
                widthSlider.resizable(axis: .horizontal).frame(height: 32)
                previewStage.resizable().frame(height: 240)
                metricsLabel
                codeLabel
            }
            .safeAreaPadding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        introLabel.text = Localization.text("containerRelativeSize.intro")
        previousButton.accessibilityLabel = Localization.text("containerRelativeSize.previous")
        nextButton.accessibilityLabel = Localization.text("containerRelativeSize.next")
        widthSlider.accessibilityLabel = Localization.text("containerRelativeSize.width")
        updatePresentation()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        for host in [pageScrollView, previewStage, previewView] as [UIView] {
            host.semanticContentAttribute = direction.appLayoutDirection.semanticContentAttribute
            host.setNeedsLayout()
        }
        codeLabel.semanticContentAttribute = .forceLeftToRight
    }

    func selectScenario(at index: Int) {
        guard let scenario = Scenario(rawValue: index) else { return }
        selectedScenario = scenario
        updatePresentation()
    }

    func setWidthFraction(_ fraction: CGFloat) {
        guard fraction.isFinite else { return }
        widthFraction = (min(1, max(0.5, fraction)) * 100).rounded() / 100
        widthSlider.value = Float(widthFraction)
        previewStage.widthFraction = widthFraction
        updateWidthLabel()
        setNeedsQuickLayout()
    }

    private func updatePresentation() {
        let title = Localization.text("containerRelativeSize.\(selectedScenario.key).title")
        scenarioButton.configuration?.title = "\(selectedScenario.rawValue + 1)/4  \(title)"
        scenarioButton.menu = UIMenu(children: Scenario.allCases.map { scenario in
            UIAction(
                title: Localization.text("containerRelativeSize.\(scenario.key).title"),
                state: scenario == selectedScenario ? .on : .off
            ) { [weak self] _ in self?.selectScenario(at: scenario.rawValue) }
        })
        expectedLabel.text = Localization.text("containerRelativeSize.\(selectedScenario.key).detail")
        codeLabel.text = selectedScenario.code
        previewView.configure(scenario: selectedScenario)
        updateWidthLabel()
        setNeedsQuickLayout()
    }

    private func updateWidthLabel() {
        let percentage = Localization.percent(Double(widthFraction))
        widthLabel.text = Localization.text("containerRelativeSize.width")
            + " · " + percentage
        widthSlider.accessibilityValue = percentage
    }

    private func updateMetrics() {
        let rows = [(Localization.text("containerRelativeSize.container"), previewView.bounds.size)]
            + previewView.visibleSamples.map { sample in
                let name = selectedScenario == .natural && sample === previewView.secondSample
                    ? Localization.text("containerRelativeSize.longText") : sample.text ?? ""
                return (name, sample.bounds.size)
            }
        let text = rows.map { name, size in
            // 尺寸按宽 × 高阅读；在 RTL 段落中隔离数值，避免两个轴视觉倒置。
            "\(name): \u{2066}\(String(format: "%.0f × %.0f pt", size.width, size.height))\u{2069}"
        }.joined(separator: "\n")
        guard metricsLabel.text != text else { return }
        metricsLabel.text = text
        setNeedsQuickLayout()
    }

    @objc private func widthChanged() { setWidthFraction(CGFloat(widthSlider.value)) }
    @objc private func previousScenario() {
        selectScenario(at: (selectedScenario.rawValue + Scenario.allCases.count - 1) % Scenario.allCases.count)
    }
    @objc private func nextScenario() {
        selectScenario(at: (selectedScenario.rawValue + 1) % Scenario.allCases.count)
    }
}

/// 独立宿主让滑块比例以页面留白后的可用宽度为基准，随窗口尺寸重新测量。
private final class ContainerRelativeSizePreviewStage: QuickLayoutView {
    let preview: ContainerRelativeSizePreviewView
    var widthFraction: CGFloat = 1 {
        didSet { setNeedsQuickLayout() }
    }

    init(preview: ContainerRelativeSizePreviewView) {
        self.preview = preview
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        let fraction = widthFraction
        return preview.resizable()
            .containerRelativeFrame(.horizontal) { width, _ in width * fraction }
            .frame(height: 240)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

final class ContainerRelativeSizePreviewView: QuickLayoutView {
    private(set) var scenario = ContainerRelativeSizeDemoViewController.Scenario.natural
    let firstSample = UILabel()
    let secondSample = UILabel()
    var didLayout: (() -> Void)?

    var visibleSamples: [UILabel] {
        scenario == .crossAxis ? [firstSample] : [firstSample, secondSample]
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        backgroundColor = .secondarySystemGroupedBackground
        layer.borderWidth = 1
        layer.borderColor = UIColor.secondaryLabel.cgColor
        accessibilityIdentifier = "containerRelativeSize.preview"
        for (index, label) in [firstSample, secondSample].enumerated() {
            label.font = .preferredFont(forTextStyle: .body)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            label.textColor = .label
            label.textAlignment = .natural
            label.backgroundColor = (index == 0 ? UIColor.systemBlue : .systemOrange).withAlphaComponent(0.22)
            label.accessibilityIdentifier = "containerRelativeSize.sample.\(index)"
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(scenario: ContainerRelativeSizeDemoViewController.Scenario) {
        self.scenario = scenario
        firstSample.text = Localization.text("containerRelativeSize.\(scenario.key).first")
        secondSample.text = scenario == .crossAxis ? nil
            : Localization.text("containerRelativeSize.\(scenario.key).second")
        setNeedsQuickLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        didLayout?()
    }

    override var body: Layout {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @LayoutBuilder private var content: Layout {
        switch scenario {
        case .natural:
            ContainerRelativeSize(.horizontal) {
                VStack(alignment: .leading, spacing: 12) {
                    firstSample.containerRelativeSize(.horizontal)
                    secondSample.containerRelativeSize(.horizontal)
                }
            }
        case .proportional:
            ContainerRelativeSize(.horizontal, length: { width, _ in width * 0.7 }) {
                VStack(alignment: .leading, spacing: 12) {
                    firstSample.resizable()
                        .containerRelativeSize(.horizontal).frame(height: 64)
                    secondSample.resizable().frame(height: 64)
                }
            }
        case .crossAxis:
            ContainerRelativeSize(.vertical, maxSize: { container in
                CGSize(width: .infinity, height: min(container.height, container.width * 9 / 16))
            }) {
                firstSample.resizable().containerRelativeSize()
            }
        case .nested:
            ContainerRelativeSize(.horizontal, length: { width, _ in width * 0.7 }) {
                VStack(alignment: .leading, spacing: 12) {
                    ContainerRelativeSize(.vertical, length: { _, _ in 80 }) {
                        firstSample.resizable().containerRelativeSize()
                    }.frame(height: 100, alignment: .topLeading)
                    secondSample.resizable().containerRelativeSize().frame(height: 120)
                }
            }
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: ContainerRelativeSizeDemoViewController())
}
