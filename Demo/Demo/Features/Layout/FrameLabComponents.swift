import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

// 功能组件持有稳定的控件并提供布局片段，不额外增加 UIView 容器层级。
// 实验状态由 FrameLabView 管理，组件只渲染输入并通过回调报告用户操作。

/// 介绍区：自由实验展示通用说明，引导实验展示当前场景的观察任务。
@MainActor
final class FrameLabIntroduction {
    private let presentation: FrameLabPresentation
    private let eyebrow = FrameLabText.make(.caption1, color: .systemBlue)
    private let heading = FrameLabText.make(.title2)
    private let intro = FrameLabText.make(.subheadline, color: .secondaryLabel)

    init(presentation: FrameLabPresentation) {
        self.presentation = presentation
        heading.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 24, weight: .bold))
        eyebrow.text = "QUICKLAYOUTKIT"
        if presentation == .guided {
            heading.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .bold))
        }
    }

    var layout: Layout {
        VStack(alignment: .leading, spacing: 6) {
            if presentation == .freeform { eyebrow }
            heading
            intro
        }.padding(.vertical, 4)
    }

    func update(scenario: FrameLabScenario) {
        heading.text = Localization.text(presentation == .guided ? "frame.guided.\(scenario.rawValue).heading" : "frame.heading")
        intro.text = Localization.text(presentation == .guided ? "frame.guided.\(scenario.rawValue).hint" : "frame.intro")
    }

    /// 用真实内容尺寸替换对齐场景提示；返回文案是否变化，供页面决定是否重排。
    @discardableResult
    func updateMeasuredHint(_ size: CGSize) -> Bool {
        let hint = Localization.text("frame.guided.alignment.size", Int(size.width.rounded()), Int(size.height.rounded()))
        guard intro.text != hint else { return false }
        intro.text = hint
        return true
    }
}

/// 场景导航：封装菜单、计数与前后按钮，通过回调交给页面切换场景。
@MainActor
final class FrameLabScenarioNavigation: NSObject {
    private let presentation: FrameLabPresentation
    private let scenarioButton = UIButton(type: .system)
    private let counter = FrameLabText.make(.subheadline, color: .secondaryLabel)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let counterSurface = FrameLabText.surface(color: .quaternarySystemFill)

    var onSelect: ((FrameLabScenario) -> Void)?
    var onMove: ((Int) -> Void)?

    init(presentation: FrameLabPresentation) {
        self.presentation = presentation
        super.init()
        scenarioButton.configuration = .plain()
        scenarioButton.configuration?.image = UIImage(systemName: "chevron.down")
        scenarioButton.configuration?.imagePlacement = .trailing
        scenarioButton.configuration?.imagePadding = 12
        scenarioButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.foregroundColor = .label
            outgoing.font = .preferredFont(forTextStyle: .headline)
            return outgoing
        }
        scenarioButton.contentHorizontalAlignment = .leading
        scenarioButton.showsMenuAsPrimaryAction = true
        scenarioButton.accessibilityIdentifier = "frame.scenario"
        for (button, symbol, identifier, selector) in [
            (previousButton, "chevron.backward", "frame.previous", #selector(previousScenario)),
            (nextButton, "chevron.forward", "frame.next", #selector(nextScenario)),
        ] {
            button.configuration = .tinted()
            button.configuration?.image = UIImage(systemName: symbol)
            button.accessibilityIdentifier = identifier
            button.addTarget(self, action: selector, for: .touchUpInside)
        }
        if presentation == .guided {
            scenarioButton.configuration?.background.backgroundColor = .secondarySystemGroupedBackground
            scenarioButton.configuration?.background.strokeColor = .separator
            scenarioButton.configuration?.background.strokeWidth = 0.5
            scenarioButton.configuration?.background.cornerRadius = 8
            scenarioButton.configuration?.titleAlignment = .leading
            scenarioButton.contentHorizontalAlignment = .fill
            for button in [previousButton, nextButton] {
                button.configuration?.background.backgroundColor = .secondarySystemGroupedBackground
                button.configuration?.background.strokeColor = .separator
                button.configuration?.background.strokeWidth = 0.5
                button.configuration?.background.cornerRadius = 8
            }
            counterSurface.layer.cornerRadius = 5
        }
    }

    func layout(accessibilityCategory: Bool) -> Layout {
        VStack(spacing: 8) {
            if presentation == .guided && accessibilityCategory {
                scenarioButton.resizable(axis: .horizontal).frame(minHeight: 44)
                HStack(spacing: 8) {
                    previousButton.resizable().frame(width: 44, height: 44)
                    counter.padding(.horizontal, 8).padding(.vertical, 4).background { counterSurface.resizable() }.frame(maxWidth: .infinity)
                    nextButton.resizable().frame(width: 44, height: 44)
                }
            } else {
                HStack(spacing: 8) {
                    scenarioButton.resizable(axis: .horizontal).frame(minHeight: 44)
                    if presentation == .guided { previousButton.resizable().frame(width: 44, height: 44) }
                    if presentation == .guided {
                        counter.padding(.horizontal, 8).padding(.vertical, 4).background { counterSurface.resizable() }
                    } else { counter }
                    if presentation == .guided { nextButton.resizable().frame(width: 44, height: 44) }
                }
            }
        }
    }

    func reloadLocalizedContent() {
        previousButton.accessibilityLabel = Localization.text("frame.previous")
        nextButton.accessibilityLabel = Localization.text("frame.next")
    }

    func update(scenario: FrameLabScenario) {
        scenarioButton.configuration?.title = Localization.text("frame.\(scenario.rawValue).title")
        counter.text = "\(FrameLabScenario.allCases.firstIndex(of: scenario)! + 1) / 6"
        scenarioButton.menu = UIMenu(children: FrameLabScenario.allCases.map { candidate in
            UIAction(title: Localization.text("frame.\(candidate.rawValue).title"),
                     state: candidate == scenario ? .on : .off) { [weak self] _ in self?.onSelect?(candidate) }
        })
        previousButton.isEnabled = scenario != FrameLabScenario.allCases.first
        nextButton.isEnabled = scenario != FrameLabScenario.allCases.last
    }

    @objc private func previousScenario() { onMove?(-1) }
    @objc private func nextScenario() { onMove?(1) }
}

/// 预览区：组合真实布局、边界图例和实测读数，将测量完成事件回传页面。
@MainActor
final class FrameLabPreviewPanel {
    private let presentation: FrameLabPresentation
    private let previewView = FrameLabPreviewView()
    private let metricsLabel = FrameLabText.make(.caption1, color: .secondaryLabel)
    private let containerLegend = FrameLabLegend(color: .secondaryLabel, dashed: true)
    private let frameLegend = FrameLabLegend(color: .systemBlue)
    private let contentLegend = FrameLabLegend(color: .systemOrange, filled: true)
    private let metricsSurface = FrameLabText.surface(color: .tertiarySystemGroupedBackground)
    private lazy var stage = FrameLabPreviewStage(preview: previewView)

    var preview: FrameLabPreviewView { previewView }
    var metrics: UILabel { metricsLabel }
    /// 预览完成布局后调用；回调期间可读取边界尺寸，不应无条件触发重新布局。
    var onMeasured: (() -> Void)?

    init(presentation: FrameLabPresentation) {
        self.presentation = presentation
        metricsLabel.textAlignment = .center
        metricsLabel.accessibilityIdentifier = "frame.metrics"
        previewView.didLayout = { [weak self] in self?.onMeasured?() }
        if presentation == .guided { metricsSurface.layer.cornerRadius = 5 }
    }

    func layout(height: CGFloat) -> Layout {
        VStack(spacing: 8) {
            stage.resizable().frame(height: height)
            HStack(spacing: 16) { containerLegend; frameLegend; contentLegend }
                .frame(maxWidth: .infinity)
            if presentation == .guided {
                metricsLabel.padding(.horizontal, 8).padding(.vertical, 5)
                    .background { metricsSurface.resizable() }.frame(maxWidth: .infinity)
            } else { metricsLabel.frame(maxWidth: .infinity) }
        }
    }

    func reloadLocalizedContent() {
        containerLegend.label.text = Localization.text("frame.container")
        frameLegend.label.text = Localization.text("frame.outer")
        contentLegend.label.text = Localization.text("frame.content")
    }

    func reloadLayoutDirection(_ semantic: UISemanticContentAttribute) {
        for view in [stage, previewView] as [UIView] {
            view.semanticContentAttribute = semantic
            view.setNeedsLayout()
        }
    }

    func updateContainer(state: FrameLabState) {
        stage.widthFraction = state.widthFraction
        previewView.state = state
    }

    /// 根据布局后的 bounds 更新读数；返回值表示文案是否发生变化。
    @discardableResult
    func updateMetrics(scenario: FrameLabScenario) -> Bool {
        let values: [(String, CGSize)] = [
            ("container", previewView.bounds.size), ("outer", previewView.frameMarker.bounds.size),
            ("content", previewView.sample.bounds.size),
        ] + (scenario == .composition ? [("result", previewView.resultMarker.bounds.size)] : [])
        // 用 LTR 隔离符固定“宽 × 高”顺序，避免阿拉伯语重排尺寸数字。
        let text = values.map { key, size in
            Localization.text("frame.\(key)") + " \u{2066}\(Int(size.width.rounded())) × \(Int(size.height.rounded()))\u{2069}"
        }.joined(separator: "  ·  ")
        guard metricsLabel.text != text else { return false }
        metricsLabel.text = text
        return true
    }

}

/// 选项区：复用分段、菜单与九宫格，按展示模式及字号提供相应布局。
@MainActor
final class FrameLabOptions: NSObject {
    private let presentation: FrameLabPresentation
    private let options = UISegmentedControl()
    private let optionMenu = UIButton(type: .system)
    private let alignmentMenu = UIButton(type: .system)
    private let alignmentGrid = FrameLabAlignmentGrid()
    private let alignmentName = FrameLabText.make(.headline, color: .systemBlue)
    private let alignmentTitle = FrameLabText.make(.headline)
    private let alignmentDescription = FrameLabText.make(.subheadline, color: .secondaryLabel)
    private let operationEyebrow = FrameLabText.make(.caption1, color: .secondaryLabel)
    private let operationTitle = FrameLabText.make(.headline)

    var onSelectOption: ((Int) -> Void)?
    var onSelectAlignment: ((Int) -> Void)?

    init(presentation: FrameLabPresentation) {
        self.presentation = presentation
        super.init()
        for button in [optionMenu, alignmentMenu] {
            button.configuration = .tinted()
            button.showsMenuAsPrimaryAction = true
        }
        optionMenu.accessibilityIdentifier = "frame.optionMenu"
        alignmentMenu.accessibilityIdentifier = "frame.alignment"
        alignmentGrid.onSelect = { [weak self] in self?.onSelectAlignment?($0) }
        alignmentName.lineBreakMode = .byCharWrapping
        alignmentName.semanticContentAttribute = .forceLeftToRight
        options.accessibilityIdentifier = "frame.options"
        options.selectedSegmentTintColor = .systemBlue
        options.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        options.addTarget(self, action: #selector(optionChanged), for: .valueChanged)
    }

    var heading: Layout {
        VStack(alignment: .leading, spacing: 4) {
            operationEyebrow
            operationTitle
        }
    }

    /// pageWidth 必须传入页面宽度，不能使用扣除卡片内边距后的选项区宽度。
    @LayoutBuilder func layout(scenario: FrameLabScenario, pageWidth: CGFloat, accessibilityCategory: Bool) -> Layout {
        if scenario == .alignment {
            if presentation == .guided {
                if pageWidth < 360 || accessibilityCategory {
                    VStack(alignment: .leading, spacing: 12) {
                        alignmentGrid.frame(width: 156, height: 156)
                        alignmentText
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        alignmentGrid.frame(width: 156, height: 156)
                        alignmentText.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                alignmentMenu.resizable(axis: .horizontal).frame(minHeight: 44)
            }
        } else if accessibilityCategory {
            optionMenu.resizable(axis: .horizontal).frame(minHeight: 44)
        } else {
            options.resizable(axis: .horizontal).frame(height: 36)
        }
    }

    private var alignmentText: Layout {
        VStack(alignment: .leading, spacing: 8) {
            alignmentName
            alignmentTitle
            alignmentDescription
        }
    }

    func reloadLayoutDirection(_ semantic: UISemanticContentAttribute) {
        alignmentGrid.semanticContentAttribute = semantic
        alignmentGrid.setNeedsLayout()
        alignmentName.semanticContentAttribute = .forceLeftToRight
    }

    func update(state: FrameLabState) {
        let optionTitles = state.scenario.optionKeys.map { Localization.text("frame.option.\($0)") }
        let currentTitles = (0..<options.numberOfSegments).map { options.titleForSegment(at: $0) }
        // 仅在选项文字变化时重建分段，保留连续操作期间的选中背景与视图身份。
        if currentTitles != optionTitles.map(Optional.some) {
            options.removeAllSegments()
            for (index, title) in optionTitles.enumerated() {
                options.insertSegment(withTitle: title, at: index, animated: false)
            }
        }
        if options.selectedSegmentIndex != state.option { options.selectedSegmentIndex = state.option }
        optionMenu.menu = UIMenu(children: state.scenario.optionKeys.enumerated().map { index, key in
            UIAction(title: Localization.text("frame.option.\(key)"), state: state.option == index ? .on : .off) { [weak self] _ in
                self?.onSelectOption?(index)
            }
        })
        if state.scenario.optionKeys.indices.contains(state.option) {
            optionMenu.configuration?.title = Localization.text("frame.option.\(state.scenario.optionKeys[state.option])")
        }
        operationEyebrow.text = ["fixed": "FRAME", "bounds": "MIN / MAX", "ideal": "IDEAL SIZE", "fill": "INFINITY", "alignment": "ALIGNMENT", "composition": "MODIFIER ORDER"][state.scenario.rawValue]
        operationTitle.text = Localization.text(state.scenario == .alignment ? "frame.guided.alignment.operation" : "frame.guided.operation")
        alignmentGrid.update(selectedIndex: state.alignmentIndex)
        alignmentName.text = "." + FrameLabState.alignmentNames[state.alignmentIndex]
        alignmentTitle.text = Localization.text("frame.alignment.\(FrameLabState.alignmentNames[state.alignmentIndex])")
        alignmentDescription.text = Localization.text("frame.guided.alignment.hint")
        alignmentMenu.configuration?.title = "." + FrameLabState.alignmentNames[state.alignmentIndex]
        alignmentMenu.menu = UIMenu(children: FrameLabState.alignmentNames.enumerated().map { index, name in
            UIAction(title: Localization.text("frame.alignment.\(name)"),
                     state: state.alignmentIndex == index ? .on : .off) { [weak self] _ in self?.onSelectAlignment?(index) }
        })
    }

    @objc private func optionChanged() { onSelectOption?(options.selectedSegmentIndex) }
}

/// 参数区：提供可分别插入页面的布局片段，适配两种模式的参数排列顺序。
@MainActor
final class FrameLabParameters: NSObject {
    private let moreButton = UIButton(type: .system)
    private let widthControl = FrameLabSliderRow(minimum: 0.5, maximum: 1, identifier: "frame.width")
    private let heightControl = FrameLabSliderRow(minimum: 140, maximum: 280, identifier: "frame.height")
    private let stretchLabel = FrameLabText.make(.body)
    private let stretchSwitch = UISwitch()

    var onWidthChange: ((CGFloat) -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var onStretchChange: ((Bool) -> Void)?
    var onToggleMore: (() -> Void)?

    init(presentation: FrameLabPresentation) {
        super.init()
        moreButton.configuration = .plain()
        moreButton.configuration?.imagePlacement = .trailing
        moreButton.configuration?.imagePadding = 8
        moreButton.configuration?.titleAlignment = .leading
        moreButton.contentHorizontalAlignment = .fill
        moreButton.accessibilityIdentifier = "frame.more"
        moreButton.addTarget(self, action: #selector(toggleMoreParameters), for: .touchUpInside)
        stretchSwitch.accessibilityIdentifier = "frame.stretch"
        stretchSwitch.addTarget(self, action: #selector(stretchChanged), for: .valueChanged)
        widthControl.onChange = { [weak self] in self?.onWidthChange?($0) }
        heightControl.onChange = { [weak self] in self?.onHeightChange?($0) }
        if presentation == .guided {
            heightControl.showsRange = true
            heightControl.title.font = .preferredFont(forTextStyle: .headline)
            moreButton.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.foregroundColor = .label
                outgoing.font = .preferredFont(forTextStyle: .headline)
                return outgoing
            }
            moreButton.configuration?.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.foregroundColor = .secondaryLabel
                outgoing.font = .preferredFont(forTextStyle: .footnote)
                return outgoing
            }
            moreButton.configuration?.titlePadding = 4
        }
    }

    // 各片段复用同一组控件；高度、宽度与拉伸无需放进一个额外容器。
    @LayoutBuilder var widthLayout: Layout { widthControl }
    @LayoutBuilder var heightLayout: Layout { heightControl }
    var moreLayout: Layout { moreButton.resizable(axis: .horizontal).frame(minHeight: 52) }

    var stretchingLayout: Layout {
        HStack(spacing: 12) {
            stretchLabel.frame(maxWidth: .infinity, alignment: .leading)
            stretchSwitch
        }
    }

    func reloadLocalizedContent() {
        widthControl.title.text = Localization.text("frame.width")
        heightControl.title.text = Localization.text("frame.height")
        widthControl.slider.accessibilityLabel = widthControl.title.text
        heightControl.slider.accessibilityLabel = heightControl.title.text
        stretchLabel.text = Localization.text("frame.stretch")
        stretchSwitch.accessibilityLabel = stretchLabel.text
    }

    func reloadLayoutDirection(_ semantic: UISemanticContentAttribute) {
        for view in [widthControl, heightControl] {
            view.semanticContentAttribute = semantic
            view.setNeedsLayout()
        }
    }

    func update(stretchesContent: Bool, supportsStretching: Bool, expanded: Bool) {
        stretchSwitch.setOn(stretchesContent, animated: false)
        updateMore(supportsStretching: supportsStretching, expanded: expanded)
    }

    func updateMore(supportsStretching: Bool, expanded: Bool) {
        moreButton.configuration?.title = Localization.text("frame.more")
        moreButton.configuration?.subtitle = Localization.text(supportsStretching ? "frame.more.stretching" : "frame.more.width")
        moreButton.configuration?.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.forward")
        moreButton.accessibilityValue = Localization.text(expanded ? "frame.expanded" : "frame.collapsed")
    }

    /// 同步滑块、显示值和可访问值；程序赋值不会触发用户操作回调。
    func updateContainer(widthFraction: CGFloat, height: CGFloat) {
        widthControl.slider.value = Float(widthFraction)
        widthControl.value.text = Localization.percent(Double(widthFraction))
        widthControl.slider.accessibilityValue = widthControl.value.text
        heightControl.slider.value = Float(height)
        heightControl.value.text = "\(Int(height)) pt"
        heightControl.slider.accessibilityValue = heightControl.value.text
    }

    @objc private func stretchChanged() { onStretchChange?(stretchSwitch.isOn) }
    @objc private func toggleMoreParameters() { onToggleMore?() }
}

/// 代码卡片：渲染代码与复制反馈；实际复制的数据由页面当前状态提供。
@MainActor
final class FrameLabCodeCard: NSObject {
    private let presentation: FrameLabPresentation
    private let codeLabel = FrameLabText.make(.footnote)
    private let codeTitle = FrameLabText.make(.caption1, color: .secondaryLabel)
    private let copyButton = UIButton(type: .system)
    private let explanation = FrameLabText.make(.footnote, color: .secondaryLabel)
    private let codeSurface = FrameLabText.surface(color: .tertiarySystemGroupedBackground)
    private let codeInsetSurface = FrameLabText.surface()

    var label: UILabel { codeLabel }
    var onCopy: (() -> Void)?

    init(presentation: FrameLabPresentation) {
        self.presentation = presentation
        super.init()
        copyButton.configuration = .plain()
        copyButton.configuration?.image = UIImage(systemName: "doc.on.doc")
        copyButton.accessibilityValue = nil
        copyButton.accessibilityIdentifier = "frame.copy"
        copyButton.addTarget(self, action: #selector(copyCode), for: .touchUpInside)
        codeLabel.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .medium))
        codeLabel.textColor = .systemIndigo
        codeLabel.lineBreakMode = .byCharWrapping
        codeLabel.textAlignment = .left
        codeLabel.semanticContentAttribute = .forceLeftToRight
        codeLabel.accessibilityIdentifier = "frame.code"
        if presentation == .guided {
            codeSurface.backgroundColor = .secondarySystemGroupedBackground
            codeSurface.layer.cornerRadius = 10
            codeInsetSurface.backgroundColor = .tertiarySystemGroupedBackground
            codeInsetSurface.layer.cornerRadius = 6
        }
    }

    var layout: Layout {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                codeTitle.frame(maxWidth: .infinity, alignment: .leading)
                copyButton.resizable().frame(width: 44, height: 44)
            }
            codeLabel.frame(maxWidth: .infinity, alignment: .leading)
                .padding(12).background { codeInsetSurface.resizable() }
            if presentation == .freeform { explanation }
        }.padding(12).background { codeSurface.resizable() }
    }

    func reloadLocalizedContent() {
        codeTitle.text = Localization.text("frame.code")
        copyButton.accessibilityLabel = Localization.text("frame.copy")
    }

    func update(state: FrameLabState) {
        let code = NSMutableAttributedString(string: state.code, attributes: [.foregroundColor: UIColor.label])
        if let expression = try? NSRegularExpression(pattern: #"\b\d+\b|\.infinity|\.topLeading|\.topTrailing|\.bottomLeading|\.bottomTrailing|\.leading|\.trailing|\.center|\.top|\.bottom"#) {
            for match in expression.matches(in: state.code, range: NSRange(location: 0, length: code.length)) {
                code.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: match.range)
            }
        }
        codeLabel.attributedText = code
        explanation.text = Localization.text("frame.\(state.scenario.rawValue).detail")
        copyButton.configuration?.image = UIImage(systemName: "doc.on.doc")
        copyButton.accessibilityValue = nil
    }

    /// 页面写入剪贴板后调用，更新图标并向辅助功能播报复制成功。
    func showCopiedFeedback() {
        copyButton.configuration?.image = UIImage(systemName: "checkmark")
        copyButton.accessibilityValue = Localization.text("frame.copied")
        UIAccessibility.post(notification: .announcement, argument: Localization.text("frame.copied"))
    }

    @objc private func copyCode() { onCopy?() }
}

/// 九个按钮固定创建一次；选择与语言变化仅更新按钮状态和可访问名称。
private final class FrameLabAlignmentGrid: QuickLayoutView {
    private let buttons = (0..<9).map { FrameLabAlignmentButton(index: $0) }
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "frame.alignmentGrid"
        for button in buttons {
            button.addTarget(self, action: #selector(selected(_:)), for: .touchUpInside)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        VStack(spacing: 6) {
            for row in 0..<3 {
                HStack(spacing: 6) {
                    for column in 0..<3 { buttons[row * 3 + column].resizable().frame(width: 48, height: 48) }
                }
            }
        }
    }

    func update(selectedIndex: Int) {
        for (index, button) in buttons.enumerated() {
            button.isSelected = index == selectedIndex
            button.accessibilityLabel = Localization.text("frame.alignment.\(FrameLabState.alignmentNames[index])")
        }
    }

    @objc private func selected(_ button: UIButton) { onSelect?(button.tag) }
}

/// 以圆点位置表达对齐方向；逻辑前缘／后缘在 RTL 下镜像显示。
private final class FrameLabAlignmentButton: UIButton {
    private let dot = UIView()

    init(index: Int) {
        super.init(frame: .zero)
        tag = index
        accessibilityIdentifier = "frame.alignment.\(FrameLabState.alignmentNames[index])"
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        dot.layer.cornerRadius = 4
        dot.isUserInteractionEnabled = false
        addSubview(dot)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isSelected: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    private func updateAppearance() {
        backgroundColor = isSelected ? .systemBlue.withAlphaComponent(0.12) : .tertiarySystemFill
        layer.borderColor = (isSelected ? UIColor.systemBlue : .separator).resolvedColor(with: traitCollection).cgColor
        dot.backgroundColor = isSelected ? .systemBlue : .secondaryLabel
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let column = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 2 - tag % 3 : tag % 3
        dot.frame = CGRect(x: 10 + CGFloat(column) * (bounds.width - 28) / 2,
                           y: 10 + CGFloat(tag / 3) * (bounds.height - 28) / 2, width: 8, height: 8)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }
}

/// 将页面提供的宽度比例应用到可用容器宽度，保持预览在舞台中居中。
private final class FrameLabPreviewStage: QuickLayoutView {
    let preview: FrameLabPreviewView
    var widthFraction: CGFloat = 1 { didSet { setNeedsQuickLayout() } }

    init(preview: FrameLabPreviewView) {
        self.preview = preview
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        let fraction = widthFraction
        return preview.resizable().containerRelativeFrame(.horizontal) { width, _ in width * fraction }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 边界图例：虚线表示容器，蓝色表示 frame，橙色填充表示内容。
private final class FrameLabLegend: QuickLayoutView {
    let label = FrameLabText.make(.caption1, color: .secondaryLabel)
    let marker: FrameLabBoundaryView

    init(color: UIColor, dashed: Bool = false, filled: Bool = false) {
        marker = FrameLabBoundaryView(color: color, dashed: dashed)
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        if filled { marker.backgroundColor = color.withAlphaComponent(0.25) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var body: Layout { HStack(spacing: 6) { marker.frame(width: 16, height: 16); label } }
}

/// 参数滑块行：显示标题、当前值和可选范围；辅助功能字号下改为纵向布局。
private final class FrameLabSliderRow: QuickLayoutView {
    let title = FrameLabText.make(.subheadline)
    let value = FrameLabText.make(.subheadline, color: .secondaryLabel)
    let slider = UISlider()
    var onChange: ((CGFloat) -> Void)?
    var showsRange = false
    private let minimumLabel = FrameLabText.make(.caption1, color: .secondaryLabel)
    private let maximumLabel = FrameLabText.make(.caption1, color: .secondaryLabel)

    init(minimum: Float, maximum: Float, identifier: String) {
        super.init(frame: .zero)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        slider.minimumValue = minimum
        slider.maximumValue = maximum
        minimumLabel.text = String(Int(minimum))
        maximumLabel.text = String(Int(maximum))
        slider.accessibilityIdentifier = identifier
        slider.addTarget(self, action: #selector(changed), for: .valueChanged)
        value.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 14, weight: .regular))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            VStack(alignment: .leading, spacing: 4) {
                title
                value
                sliderColumn
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                title.frame(width: 76, alignment: .leading).padding(.top, 12)
                sliderColumn
                value.frame(width: 60, alignment: .trailing).padding(.top, 12)
            }
        }
    }

    private var sliderColumn: Layout {
        VStack(spacing: 0) {
            slider.resizable().frame(height: 44)
            if showsRange {
                HStack {
                    minimumLabel.frame(maxWidth: .infinity, alignment: .leading)
                    maximumLabel
                }
            }
        }
    }

    @objc private func changed() { onChange?(CGFloat(slider.value)) }
}

/// 本页文字与卡片的统一样式工厂，使用动态字体及系统语义颜色。
@MainActor
enum FrameLabText {
    static func make(_ style: UIFont.TextStyle, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    static func surface(color: UIColor = .secondarySystemGroupedBackground) -> UIView {
        let view = UIView()
        view.backgroundColor = color
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }
}

#if DEBUG
/// 为组件布局片段提供真实画布宽度与字号环境，不复制整页的实验协调逻辑。
private final class FrameLabComponentPreview: QuickLayoutView {
    private let content: (CGFloat, Bool) -> Layout

    init(@LayoutBuilder content: @escaping (CGFloat, Bool) -> Layout) {
        self.content = content
        super.init(frame: .zero)
        backgroundColor = .systemGroupedBackground
        tintColor = .systemBlue
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var body: Layout {
        content(bounds.width, traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@available(iOS 17.0, *)
#Preview("组件 · 实验介绍") {
    let introduction = FrameLabIntroduction(presentation: .guided)
    introduction.update(scenario: .composition)
    return FrameLabComponentPreview { _, _ in introduction.layout }
}

@available(iOS 17.0, *)
#Preview("组件 · 场景导航") {
    let navigation = FrameLabScenarioNavigation(presentation: .guided)
    var scenario = FrameLabScenario.alignment
    navigation.reloadLocalizedContent()
    navigation.update(scenario: scenario)
    let host = FrameLabComponentPreview { _, accessibility in
        navigation.layout(accessibilityCategory: accessibility)
    }
    navigation.onSelect = { [weak navigation, weak host] in
        scenario = $0
        navigation?.update(scenario: scenario)
        host?.setNeedsQuickLayout()
    }
    navigation.onMove = { [weak navigation, weak host] delta in
        let index = FrameLabScenario.allCases.firstIndex(of: scenario)! + delta
        guard FrameLabScenario.allCases.indices.contains(index) else { return }
        scenario = FrameLabScenario.allCases[index]
        navigation?.update(scenario: scenario)
        host?.setNeedsQuickLayout()
    }
    return host
}

@available(iOS 17.0, *)
#Preview("组件 · 预览与实测尺寸") {
    let preview = FrameLabPreviewPanel(presentation: .guided)
    let state = FrameLabPresentation.guided.initialState
    preview.reloadLocalizedContent()
    preview.updateContainer(state: state)
    let host = FrameLabComponentPreview { _, _ in preview.layout(height: state.containerHeight) }
    preview.onMeasured = { [weak preview, weak host] in
        if preview?.updateMetrics(scenario: state.scenario) == true { host?.setNeedsQuickLayout() }
    }
    return host
}

@available(iOS 17.0, *)
#Preview("组件 · 九宫格对齐") {
    let options = FrameLabOptions(presentation: .guided)
    var state = FrameLabPresentation.guided.initialState
    options.update(state: state)
    let host = FrameLabComponentPreview { width, accessibility in
        VStack(alignment: .leading, spacing: 12) {
            options.heading
            options.layout(scenario: state.scenario, pageWidth: width, accessibilityCategory: accessibility)
        }
    }
    options.onSelectAlignment = { [weak options, weak host] in
        state.alignmentIndex = $0
        options?.update(state: state)
        host?.setNeedsQuickLayout()
    }
    return host
}

@available(iOS 17.0, *)
#Preview("组件 · 分段与大字号菜单") {
    let options = FrameLabOptions(presentation: .freeform)
    var state = FrameLabState()
    options.update(state: state)
    let host = FrameLabComponentPreview { width, accessibility in
        options.layout(scenario: state.scenario, pageWidth: width, accessibilityCategory: accessibility)
    }
    options.onSelectOption = { [weak options, weak host] in
        state.option = $0
        options?.update(state: state)
        host?.setNeedsQuickLayout()
    }
    return host
}

@available(iOS 17.0, *)
#Preview("组件 · 尺寸与更多参数") {
    let parameters = FrameLabParameters(presentation: .guided)
    var state = FrameLabState()
    var expanded = true
    parameters.reloadLocalizedContent()
    parameters.update(stretchesContent: state.stretchesContent, supportsStretching: true, expanded: expanded)
    parameters.updateContainer(widthFraction: state.widthFraction, height: state.containerHeight)
    let host = FrameLabComponentPreview { _, _ in
        VStack(spacing: 12) {
            parameters.heightLayout
            parameters.moreLayout
            if expanded {
                parameters.widthLayout
                parameters.stretchingLayout
            }
        }
    }
    parameters.onWidthChange = { [weak parameters, weak host] in
        state.widthFraction = ($0 * 100).rounded() / 100
        parameters?.updateContainer(widthFraction: state.widthFraction, height: state.containerHeight)
        host?.setNeedsQuickLayout()
    }
    parameters.onHeightChange = { [weak parameters, weak host] in
        state.containerHeight = $0.rounded()
        parameters?.updateContainer(widthFraction: state.widthFraction, height: state.containerHeight)
        host?.setNeedsQuickLayout()
    }
    parameters.onStretchChange = { state.stretchesContent = $0 }
    parameters.onToggleMore = { [weak parameters, weak host] in
        expanded.toggle()
        parameters?.updateMore(supportsStretching: true, expanded: expanded)
        host?.setNeedsQuickLayout()
    }
    return host
}

@available(iOS 17.0, *)
#Preview("组件 · 代码卡片") {
    let code = FrameLabCodeCard(presentation: .freeform)
    var state = FrameLabState()
    state.scenario = .composition
    state.option = 2
    code.reloadLocalizedContent()
    code.update(state: state)
    code.onCopy = { [weak code] in
        UIPasteboard.general.string = state.code
        code?.showCopiedFeedback()
    }
    return FrameLabComponentPreview { _, _ in code.layout }
}
#endif
