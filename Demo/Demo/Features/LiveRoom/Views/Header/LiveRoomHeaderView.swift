//
//  LiveRoomHeaderView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomHeaderView: LiveRoomCardView {

    private let roomAvatarButton = LiveRoomSymbolButton(frame: .zero)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let audienceButton = LiveRoomTextButton(frame: .zero)
    private let moreImageView = UIImageView(
        image: UIImage(systemName: "ellipsis")
    )

    var audienceDidTap: (() -> Void)?
    var roomAvatarDidTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

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

    private var avatarLayout: Layout {
        roomAvatarButton
            .resizable()
            .frame(width: 46, height: 46)
    }

    private var titleLayout: Layout {
        VStack(alignment: .leading, spacing: 3) {
            titleLabel
            subtitleLabel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var audienceLayout: Layout {
        audienceButton
            .fixedSize(axis: .horizontal)
            .fixedSize(axis: .vertical)
    }

    private var moreLayout: Layout {
        moreImageView
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
    }

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
            cornerRadius: 13,
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

    private func configureViews() {
        roomAvatarButton.configure(
            symbolName: "music.mic.circle.fill",
            symbolSize: 28,
            weight: .semibold,
            tintColor: .systemPink,
            backgroundColor: UIColor.systemPink.withAlphaComponent(0.28),
            cornerRadius: 23
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
        moreImageView.accessibilityLabel = DemoLocalization.text(
            "liveRoom.action.more"
        )
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomHeaderViewPreview() -> UIViewController {
    let view = LiveRoomHeaderView()
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
            LiveRoomBackdropView()
            view.resizable().padding(16)
        }
        .frame(width: 390, height: 150)
    }
}

#Preview("直播间头部") {
    makeLiveRoomHeaderViewPreview()
}
#endif
