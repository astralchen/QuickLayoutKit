import UIKit

/// PK 的测量与渲染共享尺寸，宽度来自容器而非设备型号。
struct RoomPKSeatMetrics {
    /// 按当前样式和容器宽度解析的头像直径，单位为点。
    let avatarDiameter: CGFloat
    /// 光晕外框相对头像直径增加的尺寸，单位为点。
    let haloInset: CGFloat
    /// 麦克风状态背景的直径，单位为点。
    let microphoneDiameter: CGFloat
    /// 积分文字的字号，单位为点。
    let scoreFontSize: CGFloat
    /// 用户名称的字号，单位为点。
    let nameFontSize: CGFloat
    /// 积分行包含上下内边距后的高度，单位为点。
    let scoreHeight: CGFloat
    /// 名称行的高度；不显示名称行时为零，单位为点。
    let nameHeight: CGFloat
    /// 纵向内容行之间的间距，单位为点。
    let spacing: CGFloat = 3
    /// 一个布尔值，指示当前样式是否为 PK 主持麦。
    let isHost: Bool

    /// 根据 PK 视觉样式、可用宽度和尺寸等级解析统一测量参数。
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

    /// 头像、光晕、积分和可选名称行合计的布局高度，单位为点。
    var height: CGFloat {
        ceil(avatarDiameter + haloInset + spacing + scoreHeight + (isHost ? spacing + nameHeight : 0))
    }
}

/// 根据舞台宽度计算双方主持麦和观众麦位置的几何参数。
struct RoomPKGeometry {
    /// PK 房间标记区域的固定高度，单位为点。
    static let headerHeight: CGFloat = 24
    /// 单侧房间的可用布局宽度，单位为点。
    let wingWidth: CGFloat
    /// 本房与对方区域之间的间距，单位为点。
    let centerGap: CGFloat
    /// 同侧观众麦位列之间的间距，单位为点。
    let columnSpacing: CGFloat
    /// 单侧主持麦的布局尺寸，单位为点。
    let hostSize: CGSize
    /// 单个观众麦位的布局尺寸，单位为点。
    let guestSize: CGSize
    /// 第一排观众麦相对舞台顶部的纵向起点，单位为点。
    let guestOriginY: CGFloat
    /// 两排观众麦位之间的间距，单位为点。
    let rowSpacing: CGFloat = 10

    /// 根据舞台宽度和尺寸等级计算 PK 双方的列宽、麦位尺寸与行间距。
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

    /// 返回指定房间侧和零基位置的麦位矩形。
    ///
    /// 本房始终位于物理左侧，对方位于右侧；此规则不随界面布局方向改变。
    ///
    /// - Parameters:
    ///   - side: 麦位所属的房间侧。
    ///   - position: 房间内已校验的零基位置，范围为 `0...8`。
    /// - Returns: 舞台坐标系中的麦位矩形，单位为点。
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
