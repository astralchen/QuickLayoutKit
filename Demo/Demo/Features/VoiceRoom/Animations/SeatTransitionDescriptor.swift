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

    /// 一个布尔值，指示布局或用户占位变化是否需要几何转场。
    let requiresTransition: Bool

    /// 比较源和目标展示状态，判断是否需要几何转场；首次提交不播放转场。
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

    /// 用于识别舞台几何变化的布局和可见麦位签名。
    private struct GeometrySignature: Equatable {
        /// 当前舞台使用的客户端布局标识。
        let layoutID: SeatLayoutID
        /// 布局当前的展开或收起形态。
        let variant: SeatLayoutVariant
        /// 用于选择几何计算规则的布局家族。
        let layoutFamily: SeatLayoutFamily
        /// 按房间侧和零基位置排序的可见麦位签名。
        let slots: [Slot]

        /// 提取舞台布局及可见麦位的几何签名，排除积分等纯内容变化。
        init(_ presentation: SeatStagePresentation) {
            layoutID = presentation.layoutID
            variant = presentation.variant
            layoutFamily = presentation.layoutFamily
            slots = presentation.visibleSlots
                .sorted { $0.address < $1.address }
                .map { Slot($0) }
        }
    }

    /// 用于比较单个麦位几何和用户身份的最小签名。
    private struct Slot: Equatable {
        /// 客户端布局中的稳定语义位置标识。
        let slotID: SeatSlotID
        /// 麦位所属的房间；PK 双方独立编号。
        let roomSide: SeatRoomSide
        /// 麦位在所属房间中的零基位置。
        let position: SeatPosition
        /// 麦位的业务角色，不由视觉尺寸推断。
        let role: SeatRole
        /// 客户端用于解析麦位视觉尺寸的样式标识。
        let styleID: SeatVisualStyleID
        /// 占麦用户的稳定身份；空麦时为 `nil`。
        let userID: RoomUserID?

        /// 提取影响单个麦位几何或身份的展示字段。
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
