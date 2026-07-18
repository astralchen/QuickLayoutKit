//
//  ProfileViewController.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit
import AppLocalization
import QuickLayout
import QuickLayoutKit

class ProfileViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.profile.title" }

    private let scrollView = QuickLayoutScrollView()

    private let heroBackgroundView = UIView()
    private let avatarContainerView = UIView()
    private let avatarImageView = UIImageView()
    private let statusDotView = UIView()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()
    private let locationIconView = UIImageView()
    private let locationLabel = UILabel()
    private let availabilityLabel = UILabel()

    private let projectsStatView = ProfileStatView()
    private let followersStatView = ProfileStatView()
    private let responseStatView = ProfileStatView()

    private let aboutTitleLabel = UILabel()
    private let bioLabel = UILabel()
    private let activityTitleLabel = UILabel()
    private let activityIconView = UIImageView()
    private let activityTitleValueLabel = UILabel()
    private let activityDetailLabel = UILabel()
    private let skillsTitleLabel = UILabel()
    private let skillCloudView = ProfileSkillCloudView()

    private let skillLocalizationKeys = [
        "profile.skill.uikit",
        "profile.skill.quicklayout",
        "profile.skill.localization",
        "profile.skill.rtl",
        "profile.skill.dynamicType",
        "profile.skill.keyboard",
        "profile.skill.scroll",
        "profile.skill.collection",
        "profile.skill.controllerHosting",
        "profile.skill.accessibility"
    ]

    private let messageButton = UIButton(type: .system)
    private let portfolioButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        reloadLocalizedContent()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()

        nameLabel.text = DemoLocalization.text("profile.name")
        roleLabel.text = DemoLocalization.text("profile.role")
        locationLabel.text = DemoLocalization.text("profile.location")
        availabilityLabel.text = DemoLocalization.text("profile.availability")

        projectsStatView.configure(
            value: DemoLocalization.text("profile.stats.projects.value"),
            title: DemoLocalization.text("profile.stats.projects.title")
        )
        followersStatView.configure(
            value: DemoLocalization.text("profile.stats.followers.value"),
            title: DemoLocalization.text("profile.stats.followers.title")
        )
        responseStatView.configure(
            value: DemoLocalization.text("profile.stats.response.value"),
            title: DemoLocalization.text("profile.stats.response.title")
        )

        aboutTitleLabel.text = DemoLocalization.text("profile.section.about")
        bioLabel.text = DemoLocalization.text("profile.bio")
        activityTitleLabel.text = DemoLocalization.text("profile.section.activity")
        activityTitleValueLabel.text = DemoLocalization.text("profile.activity.title")
        activityDetailLabel.text = DemoLocalization.text("profile.activity.detail")
        skillsTitleLabel.text = DemoLocalization.text("profile.section.skills")

        skillCloudView.configure(titles: skillLocalizationKeys.map(DemoLocalization.text))

        messageButton.configuration?.title = DemoLocalization.text("profile.action.message")
        portfolioButton.configuration?.title = DemoLocalization.text("profile.action.portfolio")

        setNeedsQuickLayout()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)

        let attribute = direction.appLayoutDirection.semanticContentAttribute
        [messageButton, portfolioButton].forEach {
            $0.semanticContentAttribute = attribute
        }
        skillCloudView.semanticContentAttribute = attribute
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ScrollView(scrollView) {
            VStack(spacing: 18) {
                heroSection
                statsSection
                aboutSection
                activitySection
                skillsSection
                actionsSection
            }
            .layoutDirection(view.quickLayoutDirection)
        }
        .contentMargins(.horizontal, 16)
        .safeAreaPadding(.horizontal, 0)
        .safeAreaPadding(.top, 16)
        .safeAreaPadding(.bottom, 24)
    }

    private var heroSection: Layout {
        VStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                avatarContainerView
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 104)

                avatarImageView
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 88)

                statusDotView
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 18)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }

            VStack(alignment: .center, spacing: 6) {
                nameLabel
                roleLabel
            }

            HStack(spacing: 6) {
                locationIconView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                locationLabel
            }

            availabilityLabel
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    makeRoundedBackground(color: .systemGreen.withAlphaComponent(0.12), radius: 14)
                }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background {
            heroBackgroundView
        }
    }

    private var statsSection: Layout {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                projectsStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
                followersStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
                responseStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
            }

            VStack(spacing: 10) {
                projectsStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
                followersStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
                responseStatView
                    .resizable(axis: .horizontal)
                    .frame(height: 86)
            }
        }
    }

    private var aboutSection: Layout {
        VStack(alignment: .leading, spacing: 10) {
            aboutTitleLabel
            bioLabel
        }
        .frame(maxWidth: .infinity)
        .padding(.all, 16)
        .background {
            makeCardBackground()
        }
    }

    private var activitySection: Layout {
        VStack(alignment: .leading, spacing: 12) {
            activityTitleLabel

            HStack(spacing: 12) {
                activityIconView
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 4) {
                    activityTitleValueLabel
                    activityDetailLabel
                }

                Spacer()
            }
        }
        .padding(.all, 16)
        .background {
            makeCardBackground()
        }
    }

    private var skillsSection: Layout {
        VStack(alignment: .leading, spacing: 12) {
            skillsTitleLabel

            skillCloudView
                .resizable(axis: .horizontal)
        }
        .padding(.all, 16)
        .background {
            makeCardBackground()
        }
    }

    private var actionsSection: Layout {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                messageButton
                    .resizable(axis: .horizontal)
                    .frame(height: 50)

                portfolioButton
                    .resizable(axis: .horizontal)
                    .frame(height: 50)
            }

            VStack(spacing: 10) {
                messageButton
                    .resizable(axis: .horizontal)
                    .frame(height: 50)

                portfolioButton
                    .resizable(axis: .horizontal)
                    .frame(height: 50)
            }
        }
    }

    private func setupViews() {
        view.backgroundColor = .systemGroupedBackground
        scrollView.backgroundColor = .systemGroupedBackground
        scrollView.contentInsetAdjustmentBehavior = .never

        heroBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        heroBackgroundView.layer.cornerRadius = 20
        heroBackgroundView.layer.shadowColor = UIColor.black.cgColor
        heroBackgroundView.layer.shadowOpacity = 0.08
        heroBackgroundView.layer.shadowRadius = 18
        heroBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 8)

        avatarContainerView.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        avatarContainerView.layer.cornerRadius = 52

        avatarImageView.image = UIImage(systemName: "apple.intelligence")
        avatarImageView.backgroundColor = .systemBlue
        avatarImageView.tintColor = .white
        avatarImageView.contentMode = .center
        avatarImageView.layer.cornerRadius = 44
        avatarImageView.clipsToBounds = true

        statusDotView.backgroundColor = .systemGreen
        statusDotView.layer.cornerRadius = 9
        statusDotView.layer.borderColor = UIColor.systemBackground.cgColor
        statusDotView.layer.borderWidth = 3

        nameLabel.font = .preferredFont(forTextStyle: .title2)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center

        roleLabel.font = .preferredFont(forTextStyle: .subheadline)
        roleLabel.adjustsFontForContentSizeCategory = true
        roleLabel.textColor = .secondaryLabel
        roleLabel.textAlignment = .center

        locationIconView.image = UIImage(systemName: "location.fill")
        locationIconView.tintColor = .tertiaryLabel
        locationIconView.contentMode = .scaleAspectFit

        locationLabel.font = .preferredFont(forTextStyle: .footnote)
        locationLabel.adjustsFontForContentSizeCategory = true
        locationLabel.textColor = .secondaryLabel

        availabilityLabel.font = .preferredFont(forTextStyle: .footnote)
        availabilityLabel.adjustsFontForContentSizeCategory = true
        availabilityLabel.textColor = .systemGreen

        configureSectionTitle(aboutTitleLabel)
        configureSectionTitle(activityTitleLabel)
        configureSectionTitle(skillsTitleLabel)

        bioLabel.font = .preferredFont(forTextStyle: .body)
        bioLabel.adjustsFontForContentSizeCategory = true
        bioLabel.textColor = .secondaryLabel
        bioLabel.numberOfLines = 0

        activityIconView.image = UIImage(systemName: "sparkles")
        activityIconView.tintColor = .systemBlue
        activityIconView.contentMode = .center
        activityIconView.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        activityIconView.layer.cornerRadius = 10
        activityIconView.clipsToBounds = true

        activityTitleValueLabel.font = .preferredFont(forTextStyle: .subheadline)
        activityTitleValueLabel.adjustsFontForContentSizeCategory = true
        activityTitleValueLabel.textColor = .label

        activityDetailLabel.font = .preferredFont(forTextStyle: .footnote)
        activityDetailLabel.adjustsFontForContentSizeCategory = true
        activityDetailLabel.textColor = .secondaryLabel
        activityDetailLabel.numberOfLines = 0

        configureButtons()
    }

    private func configureSectionTitle(_ label: UILabel) {
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .natural
    }

    private func configureButtons() {
        var messageConfig = UIButton.Configuration.filled()
        messageConfig.cornerStyle = .large
        messageConfig.image = UIImage(systemName: "message.fill")
        messageConfig.imagePlacement = .leading
        messageConfig.imagePadding = 8
        messageButton.configuration = messageConfig

        var portfolioConfig = UIButton.Configuration.tinted()
        portfolioConfig.cornerStyle = .large
        portfolioConfig.image = UIImage(systemName: "square.grid.2x2.fill")
        portfolioConfig.imagePlacement = .leading
        portfolioConfig.imagePadding = 8
        portfolioButton.configuration = portfolioConfig
    }

    private func makeCardBackground() -> UIView {
        let background = UIView()
        background.backgroundColor = .secondarySystemGroupedBackground
        background.layer.cornerRadius = 16
        return background
    }

    private func makeRoundedBackground(color: UIColor, radius: CGFloat) -> UIView {
        let background = UIView()
        background.backgroundColor = color
        background.layer.cornerRadius = radius
        return background
    }
}

@QuickLayout
private final class ProfileStatView: UIView {

    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, title: String) {
        valueLabel.text = value
        titleLabel.text = title
        setNeedsLayout()
    }

    private func setupViews() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16

        valueLabel.font = .preferredFont(forTextStyle: .title3)
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = .label
        valueLabel.textAlignment = .center

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
    }

    var body: Layout {
        VStack(spacing: 4) {
            valueLabel
            titleLabel
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

@QuickLayout
private final class ProfileChipView: UIView {

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
        setNeedsLayout()
    }

    private func setupViews() {
        backgroundColor = .systemBlue.withAlphaComponent(0.10)
        layer.cornerRadius = 15

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .systemBlue
    }

    var body: Layout {
        titleLabel
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }
}

@QuickLayout
private final class ProfileSkillCloudView: UIView {

    private let horizontalSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 8
    private var chipViews: [ProfileChipView] = []

    func configure(titles: [String]) {
        syncChipViews(count: titles.count)

        zip(chipViews, titles).forEach { chipView, title in
            chipView.configure(title: title)
        }

        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    var body: Layout {
        HFlow(
            itemAlignment: .center,
            lineAlignment: .leading,
            itemSpacing: horizontalSpacing,
            lineSpacing: verticalSpacing
        ) {
            ForEach(chipViews) { chipView in
                chipView
            }
        }
    }

    private func syncChipViews(count: Int) {
        if chipViews.count > count {
            chipViews.suffix(chipViews.count - count).forEach { $0.removeFromSuperview() }
            chipViews.removeLast(chipViews.count - count)
        }

        while chipViews.count < count {
            let chipView = ProfileChipView()
            chipViews.append(chipView)
        }
    }
}

#Preview {
    UINavigationController(rootViewController: ProfileViewController())
}
