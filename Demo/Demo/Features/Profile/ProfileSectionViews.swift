//
//  ProfileSectionViews.swift
//  Demo
//
//  Created by Codex on 2026/8/21.
//

import UIKit
import QuickLayout
import QuickLayoutKit

class ProfileSectionView: QuickLayoutView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
    }
}

class ProfileCardView: ProfileSectionView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
    }
}

final class ProfileHeroView: ProfileSectionView {

    private let avatarContainerView = UIView()
    private let avatarImageView = UIImageView()
    private let statusDotView = UIView()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()
    private let locationIconView = UIImageView()
    private let locationLabel = UILabel()
    private let availabilityLabel = UILabel()
    private let availabilityBackgroundView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(
        name: String,
        role: String,
        location: String,
        availability: String
    ) {
        nameLabel.text = name
        roleLabel.text = role
        locationLabel.text = location
        availabilityLabel.text = availability
        setNeedsQuickLayout()
    }

    override var body: Layout {
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
                .background { availabilityBackgroundView }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        statusDotView.layer.borderColor = UIColor.systemBackground.cgColor
    }

    private func setupViews() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 20
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 8)

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

        availabilityBackgroundView.backgroundColor = .systemGreen.withAlphaComponent(0.12)
        availabilityBackgroundView.layer.cornerRadius = 14

    }
}

struct ProfileStatContent: Equatable {
    let value: String
    let title: String
}

final class ProfileStatsView: ProfileSectionView {

    private let projectsView = ProfileStatView()
    private let followersView = ProfileStatView()
    private let responseView = ProfileStatView()

    func configure(
        projects: ProfileStatContent,
        followers: ProfileStatContent,
        response: ProfileStatContent
    ) {
        projectsView.configure(projects)
        followersView.configure(followers)
        responseView.configure(response)
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                statLayout(projectsView)
                statLayout(followersView)
                statLayout(responseView)
            }

            VStack(spacing: 10) {
                statLayout(projectsView)
                statLayout(followersView)
                statLayout(responseView)
            }
        }
    }

    private func statLayout(_ view: ProfileStatView) -> Layout {
        view
            .resizable(axis: .horizontal)
            .frame(height: 86)
    }
}

private final class ProfileStatView: ProfileCardView {

    private let valueLabel = UILabel()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(_ content: ProfileStatContent) {
        valueLabel.text = content.value
        titleLabel.text = content.title
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(spacing: 4) {
            valueLabel
            titleLabel
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private func setupViews() {
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
}

final class ProfileAboutView: ProfileCardView {

    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(title: String, body: String) {
        titleLabel.text = title
        bodyLabel.text = body
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 10) {
            titleLabel
            bodyLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.all, 16)
    }

    private func setupViews() {
        configureProfileSectionTitle(titleLabel)
        bodyLabel.font = .preferredFont(forTextStyle: .body)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0
    }
}

final class ProfileActivityView: ProfileCardView {

    private let sectionTitleLabel = UILabel()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(sectionTitle: String, title: String, detail: String) {
        sectionTitleLabel.text = sectionTitle
        titleLabel.text = title
        detailLabel.text = detail
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleLabel

            HStack(spacing: 12) {
                iconView
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 38)

                VStack(alignment: .leading, spacing: 4) {
                    titleLabel
                    detailLabel
                }

                Spacer()
            }
        }
        .padding(.all, 16)
    }

    private func setupViews() {
        configureProfileSectionTitle(sectionTitleLabel)

        iconView.image = UIImage(systemName: "sparkles")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .center
        iconView.backgroundColor = .systemBlue.withAlphaComponent(0.12)
        iconView.layer.cornerRadius = 10
        iconView.clipsToBounds = true

        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
    }
}

final class ProfileSkillsView: ProfileCardView {

    private let titleLabel = UILabel()
    private let skillCloudView = ProfileSkillCloudView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureProfileSectionTitle(titleLabel)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureProfileSectionTitle(titleLabel)
    }

    func configure(title: String, skills: [String]) {
        titleLabel.text = title
        skillCloudView.configure(titles: skills)
        setNeedsQuickLayout()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 12) {
            titleLabel
            skillCloudView.resizable(axis: .horizontal)
        }
        .padding(.all, 16)
    }
}

final class ProfileActionsView: ProfileSectionView {

    private let messageButton = ProfileActionsView.makeButton(
        style: .filled(),
        imageName: "message.fill"
    )
    private let portfolioButton = ProfileActionsView.makeButton(
        style: .tinted(),
        imageName: "square.grid.2x2.fill"
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        synchronizeButtonDirection()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        synchronizeButtonDirection()
    }

    override var semanticContentAttribute: UISemanticContentAttribute {
        didSet {
            guard semanticContentAttribute != oldValue else { return }
            synchronizeButtonDirection()
        }
    }

    func configure(messageTitle: String, portfolioTitle: String) {
        updateTitle(messageTitle, for: messageButton)
        updateTitle(portfolioTitle, for: portfolioButton)
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                actionLayout(messageButton)
                actionLayout(portfolioButton)
            }

            VStack(spacing: 10) {
                actionLayout(messageButton)
                actionLayout(portfolioButton)
            }
        }
    }

    private func actionLayout(_ button: UIButton) -> Layout {
        button
            .resizable(axis: .horizontal)
            .frame(height: 50)
    }

    private func updateTitle(_ title: String, for button: UIButton) {
        guard var configuration = button.configuration else { return }
        configuration.title = title
        button.configuration = configuration
    }

    private func synchronizeButtonDirection() {
        [messageButton, portfolioButton].forEach {
            $0.semanticContentAttribute = semanticContentAttribute
            $0.setNeedsUpdateConfiguration()
            $0.setNeedsLayout()
        }
    }

    private static func makeButton(
        style: UIButton.Configuration,
        imageName: String
    ) -> UIButton {
        var configuration = style
        configuration.cornerStyle = .large
        configuration.image = UIImage(systemName: imageName)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 8
        return UIButton(configuration: configuration)
    }
}

private final class ProfileSkillCloudView: ProfileSectionView {

    private let horizontalSpacing: CGFloat = 8
    private let verticalSpacing: CGFloat = 8
    private var chipViews: [ProfileChipView] = []

    func configure(titles: [String]) {
        syncChipViews(count: titles.count)
        zip(chipViews, titles).forEach { chipView, title in
            chipView.configure(title: title)
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncChipViews(count: Int) {
        if chipViews.count > count {
            chipViews.suffix(chipViews.count - count).forEach {
                $0.removeFromSuperview()
            }
            chipViews.removeLast(chipViews.count - count)
        }

        while chipViews.count < count {
            chipViews.append(ProfileChipView())
        }
    }
}

private final class ProfileChipView: ProfileSectionView {

    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(title: String) {
        titleLabel.text = title
        setNeedsQuickLayout()
    }

    override var body: Layout {
        titleLabel
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
    }

    private func setupViews() {
        backgroundColor = .systemBlue.withAlphaComponent(0.10)
        layer.cornerRadius = 15
        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .systemBlue
    }
}

private func configureProfileSectionTitle(_ label: UILabel) {
    label.font = .preferredFont(forTextStyle: .headline)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label
    label.textAlignment = .natural
}
