//
//  LiveRoomAudienceMemberCell.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomAudienceMemberCell: QuickLayoutCollectionViewCell {

    static let reuseIdentifier = "LiveRoomAudienceMemberCell"

    private let avatarBackgroundView = UIView()
    private let avatarImageView = UIImageView()
    private let nameLabel = UILabel()
    private let presenceLabel = UILabel()
    private let contributionLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        return nil
    }

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

    func configure(member: LiveRoomAudienceMember) {
        let color = LiveRoomTheme.seatColor(at: member.themeIndex)
        avatarBackgroundView.backgroundColor = color.withAlphaComponent(0.22)
        avatarBackgroundView.layer.borderColor = color
            .withAlphaComponent(0.86).cgColor
        avatarImageView.image = member.avatarImage
        nameLabel.text = member.displayName
        switch member.presence {
        case let .onMicrophone(seatNumber):
            presenceLabel.text = DemoLocalization.text(
                "liveRoom.audience.onMicrophone",
                seatNumber
            )
            presenceLabel.textColor = .systemGreen
        case .listening:
            presenceLabel.text = DemoLocalization.text(
                "liveRoom.audience.listening"
            )
            presenceLabel.textColor = UIColor.white.withAlphaComponent(0.54)
        }
        contributionLabel.text = DemoLocalization.text(
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
        accessibilityIdentifier = "liveRoom.audience.member.\(member.id)"
        accessibilityHint = DemoLocalization.text(
            "liveRoom.audience.profile.openHint"
        )
        accessibilityTraits.insert(.button)
        setNeedsQuickLayout()
    }

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
@MainActor
private func makeLiveRoomAudienceMemberCellPreview() -> UIViewController {
    let cell = LiveRoomAudienceMemberCell(frame: .zero)
    cell.configure(member: LiveRoomPreviewData.audienceMembers[0])
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
            cell.resizable().frame(width: .infinity, height: 66)
                .safeAreaPadding(.horizontal, 16)
        }
    }
}

#Preview("在线用户 Item") {
    makeLiveRoomAudienceMemberCellPreview()
}
#endif
