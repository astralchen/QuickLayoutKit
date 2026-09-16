//
//  RoomInformationView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 组合房间概览、详细资料和公告卡片的页面内容视图。
final class RoomInformationView: QuickLayoutView {

    /// 一次刷新所需的完整显示内容。
    struct Content {

        /// 房间概览卡片所需的显示文案。
        struct Profile {
            /// 房间的显示标题。
            let roomTitle: String
            /// 房间标题下的补充说明。
            let roomSubtitle: String
            /// 辅助功能读取头像时使用的描述。
            let avatarAccessibilityLabel: String
            /// 房间直播状态的显示文案。
            let liveStatus: String
        }

        /// 一个资料字段的标题和值。
        struct Detail {
            /// 当前区域或字段的显示标题。
            let title: String
            /// 当前字段的显示值。
            let value: String
        }

        /// 房间号、主播和在线人数字段的完整内容。
        struct Details {
            /// 当前区域或字段的显示标题。
            let title: String
            /// 房间号字段的标题与显示值。
            let roomID: Detail
            /// 主播字段的标题与显示值。
            let host: Detail
            /// 在线人数字段的标题与显示值。
            let audience: Detail
        }

        /// 公告区域的标题与正文。
        struct Announcement {
            /// 当前区域或字段的显示标题。
            let title: String
            /// 当前字段的显示值。
            let value: String
        }

        /// 房间概览卡片的显示内容。
        let profile: Profile
        /// 房间详细资料卡片的显示内容。
        let details: Details
        /// 房间公告卡片的显示内容。
        let announcement: Announcement
    }

    /// 承载内容并处理滚动的视图。
    let scrollView = QuickLayoutScrollView(.vertical)

    /// 页面使用的星点渐变背景视图。
    private let backdropView = StarfieldBackgroundView()
    /// 显示房间名称、说明和直播状态的概览卡片。
    private let profileCardView = RoomInformationProfileCardView()
    /// 详细资料区域的卡片背景。
    private let detailsCardView = RoomInformationDetailsCardView()
    /// 显示房间公告标题和正文的卡片。
    private let announcementCardView = RoomInformationAnnouncementCardView()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 将完整房间内容分别应用到概览、资料和公告卡片。
    func configure(content: Content) {
        profileCardView.configure(content: content.profile)
        detailsCardView.configure(content: content.details)
        announcementCardView.configure(content: content.announcement)
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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
private final class RoomInformationProfileCardView: QuickLayoutView {

    /// 显示占麦用户资料的卡片内容视图。
    private let cardView = TranslucentCardView()
    /// 提供头像底色和圆角的背景视图。
    private let avatarBackgroundView = UIView()
    /// 显示用户头像或备用图标的图像视图。
    private let avatarImageView = UIImageView(
        image: UIImage(systemName: "music.mic.circle.fill")
    )
    /// 显示房间名称的标签。
    private let roomTitleLabel = UILabel()
    /// 显示房间副标题的标签。
    private let roomSubtitleLabel = UILabel()
    /// 表示直播状态的圆点装饰。
    private let statusDotView = UIView()
    /// 显示直播状态文案的标签。
    private let liveStatusLabel = UILabel()
    /// 直播状态文字与圆点后方的背景。
    private let statusBackgroundView = UIView()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 更新房间概览标题、副标题和直播状态。
    func configure(content: RoomInformationView.Content.Profile) {
        roomTitleLabel.text = content.roomTitle
        roomSubtitleLabel.text = content.roomSubtitle
        avatarImageView.accessibilityLabel = content.avatarAccessibilityLabel
        liveStatusLabel.text = content.liveStatus
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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

        roomTitleLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .title2),
            color: .white,
            alignment: .center
        )
        roomTitleLabel.numberOfLines = 0
        roomSubtitleLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.66),
            alignment: .center
        )
        roomSubtitleLabel.numberOfLines = 0

        statusDotView.backgroundColor = .systemGreen
        statusDotView.layer.cornerRadius = 4
        liveStatusLabel.configureVoiceRoomInformation(
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
private final class RoomInformationDetailsCardView: QuickLayoutView {

    /// 显示占麦用户资料的卡片内容视图。
    private let cardView = TranslucentCardView()
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示房间号字段的资料行。
    private let roomIDRowView = RoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.roomID"
    )
    /// 显示主播字段的资料行。
    private let hostRowView = RoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.host"
    )
    /// 显示在线人数字段的资料行。
    private let audienceRowView = RoomInformationDetailRowView(
        valueAccessibilityIdentifier: "liveRoom.information.audience"
    )
    /// 分隔第一行与第二行资料的细线视图。
    private let firstDividerView = UIView()
    /// 分隔第二行与第三行资料的细线视图。
    private let secondDividerView = UIView()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 更新资料卡片标题及房间号、主播和在线人数三行内容。
    func configure(content: RoomInformationView.Content.Details) {
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

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        [firstDividerView, secondDividerView].forEach {
            $0.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        }
    }
}

/// 以一致间距和对齐方式展示一组资料标题和值的行视图。
private final class RoomInformationDetailRowView: QuickLayoutView {

    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示当前字段值的标签。
    private let valueLabel = UILabel()

    /// 创建资料行，并为字段值设置指定的辅助功能标识。
    init(valueAccessibilityIdentifier: String) {
        super.init(frame: .zero)
        valueLabel.accessibilityIdentifier = valueAccessibilityIdentifier
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        HStack(alignment: .center, spacing: 16) {
            titleLabel.fixedSize(axis: .horizontal)
            Spacer(minLength: 12)
            valueLabel.resizable(axis: .horizontal)
        }
        .padding(.vertical, 12)
    }

    /// 更新该资料行的标题和值。
    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.58)
        )
        valueLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .body),
            color: .white
        )
        valueLabel.numberOfLines = 0
        valueLabel.lineBreakMode = .byTruncatingMiddle
    }
}

/// 展示房间公告标题和多行正文的卡片视图。
private final class RoomInformationAnnouncementCardView: QuickLayoutView {

    /// 显示占麦用户资料的卡片内容视图。
    private let cardView = TranslucentCardView()
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示房间公告正文的标签。
    private let announcementLabel = UILabel()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        VStack(alignment: .leading, spacing: 9) {
            titleLabel.resizable(axis: .horizontal)
            announcementLabel.resizable(axis: .horizontal)
        }
        .padding(18)
        .background { cardView }
    }

    /// 更新公告标题和正文。
    func configure(content: RoomInformationView.Content.Announcement) {
        titleLabel.text = content.title
        announcementLabel.text = content.value
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        titleLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .headline),
            color: .white
        )
        announcementLabel.configureVoiceRoomInformation(
            font: .preferredFont(forTextStyle: .body),
            color: UIColor.white.withAlphaComponent(0.76)
        )
        announcementLabel.numberOfLines = 0
        announcementLabel.accessibilityIdentifier =
            "liveRoom.information.announcement"
    }
}

private extension UILabel {

    /// 应用房间资料标签共用的字体、颜色、对齐和多行显示设置。
    func configureVoiceRoomInformation(
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
/// 创建展示房间资料内容的预览控制器。
@MainActor
private func makeRoomInformationViewPreview() -> UIViewController {
    let informationView = RoomInformationView()
    informationView.configure(
        content: RoomInformationView.Content(
            profile: .init(
                roomTitle: VoiceRoomPreviewData.informationRoomTitle,
                roomSubtitle: VoiceRoomPreviewData.informationRoomSubtitle,
                avatarAccessibilityLabel: "直播间头像",
                liveStatus: VoiceRoomPreviewData.informationLiveStatus
            ),
            details: .init(
                title: VoiceRoomPreviewData.informationDetailsTitle,
                roomID: .init(
                    title: VoiceRoomPreviewData.informationRoomIDTitle,
                    value: VoiceRoomPreviewData.roomInformation.roomID
                ),
                host: .init(
                    title: VoiceRoomPreviewData.informationHostTitle,
                    value: VoiceRoomPreviewData.roomInformation.hostDisplayName
                ),
                audience: .init(
                    title: VoiceRoomPreviewData.informationAudienceTitle,
                    value: VoiceRoomPreviewData.informationAudienceValue
                )
            ),
            announcement: .init(
                title: VoiceRoomPreviewData.informationAnnouncementTitle,
                value: VoiceRoomPreviewData.informationAnnouncement
            )
        )
    )
    return QuickLayoutHostingController {
        informationView.resizable()
    }
}

@available(iOS 17.0, *)
#Preview("直播间信息") {
    makeRoomInformationViewPreview()
}
#endif
