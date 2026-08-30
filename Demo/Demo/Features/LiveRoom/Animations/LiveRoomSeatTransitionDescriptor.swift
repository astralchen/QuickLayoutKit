//
//  LiveRoomSeatTransitionDescriptor.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

/// 描述两次舞台 Presentation 之间是否存在需要动画的几何变化。
///
/// `revision`、分数和音频状态不属于舞台几何。只有布局、可见 Slot 或用户所在
/// Slot 发生变化时，Controller 才创建场景级过渡动画。
struct LiveRoomSeatTransitionDescriptor: Equatable {

    let requiresTransition: Bool

    init(
        from source: LiveRoomSeatStagePresentation?,
        to destination: LiveRoomSeatStagePresentation
    ) {
        guard let source else {
            requiresTransition = false
            return
        }
        requiresTransition = GeometrySignature(source)
            != GeometrySignature(destination)
    }

    private struct GeometrySignature: Equatable {
        let layoutID: LiveRoomSeatLayoutID
        let variant: LiveRoomSeatLayoutVariant
        let layoutFamily: LiveRoomSeatLayoutFamily
        let slots: [Slot]

        init(_ presentation: LiveRoomSeatStagePresentation) {
            layoutID = presentation.layoutID
            variant = presentation.variant
            layoutFamily = presentation.layoutFamily
            slots = presentation.visibleSlots
                .sorted { $0.position < $1.position }
                .map { Slot($0) }
        }
    }

    private struct Slot: Equatable {
        let slotID: LiveRoomSeatSlotID
        let position: LiveRoomSeatPosition
        let role: LiveRoomSeatRole
        let styleID: LiveRoomSeatVisualStyleID
        let userID: LiveRoomUserID?

        init(_ presentation: LiveRoomSeatSlotPresentation) {
            slotID = presentation.slotID
            position = presentation.position
            role = presentation.role
            styleID = presentation.styleID
            userID = presentation.assignment?.userID
        }
    }
}
