//
//  LiveRoomSeatLayout.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import CoreGraphics
import Foundation

/// 客户端布局目录中的稳定布局标识。
struct LiveRoomSeatLayoutID: Hashable, Sendable, RawRepresentable {
    let rawValue: String

    static let partyNine = Self(rawValue: "party.nine")
    static let individualAudience = Self(rawValue: "individual.audience")
}

/// 舞台结构所属的客户端布局家族。
enum LiveRoomSeatLayoutFamily: Equatable, Sendable {
    case partyGrid
    case individualAudience
    case pk(styleID: String)
}

/// 同一个布局定义在不同业务状态下的展示变体。
enum LiveRoomSeatLayoutVariant: Equatable, Sendable {
    case standard
    case collapsed
    case expanded
}

/// Slot 在业务布局中的语义角色。
enum LiveRoomSeatRole: Equatable, Sendable {
    case host
    case guest(index: Int)
    case exclusive
    case pkLeading
    case pkTrailing
}

/// 麦位视图使用的语义视觉 Token。
///
/// View 根据 Token 和当前设备环境解析像素，不允许服务端直接控制尺寸和颜色。
enum LiveRoomSeatVisualStyleID: Equatable, Sendable {
    case standardHost
    case emphasizedHost
    case standardGuest
    case exclusive
}

enum LiveRoomSeatSlotVisibility: Equatable, Sendable {
    case always
    case whenExpanded
}

enum LiveRoomSeatInteraction: Equatable, Sendable {
    case showUserCard
    case none
}

/// 与整个舞台绑定、但不属于单个麦位的装饰描述。
struct LiveRoomStageDecoration: Equatable, Sendable {
    let id: String
}

struct LiveRoomSeatSlotDefinition: Equatable, Sendable {
    let slotID: LiveRoomSeatSlotID
    let position: LiveRoomSeatPosition
    let role: LiveRoomSeatRole
    let styleID: LiveRoomSeatVisualStyleID
    let visibility: LiveRoomSeatSlotVisibility
}

/// 客户端受控的布局定义。
struct LiveRoomSeatLayoutDefinition: Equatable, Sendable {
    let id: LiveRoomSeatLayoutID
    let layoutFamily: LiveRoomSeatLayoutFamily
    let capacity: Int
    let slots: [LiveRoomSeatSlotDefinition]
    let decorations: [LiveRoomStageDecoration]
}

struct LiveRoomSeatSlotPresentation: Equatable, Sendable {
    let slotID: LiveRoomSeatSlotID
    let position: LiveRoomSeatPosition
    let assignment: LiveRoomSeatAssignment?
    let role: LiveRoomSeatRole
    let styleID: LiveRoomSeatVisualStyleID
    let isVisible: Bool
    let interaction: LiveRoomSeatInteraction
}

/// ViewModel 提交给舞台 View 的纯业务 Presentation。
struct LiveRoomSeatStagePresentation: Equatable, Sendable {
    let revision: Int64
    let layoutID: LiveRoomSeatLayoutID
    let variant: LiveRoomSeatLayoutVariant
    let layoutFamily: LiveRoomSeatLayoutFamily
    let slots: [LiveRoomSeatSlotPresentation]
    let decorations: [LiveRoomStageDecoration]

    var visibleSlots: [LiveRoomSeatSlotPresentation] {
        slots.filter(\.isVisible)
    }

    var visibleAssignments: [LiveRoomSeatAssignment] {
        visibleSlots.compactMap(\.assignment)
    }
}

/// App 当前版本支持的布局目录。
enum LiveRoomSeatLayoutCatalog {

    static let partyNine = LiveRoomSeatLayoutDefinition(
        id: .partyNine,
        layoutFamily: .partyGrid,
        capacity: 9,
        slots: (0..<9).map { index in
            LiveRoomSeatSlotDefinition(
                slotID: index == 0 ? .host : .audience(index),
                position: LiveRoomSeatPosition(rawValue: index),
                role: index == 0 ? .host : .guest(index: index),
                styleID: index == 0
                    ? .standardHost
                    : (index == 8 ? .exclusive : .standardGuest),
                visibility: .always
            )
        },
        decorations: []
    )

    static let individualAudience = LiveRoomSeatLayoutDefinition(
        id: .individualAudience,
        layoutFamily: .individualAudience,
        capacity: 5,
        slots: (0..<5).map { index in
            LiveRoomSeatSlotDefinition(
                slotID: index == 0 ? .host : .audience(index),
                position: LiveRoomSeatPosition(rawValue: index),
                role: index == 0 ? .host : .guest(index: index),
                styleID: index == 0 ? .emphasizedHost : .standardGuest,
                visibility: index == 0 ? .always : .whenExpanded
            )
        },
        decorations: []
    )

    static let supportedLayoutIDs: Set<LiveRoomSeatLayoutID> = [
        .partyNine,
        .individualAudience,
    ]
}

enum LiveRoomSeatLayoutResolutionError: Equatable, Error {
    case unsupportedBusinessMode
    case duplicateSeatID
    case duplicateSlotID
    case duplicateUserID
    case duplicatePosition
    case invalidPosition
    case slotPositionMismatch
    case capacityExceeded
}

/// 将服务端业务语义解析为客户端受支持的舞台 Presentation。
enum LiveRoomSeatLayoutResolver {

    static func resolve(
        snapshot: LiveRoomStageSnapshot
    ) -> Result<LiveRoomSeatStagePresentation, LiveRoomSeatLayoutResolutionError> {
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
        guard Set(positions).count == positions.count else {
            return .failure(.duplicatePosition)
        }
        guard positions.allSatisfy({ $0.rawValue >= 0 }) else {
            return .failure(.invalidPosition)
        }

        let definition: LiveRoomSeatLayoutDefinition
        let variant: LiveRoomSeatLayoutVariant
        switch snapshot.businessMode {
        case .party:
            definition = LiveRoomSeatLayoutCatalog.partyNine
            variant = .standard
        case .individual:
            definition = LiveRoomSeatLayoutCatalog.individualAudience
            variant = snapshot.audienceSeatState == .enabled
                ? .expanded
                : .collapsed
        case .pk, .unsupported:
            // 未注册布局家族的业务模式不能进入 View 层，调用方应保留最后有效状态。
            return .failure(.unsupportedBusinessMode)
        }

        guard snapshot.assignments.count <= definition.capacity,
            positions.allSatisfy({
                $0.rawValue < definition.capacity
            })
        else { return .failure(.capacityExceeded) }

        let assignmentsByPosition = Dictionary(
            uniqueKeysWithValues: snapshot.assignments.map {
                ($0.position, $0)
            }
        )
        guard definition.slots.allSatisfy({ slot in
            guard let assignment = assignmentsByPosition[slot.position]
            else { return true }
            return assignment.slotID == slot.slotID
        }) else { return .failure(.slotPositionMismatch) }
        let slots = definition.slots.map { slot in
            let isVisible = slot.visibility == .always
                || variant == .expanded
            // 后台数组顺序不参与布局；零基 position 决定 assignment 对应的 Slot。
            let assignment = assignmentsByPosition[slot.position]
            return LiveRoomSeatSlotPresentation(
                slotID: slot.slotID,
                position: slot.position,
                assignment: assignment,
                role: slot.role,
                styleID: slot.styleID,
                isVisible: isVisible,
                interaction: assignment?.isOccupied == true
                    ? .showUserCard
                    : .none
            )
        }
        return .success(
            LiveRoomSeatStagePresentation(
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
enum LiveRoomSeatPresentation: Int, Equatable, Sendable {
    case compact
    case regular
    case expanded
}

/// 根据容器环境解析出的舞台几何参数。
struct LiveRoomSeatLayoutMetrics: Equatable, Sendable {
    let presentation: LiveRoomSeatPresentation
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
        presentation: .compact,
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
        presentation: .regular,
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
        presentation: .expanded,
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
        switch presentation {
        case .compact: maximumSpacing = 24
        case .regular: maximumSpacing = 28
        case .expanded: maximumSpacing = 44
        }
        return Self(
            presentation: presentation,
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
