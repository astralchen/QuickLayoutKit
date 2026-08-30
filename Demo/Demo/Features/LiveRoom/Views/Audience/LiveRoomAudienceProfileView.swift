//
//  LiveRoomAudienceProfileView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomAudienceProfileView: QuickLayoutView {

    struct Content {
        let displayName: String
        let avatarImage: UIImage?
        let avatarAccessibilityLabel: String
        let presence: String
        let detailsTitle: String
        let memberIDTitle: String
        let memberID: String
        let contributionTitle: String
        let contribution: String
        let aboutTitle: String
        let about: String
        let themeColor: UIColor
    }

    let scrollView = QuickLayoutScrollView(.vertical)

    private let backdropView = LiveRoomBackdropView()
    private let heroCardView = LiveRoomCardView()
    private let detailsCardView = LiveRoomCardView()
    private let aboutCardView = LiveRoomCardView()
    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView()
    private let displayNameLabel = UILabel()
    private let presenceLabel = UILabel()
    private let presenceBackgroundView = UIView()
    private let detailsTitleLabel = UILabel()
    private let memberIDTitleLabel = UILabel()
    private let memberIDValueLabel = UILabel()
    private let contributionTitleLabel = UILabel()
    private let contributionValueLabel = UILabel()
    private let dividerView = UIView()
    private let aboutTitleLabel = UILabel()
    private let aboutLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        ZStack {
            backdropView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            ScrollView(scrollView, .vertical) {
                VStack(spacing: 14) {
                    heroCard
                    detailsCard
                    aboutCard
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            // 背景铺满屏幕，主页内容统一避让导航栏和底部安全区域。
            .safeAreaPadding(.all, 0)
        }
    }

    private var heroCard: Layout {
        VStack(spacing: 12) {
            ZStack {
                avatarBackgroundView
                    .resizable()
                    .frame(width: 108, height: 108)
                avatarImageView
                    .resizable()
                    .frame(width: 108, height: 108)
            }

            displayNameLabel
                .resizable(axis: .horizontal)
                .frame(maxWidth: .infinity, alignment: .center)

            presenceLabel
                .fixedSize(axis: .horizontal)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background { presenceBackgroundView }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .background { heroCardView }
    }

    private var detailsCard: Layout {
        VStack(alignment: .leading, spacing: 0) {
            detailsTitleLabel
                .resizable(axis: .horizontal)
                .padding(.bottom, 9)
            detailRow(
                title: memberIDTitleLabel,
                value: memberIDValueLabel
            )
            dividerView
                .resizable()
                .frame(height: 1)
            detailRow(
                title: contributionTitleLabel,
                value: contributionValueLabel
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background { detailsCardView }
    }

    private var aboutCard: Layout {
        VStack(alignment: .leading, spacing: 9) {
            aboutTitleLabel.resizable(axis: .horizontal)
            aboutLabel.resizable(axis: .horizontal)
        }
        .padding(18)
        .background { aboutCardView }
    }

    private func detailRow(title: UILabel, value: UILabel) -> Layout {
        HStack(alignment: .center, spacing: 16) {
            title.fixedSize(axis: .horizontal)
            Spacer(minLength: 12)
            value.resizable(axis: .horizontal)
        }
        .padding(.vertical, 12)
    }

    func configure(content: Content) {
        displayNameLabel.text = content.displayName
        avatarImageView.image = content.avatarImage
        avatarImageView.accessibilityLabel = content.avatarAccessibilityLabel
        presenceLabel.text = content.presence
        detailsTitleLabel.text = content.detailsTitle
        memberIDTitleLabel.text = content.memberIDTitle
        memberIDValueLabel.text = content.memberID
        contributionTitleLabel.text = content.contributionTitle
        contributionValueLabel.text = content.contribution
        aboutTitleLabel.text = content.aboutTitle
        aboutLabel.text = content.about

        avatarBackgroundView.backgroundColor = content.themeColor
            .withAlphaComponent(0.22)
        avatarBackgroundView.layer.borderColor = content.themeColor
            .withAlphaComponent(0.88).cgColor
        presenceLabel.textColor = content.themeColor
        presenceBackgroundView.backgroundColor = content.themeColor
            .withAlphaComponent(0.14)
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "liveRoom.audience.profile.view"

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        avatarBackgroundView.layer.cornerRadius = 54
        avatarBackgroundView.layer.cornerCurve = .continuous
        avatarBackgroundView.layer.borderWidth = 3
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 54
        avatarImageView.clipsToBounds = true
        avatarImageView.isAccessibilityElement = true
        avatarImageView.accessibilityTraits = .image

        configureLabel(
            displayNameLabel,
            font: .preferredFont(forTextStyle: .title1),
            color: .white,
            alignment: .center
        )
        displayNameLabel.numberOfLines = 0
        displayNameLabel.accessibilityIdentifier =
            "liveRoom.audience.profile.name"

        configureLabel(
            presenceLabel,
            font: .preferredFont(forTextStyle: .subheadline),
            color: .systemGreen,
            alignment: .center
        )
        presenceBackgroundView.layer.cornerRadius = 16
        presenceBackgroundView.layer.cornerCurve = .continuous

        configureLabel(
            detailsTitleLabel,
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        configureDetailTitleLabel(memberIDTitleLabel)
        configureDetailTitleLabel(contributionTitleLabel)
        configureDetailValueLabel(memberIDValueLabel)
        configureDetailValueLabel(contributionValueLabel)
        memberIDValueLabel.accessibilityIdentifier =
            "liveRoom.audience.profile.memberID"
        contributionValueLabel.accessibilityIdentifier =
            "liveRoom.audience.profile.contribution"
        dividerView.backgroundColor = UIColor.white.withAlphaComponent(0.09)

        configureLabel(
            aboutTitleLabel,
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        configureLabel(
            aboutLabel,
            font: .preferredFont(forTextStyle: .body),
            color: UIColor.white.withAlphaComponent(0.76)
        )
        aboutLabel.numberOfLines = 0
        aboutLabel.accessibilityIdentifier =
            "liveRoom.audience.profile.about"
    }

    private func configureDetailTitleLabel(_ label: UILabel) {
        configureLabel(
            label,
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.58)
        )
    }

    private func configureDetailValueLabel(_ label: UILabel) {
        configureLabel(
            label,
            font: .preferredFont(forTextStyle: .body),
            color: .white
        )
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingMiddle
    }

    private func configureLabel(
        _ label: UILabel,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) {
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        label.adjustsFontForContentSizeCategory = true
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomAudienceProfileViewPreview() -> UIViewController {
    let member = LiveRoomPreviewData.audienceMembers[1]
    let profileView = LiveRoomAudienceProfileView()
    profileView.configure(
        content: LiveRoomAudienceProfileView.Content(
            displayName: member.displayName,
            avatarImage: member.avatarImage,
            avatarAccessibilityLabel: "用户头像",
            presence: "2 号麦",
            detailsTitle: "用户资料",
            memberIDTitle: "用户 ID",
            memberID: String(member.id),
            contributionTitle: "贡献值",
            contribution: "⭐ 12,280",
            aboutTitle: "个人简介",
            about: "喜欢音乐，也喜欢在直播间认识有趣的人。",
            themeColor: LiveRoomTheme.seatColor(at: member.themeIndex)
        )
    )
    return QuickLayoutHostingController {
        profileView.resizable()
    }
}

#Preview("在线用户主页") {
    makeLiveRoomAudienceProfileViewPreview()
}
#endif
