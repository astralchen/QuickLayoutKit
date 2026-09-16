//
//  AudienceProfileView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 呈现观众头像、身份信息和简介的资料页视图。
final class AudienceProfileView: QuickLayoutView {

    /// 一次刷新所需的完整显示内容。
    struct Content {
        /// 界面显示的用户昵称。
        let displayName: String
        /// 内容中使用的用户头像图像。
        let avatarImage: UIImage?
        /// 辅助功能读取头像时使用的描述。
        let avatarAccessibilityLabel: String
        /// 已经本地化的用户参与状态文案。
        let presence: String
        /// 详细资料区域的标题。
        let detailsTitle: String
        /// 用户标识字段的标题。
        let memberIDTitle: String
        /// 用于资料页显示的用户标识字符串。
        let memberID: String
        /// 贡献积分字段的标题。
        let contributionTitle: String
        /// 已格式化的贡献积分文案。
        let contribution: String
        /// 用户简介区域的标题。
        let aboutTitle: String
        /// 用户简介正文。
        let about: String
        /// 当前内容使用的主题颜色。
        let themeColor: UIColor
    }

    /// 承载内容并处理滚动的视图。
    let scrollView = QuickLayoutScrollView(.vertical)

    /// 页面使用的星点渐变背景视图。
    private let backdropView = StarfieldBackgroundView()
    /// 页头主要信息区域的卡片背景。
    private let heroCardView = TranslucentCardView()
    /// 详细资料区域的卡片背景。
    private let detailsCardView = TranslucentCardView()
    /// 用户简介区域的卡片背景。
    private let aboutCardView = TranslucentCardView()
    /// 提供头像底色和圆角的背景视图。
    private let avatarBackgroundView = UIView()
    /// 显示用户头像或备用图标的图像视图。
    private let avatarImageView = UIImageView()
    /// 显示用户昵称的标签。
    private let displayNameLabel = UILabel()
    /// 显示用户在麦或收听状态的标签。
    private let presenceLabel = UILabel()
    /// 参与状态标签的背景视图。
    private let presenceBackgroundView = UIView()
    /// 显示详细资料区域标题的标签。
    private let detailsTitleLabel = UILabel()
    /// 显示用户标识字段标题的标签。
    private let memberIDTitleLabel = UILabel()
    /// 显示用户标识值的标签。
    private let memberIDValueLabel = UILabel()
    /// 显示贡献积分字段标题的标签。
    private let contributionTitleLabel = UILabel()
    /// 显示已格式化贡献积分的标签。
    private let contributionValueLabel = UILabel()
    /// 分隔相邻内容区域的细线视图。
    private let dividerView = UIView()
    /// 显示用户简介标题的标签。
    private let aboutTitleLabel = UILabel()
    /// 显示用户简介正文的标签。
    private let aboutLabel = UILabel()

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

    /// 组合页头图像、标题和状态的卡片布局。
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

    /// 组合资料标题和各字段行的卡片布局。
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

    /// 组合简介标题与正文的卡片布局。
    private var aboutCard: Layout {
        VStack(alignment: .leading, spacing: 9) {
            aboutTitleLabel.resizable(axis: .horizontal)
            aboutLabel.resizable(axis: .horizontal)
        }
        .padding(18)
        .background { aboutCardView }
    }

    /// 返回由字段标题和值组成的一行资料布局。
    private func detailRow(title: UILabel, value: UILabel) -> Layout {
        HStack(alignment: .center, spacing: 16) {
            title.fixedSize(axis: .horizontal)
            Spacer(minLength: 12)
            value.resizable(axis: .horizontal)
        }
        .padding(.vertical, 12)
    }

    /// 应用完整资料内容，并刷新对应文本、头像和主题色。
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

    /// 配置子视图的样式、交互和辅助功能属性。
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

    /// 为资料字段标题设置统一字体和次要文本颜色。
    private func configureDetailTitleLabel(_ label: UILabel) {
        configureLabel(
            label,
            font: .preferredFont(forTextStyle: .subheadline),
            color: UIColor.white.withAlphaComponent(0.58)
        )
    }

    /// 为资料字段值设置字体、颜色及显示优先级。
    private func configureDetailValueLabel(_ label: UILabel) {
        configureLabel(
            label,
            font: .preferredFont(forTextStyle: .body),
            color: .white
        )
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingMiddle
    }

    /// 应用指定字体、颜色和对齐方式的标签样式。
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
/// 创建展示观众资料视图的预览控制器。
@MainActor
private func makeAudienceProfileViewPreview() -> UIViewController {
    let member = VoiceRoomPreviewData.audienceMembers[1]
    let profileView = AudienceProfileView()
    profileView.configure(
        content: AudienceProfileView.Content(
            displayName: member.displayName,
            avatarImage: member.avatarImage,
            avatarAccessibilityLabel: "用户头像",
            presence: "2 号麦",
            detailsTitle: "用户资料",
            memberIDTitle: "用户 ID",
            memberID: member.id.rawValue,
            contributionTitle: "贡献值",
            contribution: "⭐ 12,280",
            aboutTitle: "个人简介",
            about: "喜欢音乐，也喜欢在直播间认识有趣的人。",
            themeColor: VoiceRoomTheme.seatColor(at: member.themeIndex)
        )
    )
    return QuickLayoutHostingController {
        profileView.resizable()
    }
}

@available(iOS 17.0, *)
#Preview("在线用户主页") {
    makeAudienceProfileViewPreview()
}
#endif
