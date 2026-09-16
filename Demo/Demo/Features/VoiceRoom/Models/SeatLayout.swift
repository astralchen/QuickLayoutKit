//
//  SeatLayout.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import CoreGraphics
import Foundation

/// 客户端布局目录中的稳定布局标识。
struct SeatLayoutID: Hashable, Sendable, RawRepresentable {
    /// 客户端布局目录中的原始标识字符串。
    let rawValue: String

    /// 双方各九个麦位的厅 PK 布局标识。
    static let roomPKNine = Self(rawValue: "pk.room.nine")
    /// 派对房九麦布局的标识。
    static let partyNine = Self(rawValue: "party.nine")
    /// 个播房主持麦与观众席布局的标识。
    static let individualAudience = Self(rawValue: "individual.audience")
}

/// 舞台结构所属的客户端布局家族。
enum SeatLayoutFamily: Equatable, Sendable {
    /// 派对房的麦位网格布局。
    case partyGrid
    /// 个播房主持麦与可收起观众席的布局。
    case individualAudience
    /// 指定样式的跨房 PK 布局。
    case pk(styleID: String)
}

/// 同一个布局定义在不同业务状态下的展示变体。
enum SeatLayoutVariant: Equatable, Sendable {
    /// 使用布局的标准展示形态。
    case standard
    /// 收起观众麦位，仅展示主持麦。
    case collapsed
    /// 展开布局中的观众麦位。
    case expanded
}

/// Slot 在业务布局中的语义角色。
nonisolated enum SeatRole: Equatable, Sendable {
    /// 房间主持麦角色。
    case host
    /// 指定零基位置的普通观众麦角色。
    case guest(index: Int)
    /// 房间专属座角色。
    case exclusive
    /// PK 布局前导区域的语义角色。
    case pkLeading
    /// PK 布局尾随区域的语义角色。
    case pkTrailing

    /// 房内角色只按协议位置映射，房型、左右侧和 slotID 文本不参与判断。
    static func roomSeat(at position: SeatPosition) -> Self {
        switch position.rawValue {
        case 0: .host
        case 8: .exclusive
        default: .guest(index: position.rawValue)
        }
    }

    /// 此角色处于空麦状态时使用的 SF Symbols 名称。
    var emptySeatSymbolName: String {
        self == .exclusive ? "sofa.fill" : "person.crop.circle"
    }
}

/// 麦位视图使用的语义视觉 Token。
///
/// View 根据 Token 和当前设备环境解析像素，不允许服务端直接控制尺寸和颜色。
enum SeatVisualStyleID: Equatable, Sendable {
    /// PK 主持麦的视觉尺寸样式。
    case pkHost
    /// PK 观众麦的视觉尺寸样式。
    case pkGuest
    /// 标准主持麦的视觉尺寸样式。
    case standardHost
    /// 突出显示的放大主持麦样式。
    case emphasizedHost
    /// 标准观众麦的视觉尺寸样式。
    case standardGuest
    /// 专属座的视觉尺寸样式。
    case exclusive

    /// 一个布尔值，指示当前样式是否属于 PK 布局。
    var isPK: Bool { self == .pkHost || self == .pkGuest }
}

/// 布局位置随展开状态变化的可见性规则。
enum SeatSlotVisibility: Equatable, Sendable {
    /// 始终显示此布局位置。
    case always
    /// 仅在观众席展开时显示此布局位置。
    case whenExpanded
}

/// 麦位允许响应的用户操作。
enum SeatInteraction: Equatable, Sendable {
    /// 允许打开占麦用户的资料卡。
    case showUserCard
    /// 不提供麦位点击操作。
    case none
}

/// 与整个舞台绑定、但不属于单个麦位的装饰描述。
struct RoomStageDecoration: Equatable, Sendable {
    /// 舞台装饰的稳定语义标识。
    let id: String
}

/// 客户端布局目录中一个麦位位置的定义。
struct SeatSlotDefinition: Equatable, Sendable {
    /// 客户端布局中的稳定语义位置标识。
    let slotID: SeatSlotID
    /// 麦位在所属房间中的零基位置。
    let position: SeatPosition
    /// 麦位的业务角色，不由视觉尺寸推断。
    let role: SeatRole
    /// 客户端用于解析麦位视觉尺寸的样式标识。
    let styleID: SeatVisualStyleID
    /// 该位置随舞台展开状态变化的可见性规则。
    let visibility: SeatSlotVisibility
    /// 麦位所属的房间；PK 双方独立编号。
    var roomSide: SeatRoomSide = .current
    /// 结合所属房间与零基位置得到的麦位地址。
    var address: SeatAddress { SeatAddress(roomSide: roomSide, position: position) }
}

/// 客户端受控的布局定义。
struct SeatLayoutDefinition: Equatable, Sendable {
    /// 此布局在客户端目录中的稳定标识。
    let id: SeatLayoutID
    /// 用于选择几何计算规则的布局家族。
    let layoutFamily: SeatLayoutFamily
    /// 布局允许的最大麦位数量。
    let capacity: Int
    /// 按布局定义顺序排列的麦位位置。
    let slots: [SeatSlotDefinition]
    /// 与舞台一起呈现的装饰描述。
    let decorations: [RoomStageDecoration]
}

/// 经过校验并绑定业务数据的单个麦位展示状态。
struct SeatSlotPresentation: Equatable, Sendable {
    /// 客户端布局中的稳定语义位置标识。
    let slotID: SeatSlotID
    /// 麦位在所属房间中的零基位置。
    let position: SeatPosition
    /// 此位置绑定的麦位数据；缺失记录时为 `nil`。
    let assignment: SeatAssignment?
    /// 麦位的业务角色，不由视觉尺寸推断。
    let role: SeatRole
    /// 客户端用于解析麦位视觉尺寸的样式标识。
    let styleID: SeatVisualStyleID
    /// 一个布尔值，指示此麦位是否参与当前舞台展示。
    let isVisible: Bool
    /// 此麦位当前允许响应的用户操作。
    let interaction: SeatInteraction
    /// 麦位所属的房间；PK 双方独立编号。
    var roomSide: SeatRoomSide = .current
    /// 结合所属房间与零基位置得到的麦位地址。
    var address: SeatAddress { SeatAddress(roomSide: roomSide, position: position) }
}

/// ViewModel 提交给舞台 View 的纯业务 Presentation。
struct SeatStagePresentation: Equatable, Sendable {
    /// 服务端快照的单调递增版本号。
    let revision: Int64
    /// 当前舞台使用的客户端布局标识。
    let layoutID: SeatLayoutID
    /// 布局当前的展开或收起形态。
    let variant: SeatLayoutVariant
    /// 用于选择几何计算规则的布局家族。
    let layoutFamily: SeatLayoutFamily
    /// 按布局定义顺序排列的麦位位置。
    let slots: [SeatSlotPresentation]
    /// 与舞台一起呈现的装饰描述。
    let decorations: [RoomStageDecoration]

    /// 按布局顺序排列的当前可见麦位位置。
    var visibleSlots: [SeatSlotPresentation] {
        slots.filter(\.isVisible)
    }

    /// 当前可见位置中实际存在的麦位绑定。
    var visibleAssignments: [SeatAssignment] {
        visibleSlots.compactMap(\.assignment)
    }
}

/// App 当前版本支持的布局目录。
enum SeatLayoutCatalog {

    /// 包含主持麦、普通麦和专属座的派对房九麦定义。
    static let partyNine = SeatLayoutDefinition(
        id: .partyNine,
        layoutFamily: .partyGrid,
        capacity: 9,
        slots: (0..<9).map { index in
            let position = SeatPosition(rawValue: index)
            let role = SeatRole.roomSeat(at: position)
            return SeatSlotDefinition(
                slotID: index == 0 ? .host : .audience(index),
                position: position,
                role: role,
                styleID: index == 0
                    ? .standardHost
                    : (role == .exclusive ? .exclusive : .standardGuest),
                visibility: .always
            )
        },
        decorations: []
    )

    /// 包含主持麦及四个可收起观众麦的个播房布局定义。
    static let individualAudience = SeatLayoutDefinition(
        id: .individualAudience,
        layoutFamily: .individualAudience,
        capacity: 5,
        slots: (0..<5).map { index in
            SeatSlotDefinition(
                slotID: index == 0 ? .host : .audience(index),
                position: SeatPosition(rawValue: index),
                role: .roomSeat(at: SeatPosition(rawValue: index)),
                styleID: index == 0 ? .emphasizedHost : .standardGuest,
                visibility: index == 0 ? .always : .whenExpanded
            )
        },
        decorations: []
    )

    /// 本房与对方各九个麦位的厅 PK 布局定义。
    static let roomPKNine = SeatLayoutDefinition(
        id: .roomPKNine,
        layoutFamily: .pk(styleID: "room.nine"),
        capacity: 18,
        slots: SeatRoomSide.allCases.flatMap { side in
            (0..<9).map { index in
                SeatSlotDefinition(
                    slotID: .roomPK(side, position: index),
                    position: SeatPosition(rawValue: index),
                    role: .roomSeat(at: SeatPosition(rawValue: index)),
                    styleID: index == 0 ? .pkHost : .pkGuest,
                    visibility: .always,
                    roomSide: side
                )
            }
        },
        decorations: [RoomStageDecoration(id: "room.pk")]
    )

    /// 当前客户端已注册并可解析的布局标识集合。
    static let supportedLayoutIDs: Set<SeatLayoutID> = [
        .partyNine,
        .individualAudience,
        .roomPKNine,
    ]
}

/// 服务端舞台快照不能转换为有效布局的原因。
enum SeatLayoutResolutionError: Equatable, Error {
    /// 房间模式或 PK 样式尚未注册。
    case unsupportedBusinessMode
    /// 多个绑定使用了相同的音频麦位标识。
    case duplicateSeatID
    /// 多个绑定使用了相同的布局位置标识。
    case duplicateSlotID
    /// 同一用户出现在多个麦位绑定中。
    case duplicateUserID
    /// 同一房间侧存在重复的零基位置。
    case duplicatePosition
    /// 麦位、布局位置或用户的稳定标识为空。
    case invalidStableID
    /// 占麦用户的昵称资源键为空。
    case invalidOccupantName
    /// 空麦携带了音频活动状态或非零积分。
    case invalidVacancyState
    /// 快照包含负数麦位位置，不符合零基位置约定。
    case invalidPosition
    /// 绑定的布局标识与该房间侧的位置定义不一致。
    case slotPositionMismatch
    /// 快照中的麦位数量超过布局容量。
    case capacityExceeded
}

/// 将服务端业务语义解析为客户端受支持的舞台 Presentation。
enum SeatLayoutResolver {

    /// 校验快照并将服务端业务状态转换为客户端舞台展示数据。
    ///
    /// 按房间侧与零基位置匹配布局位置；缺失的绑定保留为空麦。
    ///
    /// - Parameter snapshot: 待解析的完整服务端舞台快照。
    /// - Returns: 有效展示数据，或第一个阻止解析的结构校验错误。
    static func resolve(
        snapshot: RoomStageSnapshot
    ) -> Result<SeatStagePresentation, SeatLayoutResolutionError> {
        guard snapshot.assignments.allSatisfy({ assignment in
            !assignment.seatID.rawValue.isEmpty
                && !assignment.slotID.rawValue.isEmpty
                && assignment.occupant?.userID.rawValue.isEmpty != true
        }) else { return .failure(.invalidStableID) }
        guard snapshot.assignments.allSatisfy({ assignment in
            guard let nameKey = assignment.occupant?.nameKey else {
                return true
            }
            return !nameKey.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }) else { return .failure(.invalidOccupantName) }
        guard snapshot.assignments.allSatisfy({ assignment in
            assignment.occupant != nil
                || (assignment.audioState == .unavailable
                    && assignment.score == 0)
        }) else { return .failure(.invalidVacancyState) }
        // 在构建唯一键字典前完成身份去重，避免非法快照导致字典初始化失败。
        guard Set(snapshot.assignments.map(\.seatID)).count
                == snapshot.assignments.count
        else { return .failure(.duplicateSeatID) }
        guard Set(snapshot.assignments.map(\.slotID)).count
                == snapshot.assignments.count
        else { return .failure(.duplicateSlotID) }
        let userIDs = snapshot.assignments.compactMap(\.userID)
        guard Set(userIDs).count == userIDs.count else {
            return .failure(.duplicateUserID)
        }
        let positions = snapshot.assignments.map(\.position)
        // PK 双方都从位置零开始编号，因此唯一性必须按房间侧与位置共同判断。
        let addresses = snapshot.assignments.map(\.address)
        guard Set(addresses).count == addresses.count else {
            return .failure(.duplicatePosition)
        }
        guard positions.allSatisfy({ $0.rawValue >= 0 }) else {
            return .failure(.invalidPosition)
        }

        let definition: SeatLayoutDefinition
        let variant: SeatLayoutVariant
        switch snapshot.roomMode {
        case .party:
            definition = SeatLayoutCatalog.partyNine
            variant = .standard
        case .individual:
            definition = SeatLayoutCatalog.individualAudience
            variant = snapshot.audienceSeatState == .enabled
                ? .expanded
                : .collapsed
        case .pk(styleID: "room.nine"):
            definition = SeatLayoutCatalog.roomPKNine
            variant = .standard
        case .pk, .unsupported:
            // 未注册布局家族的业务模式不能进入 View 层，调用方应保留最后有效状态。
            return .failure(.unsupportedBusinessMode)
        }

        guard snapshot.assignments.count <= definition.capacity,
            positions.allSatisfy({
                $0.rawValue < (definition.id == .roomPKNine ? 9 : definition.capacity)
            })
        else { return .failure(.capacityExceeded) }

        guard snapshot.assignments.allSatisfy({
            definition.id == .roomPKNine || $0.roomSide == .current
        }) else { return .failure(.slotPositionMismatch) }
        let assignmentsByPosition = Dictionary(
            uniqueKeysWithValues: snapshot.assignments.map {
                ($0.address, $0)
            }
        )
        guard definition.slots.allSatisfy({ slot in
            guard let assignment = assignmentsByPosition[slot.address]
            else { return true }
            return assignment.slotID == slot.slotID
        }) else { return .failure(.slotPositionMismatch) }
        let slots = definition.slots.map { slot in
            let isVisible = slot.visibility == .always
                || variant == .expanded
            // 后台数组顺序不参与布局；房间侧与零基位置共同匹配 Slot，缺失记录保留为空麦。
            let assignment = assignmentsByPosition[slot.address]
            return SeatSlotPresentation(
                slotID: slot.slotID,
                position: slot.position,
                assignment: assignment,
                role: slot.role,
                styleID: slot.styleID,
                isVisible: isVisible,
                interaction: assignment?.isOccupied == true
                    ? .showUserCard
                    : .none,
                roomSide: slot.roomSide
            )
        }
        return .success(
            SeatStagePresentation(
                revision: snapshot.revision,
                layoutID: definition.id,
                variant: variant,
                layoutFamily: definition.layoutFamily,
                slots: slots,
                decorations: definition.decorations
            )
        )
    }
}

/// 设备环境解析后的麦位尺寸等级。
enum SeatSizeClass: Int, Equatable, Sendable {
    /// 适用于紧凑宽度或高度的麦位尺寸。
    case compact
    /// 适用于常规容器的麦位尺寸。
    case regular
    /// 适用于宽容器的放大麦位尺寸。
    case expanded
}

/// 根据容器环境解析出的舞台几何参数。
struct SeatLayoutMetrics: Equatable, Sendable {
    /// 当前环境采用的麦位尺寸等级。
    let sizeClass: SeatSizeClass
    /// 标准麦位的宽度，单位为点。
    let standardSeatWidth: CGFloat
    /// 放大主持麦的宽度，单位为点。
    let emphasizedHostWidth: CGFloat
    /// 舞台分区之间的间距，单位为点。
    let stageSpacing: CGFloat
    /// 舞台左右两侧的内边距，单位为点。
    let stageHorizontalPadding: CGFloat
    /// 舞台上下两侧的内边距，单位为点。
    let stageVerticalPadding: CGFloat
    /// 派对房麦位列之间的间距，单位为点。
    let partyHorizontalSpacing: CGFloat
    /// 派对房麦位行之间的间距，单位为点。
    let partyVerticalSpacing: CGFloat
    /// 个播房观众麦位列之间的间距，单位为点。
    let guestHorizontalSpacing: CGFloat
    /// 个播房观众麦位行之间的间距，单位为点。
    let guestVerticalSpacing: CGFloat

    /// 紧凑环境下的基础舞台尺寸参数。
    static let compact = Self(
        sizeClass: .compact,
        standardSeatWidth: 60,
        emphasizedHostWidth: 116,
        stageSpacing: 6,
        stageHorizontalPadding: 10,
        stageVerticalPadding: 4,
        partyHorizontalSpacing: 6,
        partyVerticalSpacing: 9,
        guestHorizontalSpacing: 4,
        guestVerticalSpacing: 9
    )

    /// 常规环境下的基础舞台尺寸参数。
    static let regular = Self(
        sizeClass: .regular,
        standardSeatWidth: 74,
        emphasizedHostWidth: 142,
        stageSpacing: 18,
        stageHorizontalPadding: 10,
        stageVerticalPadding: 18,
        partyHorizontalSpacing: 10,
        partyVerticalSpacing: 14,
        guestHorizontalSpacing: 7,
        guestVerticalSpacing: 16
    )

    /// 宽容器下的基础舞台尺寸参数。
    static let expanded = Self(
        sizeClass: .expanded,
        standardSeatWidth: 104,
        emphasizedHostWidth: 192,
        stageSpacing: 22,
        stageHorizontalPadding: 20,
        stageVerticalPadding: 22,
        partyHorizontalSpacing: 18,
        partyVerticalSpacing: 18,
        guestHorizontalSpacing: 12,
        guestVerticalSpacing: 18
    )

    /// 完整容纳常规派对房网格所需的最小宽度，单位为点。
    static var regularMinimumStageWidth: CGFloat {
        regular.stageHorizontalPadding * 2
            + regular.standardSeatWidth * 4
            + regular.partyHorizontalSpacing * 3
    }

    /// 启用放大麦位尺寸的最小舞台宽度；值为 560 点。
    static let expandedMinimumStageWidth: CGFloat = 560

    /// 根据可用宽度和紧凑高度偏好选择尺寸等级并分配列间距。
    static func resolve(
        availableWidth: CGFloat,
        prefersCompactHeight: Bool
    ) -> Self {
        let widthRequiresCompactLayout = availableWidth > 0
            && availableWidth < regularMinimumStageWidth
        let baseMetrics: Self
        if prefersCompactHeight || widthRequiresCompactLayout {
            baseMetrics = .compact
        } else if availableWidth >= expandedMinimumStageWidth {
            baseMetrics = .expanded
        } else {
            baseMetrics = .regular
        }
        return baseMetrics.distributingSeats(in: availableWidth)
    }

    /// 返回适配指定容器宽度的尺寸参数，并限制麦位之间的最大间距。
    private func distributingSeats(in availableWidth: CGFloat) -> Self {
        guard availableWidth > 0 else { return self }
        let availableGridWidth = max(
            0,
            availableWidth - stageHorizontalPadding * 2
        )
        let distributedSpacing = max(
            0,
            (availableGridWidth - standardSeatWidth * 4) / 3
        )
        let maximumSpacing: CGFloat
        switch sizeClass {
        case .compact: maximumSpacing = 24
        case .regular: maximumSpacing = 28
        case .expanded: maximumSpacing = 44
        }
        return Self(
            sizeClass: sizeClass,
            standardSeatWidth: standardSeatWidth,
            emphasizedHostWidth: emphasizedHostWidth,
            stageSpacing: stageSpacing,
            stageHorizontalPadding: stageHorizontalPadding,
            stageVerticalPadding: stageVerticalPadding,
            partyHorizontalSpacing: min(
                maximumSpacing,
                max(partyHorizontalSpacing, distributedSpacing)
            ),
            partyVerticalSpacing: partyVerticalSpacing,
            guestHorizontalSpacing: min(
                maximumSpacing,
                max(guestHorizontalSpacing, distributedSpacing)
            ),
            guestVerticalSpacing: guestVerticalSpacing
        )
    }
}
