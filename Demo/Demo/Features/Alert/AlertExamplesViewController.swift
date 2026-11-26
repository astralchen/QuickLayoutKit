import AppLocalization
import ListKit
import QuickLayoutKit
import UIKit

@MainActor
final class AlertExamplesViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.alertExamples.title" }

    enum Example: String, CaseIterable {
        case simple, images, textField, login, date, calendar, height, country, phone, currency
        case imagePicker, photoLibrary, color, text, contacts, location, attachments, longMessage, richText

        @MainActor var title: String {
            Localization.text("demo.alertExamples.example." + rawValue)
        }

        var symbol: String {
            switch self {
            case .simple: "exclamationmark.bubble"
            case .images: "sparkles"
            case .textField: "character.cursor.ibeam"
            case .login: "lock"
            case .date: "calendar"
            case .calendar: "calendar.badge.clock"
            case .height: "ruler"
            case .country: "globe"
            case .phone: "phone"
            case .currency: "banknote"
            case .imagePicker: "photo.on.rectangle"
            case .photoLibrary: "photo.stack"
            case .color: "paintpalette"
            case .text: "text.alignleft"
            case .contacts: "person.crop.rectangle"
            case .location: "map"
            case .attachments: "paperclip"
            case .longMessage: "text.bubble"
            case .richText: "textformat"
            }
        }
    }

    enum ImageMode: String, CaseIterable {
        case grid
        case pages
        case multiple
    }

    struct Scenario {
        var title: String?
        var message: String?
        var detailMessage: String?
        var attributedTitle: NSAttributedString?
        var attributedMessage: NSAttributedString?
        var titleMaximumLineCount: Int?
        var titleLineBreakMode: NSLineBreakMode?
        var header: UIViewController?
        var content: UIViewController?
        var usesSizeThatFits = false
        var actions: [AlertAction] = []
        var preferredAction: AlertAction?
    }

    private let engine = UISegmentedControl(items: ["QuickLayoutKit", "UIKit"])
    private let style = UISegmentedControl(items: ["", ""])
    private let anchor = UISegmentedControl(items: ["", ""])
    private let result = LocalizedLabel()
    private let measurements = LocalizedLabel()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private lazy var adapter = TableListAdapter<Int>(tableView: table)
    private let examples = Example.allCases.filter { example in
        if #available(iOS 16, *) { return true }
        return example != .calendar
    }
    private weak var activeAlert: UIViewController?
    private var hasResult = false

    #if DEBUG
    private var initialPreview: (example: Example, style: UIAlertController.Style, imageMode: ImageMode, useUIKit: Bool)?

    static func preview(
        _ example: Example, style: UIAlertController.Style = .alert,
        imageMode: ImageMode = .grid, useUIKit: Bool = false
    ) -> UINavigationController {
        let screen = AlertExamplesViewController()
        screen.initialPreview = (example, style, imageMode, useUIKit)
        return UINavigationController(rootViewController: screen)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let preview = initialPreview else { return }
        initialPreview = nil
        engine.selectedSegmentIndex = preview.useUIKit ? 1 : 0
        style.selectedSegmentIndex = preview.style == .actionSheet ? 1 : 0
        updateControls()
        view.layoutIfNeeded()
        // 优先使用实际示例行作锚点；首次列表快照尚未就绪时使用可见的样式控件。
        var source: UIView = style
        if preview.style == .actionSheet, let row = examples.firstIndex(of: preview.example),
           table.numberOfSections > 0, row < table.numberOfRows(inSection: 0) {
            let path = IndexPath(row: row, section: 0)
            table.scrollToRow(at: path, at: .none, animated: false)
            table.layoutIfNeeded()
            source = table.cellForRow(at: path) ?? style
        }
        UIView.performWithoutAnimation {
            show(preview.example, anchor: source, imageMode: preview.imageMode)
        }
    }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        engine.accessibilityIdentifier = "alerts.engine"
        style.accessibilityIdentifier = "alerts.style"
        anchor.accessibilityIdentifier = "alerts.anchor"
        engine.selectedSegmentIndex = 0
        style.selectedSegmentIndex = 0
        anchor.selectedSegmentIndex = 1
        for control in [style, engine] {
            control.addAction(UIAction { [weak self] _ in self?.updateControls() }, for: .valueChanged)
        }

        result.font = .preferredFont(forTextStyle: .footnote)
        result.adjustsFontForContentSizeCategory = true
        result.numberOfLines = 2
        result.accessibilityIdentifier = "alerts.result"
        measurements.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        measurements.textColor = .secondaryLabel
        measurements.numberOfLines = 2
        measurements.accessibilityIdentifier = "alerts.measurements"
        measurements.text = " "
        table.accessibilityIdentifier = "alerts.examples"
        updateControls()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        style.setTitle(Localization.text("demo.alertExamples.style.alert"), forSegmentAt: 0)
        style.setTitle(Localization.text("demo.alertExamples.style.actionSheet"), forSegmentAt: 1)
        anchor.setTitle(Localization.text("demo.alertExamples.anchor.none"), forSegmentAt: 0)
        anchor.setTitle(Localization.text("demo.alertExamples.anchor.popover"), forSegmentAt: 1)
        if !hasResult { result.text = Localization.text("demo.alertExamples.choose") }
        renderExamples()
    }

    override var body: Layout {
        let margins = view.directionalLayoutMargins
        return VStack(spacing: 0) {
            VStack(spacing: 8) {
                engine.resizable(axis: .horizontal)
                style.resizable(axis: .horizontal)
                if !anchor.isHidden { anchor.resizable(axis: .horizontal) }
            }
            .padding(.leading, margins.leading)
            .padding(.trailing, margins.trailing)
            .padding(.top, 8)
            .padding(.bottom, 4)
            table.resizable()
            VStack(alignment: .leading, spacing: 4) {
                result.resizable(axis: .horizontal).frame(minHeight: 2 * result.font.lineHeight)
                measurements.resizable().frame(height: 2 * measurements.font.lineHeight)
            }
            .padding(.leading, margins.leading)
            .padding(.trailing, margins.trailing)
            .padding(.bottom, 6)
        }
        .safeAreaPadding(.vertical)
    }

    private func updateControls() {
        anchor.isHidden = style.selectedSegmentIndex == 0
        let requiresAnchor = engine.selectedSegmentIndex == 1 && traitCollection.userInterfaceIdiom == .pad
        anchor.setEnabled(!requiresAnchor, forSegmentAt: 0)
        if requiresAnchor { anchor.selectedSegmentIndex = 1 }
        setNeedsQuickLayout()
    }

    private func renderExamples() {
        let locale = Localization.localizationController.locale.identifier
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                TableForEach(examples, id: \.rawValue) { example in
                    TableRow(model: example, cell: UITableViewCell.self) { [weak self] cell, example, _ in
                        self?.configure(cell, for: example)
                    }
                    .refreshID(locale)
                    .onSelect { [weak self] example, context in
                        let table = context.tableView
                        table.deselectRow(at: context.indexPath, animated: true)
                        if let cell = table.cellForRow(at: context.indexPath) {
                            self?.show(example, anchor: cell)
                        }
                    }
                }
            }
            .selectionMode(.single)
        }
    }

    private func configure(_ cell: UITableViewCell, for example: Example) {
        var content = cell.defaultContentConfiguration()
        content.text = example.title
        content.image = UIImage(systemName: example.symbol)
        content.imageProperties.tintColor = .systemBlue
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "alerts.demo.\(example.rawValue)"
        if example == .imagePicker {
            let options = UIButton(type: .system)
            options.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
            options.accessibilityLabel = Localization.text("demo.alertExamples.images.options")
            options.accessibilityIdentifier = "alerts.imageModes"
            options.frame.size = CGSize(width: 44, height: 44)
            options.menu = UIMenu(children: ImageMode.allCases.map { mode in
                UIAction(title: Localization.text("demo.alertExamples.imageMode." + mode.rawValue)) { [weak self, weak cell] _ in
                    guard let cell else { return }
                    self?.show(.imagePicker, anchor: cell, imageMode: mode)
                }
            })
            options.showsMenuAsPrimaryAction = true
            cell.accessoryView = options
        } else {
            cell.accessoryView = nil
            cell.accessoryType = .disclosureIndicator
        }
    }

    private func show(_ example: Example, anchor source: UIView, imageMode: ImageMode = .grid) {
        guard presentedViewController == nil else { return }
        let style: UIAlertController.Style = style.selectedSegmentIndex == 0 ? .alert : .actionSheet
        let anchored = style == .actionSheet && anchor.selectedSegmentIndex == 1
        var scenario = scenario(for: example, imageMode: imageMode, usesPopover: anchored, style: style)
        if #available(iOS 26, *), anchored, engine.selectedSegmentIndex == 1, example == .longMessage {
            // 为正文单独限制滚动视口的高度，给原生 Popover 的操作按钮留出空间。
            scenario.message = nil
            scenario.content = AlertExampleContent(AlertExampleTextView(presentingView: view, usesMessageStyle: true))
            scenario.usesSizeThatFits = true
        }
        let semantic = Localization.currentUIKitUpdate.semanticContentAttribute
        if #unavailable(iOS 17) {
            if let header = scenario.header { Localization.applyBoundary(semantic, to: header.view) }
            if let content = scenario.content { Localization.applyBoundary(semantic, to: content.view) }
        }
        measurements.text = " "
        report(example.title)
        if engine.selectedSegmentIndex == 0 {
            let alert = makeAlert(scenario, style: style, source: anchored ? source : nil)
            activeAlert = alert
            alert.prepareForPresentation(from: self)
            let plannedGuide = alert.contentViewControllerLayoutGuide.layoutFrame.size
            present(alert, animated: true) { [weak self, weak alert] in
                guard let alert else { return }
                if let fields = alert.textFields, !fields.isEmpty {
                    self?.showTextFieldMeasurements(fields, engine: "QuickLayoutKit")
                    return
                }
                guard let entrance = alert.entranceLayoutSnapshot, let current = alert.layoutSnapshot else { return }
                let guide = alert.contentViewControllerLayoutGuide.layoutFrame.size
                self?.showMeasurements(
                    "Entry \(Self.dimensions(entrance.contentSize)) · Planned \(Self.dimensions(plannedGuide))\nGuide \(Self.dimensions(guide)) · Panel \(Self.dimensions(current.panelSize))"
                )
            }
        } else {
            presentNative(scenario, style: style, source: anchored ? source : nil)
        }
    }

    func makeAlert(_ scenario: Scenario, style: UIAlertController.Style, source: UIView?) -> AlertController {
        let alert = AlertController(title: scenario.title, message: scenario.message, preferredStyle: style)
        alert.detailMessage = scenario.detailMessage
        alert.attributedTitle = scenario.attributedTitle
        alert.attributedMessage = scenario.attributedMessage
        if let count = scenario.titleMaximumLineCount { alert.titleMaximumLineCount = count }
        alert.titleLineBreakMode = scenario.titleLineBreakMode
        alert.contentSizing = scenario.usesSizeThatFits ? .sizeThatFits : .automatic
        alert.headerContentViewController = scenario.header
        if style == .alert, let form = scenario.content as? AlertExampleFields {
            form.addTextFields(to: alert)
        } else {
            alert.contentViewController = scenario.content
        }
        scenario.actions.forEach(alert.addAction)
        alert.preferredAction = scenario.preferredAction
        if let source {
            alert.setPopoverAnchor(source)
            if #available(iOS 26, *), scenario.content != nil || scenario.header != nil {
                // UIKit 的 Popover 优先使用嵌入控制器声明的宽度，例如颜色和附件选择器。
                alert.panelWidth = .content
            }
        }
        return alert
    }

    // 私有 UIKit 属性只用于 Demo，让两种弹窗可以显示同一份示例内容。
    func makeNativeAlert(_ scenario: Scenario, style: UIAlertController.Style, source: UIView?) -> (UIAlertController, CGFloat?) {
        let alert = UIAlertController(title: scenario.title, message: scenario.message, preferredStyle: style)
        setNativeValue(scenario.attributedTitle, key: "attributedTitle", on: alert)
        setNativeValue(scenario.attributedMessage, key: "attributedMessage", on: alert)
        if let detail = scenario.detailMessage {
            setNativeValue(NSAttributedString(string: detail), key: "attributedDetailMessage", on: alert)
        }
        setNativeValue(scenario.titleMaximumLineCount, key: "titleMaximumLineCount", on: alert)
        setNativeValue(scenario.titleLineBreakMode?.rawValue, key: "titleLineBreakMode", on: alert)
        setNativeValue(scenario.header, key: "headerContentViewController", on: alert)
        if style == .alert, let fields = scenario.content as? AlertExampleFields {
            // 让 UIKit 管理原生输入框的高度和焦点。
            fields.addNativeTextFields(to: alert)
        } else if let content = scenario.content, alert.responds(to: NSSelectorFromString("setContentViewController:")) {
            // 锚定浮层的宽度由 UIKit 协商，键盘出现时面板可能比初始尺寸更窄。
            if #available(iOS 26, *), style == .actionSheet, source == nil, let form = content as? AlertExampleFields {
                let layout = AlertController(preferredStyle: style)
                if let panelWidth = layout.prepareForPresentation(from: self)?.panelSize.width {
                    form.prepareForNativeActionSheet(panelWidth: panelWidth)
                }
            }
            alert.setValue(content, forKey: "contentViewController")
        }
        for action in scenario.actions {
            let title = action.attributedTitle.map { String($0.characters) } ?? action.title
            let native = UIAlertAction(title: title, style: action.style) { _ in action.perform() }
            native.isEnabled = action.isEnabled
            native.accessibilityIdentifier = action.accessibilityIdentifier
            setNativeValue(action.titleTextAlignment?.rawValue, key: "titleTextAlignment", on: native)
            if let image = action.image, native.responds(to: NSSelectorFromString("setImage:")) {
                native.setValue(image, forKey: "image")
            }
            if let color = action.titleColor, native.responds(to: NSSelectorFromString("setTitleTextColor:")) {
                native.setValue(color, forKey: "titleTextColor")
            }
            alert.addAction(native)
            if action === scenario.preferredAction { alert.preferredAction = native }
        }
        if let source {
            alert.popoverPresentationController?.sourceView = source
            alert.popoverPresentationController?.sourceRect = source.bounds
        }
        let measured: CGFloat?
        if scenario.usesSizeThatFits, let content = scenario.content {
            measured = measureNativeContent(content, in: alert, anchored: source != nil)
        } else {
            measured = nil
        }
        return (alert, measured)
    }

    private func presentNative(_ scenario: Scenario, style: UIAlertController.Style, source: UIView?) {
        let (alert, measured) = makeNativeAlert(scenario, style: style, source: source)
        let popoverForm = source == nil ? nil : scenario.content as? AlertExampleFields
        activeAlert = alert
        presentNativeAlert(alert, detailMessage: scenario.detailMessage, animated: true) { [weak self, weak alert, weak popoverForm] in
            guard let alert else { return }
            // 原生 Popover 转场可能重置嵌入表单在 viewIsAppearing 请求的焦点。
            popoverForm?.focusFirstFieldIfNeeded()
            if let fields = alert.textFields, !fields.isEmpty {
                self?.showTextFieldMeasurements(fields, engine: "UIKit")
                return
            }
            guard let guide = Self.nativeContentGuide(in: alert) else { return }
            let proposal = measured.map { "Measured \(Int($0.rounded())) pt" } ?? "Auto Layout"
            self?.showMeasurements("UIKit guide \(Self.dimensions(guide.layoutFrame.size)) · \(proposal)")
        }
    }

    func presentNativeAlert(_ alert: UIAlertController, detailMessage: String?, animated: Bool, completion: @escaping () -> Void) {
        let updateDetailInset = { [weak self, weak alert] in
            guard #available(iOS 26, *), let self, let alert, let detailMessage, !detailMessage.isEmpty,
                  self.addNativeDetailBottomInset(in: alert.view, text: detailMessage) else { return }
            alert.view.layoutIfNeeded()
        }
        present(alert, animated: animated) {
            updateDetailInset()
            completion()
        }
        alert.transitionCoordinator?.animate(alongsideTransition: { _ in updateDetailInset() })
    }

    // UIKit 在呈现期间创建或更新说明标签的底部约束。
    private func addNativeDetailBottomInset(in view: UIView, text: String) -> Bool {
        for subview in view.subviews {
            if let label = subview as? UILabel, label.text == text,
               let bottom = view.constraints.first(where: {
                   $0.firstAttribute == .bottom && $0.secondAttribute == .bottom && $0.relation == .equal && $0.multiplier == 1
                       && (($0.firstItem === view && $0.secondItem === label)
                           || ($0.firstItem === label && $0.secondItem === view))
               }) {
                let inset: CGFloat = bottom.firstItem === view ? 12 : -12
                if bottom.constant == inset { return false }
                bottom.constant = inset
                return true
            }
            if addNativeDetailBottomInset(in: subview, text: text) { return true }
        }
        return false
    }

    private func setNativeValue(_ value: Any?, key: String, on object: NSObject) {
        guard let value else { return }
        let name = key.prefix(1).uppercased() + key.dropFirst()
        if object.responds(to: NSSelectorFromString("set\(name):"))
            || object.responds(to: NSSelectorFromString("_set\(name):")) {
            object.setValue(value, forKey: key)
        }
    }

    private func measureNativeContent(_ content: UIViewController, in alert: UIAlertController, anchored: Bool) -> CGFloat? {
        alert.loadViewIfNeeded()
        alert.view.setNeedsLayout()
        alert.view.layoutIfNeeded()

        let width: CGFloat
        if anchored, alert.responds(to: NSSelectorFromString("_contentInsets")),
           let boxed = alert.value(forKey: "_contentInsets") as? NSValue {
            let insets = boxed.uiEdgeInsetsValue
            let panelWidth: CGFloat
            if traitCollection.userInterfaceIdiom == .pad, let ideal = Self.nativeIdealPanelWidth(in: alert) {
                panelWidth = ideal
            } else {
                panelWidth = content.view.bounds.width
            }
            width = panelWidth - insets.left - insets.right
        } else {
            width = Self.nativeContentGuide(in: alert)?.layoutFrame.width ?? 0
        }
        guard width.isFinite, width > 0 else { return nil }
        let height = content.view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        guard height.isFinite, height > 0 else { return nil }
        content.preferredContentSize = CGSize(width: 0, height: ceil(height))
        return width
    }

    private static func nativeIdealPanelWidth(in alert: UIAlertController) -> CGFloat? {
        let panel = alert.view!
        guard panel.responds(to: NSSelectorFromString("_idealLayoutWidth")),
              let value = panel.value(forKey: "_idealLayoutWidth") as? NSNumber else { return nil }
        let width = CGFloat(value.doubleValue)
        return width.isFinite && width > 0 ? width : nil
    }

    private static func nativeContentGuide(in alert: UIAlertController) -> UILayoutGuide? {
        guard alert.responds(to: NSSelectorFromString("contentViewControllerLayoutGuide")) else { return nil }
        return alert.value(forKey: "contentViewControllerLayoutGuide") as? UILayoutGuide
    }

    private func legacyActionSheetWidth(for style: UIAlertController.Style) -> CGFloat? {
        guard #unavailable(iOS 26), style == .actionSheet, traitCollection.userInterfaceIdiom == .phone else {
            return nil
        }
        // 旧版 UIKit 会居中放置嵌入内容。用框架按当前可用区域测得的面板宽度作为尺寸参考。
        let layout = AlertController(preferredStyle: style)
        return layout.prepareForPresentation(from: self)?.panelSize.width
    }

    func scenario(for example: Example, imageMode: ImageMode, usesPopover: Bool,
                  style: UIAlertController.Style = .alert) -> Scenario {
        let report: (String) -> Void = { [weak self] in self?.report($0) }
        let pick: (String) -> Void = { [weak self] in self?.finishSelection($0) }
        let cancel = AlertAction(title: Localization.text("demo.alertExamples.action.cancel"), style: .cancel) { _ in report(Localization.text("demo.alertExamples.result.cancelled")) }
        let done = AlertAction(title: Localization.text("common.done")) { _ in }
        var scenario = Scenario(title: example.title, actions: [done, cancel])
        switch example {
        case .simple, .images:
            let decorated = example == .images
            let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            scenario.message = Localization.text("demo.alertExamples.simple.message")
            let standard = AlertAction(
                title: Localization.text("demo.alertExamples.action.default"),
                appearance: decorated ? .init(image: UIImage(systemName: "paperclip"), titleColor: .systemIndigo) : .init()
            ) { _ in report(Localization.text("demo.alertExamples.result.default")) }
            let destructive = AlertAction(
                title: Localization.text("demo.alertExamples.action.destructive"),
                style: .destructive,
                appearance: decorated ? .init(image: UIImage(systemName: "trash")) : .init()
            ) { _ in report(Localization.text("demo.alertExamples.result.destructive")) }
            scenario.actions = [standard, destructive, cancel]
            if example == .simple {
                standard.accessibilityIdentifier = "alerts.action.default"
                scenario.preferredAction = standard
            }
            if decorated {
                standard.titleTextAlignment = rtl ? .right : .left
                destructive.titleTextAlignment = rtl ? .left : .right
                scenario.attributedTitle = NSAttributedString(string: example.title, attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .headline), .foregroundColor: UIColor.systemIndigo,
                ])
                scenario.attributedMessage = NSAttributedString(string: scenario.message!, attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel,
                ])
                let unavailable = AlertAction(
                    title: Localization.text("demo.alertExamples.action.unavailable"),
                    appearance: .init(image: UIImage(systemName: "lock"))
                )
                unavailable.isEnabled = false
                scenario.actions.insert(unavailable, at: 2)
            }
        case .textField, .login:
            let fields = AlertExampleFields(login: example == .login, usesPopover: usesPopover, report: report)
            scenario.content = fields
            scenario.actions = [AlertAction(title: example == .login ? Localization.text("demo.alertExamples.action.signIn") : Localization.text("common.ok")) { _ in report(fields.result) }, cancel]
        case .date:
            let picker = UIDatePicker()
            let now = Date()
            let locale = Localization.localizationController.locale
            let format = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
            picker.preferredDatePickerStyle = .wheels
            picker.datePickerMode = .dateAndTime
            picker.locale = locale
            picker.date = now
            picker.minimumDate = Calendar.current.date(byAdding: .day, value: -7, to: now)
            picker.maximumDate = Calendar.current.date(byAdding: .day, value: 30, to: now)
            picker.accessibilityIdentifier = "alerts.date.picker"
            picker.addAction(UIAction { [weak picker] _ in
                if let picker { report(picker.date.formatted(format)) }
            }, for: .valueChanged)
            scenario.content = AlertExampleContent(picker, height: 180)
            scenario.actions = [AlertAction(title: Localization.text("common.done")) { _ in
                report(picker.date.formatted(format))
            }, cancel]
        case .calendar:
            if #available(iOS 16, *) {
                let calendar = AlertExampleCalendar()
                calendar.loadViewIfNeeded()
                let timing = UISegmentedControl(items: [
                    Localization.text("demo.alertExamples.calendar.sameDay"),
                    Localization.text("demo.alertExamples.calendar.dayBefore"),
                ])
                timing.selectedSegmentIndex = 0
                timing.accessibilityIdentifier = "alerts.calendar.timing"
                let body = QuickLayoutView {
                    timing.resizable(axis: .horizontal).padding(.horizontal, 16)
                }
                scenario.message = Localization.text("demo.alertExamples.calendar.message")
                scenario.header = calendar
                scenario.content = AlertExampleContent(body, height: 44)
                scenario.actions = [AlertAction(title: Localization.text("common.done")) { _ in
                    let date = calendar.selectedDate.formatted(.dateTime.month(.abbreviated).day().year().locale(Localization.localizationController.locale))
                    let option = timing.titleForSegment(at: timing.selectedSegmentIndex) ?? ""
                    report("\(date) · \(option)")
                }, cancel]
            }
        case .height:
            let wheel = AlertExampleWheel(report: report)
            scenario.content = wheel
            scenario.actions = [AlertAction(title: Localization.text("common.done")) { _ in report(Localization.text("demo.alertExamples.height.result", wheel.selection)) }, cancel]
        case .country, .phone, .currency:
            let rows = example == .currency
                ? AlertExampleLocales.currencies()
                : AlertExampleLocales.countries(phoneCodes: example == .phone)
            scenario.content = AlertExampleList(rows: rows) { pick($0.result) }
        case .imagePicker, .photoLibrary:
            let library = example == .photoLibrary
            let images = AlertExampleImages(
                items: library ? [] : Self.sampleImages(), multiple: library || imageMode == .multiple,
                paging: imageMode == .pages, usesLibrary: library
            ) { items in report(Self.photoResult(items)) }
            scenario.content = images
            scenario.actions = [AlertAction(title: Localization.text("common.done")) { _ in report(Self.photoResult(images.selectedItems)) }, cancel]
        case .color:
            let controls = AlertExampleColor(report: report)
            let sheetWidth = legacyActionSheetWidth(for: style)
            // 旧版 UIKit 使用 Auto Layout 获取内容尺寸，现代弹窗读取子控制器的首选尺寸。
            let sizing: QuickLayoutHostingControllerSizingOptions
            if #available(iOS 26, *) { sizing = .preferredContentSize } else { sizing = .intrinsicContentSize }
            let content = QuickLayoutHostingController(sizingOptions: sizing) {
                controls.layout(idealWidth: sheetWidth)
            }
            content.view.backgroundColor = .clear
            scenario.content = content
        case .text:
            scenario.content = AlertExampleContent(AlertExampleTextView(presentingView: view))
            scenario.usesSizeThatFits = true
        case .longMessage:
            scenario.message = AlertExampleTextView.plainText
        case .richText:
            let title = Localization.text("demo.alertExamples.richText.title")
            scenario.title = title
            scenario.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: UIFont.preferredFont(forTextStyle: .headline),
                .foregroundColor: UIColor.systemIndigo,
            ])
            scenario.titleMaximumLineCount = 2
            scenario.titleLineBreakMode = .byTruncatingTail
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .natural
            paragraph.lineSpacing = 6
            let message = NSMutableAttributedString(string: Localization.text("demo.alertExamples.richText.message"),
                                                     attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ])
            let emphasis = (message.string as NSString).range(of: Localization.text("demo.alertExamples.richText.emphasis"))
            if emphasis.location != NSNotFound {
                message.addAttributes([
                    .font: UIFont.boldSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize),
                    .foregroundColor: UIColor.systemIndigo,
                ], range: emphasis)
            }
            scenario.attributedMessage = message
            scenario.detailMessage = Localization.text("demo.alertExamples.richText.detail")
            scenario.actions = [AlertAction(title: Localization.text("demo.alertExamples.action.applyChanges")) { _ in report(Localization.text("demo.alertExamples.result.applied")) }, cancel]
        case .contacts:
            scenario.content = AlertExampleContacts.make(select: pick)
        case .location:
            scenario.content = AlertExampleLocation(select: pick)
        case .attachments:
            let photos = AlertExampleImages(items: [], multiple: true, paging: false, usesLibrary: true) {
                report(Localization.text("demo.alertExamples.attachments.photosResult", Self.photoResult($0)))
            }
            scenario.content = AlertExampleAttachments(legacyActionSheetWidth: legacyActionSheetWidth(for: style)) { index in
                switch index {
                case 0: photos
                case 1: AlertExampleContacts.make { pick(Localization.text("demo.alertExamples.attachments.contactResult", $0)) }
                default: AlertExampleLocation { pick(Localization.text("demo.alertExamples.attachments.locationResult", $0)) }
                }
            }
            scenario.actions = [AlertAction(title: Localization.text("demo.alertExamples.action.send")) { _ in
                report(Localization.text("demo.alertExamples.attachments.photosResult", Self.photoResult(photos.selectedItems)))
            }, cancel]
        }
        return scenario
    }

    private func finishSelection(_ value: String) {
        guard let alert = activeAlert else { return }
        alert.view.endEditing(true)
        alert.dismiss(animated: true) { [weak self] in self?.report(value) }
    }

    private func report(_ message: String) {
        hasResult = true
        result.text = message
        setNeedsQuickLayout()
    }

    private func showMeasurements(_ value: String) {
        measurements.text = value
        setNeedsQuickLayout()
        print("ALERT_LAYOUT \(value.replacingOccurrences(of: "\n", with: " | "))")
    }

    private func showTextFieldMeasurements(_ fields: [UITextField], engine: String) {
        let sizes = fields.map { Self.dimensions($0.bounds.size) }.joined(separator: " · ")
        showMeasurements("\(engine) text fields \(sizes)")
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width.rounded()))×\(Int(size.height.rounded()))"
    }

    private static func sampleImages() -> [AlertExampleImages.Item] {
        let names = ["VoiceRoomAvatarOne", "VoiceRoomAvatarTwo", "VoiceRoomPKAvatarThree", "VoiceRoomPKAvatarSeven",
                     "VoiceRoomPKAvatarExtra02", "VoiceRoomPKAvatarExtra03", "VoiceRoomPKAvatarExtra04",
                     "VoiceRoomPKAvatarExtra05", "VoiceRoomPKAvatarExtra08", "VoiceRoomPKAvatarExtra09"]
        return names.enumerated().compactMap { index, name in
            UIImage(named: name).map { .init(id: name, title: Localization.text("demo.alertExamples.images.sample", index + 1), image: $0) }
        }
    }

    private static func photoResult(_ items: [AlertExampleImages.Item]) -> String {
        items.isEmpty ? Localization.text("demo.alertExamples.images.noneSelected") : items.map(\.title).joined(separator: ", ")
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("弹窗示例目录") {
    UINavigationController(rootViewController: AlertExamplesViewController())
}

@available(iOS 17.0, *)
#Preview("基础弹窗") {
    AlertExamplesViewController.preview(.simple)
}

@available(iOS 17.0, *)
#Preview("富文本弹窗") {
    AlertExamplesViewController.preview(.richText)
}
#endif
