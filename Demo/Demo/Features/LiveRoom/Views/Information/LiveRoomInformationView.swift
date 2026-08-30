//
//  LiveRoomInformationView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomInformationView: QuickLayoutView {

    struct Content {

        struct Profile {
            let roomTitle: String
            let roomSubtitle: String
            let avatarAccessibilityLabel: String
            let liveStatus: String
        }

        struct Detail {
            let title: String
            let value: String
        }

        struct Details {
            let title: String
            let roomID: Detail
            let host: Detail
            let audience: Detail
        }

        struct Announcement {
            let title: String
            let value: String
        }

        let profile: Profile
        let details: Details
        let announcement: Announcement
    }

    let scrollView = QuickLayoutScrollView(.vertical)

    private let backdropView = LiveRoomBackdropView()
    private let profileCardView = LiveRoomInformationProfileCardView()
    private let detailsCardView = LiveRoomInformationDetailsCardView()
    private let announcementCardView = LiveRoomInformationAnnouncementCardView()

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
                    // 卡片只跟随容器宽度，纵向必须保留内容固有高度，避免滚动测量时被压缩。
                    profileCardView.resizable(axis: .horizontal)
                    detailsCardView.resizable(axis: .horizontal)
                    announcementCardView.resizable(axis: .horizontal)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            // 背景延伸到屏幕边缘，页面内容避让导航栏、刘海与底部安全区域。
            .safeAreaPadding(.all, 0)
        }
    }

    func configure(content: Content) {
        profileCardView.configure(content: content.profile)
        detailsCardView.configure(content: content.details)
        announcementCardView.configure(content: content.announcement)
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "liveRoom.information.view"

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer
    }
}

/// 主播资料卡独立维护自身子视图，页面容器不感知其内部实现。
private final class LiveRoomInformationProfileCardView: QuickLayoutView {

    private let cardView = LiveRoomCardView()
    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView(
        image: UIImage(systemName: "music.mic.circle.fill")
    )
    private let roomTitleLabel = UILabel()
    private let roomSubtitleLabel = UILabel()
    private let statusDotView = UIView()
    private let liveStatusLabel = UILabel()
    private let statusBackgroundView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(spacing: 10) {
            ZStack {
                avatarBackgroundView
                    .resizable()
                    .frame(width: 78, height: 78)
                avatarImageView
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
            }
            roomTitleLabel.resizable(axis: .horizontal)
            roomSubtitleLabel.resizable(axis: .horizontal)
            HStack(spacing: 6) {
                statusDotView
                    .resizable()
                    .frame(width: 8, height: 8)
                liveStatusLabel.fixedSize(axis: .horizontal)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background { statusBackgroundView }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background { cardView }
    }

    func configure(content: LiveRoomInformationView.Content.Profile) {
        roomTitleLabel.text = content.roomTitle
        roomSubtitleLabel.text = content.roomSubtitle
        avatarImageView.accessibilityLabel = content.avatarAccessibilityLabel
        liveStatusLabel.text = content.liveStatus
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer

        avatarBackgroundView.backgroundColor = UIColor.systemPink
            .withAlphaComponent(0.24)
        avatarBackgroundView.layer.cornerRadius = 39
        avatarBackgroundView.layer.cornerCurve = .continuous
        avatarBackgroundView.layer.borderWidth = 2
        avatarBackgroundView.layer.borderColor = UIColor.systemPink
            .withAlphaComponent(0.82).cgColor
        avatarImageView.tintColor = .systemPink
        avatarImageView.contentMode = .scaleAspectFit
        avatarImageView.isAccessibilityElement = true
        avatarImageView.accessibilityTraits = .image

        roomTitleLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .title2),
            color: .white,
            alignment: .center
        )
        roomTitleLabel.numberOfLines = 0
        roomSubtitleLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.66),
            alignment: .center
        )
        roomSubtitleLabel.numberOfLines = 0

        statusDotView.backgroundColor = .systemGreen
        statusDotView.layer.cornerRadius = 4
        liveStatusLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .caption1),
            color: .systemGreen
        )
        statusBackgroundView.backgroundColor = UIColor.systemGreen
            .withAlphaComponent(0.13)
        statusBackgroundView.layer.cornerRadius = 14
        statusBackgroundView.layer.cornerCurve = .continuous
    }
}

/// 详情卡只负责组合语义行，避免页面持有成组的标题、值与分隔线属性。
private final class LiveRoomInformationDetailsCardView: QuickLayoutView {

    private let cardView = LiveRoomCardView()
    private let titleLabel = UILabel()
    private let roomIDRowView = LiveRoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.roomID"
    )
    private let hostRowView = LiveRoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.host"
    )
    private let audienceRowView = LiveRoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.audience"
    )
    private let firstDividerView = UIView()
    private let secondDividerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 0) {
            titleLabel
                .resizable(axis: .horizontal)
                .padding(.bottom, 9)
            // 详情行同样只横向伸缩，Dynamic Type 下不能牺牲文本高度。
            roomIDRowView.resizable(axis: .horizontal)
            firstDividerView
                .resizable()
                .frame(height: 1)
            hostRowView.resizable(axis: .horizontal)
            secondDividerView
                .resizable()
                .frame(height: 1)
            audienceRowView.resizable(axis: .horizontal)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background { cardView }
    }

    func configure(content: LiveRoomInformationView.Content.Details) {
        titleLabel.text = content.title
        roomIDRowView.configure(
            title: content.roomID.title,
            value: content.roomID.value
        )
        hostRowView.configure(
            title: content.host.title,
            value: content.host.value
        )
        audienceRowView.configure(
            title: content.audience.title,
            value: content.audience.value
        )
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        [firstDividerView, secondDividerView].forEach {
            $0.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        }
    }
}

private final class LiveRoomInformationDetailRowView: QuickLayoutView {

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    init(valueAccessibilityIdentifier: String) {
        super.init(frame: .zero)
        valueLabel.accessibilityIdentifier = valueAccessibilityIdentifier
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        HStack(alignment: .center, spacing: 16) {
            titleLabel.fixedSize(axis: .horizontal)
            Spacer(minLength: 12)
            valueLabel.resizable(axis: .horizontal)
        }
        .padding(.vertical, 12)
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.58)
        )
        valueLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .body),
            color: .white
        )
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byTruncatingMiddle
    }
}

private final class LiveRoomInformationAnnouncementCardView: QuickLayoutView {

    private let cardView = LiveRoomCardView()
    private let titleLabel = UILabel()
    private let announcementLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: 9) {
            titleLabel.resizable(axis: .horizontal)
            announcementLabel.resizable(axis: .horizontal)
        }
        .padding(18)
        .background { cardView }
    }

    func configure(content: LiveRoomInformationView.Content.Announcement) {
        titleLabel.text = content.title
        announcementLabel.text = content.value
        setNeedsQuickLayout()
    }

    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        announcementLabel.configureLiveRoomInformation(
            font: .preferredFont(forTextStyle: .body),
            color: UIColor.white.withAlphaComponent(0.76)
        )
        announcementLabel.numberOfLines = 0
        announcementLabel.accessibilityIdentifier =
            "liveRoom.information.announcement"
    }
}

private extension UILabel {

    func configureLiveRoomInformation(
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .natural
    ) {
        self.font = font
        textColor = color
        textAlignment = alignment
        adjustsFontForContentSizeCategory = true
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomInformationViewPreview() -> UIViewController {
    let informationView = LiveRoomInformationView()
    informationView.configure(
        content: LiveRoomInformationView.Content(
            profile: .init(
                roomTitle: LiveRoomPreviewData.informationRoomTitle,
                roomSubtitle: LiveRoomPreviewData.informationRoomSubtitle,
                avatarAccessibilityLabel: "直播间头像",
                liveStatus: LiveRoomPreviewData.informationLiveStatus
            ),
            details: .init(
                title: LiveRoomPreviewData.informationDetailsTitle,
                roomID: .init(
                    title: LiveRoomPreviewData.informationRoomIDTitle,
                    value: LiveRoomPreviewData.roomInformation.roomID
                ),
                host: .init(
                    title: LiveRoomPreviewData.informationHostTitle,
                    value: LiveRoomPreviewData.roomInformation.hostDisplayName
                ),
                audience: .init(
                    title: LiveRoomPreviewData.informationAudienceTitle,
                    value: LiveRoomPreviewData.informationAudienceValue
                )
            ),
            announcement: .init(
                title: LiveRoomPreviewData.informationAnnouncementTitle,
                value: LiveRoomPreviewData.informationAnnouncement
            )
        )
    )
    return QuickLayoutHostingController {
        informationView.resizable()
    }
}

#Preview("直播间信息") {
    makeLiveRoomInformationViewPreview()
}
#endif
