//
//  ViewControllerRepresentableDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class ViewControllerRepresentableDemoViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.representable.title" }

    private let scrollView = QuickLayoutScrollView()
    private let stateLabel = UILabel()
    private let logTextView = UITextView()

    private lazy var showLazyButton = makeButton(titleKey: "representable.showLazy", action: #selector(showLazyA))
    private lazy var hideHostButton = makeButton(titleKey: "representable.hide", action: #selector(hideHost))
    private lazy var showAgainButton = makeButton(titleKey: "representable.showAgain", action: #selector(showAgain))
    private lazy var replaceButton = makeButton(titleKey: "representable.replace", action: #selector(replaceLoadedChild))
    private lazy var preferredSizeButton = makeButton(titleKey: "representable.preferredSize", action: #selector(togglePreferredContentSize))
    private lazy var resetButton = makeButton(titleKey: "representable.reset", action: #selector(resetLazyView))

    private var showsChild = false
    private var childSequence = 0
    private var logLines: [String] = []

    private lazy var lazyChild: LazyView<QuickLayoutViewControllerRepresentable> = makeLazyChild(name: "A")

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        stateLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        stateLabel.textColor = .secondaryLabel
        stateLabel.numberOfLines = 0

        logTextView.backgroundColor = .secondarySystemGroupedBackground
        logTextView.textColor = .label
        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.isEditable = false
        logTextView.isScrollEnabled = true
        logTextView.layer.cornerRadius = 8
        logTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        appendLog("Demo viewDidLoad")
        appendLazyStateLog()
        refreshStateLabel()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        showLazyButton.configuration?.title = DemoLocalization.text("representable.showLazy")
        hideHostButton.configuration?.title = DemoLocalization.text("representable.hide")
        showAgainButton.configuration?.title = DemoLocalization.text("representable.showAgain")
        replaceButton.configuration?.title = DemoLocalization.text("representable.replace")
        preferredSizeButton.configuration?.title = DemoLocalization.text("representable.preferredSize")
        resetButton.configuration?.title = DemoLocalization.text("representable.reset")
        (lazyChild.ifLoaded?.viewController as? LoggingChildViewController)?.reloadLocalizedContent()
        refreshStateLabel()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 12) {
                stateLabel

                VStack(spacing: 8) {
                    showLazyButton.resizable().frame(height: 44)
                    hideHostButton.resizable().frame(height: 44)
                    showAgainButton.resizable().frame(height: 44)
                    replaceButton.resizable().frame(height: 44)
                    preferredSizeButton.resizable().frame(height: 44)
                    resetButton.resizable().frame(height: 44)
                }

                if showsChild {
                    lazyChild
                        .frame(height: 260)
                }

                logTextView
                    .resizable()
                    .frame(height: 360)
            }
        }
        .contentMargins(16)
        .safeAreaPadding(0)
    }
}

private extension ViewControllerRepresentableDemoViewController {

    @objc func showLazyA() {
        appendLog("Action: Show Lazy A")
        showsChild = true
        refreshLayout()
        appendLazyStateLog()
    }

    @objc func hideHost() {
        appendLog("Action: Hide Host")
        showsChild = false
        refreshLayout()
        appendLazyStateLog()
    }

    @objc func showAgain() {
        appendLog("Action: Show Again")
        showsChild = true
        refreshLayout()
        appendLazyStateLog()
    }

    @objc func replaceLoadedChild() {
        appendLog("Action: Replace Loaded Child")

        guard let host = lazyChild.ifLoaded else {
            appendLog("Replace skipped: LazyView ifLoaded=nil")
            appendLazyStateLog()
            return
        }

        childSequence += 1
        host.setViewController(makeLoggingChild(name: "Replacement \(childSequence)"))
        refreshLayout()
        appendLazyStateLog()
    }

    @objc func resetLazyView() {
        appendLog("Action: Reset LazyView")

        lazyChild.ifLoaded?.dismantleViewController()
        showsChild = false
        childSequence += 1
        lazyChild = makeLazyChild(name: "Reset \(childSequence)")
        refreshLayout()
        appendLazyStateLog()
    }

    @objc func togglePreferredContentSize() {
        appendLog("Action: Toggle preferredContentSize")

        guard let host = lazyChild.ifLoaded,
              let child = host.viewController as? LoggingChildViewController else {
            appendLog("Preferred size skipped: LazyView ifLoaded=nil")
            appendLazyStateLog()
            return
        }

        child.togglePreferredContentSize()
        host.invalidateChildLayout()
        refreshLayout()
        appendLazyStateLog()
    }

    func refreshLayout() {
        refreshStateLabel()
        setNeedsQuickLayout()
        quickLayoutIfNeeded()
        refreshStateLabel()
    }

    func makeLazyChild(name: String) -> LazyView<QuickLayoutViewControllerRepresentable> {
        LazyView { [unowned self] in
            appendLog("LazyView factory invoked for child \(name)")

            let child = makeLoggingChild(name: name)
            let host = QuickLayoutViewControllerRepresentable(child)
            host.eventHandler = { [weak self] event in
                self?.appendLog("Representable event: \(event.name)")
            }
            host.detailedEventHandler = { [weak self] event in
                self?.appendLog("Representable detailed: \(Self.describeDetailedEvent(event))")
            }

            return host
        }
    }

    func makeLoggingChild(name: String) -> LoggingChildViewController {
        LoggingChildViewController(name: name) { [weak self] message in
            self?.appendLog(message)
        }
    }

    func makeButton(titleKey: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = DemoLocalization.text(titleKey)
        configuration.baseBackgroundColor = .systemBlue.withAlphaComponent(0.12)
        configuration.baseForegroundColor = .systemBlue
        configuration.cornerStyle = .medium

        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    func appendLazyStateLog() {
        appendLog(lazyStateDescription())
    }

    func refreshStateLabel() {
        stateLabel.text = lazyStateDescription()
    }

    func lazyStateDescription() -> String {
        let loadedHost = lazyChild.ifLoaded
        let hostText = loadedHost.map { String(describing: type(of: $0)) } ?? "nil"
        let childText = loadedHost?.viewController.map { viewController in
            if let child = viewController as? LoggingChildViewController {
                return "\(String(describing: type(of: child)))(name: \(child.name), preferred: \(Self.describe(child.preferredContentSize)))"
            }
            return String(describing: type(of: viewController))
        } ?? "nil"

        return "LazyView isLoaded=\(lazyChild.isLoaded), ifLoaded=\(hostText), child=\(childText), showsChild=\(showsChild)"
    }

    func appendLog(_ message: String) {
        let line = "[\(Self.logTimestamp())] \(message)"
        print(line)

        logLines.append(line)
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }

        logTextView.text = logLines.joined(separator: "\n")
        let end = NSRange(location: max(logTextView.text.count - 1, 0), length: 1)
        logTextView.scrollRangeToVisible(end)
        refreshStateLabel()
    }

    static func logTimestamp() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    static func describeDetailedEvent(_ event: QuickLayoutViewControllerRepresentable.DetailedEvent) -> String {
        [
            "kind=\(event.kind.name)",
            "parent=\(describe(event.parent))",
            "child=\(describe(event.viewController))",
            "old=\(describe(event.oldViewController))",
            "new=\(describe(event.newViewController))",
            "reason=\(event.reason ?? "nil")"
        ].joined(separator: ", ")
    }

    static func describe(_ viewController: UIViewController?) -> String {
        guard let viewController else { return "nil" }
        if let child = viewController as? LoggingChildViewController {
            return "\(String(describing: type(of: child)))(\(child.name))"
        }
        return String(describing: type(of: viewController))
    }

    static func describe(_ size: CGSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }
}

private final class LoggingChildViewController: UIViewController, LocalizedContentUpdating, UserInterfaceLayoutDirectionUpdating {

    let name: String

    private let logHandler: (String) -> Void
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var usesExpandedPreferredSize = false

    init(name: String, logHandler: @escaping (String) -> Void) {
        self.name = name
        self.logHandler = logHandler
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 320, height: 220)
        log("init")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        log("deinit")
    }

    override func loadView() {
        log("loadView")

        let view = UIView()
        view.backgroundColor = .tertiarySystemGroupedBackground
        view.layer.cornerRadius = 8
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor

        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .label

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .systemGreen.withAlphaComponent(0.16)
        configuration.baseForegroundColor = .systemGreen
        configuration.cornerStyle = .medium
        actionButton.configuration = configuration
        actionButton.addTarget(self, action: #selector(childButtonTapped), for: .touchUpInside)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(actionButton)
        self.view = view
        reloadLocalizedContent()
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        log("viewDidLoad")
    }

    func reloadLocalizedContent() {
        titleLabel.text = DemoLocalization.text("representable.child.title", name)
        subtitleLabel.text = DemoLocalization.text("representable.child.subtitle")
        actionButton.configuration?.title = DemoLocalization.text("representable.child.button")
        viewIfLoaded?.setNeedsLayout()
    }

    func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        viewIfLoaded?.semanticContentAttribute = direction.appLayoutDirection.semanticContentAttribute
        viewIfLoaded?.setNeedsLayout()
    }

    func togglePreferredContentSize() {
        usesExpandedPreferredSize.toggle()
        preferredContentSize = CGSize(width: 320, height: usesExpandedPreferredSize ? 320 : 220)
        log("preferredContentSize changed to \(Int(preferredContentSize.width))x\(Int(preferredContentSize.height))")
        viewIfLoaded?.setNeedsLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        log("viewWillAppear(animated: \(animated))")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        log("viewDidAppear(animated: \(animated))")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        log("viewWillDisappear(animated: \(animated))")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        log("viewDidDisappear(animated: \(animated))")
    }

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        log("willMove(toParent: \(String(describing: parent.map { type(of: $0) })))")
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        log("didMove(toParent: \(String(describing: parent.map { type(of: $0) })))")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let contentBounds = view.bounds.insetBy(dx: 16, dy: 16)
        titleLabel.frame = CGRect(x: contentBounds.minX, y: contentBounds.minY, width: contentBounds.width, height: 28)
        subtitleLabel.frame = CGRect(x: contentBounds.minX, y: titleLabel.frame.maxY + 8, width: contentBounds.width, height: 40)
        actionButton.frame = CGRect(x: contentBounds.minX, y: subtitleLabel.frame.maxY + 16, width: contentBounds.width, height: 44)

        log("viewDidLayoutSubviews")
    }

    @objc private func childButtonTapped() {
        log("button target-action")
    }

    private func log(_ event: String) {
        logHandler("Child[\(name)] \(event)")
    }
}


#Preview {
    UINavigationController(rootViewController: ViewControllerRepresentableDemoViewController())
}
