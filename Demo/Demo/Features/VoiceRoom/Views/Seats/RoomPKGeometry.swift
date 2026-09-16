import UIKit

/// PK 的测量与渲染共享尺寸，宽度来自容器而非设备型号。
struct RoomPKSeatMetrics {
    let avatarDiameter: CGFloat
    let haloInset: CGFloat
    let microphoneDiameter: CGFloat
    let scoreFontSize: CGFloat
    let nameFontSize: CGFloat
    let scoreHeight: CGFloat
    let nameHeight: CGFloat
    let spacing: CGFloat = 3
    let isHost: Bool

    init(styleID: SeatVisualStyleID, width: CGFloat, sizeClass: SeatSizeClass = .regular) {
        isHost = styleID == .pkHost
        haloInset = isHost ? 8 : 4
        avatarDiameter = max(0, min(isHost ? (sizeClass == .compact ? 60 : 94) : (sizeClass == .compact ? 46 : 58), width - haloInset))
        microphoneDiameter = min(isHost ? 22 : 16, avatarDiameter * 0.45)
        scoreFontSize = isHost ? 12 : 10
        nameFontSize = 14
        scoreHeight = ceil(UIFont.monospacedDigitSystemFont(ofSize: scoreFontSize, weight: .semibold).lineHeight) + 4
        nameHeight = isHost ? ceil(UIFont.systemFont(ofSize: nameFontSize, weight: .semibold).lineHeight) : 0
    }

    var height: CGFloat {
        ceil(avatarDiameter + haloInset + spacing + scoreHeight + (isHost ? spacing + nameHeight : 0))
    }
}

struct RoomPKGeometry {
    static let headerHeight: CGFloat = 24
    let wingWidth: CGFloat
    let centerGap: CGFloat
    let columnSpacing: CGFloat
    let hostSize: CGSize
    let guestSize: CGSize
    let guestOriginY: CGFloat
    let rowSpacing: CGFloat = 10

    init(width: CGFloat, sizeClass: SeatSizeClass = .regular) {
        centerGap = min(20, max(0, width) * 0.05)
        wingWidth = max(0, (width - centerGap) / 2)
        columnSpacing = min(6, wingWidth * 0.03)
        let hostWidth = min(142, max(0, wingWidth - 12))
        let guestWidth = min(64, max(0, (wingWidth - columnSpacing * 3) / 4))
        hostSize = CGSize(width: hostWidth, height: RoomPKSeatMetrics(styleID: .pkHost, width: hostWidth, sizeClass: sizeClass).height)
        guestSize = CGSize(width: guestWidth, height: RoomPKSeatMetrics(styleID: .pkGuest, width: guestWidth, sizeClass: sizeClass).height)
        guestOriginY = Self.headerHeight + hostSize.height + 12
    }

    func frame(side: SeatRoomSide, position: Int) -> CGRect {
        let originX = side == .current ? 0 : wingWidth + centerGap
        if position == 0 {
            return CGRect(x: originX + (wingWidth - hostSize.width) / 2,
                          y: Self.headerHeight, width: hostSize.width, height: hostSize.height)
        }
        let offset = position - 1
        let rowWidth = guestSize.width * 4 + columnSpacing * 3
        return CGRect(x: originX + (wingWidth - rowWidth) / 2 + CGFloat(offset % 4) * (guestSize.width + columnSpacing),
                      y: guestOriginY + CGFloat(offset / 4) * (guestSize.height + rowSpacing),
                      width: guestSize.width, height: guestSize.height)
    }
}
