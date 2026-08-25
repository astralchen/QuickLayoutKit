//
//  CounterViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

final class CounterViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.counter.title" }

    private let viewModel: CounterViewModel
    private let scrollView = QuickLayoutScrollView()
    private let heroView = CounterHeroView()
    private let controlsView = CounterControlsView()
    private let statusView = CounterStatusView()

    // 作为该示例的公开交互边界，供 Demo 测试和辅助功能检查访问。
    var counterLabel: UILabel { controlsView.countLabel }
    var incrementButton: QuickLayoutButton { controlsView.incrementButton }
    var decrementButton: QuickLayoutButton { controlsView.decrementButton }
    var resetButton: QuickLayoutButton { statusView.resetButton }

    convenience init() {
        self.init(viewModel: CounterViewModel(initialCount: 3))
    }

    init(viewModel: CounterViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = CounterViewModel(initialCount: 3)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground

        incrementButton.action = { [weak self] in
            self?.viewModel.increment()
        }
        decrementButton.action = { [weak self] in
            self?.viewModel.decrement()
        }
        resetButton.action = { [weak self] in
            self?.confirmReset()
        }

        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        viewModel.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)

        let update = DemoLocalization.layoutDirectionUpdate(direction)
        UIViewLayoutDirectionUpdater.apply(
            update,
            to: [
                UIViewLayoutDirectionTarget(
                    scrollView,
                    policy: .followApplication
                ),
                UIViewLayoutDirectionTarget(
                    incrementButton,
                    policy: .followApplication
                ),
                UIViewLayoutDirectionTarget(
                    decrementButton,
                    policy: .followApplication
                ),
                UIViewLayoutDirectionTarget(
                    resetButton,
                    policy: .followApplication
                ),
            ]
        )
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(spacing: 16) {
                heroView
                    .resizable(axis: .horizontal)
                controlsView
                    .resizable(axis: .horizontal)
                statusView
                    .resizable(axis: .horizontal)
            }
            .padding(.vertical, 16)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func confirmReset() {
        guard viewModel.state.canReset else { return }

        let alert = UIAlertController(
            title: DemoLocalization.text("counter.reset.confirm.title"),
            message: DemoLocalization.text("counter.reset.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(
                title: DemoLocalization.text("counter.reset.cancel"),
                style: .cancel
            )
        )
        alert.addAction(
            UIAlertAction(
                title: DemoLocalization.text("counter.reset.action"),
                style: .destructive
            ) { [weak self] _ in
                self?.viewModel.reset()
            }
        )
        present(alert, animated: true)
    }

    private func render(_ state: CounterViewModel.State) {
        heroView.configure(state)
        controlsView.configure(state)
        statusView.configure(state)
        setNeedsQuickLayout()
    }
}

private class CounterCardView: QuickLayoutView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureCard()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureCard()
    }

    private func configureCard() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
    }
}

private final class CounterHeroView: CounterCardView {

    private let eyebrowLabel = UILabel()
    private let headlineLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconBackgroundView = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "drop.fill"))
    private let progressLabel = UILabel()
    private let goalLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ state: CounterViewModel.State) {
        eyebrowLabel.text = state.eyebrow
        headlineLabel.text = state.headline
        subtitleLabel.text = state.subtitle
        progressLabel.text = state.progressText
        goalLabel.text = state.goalText
        progressView.setProgress(state.progress, animated: window != nil)
        progressView.accessibilityLabel = state.headline
        progressView.accessibilityValue = state.progressText
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    eyebrowLabel
                    headlineLabel
                    subtitleLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ZStack {
                    iconBackgroundView
                        .resizable()
                        .frame(width: 58, height: 58)
                    iconView
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 28)
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    progressLabel
                    Spacer()
                    goalLabel
                }
                progressView
                    .resizable(axis: .horizontal)
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func setupViews() {
        backgroundColor = .systemIndigo.withAlphaComponent(0.10)

        eyebrowLabel.font = .preferredFont(forTextStyle: .caption1)
        eyebrowLabel.adjustsFontForContentSizeCategory = true
        eyebrowLabel.textColor = .systemIndigo

        headlineLabel.font = .preferredFont(forTextStyle: .title2)
        headlineLabel.adjustsFontForContentSizeCategory = true
        headlineLabel.numberOfLines = 0
        headlineLabel.textColor = .label

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = .secondaryLabel

        iconBackgroundView.backgroundColor = .systemIndigo
        iconBackgroundView.layer.cornerRadius = 18
        iconBackgroundView.layer.cornerCurve = .continuous

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit

        progressLabel.font = .preferredFont(forTextStyle: .subheadline)
        progressLabel.adjustsFontForContentSizeCategory = true
        progressLabel.textColor = .label

        goalLabel.font = .preferredFont(forTextStyle: .caption1)
        goalLabel.adjustsFontForContentSizeCategory = true
        goalLabel.textColor = .secondaryLabel

        progressView.progressTintColor = .systemIndigo
        progressView.trackTintColor = .systemIndigo.withAlphaComponent(0.16)
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true
        progressView.isAccessibilityElement = true
    }
}

private final class CounterControlsView: CounterCardView {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    let countLabel = UILabel()
    private let unitLabel = UILabel()
    let incrementButton = CounterActionButton(
        style: .filled,
        imageName: "plus"
    )
    let decrementButton = CounterActionButton(
        style: .tinted,
        imageName: "minus"
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ state: CounterViewModel.State) {
        titleLabel.text = state.controlsTitle
        subtitleLabel.text = state.controlsSubtitle
        countLabel.text = state.countText
        unitLabel.text = state.unitText
        incrementButton.title = state.incrementTitle
        decrementButton.title = state.decrementTitle
        decrementButton.isEnabled = state.canDecrement

        // 控件组本身不作为辅助功能元素，使两个按钮仍可被分别访问；
        // 当前计数负责播报整体进度。
        countLabel.accessibilityLabel = state.controlsTitle
        countLabel.accessibilityValue = state.progressText
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                titleLabel
                subtitleLabel
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    horizontalButton(decrementButton)
                    countLayout
                    horizontalButton(incrementButton)
                }

                VStack(spacing: 12) {
                    countLayout
                    verticalButton(decrementButton)
                    verticalButton(incrementButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var countLayout: Layout {
        VStack(spacing: 2) {
            countLabel
            unitLabel
        }
        .frame(minWidth: 76)
    }

    private func horizontalButton(_ button: QuickLayoutButton) -> Layout {
        button
            .resizable(axis: .horizontal)
            .frame(height: 52)
            .frame(minWidth: 96, idealWidth: 96)
    }

    private func verticalButton(_ button: QuickLayoutButton) -> Layout {
        button
            .resizable(axis: .horizontal)
            .frame(height: 52)
    }

    private func setupViews() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        subtitleLabel.font = .preferredFont(forTextStyle: .footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textColor = .secondaryLabel

        countLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .monospacedDigitSystemFont(ofSize: 42, weight: .bold)
        )
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textAlignment = .center
        countLabel.isAccessibilityElement = true

        unitLabel.font = .preferredFont(forTextStyle: .caption1)
        unitLabel.adjustsFontForContentSizeCategory = true
        unitLabel.numberOfLines = 2
        unitLabel.textAlignment = .center
        unitLabel.textColor = .secondaryLabel

        incrementButton.accessibilityIdentifier = "counter.increment"
        decrementButton.accessibilityIdentifier = "counter.decrement"
    }

}

/// Demo 为框架无样式按钮基元提供的外观。
///
/// `QuickLayoutButton` 提供控件状态和操作分发；该类型负责全部视觉选择，
/// 包括内容、颜色、圆角形状以及按下和禁用状态的表现。
private final class CounterActionButton: QuickLayoutButton {

    enum Style {
        case filled
        case tinted
        case destructive
    }

    private let style: Style
    private let backgroundView = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    var title: String? {
        get { titleLabel.text }
        set {
            guard titleLabel.text != newValue else { return }
            titleLabel.text = newValue
            accessibilityLabel = newValue
            setNeedsQuickLayout()
        }
    }

    init(style: Style, imageName: String? = nil) {
        self.style = style
        super.init(action: {})
        imageView.image = imageName.flatMap(UIImage.init(systemName:))
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        style = .filled
        super.init(coder: coder)
        configureAppearance()
    }

    override var body: Layout {
        buttonContent
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minHeight: 44)
            .background { backgroundView }
    }

    @LayoutBuilder
    private var buttonContent: Layout {
        if imageView.image != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    buttonImage
                    titleLabel
                }
                .padding(.horizontal, 16)

                titleLabel
                    .padding(.horizontal, 12)

                buttonImage
                    .padding(.horizontal, 12)
            }
        } else {
            titleLabel
                .padding(.horizontal, 16)
        }
    }

    private var buttonImage: Layout {
        imageView
            .resizable()
            .scaledToFit()
            .frame(width: 17, height: 17)
    }

    private func configureAppearance() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        imageView.contentMode = .scaleAspectFit

        backgroundView.layer.cornerRadius = 14
        backgroundView.layer.cornerCurve = .continuous

        switch style {
        case .filled:
            titleLabel.textColor = .white
            imageView.tintColor = .white
            backgroundView.backgroundColor = .systemIndigo
        case .tinted:
            titleLabel.textColor = .systemIndigo
            imageView.tintColor = .systemIndigo
            backgroundView.backgroundColor = .systemIndigo.withAlphaComponent(
                0.12
            )
        case .destructive:
            role = .destructive
            titleLabel.textColor = .systemRed
            imageView.tintColor = .systemRed
            backgroundView.backgroundColor = .clear
        }

        stateUpdateHandler = { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: QuickLayoutButtonState) {
        let enabledAlpha: CGFloat = state.isEnabled ? 1 : 0.38
        let pressedAlpha: CGFloat = state.isPressed ? 0.68 : 1
        alpha = enabledAlpha
        backgroundView.alpha = pressedAlpha
        titleLabel.alpha = pressedAlpha
        imageView.alpha = pressedAlpha
    }
}

private final class CounterStatusView: CounterCardView {

    private let iconBackgroundView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    let resetButton = CounterActionButton(style: .destructive)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ state: CounterViewModel.State) {
        titleLabel.text = state.statusTitle
        messageLabel.text = state.statusMessage
        resetButton.title = state.resetTitle
        resetButton.isEnabled = state.canReset

        let isComplete = state.count >= state.goal
        iconView.image = UIImage(
            systemName: isComplete ? "checkmark.seal.fill" : "sparkles"
        )
        iconView.tintColor = isComplete ? .systemGreen : .systemIndigo
        iconBackgroundView.backgroundColor = (
            isComplete ? UIColor.systemGreen : UIColor.systemIndigo
        ).withAlphaComponent(0.12)
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    iconBackgroundView
                        .resizable()
                        .frame(width: 48, height: 48)
                    iconView
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }

                VStack(alignment: .leading, spacing: 4) {
                    titleLabel
                    messageLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            resetButton
                .resizable(axis: .horizontal)
                .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func setupViews() {
        iconBackgroundView.layer.cornerRadius = 15
        iconBackgroundView.layer.cornerCurve = .continuous

        iconView.contentMode = .scaleAspectFit

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .secondaryLabel

        resetButton.accessibilityIdentifier = "counter.reset"
    }

}

#Preview {
    UINavigationController(rootViewController: CounterViewController())
}
