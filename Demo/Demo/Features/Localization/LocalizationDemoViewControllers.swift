//
//  LocalizationDemoViewControllers.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class LocalizationOverviewViewController: DemoQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.localizationOverview.title" }

    private let scrollView = QuickLayoutScrollView()
    private let bodyLabel = UILabel()
    private let currentLanguageLabel = UILabel()
    private let directionLabel = UILabel()
    private var languageButtons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        [bodyLabel, currentLanguageLabel, directionLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .preferredFont(forTextStyle: .body)
        }
        currentLanguageLabel.textColor = .secondaryLabel
        directionLabel.textColor = .secondaryLabel

        languageButtons = [
            makeLanguageButton(identifier: LocalizationController.followSystemLocaleIdentifier),
            makeLanguageButton(identifier: AppLocale.englishUS.identifier),
            makeLanguageButton(identifier: AppLocale.simplifiedChinese.identifier),
            makeLanguageButton(identifier: AppLocale.arabic.identifier)
        ]

        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 16) {
                bodyLabel
                currentLanguageLabel
                directionLabel

                VStack(spacing: 10) {
                    ForEach(languageButtons) { button in
                        button.resizable().frame(height: 52)
                    }
                }
            }
        }
        .contentMargins(20)
        .safeAreaPadding(0)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        bodyLabel.text = DemoLocalization.text("localization.overview.body")
        currentLanguageLabel.text = "\(DemoLocalization.text("language.current")): \(DemoLocalization.currentLanguageSummary())"
        directionLabel.text = "\(DemoLocalization.text("language.direction")): \(DemoLocalization.currentLayoutDirection == .rightToLeft ? "RTL" : "LTR")"
        languageButtons.forEach(updateLanguageButton(_:))
    }

    private func makeLanguageButton(identifier: String) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = .systemBlue.withAlphaComponent(0.1)
        configuration.baseForegroundColor = .systemBlue
        configuration.titleAlignment = .leading
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8

        let button = UIButton(configuration: configuration)
        button.accessibilityIdentifier = identifier
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { _ in
            Task { @MainActor in
                DemoLocalization.setLocale(identifier: identifier)
            }
        }, for: .touchUpInside)
        updateLanguageButton(button)
        return button
    }

    private func updateLanguageButton(_ button: UIButton) {
        guard let identifier = button.accessibilityIdentifier else { return }
        button.semanticContentAttribute = .unspecified
        button.contentHorizontalAlignment = .leading

        var configuration = button.configuration ?? UIButton.Configuration.filled()
        configuration.titleAlignment = .leading
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8

        if identifier == LocalizationController.followSystemLocaleIdentifier {
            configuration.title = DemoLocalization.text("language.follow.system")
            configuration.subtitle = DemoLocalization.localeDisplayName(DemoLocalization.localizationController.currentLocale)
            configuration.image = DemoLocalization.localizationController.followsSystemLocale ? UIImage(systemName: "checkmark") : nil
            button.configuration = configuration
            return
        }

        guard let locale = DemoLocalization.localizationController.supportedLocales.first(where: { $0.identifier == identifier }) else {
            return
        }
        configuration.title = locale.nativeDisplayName
        configuration.subtitle = DemoLocalization.localeDisplayName(locale)
        configuration.image = (!DemoLocalization.localizationController.followsSystemLocale && locale == DemoLocalization.localizationController.currentLocale) ? UIImage(systemName: "checkmark") : nil
        button.configuration = configuration
    }
}

final class UIKitLocalizationShowcaseViewController: DemoViewController {
    override var localizedTitleKey: String? { "demo.uikitLocalization.title" }

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let modalButton = UIButton(type: .system)
    private let collectionView: UICollectionView
    private let cellReuseIdentifier = "LocalizationShowcaseCell"

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 12
        layout.itemSize = CGSize(width: 132, height: 64)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.numberOfLines = 0
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        modalButton.addTarget(self, action: #selector(showModal), for: .touchUpInside)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.register(LocalizationShowcaseCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, modalButton, collectionView])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            collectionView.heightAnchor.constraint(equalToConstant: 82)
        ])

        reloadLocalizedContent()
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        titleLabel.text = DemoLocalization.text("demo.uikitLocalization.title")
        subtitleLabel.text = DemoLocalization.text("uikit.showcase.subtitle")
        modalButton.setTitle(DemoLocalization.text("uikit.showModal"), for: .normal)
        collectionView.reloadData()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        collectionView.applyUserInterfaceLayoutDirection(
            direction.appLayoutDirection,
            preservingVisibleItem: true
        )
    }

    @objc private func showModal() {
        let modal = LocalizationModalViewController()
        let navigationController = UINavigationController(rootViewController: modal)
        navigationController.view.semanticContentAttribute = DemoLocalization.currentLayoutDirection.semanticContentAttribute
        present(navigationController, animated: true)
    }
}

extension UIKitLocalizationShowcaseViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        3
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! LocalizationShowcaseCell
        cell.configure(text: DemoLocalization.text("uikit.collection.\(indexPath.item + 1)"))
        return cell
    }
}

private final class LocalizationShowcaseCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .secondarySystemFill
        backgroundConfiguration.cornerRadius = 8
        backgroundConfiguration.strokeColor = .separator.withAlphaComponent(0.2)
        backgroundConfiguration.strokeWidth = 1 / UIScreen.main.scale
        self.backgroundConfiguration = backgroundConfiguration

        label.font = .preferredFont(forTextStyle: .callout)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        label.text = text
    }
}

private final class LocalizationModalViewController: DemoViewController {
    override var localizedTitleKey: String? { "uikit.showModal" }

    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: DemoLocalization.text("common.close"), style: .done, target: self, action: #selector(close))
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        label.text = DemoLocalization.text("uikit.modal.message")
        navigationItem.leftBarButtonItem?.title = DemoLocalization.text("common.close")
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

final class DirectionalNavigationDemoViewController: DemoViewController {
    override var localizedTitleKey: String? { "demo.directionalNavigation.title" }

    private let label = UILabel()
    private let edgeLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        edgeLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        edgeLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [label, edgeLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        reloadLocalizedContent()
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        label.text = DemoLocalization.text("navigation.body")
        reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
        updateEdgeLabel()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        let appDirection = direction.appLayoutDirection
        let leading = UIBarButtonItem(title: DemoLocalization.text("navigation.leading"), style: .plain, target: nil, action: nil)
        let trailing = UIBarButtonItem(title: DemoLocalization.text("navigation.trailing"), style: .plain, target: nil, action: nil)
        let language = UIBarButtonItem(
            image: UIImage(systemName: "globe"),
            primaryAction: nil,
            menu: DemoLocalization.languageMenu()
        )
        language.accessibilityLabel = DemoLocalization.text("language.menu.accessibility")

        switch direction {
        case .leftToRight:
            navigationItem.leftBarButtonItem = leading
            navigationItem.rightBarButtonItems = [language, trailing]
        case .rightToLeft:
            navigationItem.leftBarButtonItem = trailing
            navigationItem.rightBarButtonItems = [language, leading]
        @unknown default:
            navigationItem.leftBarButtonItem = leading
            navigationItem.rightBarButtonItems = [language, trailing]
        }
        if let edgePan = navigationController?.interactivePopGestureRecognizer as? UIScreenEdgePanGestureRecognizer {
            edgePan.edges = DirectionalLayout.backSwipeRectEdge(layoutDirection: appDirection)
        }
        updateEdgeLabel()
    }

    private func updateEdgeLabel() {
        let edge = DirectionalLayout.backSwipeEdge(layoutDirection: DemoLocalization.currentLayoutDirection) == .right ? "right" : "left"
        edgeLabel.text = "Back edge: \(edge), chevron: \(DirectionalLayout.backChevronSystemName(layoutDirection: DemoLocalization.currentLayoutDirection))"
    }
}

final class SemanticGestureDemoViewController: DemoViewController {
    override var localizedTitleKey: String? { "demo.semanticGesture.title" }

    private let containerView = UIView()
    private let hintLabel = UILabel()
    private let resultLabel = UILabel()
    private var translationX: CGFloat = 0
    private var lastDirection: SemanticHorizontalDirection?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        containerView.backgroundColor = .secondarySystemGroupedBackground
        containerView.layer.cornerRadius = 12
        hintLabel.font = .preferredFont(forTextStyle: .body)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        resultLabel.font = .preferredFont(forTextStyle: .headline)
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [hintLabel, resultLabel])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stack)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.heightAnchor.constraint(equalToConstant: 180),
            stack.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20)
        ])

        containerView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        hintLabel.text = DemoLocalization.text("gesture.hint")
        updateResultLabel()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        translationX = gesture.translation(in: containerView).x
        lastDirection = DirectionalLayout.semanticHorizontalDirection(
            translationX: translationX,
            layoutDirection: DemoLocalization.currentLayoutDirection
        )
        updateResultLabel()
    }

    private func updateResultLabel() {
        let directionText: String
        switch lastDirection {
        case .leading:
            directionText = DemoLocalization.text("gesture.leading")
        case .trailing:
            directionText = DemoLocalization.text("gesture.trailing")
        case nil:
            directionText = DemoLocalization.text("gesture.none")
        }

        let backSwipe = DirectionalLayout.isBackSwipe(
            translationX: translationX,
            layoutDirection: DemoLocalization.currentLayoutDirection
        ) ? "true" : "false"
        resultLabel.text = "\(directionText)\ntranslation.x \(Int(translationX))\n\(DemoLocalization.text("gesture.backSwipe", backSwipe))"
    }
}

final class LocalizationBoundaryDemoViewController: DemoViewController {
    override var localizedTitleKey: String? { "demo.localizationBoundary.title" }

    private let bodyLabel = UILabel()
    private let metadataLabel = UILabel()
    private let alertButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        [bodyLabel, metadataLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .preferredFont(forTextStyle: .body)
        }
        metadataLabel.textColor = .secondaryLabel
        alertButton.addTarget(self, action: #selector(showBoundaryAlert), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [bodyLabel, metadataLabel, alertButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        bodyLabel.text = DemoLocalization.text("boundary.body")
        metadataLabel.text = DemoLocalization.text("boundary.systemMetadata")
        alertButton.setTitle(DemoLocalization.text("boundary.recreateAlert"), for: .normal)
    }

    @objc private func showBoundaryAlert() {
        let alert = UIAlertController(
            title: DemoLocalization.text("demo.localizationBoundary.title"),
            message: "\(DemoLocalization.text("boundary.body"))\n\n\(DemoLocalization.text("boundary.systemMetadata"))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: DemoLocalization.text("common.ok"), style: .default))
        present(alert, animated: true)
    }
}


#Preview {
    UINavigationController(rootViewController: LocalizationOverviewViewController())
}
