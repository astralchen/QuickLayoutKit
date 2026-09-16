import AppLocalization
import UIKit

/// 所有房型共用的麦位内容解析；几何尺寸仍由 styleID 和 Metrics 决定。
@MainActor
struct SeatDisplayContent {
    /// 按占麦用户或空麦角色解析的本地化名称。
    let name: String
    /// 按当前用户或空麦角色解析的头像图像。
    let avatarImage: UIImage?
    /// 积分或空麦状态的显示文案。
    let scoreText: String

    /// 根据占麦用户和布局角色解析名称、头像及积分或空麦文案。
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

    /// 将 PK 积分转换为紧凑显示文案。
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
    /// 按主持麦、普通麦或专属座角色生成的本地化空麦名称。
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
