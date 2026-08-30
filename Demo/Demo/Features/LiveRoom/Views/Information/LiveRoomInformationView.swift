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
        let roomTitle: String
        let roomSubtitle: String
        let avatarAccessibilityLabel: String
        let liveStatus: String
        let detailsTitle: String
        let roomIDTitle: String
        let roomID: String
        let hostTitle: String
        let hostDisplayName: String
        let audienceTitle: String
        let audienceValue: String
        let announcementTitle: String
        let announcement: String
    }

    let scrollView = QuickLayoutScrollView(.vertical)

    private let backdropView = LiveRoomBackdropView()
    private let profileCardView = LiveRoomCardView()
    private let detailsCardView = LiveRoomCardView()
    private let announcementCardView = LiveRoomCardView()
    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView(
        image: UIImage(systemName: "music.mic.circle.fill")
    )
    private let roomTitleLabel = UILabel()
    private let roomSubtitleLabel = UILabel()
    private let statusDotView = UIView()
    private let liveStatusLabel = UILabel()
    private let statusBackgroundView = UIView()
    private let detailsTitleLabel = UILabel()
    private let roomIDTitleLabel = UILabel()
    private let roomIDValueLabel = UILabel()
    private let hostTitleLabel = UILabel()
    private let hostValueLabel = UILabel()
    private let audienceTitleLabel = UILabel()
    private let audienceValueLabel = UILabel()
    private let firstDividerView = UIView()
    private let secondDividerView = UIView()
    private let announcementTitleLabel = UILabel()
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
        ZStack {
            backdropView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            ScrollView(scrollView, .vertical) {
                VStack(spacing: 14) {
                    profileCard
                    detailsCard
                    announcementCard
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

    private var profileCard: Layout {
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
            roomTitleLabel
                .resizable(axis: .horizontal)
            roomSubtitleLabel
                .resizable(axis: .horizontal)
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
        .background { profileCardView }
    }

    private var detailsCard: Layout {
        VStack(alignment: .leading, spacing: 0) {
            detailsTitleLabel
                .resizable(axis: .horizontal)
                .padding(.bottom, 9)
            detailRow(title: roomIDTitleLabel, value: roomIDValueLabel)
            firstDividerView
                .resizable()
                .frame(height: 1)
            detailRow(title: hostTitleLabel, value: hostValueLabel)
            secondDividerView
                .resizable()
                .frame(height: 1)
            detailRow(title: audienceTitleLabel, value: audienceValueLabel)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .background { detailsCardView }
    }

    private var announcementCard: Layout {
        VStack(alignment: .leading, spacing: 9) {
            announcementTitleLabel
                .resizable(axis: .horizontal)
            announcementLabel
                .resizable(axis: .horizontal)
        }
        .padding(18)
        .background { announcementCardView }
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
        roomTitleLabel.text = content.roomTitle
        roomSubtitleLabel.text = content.roomSubtitle
        avatarImageView.accessibilityLabel = content.avatarAccessibilityLabel
        liveStatusLabel.text = content.liveStatus
        detailsTitleLabel.text = content.detailsTitle
        roomIDTitleLabel.text = content.roomIDTitle
        roomIDValueLabel.text = content.roomID
        hostTitleLabel.text = content.hostTitle
        hostValueLabel.text = content.hostDisplayName
        audienceTitleLabel.text = content.audienceTitle
        audienceValueLabel.text = content.audienceValue
        announcementTitleLabel.text = content.announcementTitle
        announcementLabel.text = content.announcement
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

        configureLabel(
            roomTitleLabel,
            font: .preferredFont(forTextStyle: .title2),
            color: .white,
            alignment: .center
        )
        roomTitleLabel.numberOfLines = 0
        configureLabel(
            roomSubtitleLabel,
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.66),
            alignment: .center
        )
        roomSubtitleLabel.numberOfLines = 0

        statusDotView.backgroundColor = .systemGreen
        statusDotView.layer.cornerRadius = 4
        liveStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        liveStatusLabel.textColor = .systemGreen
        liveStatusLabel.adjustsFontForContentSizeCategory = true
        statusBackgroundView.backgroundColor = UIColor.systemGreen
            .withAlphaComponent(0.13)
        statusBackgroundView.layer.cornerRadius = 14
        statusBackgroundView.layer.cornerCurve = .continuous

        configureLabel(
            detailsTitleLabel,
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        configureDetailTitleLabel(roomIDTitleLabel)
        configureDetailTitleLabel(hostTitleLabel)
        configureDetailTitleLabel(audienceTitleLabel)
        configureDetailValueLabel(roomIDValueLabel)
        configureDetailValueLabel(hostValueLabel)
        configureDetailValueLabel(audienceValueLabel)
        roomIDValueLabel.accessibilityIdentifier =
            "liveRoom.information.roomID"
        hostValueLabel.accessibilityIdentifier =
            "liveRoom.information.host"
        audienceValueLabel.accessibilityIdentifier =
            "liveRoom.information.audience"
        [firstDividerView, secondDividerView].forEach {
            $0.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        }

        configureLabel(
            announcementTitleLabel,
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        configureLabel(
            announcementLabel,
            font: .preferredFont(forTextStyle: .body),
            color: UIColor.white.withAlphaComponent(0.76)
        )
        announcementLabel.numberOfLines = 0
        announcementLabel.accessibilityIdentifier =
            "liveRoom.information.announcement"
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
private func makeLiveRoomInformationViewPreview() -> UIViewController {
    let informationView = LiveRoomInformationView()
    informationView.configure(
        content: LiveRoomInformationView.Content(
            roomTitle: LiveRoomPreviewData.informationRoomTitle,
            roomSubtitle: LiveRoomPreviewData.informationRoomSubtitle,
            avatarAccessibilityLabel: "直播间头像",
            liveStatus: LiveRoomPreviewData.informationLiveStatus,
            detailsTitle: LiveRoomPreviewData.informationDetailsTitle,
            roomIDTitle: LiveRoomPreviewData.informationRoomIDTitle,
            roomID: LiveRoomPreviewData.roomInformation.roomID,
            hostTitle: LiveRoomPreviewData.informationHostTitle,
            hostDisplayName: LiveRoomPreviewData.roomInformation
                .hostDisplayName,
            audienceTitle: LiveRoomPreviewData.informationAudienceTitle,
            audienceValue: LiveRoomPreviewData.informationAudienceValue,
            announcementTitle: LiveRoomPreviewData
                .informationAnnouncementTitle,
            announcement: LiveRoomPreviewData.informationAnnouncement
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
