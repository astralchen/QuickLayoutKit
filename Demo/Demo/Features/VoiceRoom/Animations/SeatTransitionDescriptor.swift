//
//  SeatTransitionDescriptor.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 描述两次舞台 Presentation 之间是否存在需要动画的几何变化。
///
/// `revision`、分数和音频状态不属于舞台几何。只有布局、可见 Slot 或用户所在
/// Slot 发生变化时，Controller 才创建场景级过渡动画。
struct SeatTransitionDescriptor: Equatable {

    let requiresTransition: Bool

    init(
        from source: SeatStagePresentation?,
        to destination: SeatStagePresentation
    ) {
        guard let source else {
            requiresTransition = false
            return
        }
        requiresTransition = GeometrySignature(source)
            != GeometrySignature(destination)
    }

    private struct GeometrySignature: Equatable {
        let layoutID: SeatLayoutID
        let variant: SeatLayoutVariant
        let layoutFamily: SeatLayoutFamily
        let slots: [Slot]

        init(_ presentation: SeatStagePresentation) {
            layoutID = presentation.layoutID
            variant = presentation.variant
            layoutFamily = presentation.layoutFamily
            slots = presentation.visibleSlots
                .sorted { $0.address < $1.address }
                .map { Slot($0) }
        }
    }

    private struct Slot: Equatable {
        let slotID: SeatSlotID
        let roomSide: SeatRoomSide
        let position: SeatPosition
        let role: SeatRole
        let styleID: SeatVisualStyleID
        let userID: RoomUserID?

        init(_ presentation: SeatSlotPresentation) {
            slotID = presentation.slotID
            roomSide = presentation.roomSide
            position = presentation.position
            role = presentation.role
            styleID = presentation.styleID
            userID = presentation.assignment?.userID
        }
    }
}
