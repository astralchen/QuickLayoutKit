import AppLocalization
import UIKit

/// 所有房型共用的麦位内容解析；几何尺寸仍由 styleID 和 Metrics 决定。
@MainActor
struct SeatDisplayContent {
    let name: String
    let avatarImage: UIImage?
    let scoreText: String

    init(presentation: SeatSlotPresentation) {
        let assignment = presentation.assignment
        let vacantName = presentation.role.localizedSeatName
        name = assignment?.occupantNameKey.map { Localization.text($0) } ?? vacantName
        if let assignment, assignment.isOccupied {
            avatarImage = assignment.avatarImage
            scoreText = presentation.styleID.isPK
                ? Self.pkScoreText(assignment.score)
                : Localization.text("liveRoom.seat.score", assignment.score)
        } else {
            // 缺失 assignment 和明确的空麦记录必须产生相同内容。
            avatarImage = UIImage(systemName: presentation.role.emptySeatSymbolName)
            scoreText = presentation.styleID.isPK
                ? vacantName
                : Localization.text("liveRoom.seat.available")
        }
    }

    private static func pkScoreText(_ score: Int) -> String {
        guard score >= 10_000 else { return String(score) }
        let precision = score >= 10_000_000 ? 0 : (score >= 1_000_000 ? 1 : 2)
        return Localization.text(
            "liveRoom.pk.score.tenThousands",
            String(format: "%.*f", precision, Double(score) / 10_000)
        )
    }
}

@MainActor
extension SeatRole {
    var localizedSeatName: String {
        switch self {
        case .host:
            Localization.text("liveRoom.userCard.hostSeat")
        case .exclusive:
            Localization.text("liveRoom.seat.eight")
        case .guest(let index):
            Localization.text("liveRoom.userCard.guestSeat", index)
        case .pkLeading, .pkTrailing:
            Localization.text("liveRoom.seat.available")
        }
    }
}
