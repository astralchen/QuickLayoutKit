//
//  RoomHeaderView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 展示房间头像、标题和在线人数入口的页头视图。
final class RoomHeaderView: TranslucentCardView {

    /// 打开房间资料页的头像按钮。
    private let roomAvatarButton = SymbolButton(frame: .zero)
    /// 显示组件主标题的标签。
    private let titleLabel = UILabel()
    /// 显示标题补充说明的标签。
    private let subtitleLabel = UILabel()
    /// 显示在线人数并打开观众面板的按钮。
    private let audienceButton = CapsuleTextButton(frame: .zero)
    /// 提示页头可查看更多信息的装饰图标。
    private let moreImageView = UIImageView(
        image: UIImage(systemName: "ellipsis")
    )

    /// 用户点击在线人数入口时调用的回调。
    var audienceDidTap: (() -> Void)?
    /// 用户点击房间头像入口时调用的回调。
    var roomAvatarDidTap: (() -> Void)?

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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 11) {
                avatarLayout
                titleLayout
                audienceLayout
                moreLayout
            }
            .padding(12)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    avatarLayout
                    titleLayout
                }
                HStack(spacing: 8) {
                    audienceLayout
                    Spacer()
                    moreLayout
                }
            }
            .padding(12)
        }
    }

    /// 页头房间头像入口的布局。
    private var avatarLayout: Layout {
        roomAvatarButton
            .resizable()
            .frame(width: 46, height: 46)
    }

    /// 页头主标题与副标题的布局。
    private var titleLayout: Layout {
        VStack(alignment: .leading, spacing: 3) {
            titleLabel
            subtitleLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 页头在线人数入口的布局。
    private var audienceLayout: Layout {
        audienceButton
            .fixedSize(axis: .horizontal)
            .fixedSize(axis: .vertical)
    }

    /// 页头更多信息指示图标的布局。
    private var moreLayout: Layout {
        moreImageView
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
    }

    /// 更新房间文案、在线人数和各导航入口的辅助功能说明。
    func configure(
        roomTitle: String,
        roomSubtitle: String,
        audience: String,
        audienceAccessibilityHint: String,
        avatarAccessibilityLabel: String,
        avatarAccessibilityHint: String
    ) {
        titleLabel.text = roomTitle
        subtitleLabel.text = roomSubtitle
        audienceButton.configure(
            title: audience,
            font: .preferredFont(forTextStyle: .caption1),
            foregroundColor: .white,
            backgroundColor: UIColor.white.withAlphaComponent(0.14),
            contentInsets: EdgeInsets(
                top: 6,
                leading: 9,
                bottom: 6,
                trailing: 9
            )
        )
        audienceButton.accessibilityHint = audienceAccessibilityHint
        roomAvatarButton.accessibilityLabel = avatarAccessibilityLabel
        roomAvatarButton.accessibilityHint = avatarAccessibilityHint
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        roomAvatarButton.configure(
            symbolName: "music.mic.circle.fill",
            symbolSize: 28,
            weight: .semibold,
            tintColor: .systemPink,
            backgroundColor: UIColor.systemPink.withAlphaComponent(0.28)
        )
        roomAvatarButton.accessibilityIdentifier =
            "liveRoom.room.avatar.button"
        roomAvatarButton.action = { [weak self] in
            self?.roomAvatarDidTap?()
        }

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1

        audienceButton.accessibilityIdentifier = "liveRoom.audience.button"
        audienceButton.action = { [weak self] in
            self?.audienceDidTap?()
        }

        moreImageView.tintColor = .white
        moreImageView.contentMode = .scaleAspectFit
        moreImageView.accessibilityLabel = Localization.text(
            "liveRoom.action.more"
        )
    }
}

#if DEBUG
/// 创建展示房间页头的预览控制器。
@MainActor
private func makeRoomHeaderViewPreview() -> UIViewController {
    let view = RoomHeaderView()
    view.configure(
        roomTitle: "预览音乐小屋",
        roomSubtitle: "唱歌 · 聊天 · Preview 专用数据",
        audience: "8,888 人在线",
        audienceAccessibilityHint: "打开在线用户列表",
        avatarAccessibilityLabel: "直播间头像",
        avatarAccessibilityHint: "查看直播间信息"
    )
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView()
            view.resizable(axis: .horizontal).padding(16)
        }
    }
}

@available(iOS 17.0, *)
#Preview("直播间头部") {
    makeRoomHeaderViewPreview()
}
#endif
