//
//  LocalizationViewControllers.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class LocalizationOverviewViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.localizationOverview.title" }

    private let viewModel: LocalizationOverviewViewModel
    private let scrollView = QuickLayoutScrollView()
    private let bodyLabel = LocalizedLabel()
    private let currentLanguageLabel = LocalizedLabel()
    private let directionLabel = LocalizedLabel()
    private var languageButtons: [UIButton] = []

    convenience init() {
        self.init(viewModel: LocalizationOverviewViewModel())
    }

    init(viewModel: LocalizationOverviewViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = LocalizationOverviewViewModel()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        [bodyLabel, currentLanguageLabel, directionLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .preferredFont(forTextStyle: .body)
        }
        currentLanguageLabel.textColor = .secondaryLabel
        directionLabel.textColor = .secondaryLabel

        languageButtons = viewModel.state.languages.map {
            makeLanguageButton(option: $0)
        }
        bindViewModel()
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
        viewModel.refreshLocalizedContent()
    }

    private func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: LocalizationOverviewViewModel.State) {
        bodyLabel.text = state.bodyText
        currentLanguageLabel.text = state.currentLanguageText
        directionLabel.text = state.directionText

        for button in languageButtons {
            guard let identifier = button.accessibilityIdentifier,
                  let option = state.languages.first(where: {
                      $0.identifier == identifier
                  }) else {
                continue
            }
            updateLanguageButton(button, option: option)
        }
        setNeedsQuickLayout()
    }

    private func makeLanguageButton(
        option: LocalizationOverviewViewModel.LanguageOption
    ) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .medium
        configuration.baseBackgroundColor = .systemBlue.withAlphaComponent(0.1)
        configuration.baseForegroundColor = .systemBlue
        configuration.titleAlignment = .leading
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.title = option.title
        configuration.subtitle = option.subtitle
        configuration.image = option.isSelected
            ? UIImage(systemName: "checkmark")
            : nil

        let button = LocalizedButton(configuration: configuration)
        button.accessibilityIdentifier = option.identifier
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            Task { @MainActor in
                self?.viewModel.selectLanguage(identifier: option.identifier)
            }
        }, for: .touchUpInside)
        return button
    }

    private func updateLanguageButton(
        _ button: UIButton,
        option: LocalizationOverviewViewModel.LanguageOption
    ) {
        button.contentHorizontalAlignment = .leading

        guard var configuration = button.configuration else {
            assertionFailure("Language buttons require UIButton.Configuration")
            return
        }
        configuration.titleAlignment = .leading
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.title = option.title
        configuration.subtitle = option.subtitle
        configuration.image = option.isSelected
            ? UIImage(systemName: "checkmark")
            : nil
        button.configuration = configuration
    }
}

final class UIKitLocalizationShowcaseViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.uikitLocalization.title" }

    private let titleLabel = LocalizedLabel()
    private let scrollView = QuickLayoutScrollView()
    private let subtitleLabel = LocalizedLabel()
    private let modalButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = Localization.text("uikit.showModal")
        return LocalizedButton(configuration: configuration)
    }()
    private let collectionView: UICollectionView
    private let cellRegistration: UICollectionView.CellRegistration<
        LocalizationShowcaseCell,
        Int
    >

    private var collectionLayoutDirection: UIUserInterfaceLayoutDirection?

    private static func makeCollectionLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(layoutSize: .init(
            widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)
        ))
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .absolute(132), heightDimension: .absolute(64)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 12
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = .horizontal
        // 由原生布局根据继承的方向解析 leading，包括内容宽度不足一个视口的情况。
        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }

    init() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: Self.makeCollectionLayout())
        cellRegistration = UICollectionView.CellRegistration<LocalizationShowcaseCell, Int> {
            cell,
            _,
            item in
            cell.configure(
                text: Localization.text(
                    "uikit.collection.\(item + 1)"
                )
            )
        }
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
        subtitleLabel.accessibilityIdentifier = "localization.demo.body"

        modalButton.addTarget(self, action: #selector(showModal), for: .touchUpInside)
        collectionView.backgroundColor = .clear
        collectionView.accessibilityIdentifier = "uikitLocalization.collection"
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self

        // 页面滚动宿主负责外层安全区，集合视图只负责自己的横向内容。
        collectionView.contentInsetAdjustmentBehavior = .never

        reloadLocalizedContent()
        reloadLayoutDirection(Localization.currentUIKitDirection)
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 16) {
                titleLabel.resizable(axis: .horizontal)
                subtitleLabel.resizable(axis: .horizontal)
                modalButton.resizable(axis: .horizontal).frame(minHeight: 44)
                collectionView.resizable().frame(height: 82)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(20, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        titleLabel.text = Localization.text("demo.uikitLocalization.title")
        subtitleLabel.text = Localization.text("uikit.showcase.subtitle")
        if var configuration = modalButton.configuration {
            configuration.title = Localization.text("uikit.showModal")
            modalButton.configuration = configuration
        } else {
            assertionFailure("Modal button requires UIButton.Configuration")
        }
        collectionView.reloadData()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        guard collectionLayoutDirection != direction else { return }
        collectionLayoutDirection = direction
        // Compositional Layout 会缓存首次解析的方向；切换时更换原生布局实例。
        // 保留集合视图身份与 unspecified，不逐项镜像 frame 或强制子视图语义。
        collectionView.setCollectionViewLayout(Self.makeCollectionLayout(), animated: false)
    }

    @objc private func showModal() {
        let modal = LocalizationModalViewController()
        let navigationController = UINavigationController(rootViewController: modal)
        present(navigationController, animated: true)
    }
}

extension UIKitLocalizationShowcaseViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        3
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration,
            for: indexPath,
            item: indexPath.item
        )
    }
}

extension UIKitLocalizationShowcaseViewController: UICollectionViewDelegate {
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        (cell as? LocalizationShowcaseCell)?.configure(
            text: Localization.text("uikit.collection.\(indexPath.item + 1)")
        )
    }
}

private final class LocalizationShowcaseCell: UICollectionViewCell {
    private let label = LocalizedLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        var backgroundConfiguration = UIBackgroundConfiguration.clear()
        backgroundConfiguration.backgroundColor = .secondarySystemFill
        backgroundConfiguration.cornerRadius = 8
        backgroundConfiguration.strokeColor = .separator.withAlphaComponent(0.2)
        backgroundConfiguration.strokeWidth = 1 / traitCollection.displayScale
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

private final class LocalizationModalViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "uikit.showModal" }

    private let label = LocalizedLabel()
    private let scrollView = QuickLayoutScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .body)
        label.numberOfLines = 0
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Localization.text("common.close"), style: .done, target: self, action: #selector(close))
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            label.resizable(axis: .horizontal)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .contentMargins(24, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        label.text = Localization.text("uikit.modal.message")
        navigationItem.leftBarButtonItem?.title = Localization.text("common.close")
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

final class DirectionalNavigationViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.directionalNavigation.title" }

    private let label = LocalizedLabel()
    private let edgeLabel = LocalizedLabel()
    private let scrollView = QuickLayoutScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // leading 按钮属于当前示例，不用于替换导航控制器的返回按钮。
        // 保留系统返回按钮，使其 RTL 镜像、辅助功能和交互式返回行为继续由 UIKit 管理。
        navigationItem.leftItemsSupplementBackButton = true
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        edgeLabel.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        edgeLabel.textColor = .secondaryLabel
        edgeLabel.numberOfLines = 0
        label.accessibilityIdentifier = "localization.demo.body"

        reloadLocalizedContent()
        reloadLayoutDirection(Localization.currentUIKitDirection)
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 16) {
                label.resizable(axis: .horizontal)
                edgeLabel.resizable(axis: .horizontal)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(20, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        label.text = Localization.text("navigation.body")
        reloadLayoutDirection(Localization.currentUIKitDirection)
        updateEdgeLabel()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)

        let leading = UIBarButtonItem(title: Localization.text("navigation.leading"), style: .plain, target: nil, action: nil)
        let trailing = UIBarButtonItem(title: Localization.text("navigation.trailing"), style: .plain, target: nil, action: nil)
        let language = UIBarButtonItem(
            image: UIImage(systemName: "globe"),
            primaryAction: nil,
            menu: Localization.languageMenu()
        )
        language.accessibilityLabel = Localization.text("language.menu.accessibility")

        // UIKit 按导航栏方向解析前后缘，系统返回手势由导航控制器管理。
        navigationItem.leftBarButtonItem = leading
        navigationItem.rightBarButtonItems = [language, trailing]
        updateEdgeLabel()
    }

    private func updateEdgeLabel() {
        let layoutDirection = view.effectiveUserInterfaceLayoutDirection
        let edgeKey = DirectionalLayout.backSwipeRectEdge(
            layoutDirection: layoutDirection
        ) == .right
            ? "navigation.edge.right"
            : "navigation.edge.left"
        edgeLabel.text = Localization.text(
            "navigation.edge.summary",
            Localization.text(edgeKey),
            DirectionalLayout.backChevronSystemName(
                layoutDirection: layoutDirection
            )
        )
    }
}

final class SemanticGestureViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.semanticGesture.title" }

    // UIKit may still measure this view after its controller has been released.
    private lazy var containerView = QuickLayoutView { [hintLabel, resultLabel] in
        VStack(spacing: 12) {
            hintLabel.resizable(axis: .horizontal)
            resultLabel.resizable(axis: .horizontal)
        }
        .padding(20)
        .frame(minHeight: 180)
    }
    private let scrollView = QuickLayoutScrollView()
    private let hintLabel = LocalizedLabel()
    private let resultLabel = LocalizedLabel()
    private var translationX: CGFloat = 0
    private var lastDirection: NSDirectionalRectEdge?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        containerView.backgroundColor = .secondarySystemGroupedBackground
        containerView.layer.cornerRadius = 12
        hintLabel.font = .preferredFont(forTextStyle: .body)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.accessibilityIdentifier = "localization.demo.body"
        resultLabel.font = .preferredFont(forTextStyle: .headline)
        resultLabel.textAlignment = .center
        resultLabel.numberOfLines = 0

        containerView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            containerView
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .contentMargins(20, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        hintLabel.text = Localization.text("gesture.hint")
        updateResultLabel()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

        if translationX != 0 {
            lastDirection = DirectionalLayout.semanticHorizontalDirection(
                translationX: translationX,
                layoutDirection: direction
            )
        }
        updateResultLabel()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        translationX = gesture.translation(in: containerView).x
        lastDirection = DirectionalLayout.semanticHorizontalDirection(
            translationX: translationX,
            layoutDirection: containerView.effectiveUserInterfaceLayoutDirection
        )
        updateResultLabel()
    }

    private func updateResultLabel() {
        let directionText: String
        switch lastDirection {
        case .leading:
            directionText = Localization.text("gesture.leading")
        case .trailing:
            directionText = Localization.text("gesture.trailing")
        default:
            directionText = Localization.text("gesture.none")
        }

        let isBackSwipe = DirectionalLayout.isBackSwipe(
            translationX: translationX,
            layoutDirection: containerView.effectiveUserInterfaceLayoutDirection
        )
        let backSwipeText = Localization.text(
            isBackSwipe ? "common.boolean.true" : "common.boolean.false"
        )
        resultLabel.text = [
            directionText,
            Localization.text(
                "gesture.translation",
                Int64(translationX)
            ),
            Localization.text("gesture.backSwipe", backSwipeText),
        ].joined(separator: "\n")
        containerView.setNeedsQuickLayout()
        setNeedsQuickLayout()
    }
}

final class LocalizationBoundaryViewController: LocalizedQuickLayoutHostingController {
    override var localizedTitleKey: String? { "demo.localizationBoundary.title" }

    private let bodyLabel = LocalizedLabel()
    private let metadataLabel = LocalizedLabel()
    private let scrollView = QuickLayoutScrollView()
    private let alertButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = Localization.text(
            "boundary.recreateAlert"
        )
        return LocalizedButton(configuration: configuration)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        [bodyLabel, metadataLabel].forEach {
            $0.numberOfLines = 0
            $0.font = .preferredFont(forTextStyle: .body)
        }
        metadataLabel.textColor = .secondaryLabel
        bodyLabel.accessibilityIdentifier = "localization.demo.body"
        alertButton.addTarget(self, action: #selector(showBoundaryAlert), for: .touchUpInside)

        reloadLocalizedContent()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(alignment: .leading, spacing: 16) {
                bodyLabel.resizable(axis: .horizontal)
                metadataLabel.resizable(axis: .horizontal)
                alertButton.resizable(axis: .horizontal).frame(minHeight: 44)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .contentMargins(20, for: .scrollContent)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        bodyLabel.text = Localization.text("boundary.body")
        metadataLabel.text = Localization.text("boundary.systemMetadata")
        if var configuration = alertButton.configuration {
            configuration.title = Localization.text(
                "boundary.recreateAlert"
            )
            alertButton.configuration = configuration
        } else {
            assertionFailure("Alert button requires UIButton.Configuration")
        }
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

    }

    @objc private func showBoundaryAlert() {
        let alert = UIAlertController(
            title: Localization.text("demo.localizationBoundary.title"),
            message: "\(Localization.text("boundary.body"))\n\n\(Localization.text("boundary.systemMetadata"))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localization.text("common.ok"), style: .default))
        present(alert, animated: true)
    }
}


@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: LocalizationOverviewViewController())
}
