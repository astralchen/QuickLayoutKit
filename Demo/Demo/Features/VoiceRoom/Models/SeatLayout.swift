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
    let rawValue: String

    static let roomPKNine = Self(rawValue: "pk.room.nine")
    static let partyNine = Self(rawValue: "party.nine")
    static let individualAudience = Self(rawValue: "individual.audience")
}

/// 舞台结构所属的客户端布局家族。
enum SeatLayoutFamily: Equatable, Sendable {
    case partyGrid
    case individualAudience
    case pk(styleID: String)
}

/// 同一个布局定义在不同业务状态下的展示变体。
enum SeatLayoutVariant: Equatable, Sendable {
    case standard
    case collapsed
    case expanded
}

/// Slot 在业务布局中的语义角色。
nonisolated enum SeatRole: Equatable, Sendable {
    case host
    case guest(index: Int)
    case exclusive
    case pkLeading
    case pkTrailing

    /// 房内角色只按协议位置映射，房型、左右侧和 slotID 文本不参与判断。
    static func roomSeat(at position: SeatPosition) -> Self {
        switch position.rawValue {
        case 0: .host
        case 8: .exclusive
        default: .guest(index: position.rawValue)
        }
    }

    var emptySeatSymbolName: String {
        self == .exclusive ? "sofa.fill" : "person.crop.circle"
    }
}

/// 麦位视图使用的语义视觉 Token。
///
/// View 根据 Token 和当前设备环境解析像素，不允许服务端直接控制尺寸和颜色。
enum SeatVisualStyleID: Equatable, Sendable {
    case pkHost
    case pkGuest
    case standardHost
    case emphasizedHost
    case standardGuest
    case exclusive

    var isPK: Bool { self == .pkHost || self == .pkGuest }
}

enum SeatSlotVisibility: Equatable, Sendable {
    case always
    case whenExpanded
}

enum SeatInteraction: Equatable, Sendable {
    case showUserCard
    case none
}

/// 与整个舞台绑定、但不属于单个麦位的装饰描述。
struct RoomStageDecoration: Equatable, Sendable {
    let id: String
}

struct SeatSlotDefinition: Equatable, Sendable {
    let slotID: SeatSlotID
    let position: SeatPosition
    let role: SeatRole
    let styleID: SeatVisualStyleID
    let visibility: SeatSlotVisibility
    var roomSide: SeatRoomSide = .current
    var address: SeatAddress { SeatAddress(roomSide: roomSide, position: position) }
}

/// 客户端受控的布局定义。
struct SeatLayoutDefinition: Equatable, Sendable {
    let id: SeatLayoutID
    let layoutFamily: SeatLayoutFamily
    let capacity: Int
    let slots: [SeatSlotDefinition]
    let decorations: [RoomStageDecoration]
}

struct SeatSlotPresentation: Equatable, Sendable {
    let slotID: SeatSlotID
    let position: SeatPosition
    let assignment: SeatAssignment?
    let role: SeatRole
    let styleID: SeatVisualStyleID
    let isVisible: Bool
    let interaction: SeatInteraction
    var roomSide: SeatRoomSide = .current
    var address: SeatAddress { SeatAddress(roomSide: roomSide, position: position) }
}

/// ViewModel 提交给舞台 View 的纯业务 Presentation。
struct SeatStagePresentation: Equatable, Sendable {
    let revision: Int64
    let layoutID: SeatLayoutID
    let variant: SeatLayoutVariant
    let layoutFamily: SeatLayoutFamily
    let slots: [SeatSlotPresentation]
    let decorations: [RoomStageDecoration]

    var visibleSlots: [SeatSlotPresentation] {
        slots.filter(\.isVisible)
    }

    var visibleAssignments: [SeatAssignment] {
        visibleSlots.compactMap(\.assignment)
    }
}

/// App 当前版本支持的布局目录。
enum SeatLayoutCatalog {

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

    static let supportedLayoutIDs: Set<SeatLayoutID> = [
        .partyNine,
        .individualAudience,
        .roomPKNine,
    ]
}

enum SeatLayoutResolutionError: Equatable, Error {
    case unsupportedBusinessMode
    case duplicateSeatID
    case duplicateSlotID
    case duplicateUserID
    case duplicatePosition
    case invalidStableID
    case invalidOccupantName
    case invalidVacancyState
    case invalidPosition
    case slotPositionMismatch
    case capacityExceeded
}

/// 将服务端业务语义解析为客户端受支持的舞台 Presentation。
enum SeatLayoutResolver {

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
            // 后台数组顺序不参与布局；零基 position 决定 assignment 对应的 Slot。
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
    case compact
    case regular
    case expanded
}

/// 根据容器环境解析出的舞台几何参数。
struct SeatLayoutMetrics: Equatable, Sendable {
    let sizeClass: SeatSizeClass
    let standardSeatWidth: CGFloat
    let emphasizedHostWidth: CGFloat
    let stageSpacing: CGFloat
    let stageHorizontalPadding: CGFloat
    let stageVerticalPadding: CGFloat
    let partyHorizontalSpacing: CGFloat
    let partyVerticalSpacing: CGFloat
    let guestHorizontalSpacing: CGFloat
    let guestVerticalSpacing: CGFloat

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

    static var regularMinimumStageWidth: CGFloat {
        regular.stageHorizontalPadding * 2
            + regular.standardSeatWidth * 4
            + regular.partyHorizontalSpacing * 3
    }

    static let expandedMinimumStageWidth: CGFloat = 560

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
