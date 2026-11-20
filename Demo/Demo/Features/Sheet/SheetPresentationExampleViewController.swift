import AppLocalization
import QuickLayoutKit
import UIKit

final class SheetPresentationExampleViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.sheetPresentation.title" }
    private let engine = UISegmentedControl(items: ["QuickLayoutKit", "UIKit"])
    private let initialDetent = UISegmentedControl(items: ["", ""])
    private let options = LocalizedButton(type: .system)
    private let background = LocalizedButton(type: .system)
    private let pose = SheetPoseLabel()
    private var taps = 0
    private var enabled: Set<Option> = [.grabber, .expand, .page, .edge]
    private var placement = 0
    private enum Option: String, CaseIterable {
        case grabber, expand, undim, custom, page, edge, width, anchor, radius, material
        var key: String { "sheet.option." + rawValue }
    }
    private let openButton = LocalizedButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        engine.selectedSegmentIndex = 0
        engine.accessibilityIdentifier = "sheet.engine"
        initialDetent.accessibilityIdentifier = "sheet.initialDetent"
        initialDetent.selectedSegmentIndex = 0
        options.showsMenuAsPrimaryAction = true
        options.accessibilityIdentifier = "sheet.options"
        background.accessibilityIdentifier = "sheet.background"
        background.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            taps += 1
            updateBackground()
        }, for: .touchUpInside)
        openButton.configuration = .filled()
        openButton.accessibilityIdentifier = "sheet.open"
        openButton.addTarget(self, action: #selector(openSheet), for: .touchUpInside)
    }

    override var body: Layout {
        VStack(spacing: 16) {
            engine.resizable(axis: .horizontal)
            initialDetent.resizable(axis: .horizontal)
            openButton
            options
            background
            pose
            Spacer()
        }.padding(16).safeAreaPadding()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        initialDetent.setTitle(Localization.text("sheet.medium"), forSegmentAt: 0)
        initialDetent.setTitle(Localization.text("sheet.large"), forSegmentAt: 1)
        openButton.setTitle(Localization.text("sheet.open"), for: .normal)
        options.setTitle(Localization.text("sheet.options"), for: .normal)
        updateMenu()
        updateBackground()
        pose.refresh()
    }

    private func updateBackground() {
        background.setTitle("\(Localization.text("panel.background")) · \(taps)", for: .normal)
    }

    private func updateMenu() {
        let toggles = Option.allCases.map { option in
            UIAction(title: Localization.text(option.key), state: enabled.contains(option) ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if enabled.contains(option) { enabled.remove(option) } else { enabled.insert(option) }
                updateMenu()
            }
        }
        let positions = ["automatic", "leading", "center", "trailing"].enumerated().map { index, name in
            UIAction(title: name, state: placement == index ? .on : .off) { [weak self] _ in
                self?.placement = index
                self?.updateMenu()
            }
        }
        options.menu = UIMenu(children: toggles + [UIMenu(title: Localization.text("sheet.placement"), children: positions)])
    }

    @objc private func openSheet() {
        let content = SheetExampleContent()
        let startsLarge = initialDetent.selectedSegmentIndex == 1
        content.highlight(startsLarge ? 2 : 1)
        content.showsMaterial = enabled.contains(.material)
        let flags = enabled
        let position = placement
        let anchor = flags.contains(.anchor) ? openButton : nil
        content.preferredContentSize = CGSize(width: 360, height: 500)
        content.custom.isHidden = !flags.contains(.custom)
        if engine.selectedSegmentIndex == 0 {
            content.choose = { [weak content] index in
                guard let sheet = content?.customSheetPresentationController else { return }
                sheet.animateChanges { sheet.selectedDetentIdentifier = ["third", .medium, .large][index] }
            }
            presentSheet(content) { [weak content] sheet in
                sheet.delegate = content
                let medium = SheetPresentationController.Detent.medium()
                if flags.contains(.material) { medium.backgroundEffect = UIBlurEffect(style: .systemMaterial) }
                sheet.detents = [medium, .large()]
                if ProcessInfo.processInfo.arguments.contains("-sheet-geometry") {
                    sheet.detents.insert(.custom { [weak content] context in
                        content?.resolvedGeometry = [context.maximumDetentValue, medium.resolvedValue(in: context) ?? -1]
                        return nil
                    }, at: 0)
                }
                if flags.contains(.custom) {
                    sheet.detents.insert(.custom(identifier: "third") { $0.maximumDetentValue / 3 }, at: 0)
                }
                sheet.selectedDetentIdentifier = startsLarge ? .large : .medium
                sheet.sourceView = anchor
                sheet.preferredPlacement = [.automatic, .leading, .center, .trailing][position]
                sheet.prefersPageSizing = flags.contains(.page)
                sheet.prefersEdgeAttachedInCompactHeight = flags.contains(.edge)
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = flags.contains(.width)
                sheet.prefersGrabberVisible = flags.contains(.grabber)
                sheet.prefersScrollingExpandsWhenScrolledToEdge = flags.contains(.expand)
                sheet.largestUndimmedDetentIdentifier = flags.contains(.undim) ? .medium : nil
                sheet.preferredCornerRadius = flags.contains(.radius) ? 16 : nil
            }
        } else {
            content.modalPresentationStyle = .pageSheet
            if let sheet = content.sheetPresentationController {
                sheet.delegate = content
                let medium = UISheetPresentationController.Detent.medium()
                if #available(iOS 26.1, *), flags.contains(.material) { medium.backgroundEffect = UIBlurEffect(style: .systemMaterial) }
                sheet.detents = [medium, .large()]
                if #available(iOS 16, *), ProcessInfo.processInfo.arguments.contains("-sheet-geometry") {
                    sheet.detents.insert(.custom { [weak content] context in
                        content?.resolvedGeometry = [context.maximumDetentValue, medium.resolvedValue(in: context) ?? -1]
                        return nil
                    }, at: 0)
                }
                if #available(iOS 16, *), flags.contains(.custom) {
                    sheet.detents.insert(.custom(identifier: .init("third")) { $0.maximumDetentValue / 3 }, at: 0)
                } else { content.custom.isHidden = true }
                sheet.selectedDetentIdentifier = startsLarge ? .large : .medium
                sheet.sourceView = anchor
                #if compiler(>=6.4)
                if #available(iOS 27, *) { sheet.preferredPlacement = [.automatic, .leading, .center, .trailing][position] }
                #endif
                if #available(iOS 17, *) { sheet.prefersPageSizing = flags.contains(.page) }
                sheet.prefersEdgeAttachedInCompactHeight = flags.contains(.edge)
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = flags.contains(.width)
                sheet.prefersGrabberVisible = flags.contains(.grabber)
                sheet.prefersScrollingExpandsWhenScrolledToEdge = flags.contains(.expand)
                sheet.largestUndimmedDetentIdentifier = flags.contains(.undim) ? .medium : nil
                sheet.preferredCornerRadius = flags.contains(.radius) ? 16 : nil
                content.choose = { [weak sheet] index in
                    sheet?.animateChanges { sheet?.selectedDetentIdentifier = [.init("third"), .medium, .large][index] }
                }
            }
            present(content, animated: true)
        }
    }
}

final class SheetExampleContent: LocalizedViewController, UITableViewDataSource, SheetPresentationControllerDelegate, UISheetPresentationControllerDelegate {
    var resolvedGeometry: [CGFloat] = []
    var showsMaterial = false
    var choose: ((Int) -> Void)?
    let custom = UIButton(type: .system)
    private let medium = LocalizedButton(type: .system)
    private let large = LocalizedButton(type: .system)
    private let close = LocalizedButton(type: .system)
    private let list = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = showsMaterial ? .clear : .systemBackground
        if showsMaterial { list.backgroundColor = .clear }
        list.accessibilityIdentifier = "sheet.list"
        list.dataSource = self
        list.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        custom.setTitle("1/3", for: .normal)
        custom.accessibilityIdentifier = "sheet.third"
        custom.addAction(UIAction { [weak self] _ in self?.select(0) }, for: .touchUpInside)
        medium.accessibilityIdentifier = "sheet.medium"
        large.accessibilityIdentifier = "sheet.large"
        close.accessibilityIdentifier = "sheet.close"
        medium.addAction(UIAction { [weak self] _ in self?.select(1) }, for: .touchUpInside)
        large.addAction(UIAction { [weak self] _ in self?.select(2) }, for: .touchUpInside)
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [custom, medium, large, close])
        actions.distribution = .fillEqually
        for child in [actions, list] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            actions.topAnchor.constraint(equalTo: safe.topAnchor, constant: 18),
            actions.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            actions.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            list.topAnchor.constraint(equalTo: actions.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        medium.setTitle(Localization.text("sheet.medium"), for: .normal)
        large.setTitle(Localization.text("sheet.large"), for: .normal)
        close.setTitle(Localization.text("panel.close"), for: .normal)
        list.reloadData()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard ProcessInfo.processInfo.arguments.contains("-sheet-geometry"),
              let pc = presentationController, let container = pc.containerView, let window = view.window else { return }
        let rect = view.convert(view.bounds, to: window)
        list.accessibilityValue = "resolved=\(resolvedGeometry) content=\(rect) contentSafe=\(view.safeAreaInsets) window=\(window.safeAreaInsets) container=\(container.safeAreaInsets) readable=\(container.readableContentGuide.layoutFrame) margins=\(container.layoutMargins) hostMargins=\(pc.presentingViewController.view.layoutMargins)"
    }

    func highlight(_ index: Int) {
        for (position, button) in [custom, medium, large].enumerated() { button.isSelected = position == index }
    }

    private func select(_ index: Int) {
        choose?(index)
        highlight(index)
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: SheetPresentationController) {
        highlight(sheet.selectedDetentIdentifier == .large ? 2 : sheet.selectedDetentIdentifier == .medium ? 1 : 0)
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
        highlight(sheet.selectedDetentIdentifier == .large ? 2 : sheet.selectedDetentIdentifier == .medium ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var configuration = cell.defaultContentConfiguration()
        configuration.text = "\(Localization.text("panel.row")) \(indexPath.row + 1)"
        cell.contentConfiguration = configuration
        cell.accessibilityIdentifier = "sheet.row.\(indexPath.row)"
        return cell
    }
}

private final class SheetPoseLabel: UILabel {
    private var pose: ArrangementDevicePose?
    private var angle: CGFloat?

    init() {
        super.init(frame: .zero)
        font = .preferredFont(forTextStyle: .footnote)
        accessibilityIdentifier = "sheet.pose"
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                angle = update.hinge?.angle
                pose = update.hinge.map {
                    switch $0.status {
                    case .closed: .closed
                    case .fullyOpen: .open
                    case .partiallyOpen: .partial
                    default: .unknown
                    }
                }
                refresh()
            })
        }
        #endif
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() { super.layoutSubviews(); refresh() }

    func refresh() {
        guard let pose, let angle else { text = nil; return }
        let resolved = pose.resolved(in: window)
        guard resolved != .unknown else { text = nil; return }
        let display = Localization.text(resolved == .closed ? "sheet.outerDisplay" : "sheet.innerDisplay")
        let name = Localization.text("arrangement.pose." + resolved.rawValue)
        let value = display + " · " + name + String(format: " · %.1f°", angle * 180 / .pi)
        if value != text { text = value }
    }
}
