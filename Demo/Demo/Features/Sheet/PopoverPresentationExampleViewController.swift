import QuickLayoutKit
import UIKit

final class PopoverPresentationExampleViewController: LocalizedQuickLayoutHostingController, PopoverPresentationControllerDelegate, UIPopoverPresentationControllerDelegate {
    override var localizedTitleKey: String? { "demo.popoverPresentation.title" }
    private let engine = UISegmentedControl(items: ["QuickLayoutKit", "UIKit"])
    private let options = UIButton(type: .system)
    private let canvas = PopoverAnchorButton(frame: .zero)
    private var appearance: Set<PopoverComparisonOption> = []
    private enum EffectChoice {
        case automatic, darkBlur, clearGlass, transparent

        @available(iOS 26.1, *)
        @MainActor var effect: UIVisualEffect? {
            switch self {
            case .automatic: return nil
            case .darkBlur: return UIBlurEffect(style: .dark)
            case .clearGlass: return UIGlassEffect(style: .clear)
            case .transparent: return UIColorEffect(color: .clear)
            }
        }
    }
    private var effectChoice = EffectChoice.automatic
    private var popoverColor: UIColor?
    private var popoverMargins: UIEdgeInsets?
    private enum BackgroundChoice {
        case automatic, solid, outlined, customOutlined

        func viewClass(native: Bool) -> (any UIPopoverBackgroundViewMethods.Type)? {
            switch self {
            case .automatic: return nil
            case .solid: return SolidPopoverBackground.self
            case .outlined: return native ? UIOutlinedPopoverBackground.self : OutlinedPopoverBackground.self
            case .customOutlined: return native ? DemoUIOutlinedPopoverBackground.self : DemoOutlinedPopoverBackground.self
            }
        }
    }
    private var backgroundChoice = BackgroundChoice.automatic
    private var canOverlapSourceViewRect = false
    private var adapts = false
    private var directions = UIPopoverArrowDirection.any
    private lazy var barItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), style: .plain,
                                              target: self, action: #selector(openItem(_:)))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        engine.addAction(UIAction { [weak self] _ in self?.reloadLocalizedContent() }, for: .valueChanged)
        engine.selectedSegmentIndex = 0
        engine.accessibilityIdentifier = "popover.engine"
        options.showsMenuAsPrimaryAction = true
        options.accessibilityIdentifier = "popover.options"
        canvas.backgroundColor = .secondarySystemGroupedBackground
        canvas.accessibilityIdentifier = "popover.canvas"
        canvas.action = { [weak self] in
            guard let self else { return }
            open(rect: canvas.sourceRect)
        }
        canvas.hint.numberOfLines = 0
        canvas.hint.textAlignment = .center
        canvas.hint.textColor = .secondaryLabel
        canvas.hint.font = .preferredFont(forTextStyle: .body)
        canvas.hint.adjustsFontForContentSizeCategory = true
        // 保留基类安装的语言切换入口。
        navigationItem.rightBarButtonItems = [barItem] + (navigationItem.rightBarButtonItems ?? [])
        reloadLocalizedContent()
    }

    override var body: Layout {
        VStack(spacing: 8) {
            engine
            options
            canvas.resizable().frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(.top, 12).safeAreaPadding()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        options.setTitle(Localization.text("sheet.options"), for: .normal)
        barItem.accessibilityLabel = Localization.text("popover.item")
        canvas.hint.text = Localization.text("popover.hint")
        canvas.accessibilityLabel = canvas.hint.text
        canvas.setNeedsQuickLayout()
        let choices: [(UIPopoverArrowDirection, String)] = [(.any, "any"), (.up, "up"), (.down, "down"), (.left, "left"), (.right, "right")]
        let actions = choices.map { dir, key in
            UIAction(title: Localization.text("popover." + key), state: dir == directions ? .on : .off) { [weak self] _ in
                self?.directions = dir
                self?.reloadLocalizedContent()
            }
        }
        let adapt = UIAction(title: Localization.text("popover.adapt"), state: adapts ? .on : .off) { [weak self] _ in
            self?.adapts.toggle()
            self?.reloadLocalizedContent()
        }
        var entries: [UIMenuElement] = actions + [adapt]
        let defaultTitle = Localization.text("popover.default")
        entries += [
            selectionMenu("sourceRect", \.canvas.sourceRectSize, [("1 pt", 1), ("30 pt", 30), ("80 pt", 80)]),
            selectionMenu("canOverlapSourceViewRect", \.canOverlapSourceViewRect, [("false", false), ("true", true)]),
            selectionMenu("backgroundColor", \.popoverColor, [
                (defaultTitle, nil), ("systemTeal", .systemTeal), ("clear", .clear)
            ]),
            selectionMenu("popoverLayoutMargins", \.popoverMargins, [
                (defaultTitle, nil), ("24 pt", UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)),
                ("12 / 48 / 32 / 16 pt", UIEdgeInsets(top: 12, left: 48, bottom: 32, right: 16))
            ]),
            selectionMenu("popoverBackgroundViewClass", \.backgroundChoice, [
                (defaultTitle, .automatic), (Localization.text("popover.solidBackground"), .solid),
                (Localization.text("popover.outlinedBackground"), .outlined),
                (Localization.text("popover.customOutlinedBackground"), .customOutlined)
            ])
        ]
        if #available(iOS 26.1, *) {
            entries.append(selectionMenu("backgroundEffect", \.effectChoice, [
                (defaultTitle, .automatic), ("UIBlurEffect · dark", .darkBlur), ("UIGlassEffect · clear", .clearGlass),
                ("UIColorEffect · clear", .transparent)
            ]))
        }
        var availableOptions = PopoverComparisonOption.allCases
        #if !DEBUG
        if engine.selectedSegmentIndex != 0 {
            availableOptions = backgroundChoice == .automatic ? [] : [.radius, .corners]
        }
        #endif
        if !availableOptions.isEmpty {
            let settings = availableOptions.compactMap { option -> UIAction? in
                if #unavailable(iOS 26), option == .corners { return nil }
                return UIAction(title: option.rawValue, state: appearance.contains(option) ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    if appearance.remove(option) == nil { appearance.insert(option) }
                    if option == .radius { appearance.remove(.corners) }
                    if option == .corners { appearance.remove(.radius) }
                    reloadLocalizedContent()
                }
            }
            entries.append(UIMenu(options: .displayInline, children: settings))
        }
        options.menu = UIMenu(children: entries)
    }

    private func selectionMenu<Value: Equatable>(_ title: String,
        _ key: ReferenceWritableKeyPath<PopoverPresentationExampleViewController, Value>,
        _ choices: [(String, Value)]) -> UIMenu {
        let actions = choices.map { label, value in
            UIAction(title: label, state: self[keyPath: key] == value ? .on : .off) { [weak self] _ in
                self?[keyPath: key] = value
                self?.reloadLocalizedContent()
            }
        }
        return UIMenu(title: title, options: .singleSelection, children: actions)
    }

    @objc private func openItem(_ item: UIBarButtonItem) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-popover-source-diagnostics"), let window = view.window {
            // 仅在示例的调试构建中对照系统返回的来源视图。
            for name in ["view", "_viewForPresenting", "_sourceViewForPresentationInWindow:"] {
                let selector = NSSelectorFromString(name)
                guard item.responds(to: selector) else { continue }
                let result = name.hasSuffix(":") ? item.perform(selector, with: window) : item.perform(selector)
                if let source = result?.takeUnretainedValue() as? UIView {
                    print("Popover \(name) \(type(of: source)) \(source.convert(source.bounds, to: window))")
                }
            }
        }
        #endif
        open(item: item)
    }

    private func open(rect: CGRect = .null, item: UIBarButtonItem? = nil) {
        let content = UIViewController()
        content.preferredContentSize = CGSize(width: 220, height: 140)
        let close = UIButton(type: .close)
        close.accessibilityIdentifier = "popover.close"
        close.addAction(UIAction { [weak content] _ in content?.dismiss(animated: true) }, for: .touchUpInside)
        content.view.addSubview(close)
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([close.centerXAnchor.constraint(equalTo: content.view.centerXAnchor),
                                     close.centerYAnchor.constraint(equalTo: content.view.centerYAnchor)])
        let settings = PopoverComparisonOption.allCases.filter { appearance.contains($0) && $0 != .offset }
        let setsOffset = appearance.contains(.offset)
        if engine.selectedSegmentIndex == 0 {
            presentPopover(content) { pc in
                pc.popoverDelegate = self
                pc.sourceView = canvas
                // 较早系统没有公开的按钮位置接口，使用可见导航栏作为后备锚点。
                pc.sourceRect = rect
                if let item {
                    pc.barButtonItem = item
                    pc.sourceView = navigationController?.navigationBar
                }
                if #available(iOS 26.1, *) { pc.backgroundEffect = effectChoice.effect }
                pc.backgroundColor = popoverColor
                if let popoverMargins { pc.popoverLayoutMargins = popoverMargins }
                pc.popoverBackgroundViewClass = backgroundChoice.viewClass(native: false)
                pc.canOverlapSourceViewRect = canOverlapSourceViewRect
                pc.permittedArrowDirections = directions
                pc.adaptiveSheetPresentationController.detents = [.medium(), .large()]
                settings.forEach { $0.apply(to: pc) }
            } completion: { [weak content] in
                if setsOffset, let pc = content?.customPopoverPresentationController { PopoverComparisonOption.offset.apply(to: pc) }
            }
        } else {
            content.modalPresentationStyle = .popover
            guard let pc = content.popoverPresentationController else { return }
            pc.delegate = self
            if let item {
                if #available(iOS 16, *) { pc.sourceItem = item } else { pc.barButtonItem = item }
            } else { pc.sourceView = canvas; pc.sourceRect = rect }
            if #available(iOS 26.1, *) { pc.backgroundEffect = effectChoice.effect }
            pc.backgroundColor = popoverColor
            if let popoverMargins { pc.popoverLayoutMargins = popoverMargins }
            pc.popoverBackgroundViewClass = backgroundChoice.viewClass(native: true)
            pc.canOverlapSourceViewRect = canOverlapSourceViewRect
            pc.permittedArrowDirections = directions
            pc.adaptiveSheetPresentationController.detents = [.medium(), .large()]
            settings.forEach { $0.apply(to: pc) }
            #if DEBUG
            present(content, animated: true) { if setsOffset { PopoverComparisonOption.offset.apply(to: pc) } }
            #else
            present(content, animated: true)
            #endif
        }
    }

    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        adapts && traitCollection.horizontalSizeClass == .compact ? .pageSheet : .none
    }
}

/// 保留上次点选的位置，切换尺寸、呈现方式或重叠开关后可复用同一锚点。
final class PopoverAnchorButton: QuickLayoutButton {
    let hint = UILabel()
    private var touchPoint: CGPoint?
    var sourceRectSize: CGFloat = 1 { didSet { setNeedsLayout() } }
    private let marker = CALayer()
    private let locator = CAShapeLayer()

    var sourceRect: CGRect {
        let side = min(sourceRectSize, bounds.width, bounds.height)
        let point = touchPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        // 靠边时平移整个正方形，保证画出的范围和传给呈现控制器的尺寸一致。
        let x = min(max(point.x - side / 2, bounds.minX), bounds.maxX - side)
        let y = min(max(point.y - side / 2, bounds.minY), bounds.maxY - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    override var body: Layout {
        hint.padding(.horizontal, 24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = sourceRect
        let color = UIColor.systemBlue.resolvedColor(with: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if marker.superlayer == nil {
            marker.name = "popover.sourceRect"
            layer.addSublayer(marker)
            layer.addSublayer(locator)
        }
        marker.frame = rect
        marker.backgroundColor = color.withAlphaComponent(0.16).cgColor
        marker.borderColor = color.cgColor
        marker.borderWidth = 1
        // 1 pt 的实际锚点另外用空心环标出，方便在画布上找到它。
        locator.isHidden = sourceRectSize != 1
        locator.frame = CGRect(x: rect.midX - 5, y: rect.midY - 5, width: 10, height: 10)
        locator.path = UIBezierPath(ovalIn: locator.bounds).cgPath
        locator.fillColor = nil
        locator.strokeColor = color.cgColor
        CATransaction.commit()
    }

    func selectAnchor(at point: CGPoint) {
        guard bounds.contains(point) else { return }
        touchPoint = point
        setNeedsLayout()
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { selectAnchor(at: touch.location(in: self)) }
        super.endTracking(touch, with: event)
    }
}

/// 两种呈现共用宽箭头和非对称内容边距。菜单未指定颜色时使用黄色，便于与默认描边比较。
final class DemoOutlinedPopoverBackground: OutlinedPopoverBackground {
    override nonisolated class func arrowBase() -> CGFloat { 64 }
    override nonisolated class func arrowHeight() -> CGFloat { 24 }
    override nonisolated class func contentViewInsets() -> UIEdgeInsets {
        .init(top: 9, left: 11, bottom: 13, right: 15)
    }

    override func applyPopoverAppearance(from controller: UIPresentationController, backgroundColor: UIColor?) {
        super.applyPopoverAppearance(from: controller, backgroundColor: backgroundColor ?? .systemYellow)
    }
}

/// UIKit 通过包装类创建同一个绘图子类，并读取其布局度量。
final class DemoUIOutlinedPopoverBackground: UIOutlinedPopoverBackground {
    override nonisolated class var drawingViewClass: OutlinedPopoverBackground.Type { DemoOutlinedPopoverBackground.self }
}
