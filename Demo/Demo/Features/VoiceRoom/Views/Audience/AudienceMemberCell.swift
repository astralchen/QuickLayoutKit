//
//  AudienceMemberCell.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 显示观众头像、参与状态和贡献值的列表单元格。
final class AudienceMemberCell: QuickLayoutCollectionViewCell {

    /// 集合视图注册和复用此单元格时使用的标识。
    static let reuseIdentifier = "VoiceRoomAudienceMemberCell"

    /// 提供头像底色和圆角的背景视图。
    private let avatarBackgroundView = UIView()
    /// 显示用户头像或备用图标的图像视图。
    private let avatarImageView = UIImageView()
    /// 显示用户昵称或空麦名称的标签。
    private let nameLabel = UILabel()
    /// 显示用户在麦或收听状态的标签。
    private let presenceLabel = UILabel()
    /// 显示用户贡献积分的标签。
    private let contributionLabel = UILabel()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        HStack(spacing: 11) {
            ZStack {
                avatarBackgroundView
                    .resizable()
                    .frame(width: 44, height: 44)
                avatarImageView
                    .resizable()
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                nameLabel
                    .resizable(axis: .horizontal)
                presenceLabel
                    .resizable(axis: .horizontal)
            }

            Spacer(minLength: 8)

            contributionLabel
                .fixedSize(axis: .horizontal)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 使用观众资料更新头像、状态、贡献值及辅助功能描述。
    func configure(member: AudienceMember) {
        let color = VoiceRoomTheme.seatColor(at: member.themeIndex)
        avatarBackgroundView.backgroundColor = color.withAlphaComponent(0.22)
        avatarBackgroundView.layer.borderColor = color
            .withAlphaComponent(0.86).cgColor
        avatarImageView.image = member.avatarImage
        nameLabel.text = member.displayName
        switch member.presence {
        case let .onMicrophone(address):
            presenceLabel.text = Localization.text(
                "liveRoom.audience.onMicrophone",
                address.position.rawValue + 1
            )
            presenceLabel.textColor = .systemGreen
        case .listening:
            presenceLabel.text = Localization.text(
                "liveRoom.audience.listening"
            )
            presenceLabel.textColor = UIColor.white.withAlphaComponent(0.54)
        }
        contributionLabel.text = Localization.text(
            "liveRoom.audience.contribution",
            member.contributionScore
        )
        accessibilityLabel = [
            nameLabel.text,
            presenceLabel.text,
            contributionLabel.text,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
        accessibilityIdentifier = "liveRoom.audience.member.\(member.id.rawValue)"
        accessibilityHint = Localization.text(
            "liveRoom.audience.profile.openHint"
        )
        accessibilityTraits.insert(.button)
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        quickLayoutHorizontalFlexibility = .fixedSize
        quickLayoutVerticalFlexibility = .fixedSize
        backgroundColor = UIColor.white.withAlphaComponent(0.055)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        avatarBackgroundView.layer.cornerRadius = 22
        avatarBackgroundView.layer.borderWidth = 2
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.layer.cornerRadius = 22
        avatarImageView.clipsToBounds = true

        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.textColor = .white
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.78

        presenceLabel.font = .preferredFont(forTextStyle: .caption1)
        presenceLabel.adjustsFontForContentSizeCategory = true

        contributionLabel.font = .monospacedDigitSystemFont(
            ofSize: 12,
            weight: .semibold
        )
        contributionLabel.textColor = .systemYellow
        contributionLabel.textAlignment = .right
    }
}

#if DEBUG
/// 创建展示观众列表单元格的预览控制器。
@MainActor
private func makeAudienceMemberCellPreview() -> UIViewController {
    let cell = AudienceMemberCell(frame: .zero)
    cell.configure(member: VoiceRoomPreviewData.audienceMembers[0])
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            cell.resizable().frame(width: .infinity, height: 66)
                .safeAreaPadding(.horizontal, 16)
        }
    }
}

@available(iOS 17.0, *)
#Preview("在线用户 Item") {
    makeAudienceMemberCellPreview()
}
#endif
