import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 组合功能区并管理实验状态；组件持有稳定控件，预览使用真实 frame API。
final class FrameLabView: QuickLayoutView {
    let presentation: FrameLabPresentation
    let pageScrollView = QuickLayoutScrollView(.vertical, showsIndicators: false)
    /// 当前页面的实验状态；所有控件操作由页面统一写入，再分发给组件。
    private(set) var state: FrameLabState
    /// 引导实验的参数展开状态，与另一展示模式隔离。
    private(set) var showsMoreParameters = false
    private var savedScrollPosition: CGPoint?
    private var needsScrollRestoration = false

    private let introduction: FrameLabIntroduction
    private let navigation: FrameLabScenarioNavigation
    private let preview: FrameLabPreviewPanel
    private let options: FrameLabOptions
    private let parameters: FrameLabParameters
    private let code: FrameLabCodeCard
    private let surfaces: FrameLabPageSurfaces

    // 保留只读检查入口，底层控件由各自组件持有。
    var previewView: FrameLabPreviewView { preview.preview }
    var codeLabel: UILabel { code.label }
    var metricsLabel: UILabel { preview.metrics }

    init(presentation: FrameLabPresentation = .freeform) {
        self.presentation = presentation
        state = presentation.initialState
        introduction = FrameLabIntroduction(presentation: presentation)
        navigation = FrameLabScenarioNavigation(presentation: presentation)
        preview = FrameLabPreviewPanel(presentation: presentation)
        options = FrameLabOptions(presentation: presentation)
        parameters = FrameLabParameters(presentation: presentation)
        code = FrameLabCodeCard(presentation: presentation)
        surfaces = FrameLabPageSurfaces(presentation: presentation)
        super.init(frame: .zero)
        backgroundColor = .systemGroupedBackground
        tintColor = .systemBlue
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        pageScrollView.quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        pageScrollView.accessibilityIdentifier = "frame.page"
        bindActions()
        reloadLocalizedContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 组件只报告操作意图；弱引用避免页面与组件回调互相持有。
    private func bindActions() {
        navigation.onSelect = { [weak self] in self?.selectScenario($0) }
        navigation.onMove = { [weak self] in self?.moveScenario(by: $0) }
        options.onSelectOption = { [weak self] in self?.selectOption($0) }
        options.onSelectAlignment = { [weak self] in self?.selectAlignment($0) }
        parameters.onWidthChange = { [weak self] in self?.setContainer(widthFraction: $0) }
        parameters.onHeightChange = { [weak self] in self?.setContainer(height: $0) }
        parameters.onStretchChange = { [weak self] in self?.setStretching($0) }
        parameters.onToggleMore = { [weak self] in self?.toggleMoreParameters() }
        preview.onMeasured = { [weak self] in self?.updateMetrics() }
        code.onCopy = { [weak self] in self?.copyCode() }
    }

    override var body: Layout {
        ScrollView(pageScrollView) {
            VStack(alignment: .leading, spacing: 12) {
                if presentation == .freeform {
                    introduction.layout
                    VStack(spacing: 8) {
                        scenarioNavigation
                        experimentOptions
                    }.padding(12).background { surfaces.scenario.resizable() }
                    preview.layout(height: state.containerHeight).padding(12)
                        .background { surfaces.stage.resizable() }
                    VStack(spacing: 4) {
                        parameters.widthLayout
                        parameters.heightLayout
                    }.padding(12).background { surfaces.controls.resizable() }
                    if state.supportsStretching {
                        parameters.stretchingLayout.padding(12).background { surfaces.stretch.resizable() }
                    }
                } else {
                    scenarioNavigation
                    introduction.layout.padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        preview.layout(height: state.containerHeight).padding(.vertical, 4)
                        surfaces.operationDivider.resizable().frame(height: 0.5)
                        options.heading
                        experimentOptions
                        surfaces.heightDivider.resizable().frame(height: 0.5)
                        parameters.heightLayout
                        surfaces.moreDivider.resizable().frame(height: 0.5)
                        parameters.moreLayout
                        if showsMoreParameters {
                            parameters.widthLayout
                            if state.supportsStretching { parameters.stretchingLayout }
                        }
                    }.padding(12).background { surfaces.stage.resizable() }
                }
                code.layout
            }
            .safeAreaPadding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var scenarioNavigation: Layout {
        navigation.layout(accessibilityCategory: traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
    }

    private var experimentOptions: Layout {
        options.layout(scenario: state.scenario, pageWidth: bounds.width,
                       accessibilityCategory: traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
    }

    /// 在页面从布局中移除前记录当前位置。
    func saveScrollPosition() {
        savedScrollPosition = pageScrollView.contentOffset
    }

    /// 延迟到布局后恢复，确保使用当前窗口尺寸下的 contentSize 限制偏移。
    func prepareScrollRestoration() {
        needsScrollRestoration = true
        setNeedsQuickLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pageScrollView.layoutIfNeeded()
        let requested = needsScrollRestoration ? (savedScrollPosition ?? pageScrollView.contentOffset) : pageScrollView.contentOffset
        needsScrollRestoration = false
        let inset = pageScrollView.adjustedContentInset
        // 每次布局都收敛到有效范围，兼顾旋转、字号变化以及内容折叠。
        let maximumY = max(-inset.top, pageScrollView.contentSize.height - pageScrollView.bounds.height + inset.bottom)
        let offset = CGPoint(x: -inset.left, y: min(maximumY, max(-inset.top, requested.y)))
        if pageScrollView.contentOffset != offset { pageScrollView.setContentOffset(offset, animated: false) }
    }

    func toggleMoreParameters() {
        showsMoreParameters.toggle()
        parameters.updateMore(supportsStretching: state.supportsStretching, expanded: showsMoreParameters)
        setNeedsQuickLayout()
    }

    /// 按场景声明顺序前后移动；首尾不循环跳转。
    func moveScenario(by delta: Int) {
        let index = FrameLabScenario.allCases.firstIndex(of: state.scenario)! + delta
        guard FrameLabScenario.allCases.indices.contains(index) else { return }
        selectScenario(FrameLabScenario.allCases[index])
    }

    /// 切换场景时恢复该场景的主要选项和拉伸默认值，保留容器尺寸与对齐位置。
    func selectScenario(_ scenario: FrameLabScenario) {
        state.scenario = scenario
        state.option = scenario == .fixed || scenario == .bounds ? 2 : 0
        state.stretchesContent = scenario == .bounds
        refresh()
    }

    func selectOption(_ index: Int) {
        guard state.scenario.optionKeys.indices.contains(index) else { return }
        state.option = index
        refresh()
    }

    func selectAlignment(_ index: Int) {
        guard FrameLabState.alignments.indices.contains(index) else { return }
        state.alignmentIndex = index
        refresh()
    }

    func setStretching(_ stretches: Bool) {
        guard state.supportsStretching else { return }
        state.stretchesContent = stretches
        refresh()
    }

    /// 更新提供的尺寸，忽略非有限值，并将宽度比例及高度限制到滑块范围。
    func setContainer(widthFraction: CGFloat? = nil, height: CGFloat? = nil) {
        if let widthFraction, widthFraction.isFinite {
            state.widthFraction = (min(1, max(0.5, widthFraction)) * 100).rounded() / 100
        }
        if let height, height.isFinite { state.containerHeight = min(280, max(140, height)).rounded() }
        // 滑块连续变化时只更新尺寸，保留分段选中背景和菜单的呈现状态。
        refreshContainer()
    }

    /// 恢复本模式初始实验并收起更多参数；滚动位置由后续布局限制到有效范围。
    func reset() {
        state = presentation.initialState
        showsMoreParameters = false
        refresh()
    }

    func reloadLocalizedContent() {
        navigation.reloadLocalizedContent()
        preview.reloadLocalizedContent()
        parameters.reloadLocalizedContent()
        code.reloadLocalizedContent()
        refresh()
        updateMetrics()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        let semantic = direction.appLayoutDirection.semanticContentAttribute
        semanticContentAttribute = semantic
        pageScrollView.semanticContentAttribute = semantic
        preview.reloadLayoutDirection(semantic)
        options.reloadLayoutDirection(semantic)
        parameters.reloadLayoutDirection(semantic)
        setNeedsQuickLayout()
    }

    /// 场景、选项或语言变化时刷新全部展示内容；连续尺寸调节不走此路径。
    private func refresh() {
        introduction.update(scenario: state.scenario)
        navigation.update(scenario: state.scenario)
        options.update(state: state)
        parameters.update(stretchesContent: state.stretchesContent,
                          supportsStretching: state.supportsStretching, expanded: showsMoreParameters)
        code.update(state: state)
        refreshContainer()
    }

    /// 尺寸专用刷新路径，避免重建选项、菜单或代码导致拖动期间闪烁。
    private func refreshContainer() {
        parameters.updateContainer(widthFraction: state.widthFraction, height: state.containerHeight)
        preview.updateContainer(state: state)
        setNeedsQuickLayout()
    }

    /// 接收真实布局结果；只有读数或引导提示变化时才请求下一次布局。
    private func updateMetrics() {
        let metricsChanged = preview.updateMetrics(scenario: state.scenario)
        let hintChanged = presentation == .guided && state.scenario == .alignment
            ? introduction.updateMeasuredHint(previewView.sample.bounds.size) : false
        if metricsChanged || hintChanged { setNeedsQuickLayout() }
    }

    private func copyCode() {
        UIPasteboard.general.string = state.code
        code.showCopiedFeedback()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            setNeedsQuickLayout()
        }
    }
}

/// 卡片与分隔线属于页面组合，保持原有布局层级和稳定实例。
@MainActor
private struct FrameLabPageSurfaces {
    let scenario = FrameLabText.surface()
    let stage = FrameLabText.surface(color: .secondarySystemGroupedBackground.withAlphaComponent(0.5))
    let controls = FrameLabText.surface()
    let stretch = FrameLabText.surface()
    let operationDivider = UIView()
    let heightDivider = UIView()
    let moreDivider = UIView()

    init(presentation: FrameLabPresentation) {
        if presentation == .guided {
            stage.backgroundColor = .secondarySystemGroupedBackground
            stage.layer.cornerRadius = 10
            for divider in [operationDivider, heightDivider, moreDivider] { divider.backgroundColor = .separator }
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("页面 · 自由实验") {
    FrameLabView(presentation: .freeform)
}

@available(iOS 17.0, *)
#Preview("页面 · 引导实验／更多参数") {
    let page = FrameLabView(presentation: .guided)
    page.selectScenario(.bounds)
    page.toggleMoreParameters()
    return page
}
#endif
