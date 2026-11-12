import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 插入内容始终固定在边缘；列表可滚动经过其背景，末项仍可完整到达。
final class SafeAreaInsetViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.safeAreaInset.title" }
    let stage = SafeAreaInsetStageView()
    private let scenarioButton = UIButton(type: .system)
    private let spacingButton = UIButton(type: .system)
    private let sizeButton = UIButton(type: .system)
    private let explanationLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        scenarioButton.accessibilityIdentifier = "safeAreaInset.scenario"
        spacingButton.accessibilityIdentifier = "safeAreaInset.spacing"
        sizeButton.accessibilityIdentifier = "safeAreaInset.size"
        for button in [scenarioButton, spacingButton, sizeButton] {
            button.configuration = .tinted()
            button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        scenarioButton.showsMenuAsPrimaryAction = true
        spacingButton.showsMenuAsPrimaryAction = true
        sizeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.stage.expanded.toggle()
            self.updatePresentation()
        }, for: .touchUpInside)
        explanationLabel.font = .preferredFont(forTextStyle: .footnote)
        explanationLabel.adjustsFontForContentSizeCategory = true
        explanationLabel.textColor = .secondaryLabel
        explanationLabel.numberOfLines = 0
        reloadLocalizedContent()
    }

    override var body: Layout {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                scenarioButton.resizable(axis: .horizontal).frame(minHeight: 44)
                HStack(spacing: 8) {
                    spacingButton.resizable(axis: .horizontal).frame(minHeight: 44)
                    sizeButton.resizable(axis: .horizontal).frame(minHeight: 44)
                }
                explanationLabel
            }
            .padding(.vertical, 10)
            .safeAreaPadding(.horizontal, 16)
            stage.resizable()
        }.safeAreaPadding(.top, 0)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        stage.reloadText()
        updatePresentation()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        let attribute: UISemanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        stage.semanticContentAttribute = attribute
        stage.scrollView.semanticContentAttribute = attribute
        stage.primaryBar.semanticContentAttribute = attribute
        stage.secondaryBar.semanticContentAttribute = attribute
        stage.setNeedsQuickLayout()
    }

    func selectScenario(_ scenario: SafeAreaInsetStageView.Scenario) {
        stage.endEditing(true)
        stage.scenario = scenario
        updatePresentation()
    }

    private func updatePresentation() {
        scenarioButton.setTitle(Localization.text(stage.scenario.titleKey), for: .normal)
        scenarioButton.menu = UIMenu(children: SafeAreaInsetStageView.Scenario.allCases.map { scenario in
            UIAction(title: Localization.text(scenario.titleKey), state: stage.scenario == scenario ? .on : .off) { [weak self] _ in
                self?.selectScenario(scenario)
            }
        })
        spacingButton.setTitle("spacing: \(Int(stage.spacing))", for: .normal)
        spacingButton.menu = UIMenu(children: [-8, 0, 8, 20].map { value in
            UIAction(title: "\(value) pt", state: stage.spacing == CGFloat(value) ? .on : .off) { [weak self] _ in
                self?.stage.spacing = CGFloat(value)
                self?.updatePresentation()
            }
        })
        sizeButton.setTitle(Localization.text(stage.expanded ? "safeAreaInset.collapse" : "safeAreaInset.expand"), for: .normal)
        explanationLabel.text = Localization.text("safeAreaInset.explanation")
        stage.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }
}

final class SafeAreaInsetStageView: QuickLayoutView {
    enum Scenario: String, CaseIterable {
        case bottom, top, leading, trailing, repeated, mixed, keyboard, none
        var titleKey: String { "safeAreaInset.scenario.\(rawValue)" }
    }
    var scenario = Scenario.bottom
    var spacing: CGFloat = 8
    var expanded = false
    let scrollView = QuickLayoutScrollView(.vertical)
    let primaryBar = SafeAreaInsetBarView()
    let secondaryBar = SafeAreaInsetBarView()
    private let rows: [UILabel] = (1...24).map { index in
        let label = UILabel()
        label.tag = index
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.accessibilityIdentifier = "safeAreaInset.row.\(index)"
        return label
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        accessibilityIdentifier = "safeAreaInset.stage"
        scrollView.accessibilityIdentifier = "safeAreaInset.scroll"
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        primaryBar.accessibilityIdentifier = "safeAreaInset.primary"
        secondaryBar.accessibilityIdentifier = "safeAreaInset.secondary"
        secondaryBar.insetBackground.backgroundColor = .secondarySystemBackground
        reloadText()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 只有靠容器底边的栏绘制底部延伸；键盘随动改变的是内容边界，
        // 不能把从键盘上沿到容器底部的整段空隙当作背景扩展量。
        let bottomBar: SafeAreaInsetBarView?
        switch scenario {
        case .bottom, .mixed, .keyboard: bottomBar = primaryBar
        case .repeated: bottomBar = secondaryBar
        default: bottomBar = nil
        }
        let containerSafeBottom = bounds.maxY - safeAreaInsets.bottom
        for bar in [primaryBar, secondaryBar] {
            let reachesContainerBottom = bar === bottomBar
                && abs(bar.frame.maxY - containerSafeBottom) < 0.5
            bar.backgroundBottomExtension = reachesContainerBottom ? max(0, safeAreaInsets.bottom) : 0
        }
        if #available(iOS 17.0, *) {
            let padding = scenario == .keyboard ? primaryBar.bounds.height + max(0, spacing) : 0
            if abs(quickLayoutKeyboardDismissPadding - padding) > 0.5 {
                quickLayoutKeyboardDismissPadding = padding
            }
        }
    }

    func reloadText() {
        for label in rows {
            label.text = "\(label.tag.formatted(.number))  ·  " + Localization.text(label.tag == 24 ? "safeAreaInset.lastRow" : "safeAreaInset.row")
        }
        primaryBar.titleLabel.text = Localization.text("safeAreaInset.primary")
        secondaryBar.titleLabel.text = Localization.text("safeAreaInset.secondary")
        primaryBar.field.placeholder = Localization.text("safeAreaInset.placeholder")
        secondaryBar.field.placeholder = primaryBar.field.placeholder
        setNeedsQuickLayout()
    }

    override var body: Layout {
        let page = ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { label in
                    label.resizable(axis: .horizontal).padding(.vertical, 18)
                }
            }
        }.contentMargins(.horizontal, 20, for: .scrollContent)
        primaryBar.expanded = expanded
        primaryBar.showsInput = scenario == .keyboard
        secondaryBar.expanded = false
        secondaryBar.showsInput = false
        switch scenario {
        case .none:
            return page
        case .bottom, .keyboard:
            return page.safeAreaInset(edge: .bottom, spacing: spacing) { primaryBar.resizable(axis: .horizontal) }
        case .top:
            return page.safeAreaInset(edge: .top, alignment: .leading, spacing: spacing) { primaryBar.resizable(axis: .horizontal) }
        case .leading:
            return page.safeAreaInset(edge: HorizontalEdge.leading, alignment: .top, spacing: spacing) {
                primaryBar.frame(width: expanded ? 132 : 96)
            }
        case .trailing:
            return page.safeAreaInset(edge: HorizontalEdge.trailing, alignment: .bottom, spacing: spacing) {
                primaryBar.frame(width: expanded ? 132 : 96)
            }
        case .repeated:
            return page.safeAreaInset(edge: .bottom, spacing: spacing) { primaryBar.resizable(axis: .horizontal) }
                .safeAreaInset(edge: .bottom, spacing: spacing) { secondaryBar.resizable(axis: .horizontal) }
        case .mixed:
            return page.safeAreaInset(edge: .bottom, spacing: spacing) { primaryBar.resizable(axis: .horizontal) }
                .safeAreaInset(edge: .top, spacing: spacing) { secondaryBar.resizable(axis: .horizontal) }
        }
    }
}

final class SafeAreaInsetBarView: QuickLayoutView, UITextFieldDelegate {
    // 独立装饰层，不参与内容测量，也不改变 safeAreaInset 的预留量。
    let insetBackground = UIView()
    var backgroundBottomExtension: CGFloat = 0 {
        didSet { updateBackgroundFrame() }
    }
    let titleLabel = UILabel()
    let field = UITextField()
    var expanded = false {
        didSet { if expanded != oldValue { invalidateContentLayout() } }
    }
    var showsInput = false {
        didSet { if showsInput != oldValue { invalidateContentLayout() } }
    }

    private func invalidateContentLayout() {
        invalidateIntrinsicContentSize()
        setNeedsQuickLayout()
        superview?.setNeedsLayout()
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        insetBackground.backgroundColor = .tertiarySystemBackground
        insetBackground.isUserInteractionEnabled = false
        insetBackground.accessibilityElementsHidden = true
        addSubview(insetBackground)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityIdentifier = "safeAreaInset.barTitle"
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .done
        field.delegate = self
        field.accessibilityIdentifier = "safeAreaInset.input"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var body: Layout {
        VStack(alignment: .leading, spacing: 10) {
            titleLabel
            if showsInput { field.resizable().frame(minHeight: 44) }
        }.padding(.horizontal, 16).padding(.vertical, expanded ? 30 : 14)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        updateBackgroundFrame()
        sendSubviewToBack(insetBackground)
    }

    private func updateBackgroundFrame() {
        insetBackground.frame = CGRect(
            x: bounds.minX, y: bounds.minY,
            width: bounds.width, height: bounds.height + backgroundBottomExtension
        )
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
