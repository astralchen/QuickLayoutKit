import AppLocalization
import QuickLayoutKit
import UIKit

/// 两种实现使用相同的内容和配置，读数反映当前实际几何。
final class AdaptivePanelExampleViewController: LocalizedQuickLayoutHostingController, UISheetPresentationControllerDelegate {
    override var localizedTitleKey: String? { "demo.adaptivePanel.title" }
    private let engine = UISegmentedControl(items: ["QuickLayoutKit", "UIKit"])
    private let detentControl = UISegmentedControl(items: ["1/3", "medium", "large"])
    private let placementControl = UISegmentedControl(items: ["automatic", "leading", "center", "trailing"])
    private let expandSwitch = UISwitch()
    private let dimSwitch = UISwitch()
    private let expandLabel = UILabel()
    private let dimLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let backgroundButton = UIButton(type: .system)
    private let metrics = UILabel()
    private let pose = UILabel()
    private let scroll = QuickLayoutScrollView()
    private var panel: AdaptivePanelController?
    private var nativeContent: AdaptivePanelExampleContent?
    private var taps = 0
    private var angle: CGFloat?
    private var devicePose: ArrangementDevicePose?
    private var switchingEngine = false
    private var nativeMaximum: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        engine.selectedSegmentIndex = 0
        detentControl.selectedSegmentIndex = 0
        placementControl.selectedSegmentIndex = 0
        expandSwitch.isOn = true
        engine.accessibilityIdentifier = "panel.engine"
        detentControl.accessibilityIdentifier = "panel.detent"
        placementControl.accessibilityIdentifier = "panel.placement"
        openButton.accessibilityIdentifier = "panel.open"
        backgroundButton.accessibilityIdentifier = "panel.background"
        metrics.accessibilityIdentifier = "panel.metrics"
        pose.accessibilityIdentifier = "panel.pose"
        expandSwitch.accessibilityIdentifier = "panel.scrollExpansion"
        dimSwitch.accessibilityIdentifier = "panel.dimming"
        engine.addTarget(self, action: #selector(engineChanged), for: .valueChanged)
        detentControl.addTarget(self, action: #selector(detentChanged), for: .valueChanged)
        placementControl.addTarget(self, action: #selector(configurationChanged), for: .valueChanged)
        expandSwitch.addTarget(self, action: #selector(configurationChanged), for: .valueChanged)
        dimSwitch.addTarget(self, action: #selector(configurationChanged), for: .valueChanged)
        openButton.addTarget(self, action: #selector(openPanel), for: .touchUpInside)
        backgroundButton.addTarget(self, action: #selector(backgroundTapped), for: .touchUpInside)
        openButton.configuration = .filled()
        backgroundButton.configuration = .tinted()
        for label in [expandLabel, dimLabel] {
            label.font = .preferredFont(forTextStyle: .body)
            label.numberOfLines = 0
        }
        for label in [metrics, pose] {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.numberOfLines = 0
        }
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                angle = update.hinge?.angle
                devicePose = update.hinge.map {
                    switch $0.status {
                    case .closed: .closed
                    case .partiallyOpen: .partial
                    case .fullyOpen: .open
                    default: .unknown
                    }
                }
                updatePose()
            })
        }
        #endif
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scroll) {
            VStack(alignment: .leading, spacing: 12) {
                engine.resizable(axis: .horizontal)
                openButton
                backgroundButton
                metrics.resizable(axis: .horizontal)
                pose.resizable(axis: .horizontal)
                detentControl.resizable(axis: .horizontal)
                placementControl.resizable(axis: .horizontal)
                HStack(spacing: 12) { expandLabel; Spacer(); expandSwitch }
                HStack(spacing: 12) { dimLabel; Spacer(); dimSwitch }
            }.padding(.vertical, 16).safeAreaPadding(.horizontal, 16)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        openButton.setTitle(Localization.text("panel.open"), for: .normal)
        backgroundButton.setTitle(Localization.text("panel.background") + " · \(taps)", for: .normal)
        expandLabel.text = Localization.text("panel.scrollExpansion")
        dimLabel.text = Localization.text("panel.dimming")
        expandSwitch.accessibilityLabel = expandLabel.text
        dimSwitch.accessibilityLabel = dimLabel.text
        updatePose()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePose()
        updateNativeMetrics()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.updatePose() }
    }

    private var identifier: AdaptivePanelDetent.Identifier {
        switch detentControl.selectedSegmentIndex {
        case 1: .medium
        case 2: .large
        default: "small"
        }
    }

    /// 系统内建标识使用 UIKit 常量，不能假定它们的 rawValue 等于显示名称。
    private var nativeIdentifier: UISheetPresentationController.Detent.Identifier {
        switch detentControl.selectedSegmentIndex {
        case 1: .medium
        case 2: .large
        default: .init("small")
        }
    }

    private func nativeDetentName(_ identifier: UISheetPresentationController.Detent.Identifier?) -> String {
        if identifier == .medium { return "medium" }
        if identifier == .large { return "large" }
        return identifier?.rawValue ?? "—"
    }

    @objc private func openPanel() {
        guard panel == nil, nativeContent == nil, !switchingEngine else { return }
        let content = AdaptivePanelExampleContent()
        content.onClose = { [weak self] in self?.closePanel() }
        if engine.selectedSegmentIndex == 0 {
            let panel = AdaptivePanelController(contentViewController: content)
            panel.safeAreaSource = .window
            panel.detents = [.custom(identifier: "small") { $0.maximumDetentValue / 3 }, .medium(), .large()]
            panel.selectedDetentIdentifier = identifier
            panel.trackingScrollView = content.tableView
            panel.onDismiss = { [weak self] in self?.panel = nil }
            panel.onSelectedDetentChange = { [weak self] id, _ in self?.updateSelected(id.rawValue) }
            panel.onGeometryChange = { [weak self] _, _ in self?.updatePanelMetrics() }
            self.panel = panel
            configurationChanged()
            // 与系统 presentation 一样使用当前窗口的根容器，避免导航栏把最大档位压缩。
            // 通用组件仍允许调用方明确传入局部容器。
            panel.show(in: view.window?.rootViewController ?? self)
        } else {
            content.modalPresentationStyle = .pageSheet
            nativeContent = content
            if let sheet = content.sheetPresentationController {
                if #available(iOS 16.0, *) {
                    sheet.detents = [.custom(identifier: .init("small")) { [weak self] context in
                        self?.nativeMaximum = context.maximumDetentValue
                        return context.maximumDetentValue / 3
                    }, .medium(), .large()]
                } else {
                    sheet.detents = [.medium(), .large()]
                }
                sheet.selectedDetentIdentifier = nativeIdentifier
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 24
                sheet.prefersEdgeAttachedInCompactHeight = true
                if #available(iOS 17.0, *) { sheet.prefersPageSizing = true }
                sheet.delegate = self
                configurationChanged()
            }
            content.onLayout = { [weak self] in self?.updateNativeMetrics() }
            present(content, animated: true) { [weak self] in self?.updateNativeMetrics() }
        }
    }

    private func closePanel(completion: (() -> Void)? = nil) {
        if let panel {
            panel.dismiss { completion?() }
        } else if nativeContent != nil {
            dismiss(animated: true) { [weak self] in self?.nativeContent = nil; completion?() }
        } else { completion?() }
    }

    @objc private func engineChanged() {
        guard panel != nil || nativeContent != nil else { return }
        switchingEngine = true
        closePanel { [weak self] in
            self?.switchingEngine = false
            self?.openPanel()
        }
    }

    @objc private func backgroundTapped() {
        taps += 1
        backgroundButton.setTitle(Localization.text("panel.background") + " · \(taps)", for: .normal)
    }

    @objc private func detentChanged() {
        panel?.selectDetent(identifier)
        nativeContent?.sheetPresentationController?.animateChanges {
            self.nativeContent?.sheetPresentationController?.selectedDetentIdentifier = self.nativeIdentifier
        }
        updateNativeMetrics()
    }

    @objc private func configurationChanged() {
        if let panel {
            panel.animateChanges {
                panel.prefersScrollingExpandsWhenScrolledToEdge = self.expandSwitch.isOn
                panel.largestUndimmedDetentIdentifier = self.dimSwitch.isOn ? .medium : nil
                panel.preferredPlacement = [.automatic, .leading, .center, .trailing][self.placementControl.selectedSegmentIndex]
            }
        }
        if let sheet = nativeContent?.sheetPresentationController {
            sheet.animateChanges {
                sheet.prefersScrollingExpandsWhenScrolledToEdge = self.expandSwitch.isOn
                sheet.largestUndimmedDetentIdentifier = self.dimSwitch.isOn ? .medium : .large
                #if compiler(>=6.4)
                if #available(iOS 27.0, *) {
                    sheet.preferredPlacement = [.automatic, .leading, .center, .trailing][self.placementControl.selectedSegmentIndex]
                }
                #endif
            }
        }
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        updateSelected(nativeDetentName(sheetPresentationController.selectedDetentIdentifier))
        updateNativeMetrics()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { nativeContent = nil }

    private func updateSelected(_ value: String) {
        detentControl.selectedSegmentIndex = ["small", "medium", "large"].firstIndex(of: value) ?? 0
    }

    private func updatePanelMetrics() {
        guard let panel, let context = panel.context else { return }
        publishMetrics(engine: "QuickLayoutKit", frame: panel.panelFrame, container: context.containerBounds,
                       safeArea: context.safeAreaInsets, region: context.availableRegion,
                       maximum: context.maximumDetentValue, detent: panel.selectedDetentIdentifier?.rawValue,
                       traits: context.containerTraitCollection, content: panel.contentViewController as? AdaptivePanelExampleContent)
    }

    private func updateNativeMetrics() {
        guard let content = nativeContent, content.isViewLoaded, content.view.window != nil,
              let presentation = content.sheetPresentationController, let container = presentation.containerView else { return }
        // 使用系统 presentation container 坐标，避免将内容区域与父页面区域混为一谈。
        let frame = content.view.convert(content.view.bounds, to: container)
        publishMetrics(engine: "UIKit", frame: frame, container: container.bounds,
                       safeArea: container.safeAreaInsets, region: nil, maximum: nativeMaximum,
                       detent: nativeDetentName(presentation.selectedDetentIdentifier),
                       traits: container.traitCollection, content: content)
    }

    /// 诊断信息同时显示在页面和面板内部，展开后也能截图比较。
    private func publishMetrics(engine: String, frame: CGRect, container: CGRect, safeArea: UIEdgeInsets,
                                region: CGRect?, maximum: CGFloat, detent: String?,
                                traits: UITraitCollection, content: AdaptivePanelExampleContent?) {
        func size(_ rect: CGRect) -> String { "\(Int(rect.width))×\(Int(rect.height))" }
        func sizeClass(_ value: UIUserInterfaceSizeClass) -> String {
            switch value { case .compact: "compact"; case .regular: "regular"; case .unspecified: "unspecified"; @unknown default: "unknown" }
        }
        let interfaceOrientation: UIInterfaceOrientation?
        if #available(iOS 16.0, *) {
            interfaceOrientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
        } else {
            interfaceOrientation = view.window?.windowScene?.interfaceOrientation
        }
        let orientation: String
        switch interfaceOrientation {
        case .portrait, .portraitUpsideDown: orientation = "纵屏"
        case .landscapeLeft, .landscapeRight: orientation = "横屏"
        default: orientation = "未知方向"
        }
        let regionText = region.map { "\(Int($0.minX)),\(Int($0.minY)) · \(size($0))" } ?? "UIKit 管理"
        let text = """
        \(engine) · \(detent ?? "—") · \(orientation) · \(poseDescription)
        面板 \(size(frame)) · 容器 \(size(container)) pt
        horizontalSizeClass: \(sizeClass(traits.horizontalSizeClass)) · verticalSizeClass: \(sizeClass(traits.verticalSizeClass))
        位置 \(Int(frame.minX)),\(Int(frame.minY)) · 最大高度 \(Int(maximum))
        安全区 T/L/B/R \(Int(safeArea.top))/\(Int(safeArea.left))/\(Int(safeArea.bottom))/\(Int(safeArea.right))
        可用区域 \(regionText)
        """
        if metrics.text != text { metrics.text = text }
        content?.updateDiagnostics(text, frame: frame, maximum: maximum)
    }

    private var poseDescription: String {
        let name = devicePose?.resolved(in: viewIfLoaded?.window).rawValue ?? "unavailable"
        let degrees = angle.map { String(format: "%.1f°", Double($0 * 180 / .pi)) } ?? "—"
        return "\(name) · 折叠角度 \(degrees)"
    }

    private func updatePose() {
        pose.text = poseDescription
        updatePanelMetrics()
        updateNativeMetrics()
    }

}

/// 两个宿主共用这份内容，包含输入、滚动、选择和关闭操作。
final class AdaptivePanelExampleContent: QuickLayoutHostingController, UITableViewDataSource, UITableViewDelegate {
    let tableView = UITableView()
    private let field = UITextField()
    private let closeButton = UIButton(type: .system)
    private let diagnostics = UILabel()
    var onClose: (() -> Void)?
    var onLayout: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        diagnostics.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        diagnostics.numberOfLines = 0
        diagnostics.textColor = .label
        diagnostics.accessibilityIdentifier = "panel.diagnostics"
        field.borderStyle = .roundedRect
        // 逐键对照时固定输入行为，避免系统补全或组合文本改写测试串。正常示例沿用用户的输入设置。
        if ProcessInfo.processInfo.arguments.contains("-panel-literal-keyboard-input") {
            field.keyboardType = .asciiCapable
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            if #available(iOS 17.0, *) { field.inlinePredictionType = .no }
        }
        field.placeholder = Localization.text("panel.input")
        field.accessibilityIdentifier = "panel.input"
        closeButton.setTitle(Localization.text("panel.close"), for: .normal)
        closeButton.accessibilityIdentifier = "panel.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = .clear
        tableView.accessibilityIdentifier = "panel.list"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    }

    override var body: Layout {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                field.resizable(axis: .horizontal)
                closeButton
            }.frame(height: 40).padding(.horizontal, 16).padding(.top, 8)
            diagnostics.resizable(axis: .horizontal).padding(.horizontal, 16)
            tableView.resizable()
        }
        // 页面浮层的外框可覆盖系统侧栏，输入和关闭操作仍必须避开内容安全区。
        .safeAreaPadding(.horizontal)
    }

    func updateDiagnostics(_ text: String, frame: CGRect, maximum: CGFloat) {
        // 对照测试读取未取整的 pt 值，避免整数显示掩盖外框误差。
        if ProcessInfo.processInfo.arguments.contains("-panel-geometry-measurements") {
            diagnostics.accessibilityValue = [frame.minX, frame.minY, frame.width, frame.height, maximum]
                .map { String(Double($0)) }.joined(separator: ",")
        }
        guard diagnostics.text != text else { return }
        diagnostics.text = text
        viewIfLoaded?.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // windowScene 的方向在转换完成时才稳定，刷新最终尺寸与方向读数。
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.onLayout?() }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = "\(Localization.text("panel.row")) \(indexPath.row + 1)"
        cell.contentConfiguration = configuration
        cell.backgroundColor = .clear
        cell.accessibilityIdentifier = "panel.row.\(indexPath.row)"
        return cell
    }
}
