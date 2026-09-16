//
//  RoomStageSnapshot.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 服务端声明的直播间业务模式。
nonisolated enum RoomMode: Equatable, Sendable {
    /// 使用派对房业务模式。
    case party
    /// 使用个播房业务模式。
    case individual
    /// 使用指定样式的跨房 PK 模式。
    case pk(styleID: String)
    /// 当前客户端尚不支持的服务端业务模式。
    case unsupported(rawValue: String)
}

/// 个播房中观众席的开放状态。
nonisolated enum AudienceSeatState: Equatable, Sendable {
    /// 关闭个播房的观众麦位。
    case disabled
    /// 开放个播房的观众麦位。
    case enabled
}

/// 服务端允许当前主播执行的业务操作。
nonisolated enum RoomCapability: Hashable, Sendable {
    /// 允许切换房间业务类型。
    case switchRoomType
    /// 允许开放或关闭观众麦位。
    case toggleAudienceSeats
    /// 允许发起跨房 PK。
    case startPK
    /// 允许结束当前 PK。
    case endPK

    /// Demo 服务端针对业务模式返回的默认能力集合。
    static func defaults(
        for roomMode: RoomMode
    ) -> Set<Self> {
        switch roomMode {
        case .party:
            return [.switchRoomType, .startPK]
        case .individual:
            return [.switchRoomType, .toggleAudienceSeats, .startPK]
        case .pk:
            return [.switchRoomType, .startPK, .endPK]
        case .unsupported:
            return []
        }
    }
}

/// 服务端下发的一次完整舞台业务快照。
///
/// `revision` 必须单调递增。客户端只提交比当前 revision 更新且校验通过的快照，
/// 从而避免网络乱序让舞台回退到旧状态。
nonisolated struct RoomStageSnapshot: Equatable, Sendable {
    /// 服务端快照的单调递增版本号。
    let revision: Int64
    /// 服务端确认的房间业务模式。
    let roomMode: RoomMode
    /// 个播房观众麦位的开放状态。
    let audienceSeatState: AudienceSeatState
    /// 快照中的麦位绑定；数组顺序不表示业务位置。
    let assignments: [SeatAssignment]
    /// 当前房间允许执行的业务操作集合。
    let capabilities: Set<RoomCapability>
}

/// 持续提供后台舞台快照的接口。
///
/// 网络层负责把长连接、轮询或事件总线转换为按 revision 递增的 AsyncStream；
/// ViewModel 只负责校验和提交快照。
nonisolated protocol RoomStageSnapshotProviding: Sendable {
    /// 返回持续提供舞台快照的异步流。
    ///
    /// 订阅方负责取消消费任务，并在提交前校验版本与快照结构。
    ///
    /// - Returns: 服务端舞台快照流。
    func stageSnapshots() async -> AsyncStream<RoomStageSnapshot>
}

/// 主播从生产菜单发起的业务命令。
///
/// 命令本身不会直接修改布局；只有服务端确认后返回的新快照可以提交 UI 状态。
nonisolated enum RoomCommand: Equatable, Sendable {
    /// 请求切换到指定业务模式。
    case switchRoomType(RoomMode)
    /// 请求开放或关闭观众麦位。
    case setAudienceSeatsEnabled(Bool)
    /// 请求以指定样式开始 PK。
    case startPK(styleID: String)
    /// 请求结束 PK 并恢复进入前的房间状态。
    case endPK
}

/// 发送直播间业务命令并等待服务端确认快照的接口。
nonisolated protocol RoomCommandHandling: Sendable {
    /// 发送业务命令并等待服务端确认。
    ///
    /// - Parameter command: 需要执行的房间业务操作。
    /// - Returns: 服务端确认操作后的完整舞台快照。
    /// - Throws: 命令处理或传输失败时抛出的错误。
    func send(_ command: RoomCommand) async throws
        -> RoomStageSnapshot
}

/// 房间业务命令无法执行的原因。
nonisolated enum RoomCommandError: LocalizedError {
    /// 当前模式或样式不支持此命令。
    case unsupported

    /// 可用于错误展示或诊断的本地化说明。
    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "The requested live-room business command is unsupported."
        }
    }
}

/// Demo 使用的服务端命令模拟器。
///
/// Actor 串行维护 revision，确保快速连续命令也不会生成重复版本。
actor MockRoomCommandHandler:
    RoomCommandHandling {

    /// 模拟服务端最近一次提交的舞台快照。
    private var snapshot: RoomStageSnapshot
    /// 进入 PK 前保存的快照；结束 PK 时用于恢复阵容和观众席状态。
    private var snapshotBeforePK: RoomStageSnapshot?
    /// 切换到派对房时使用的固定阵容。
    private let partyAssignments: [SeatAssignment]
    /// 切换到个播房时使用的固定阵容。
    private let individualAssignments: [SeatAssignment]

    /// 使用初始快照及两套固定房型阵容创建模拟命令处理器。
    init(
        snapshot: RoomStageSnapshot,
        partyAssignments: [SeatAssignment],
        individualAssignments: [SeatAssignment]
    ) {
        self.snapshot = snapshot
        self.partyAssignments = partyAssignments
        self.individualAssignments = individualAssignments
    }

    /// 执行模拟业务命令并返回版本递增的快照。
    ///
    /// 进入 PK 时保存原快照；结束 PK 时恢复原房型、阵容及观众席状态。
    ///
    /// - Parameter command: 待执行的业务命令。
    /// - Returns: 操作完成后的模拟服务端快照。
    /// - Throws: 不支持的模式或 PK 样式对应的 `RoomCommandError.unsupported`。
    func send(_ command: RoomCommand) async throws
        -> RoomStageSnapshot {
        let nextMode: RoomMode
        let nextAudienceState: AudienceSeatState
        let nextAssignments: [SeatAssignment]

        switch command {
        case let .switchRoomType(mode):
            guard mode == .party || mode == .individual else {
                throw RoomCommandError.unsupported
            }
            snapshotBeforePK = nil
            nextAssignments = mode == .individual ? individualAssignments : partyAssignments
            nextMode = mode
            nextAudienceState = mode == .individual
                ? .disabled
                : .enabled
        case let .setAudienceSeatsEnabled(isEnabled):
            guard snapshot.roomMode == .individual else {
                throw RoomCommandError.unsupported
            }
            nextAssignments = snapshot.assignments
            nextMode = snapshot.roomMode
            nextAudienceState = isEnabled ? .enabled : .disabled
        case let .startPK(styleID):
            guard styleID == "room.nine" else { throw RoomCommandError.unsupported }
            if snapshot.roomMode == .pk(styleID: styleID) { return snapshot }
            snapshotBeforePK = snapshot
            nextMode = .pk(styleID: styleID)
            nextAudienceState = .enabled
            // 保留本房用户与麦位绑定，仅为 PK 配置独立头像。
            // 个播进入时 5–8 号麦由 Resolver 补为空位。
            nextAssignments = RoomPKFixtures.currentAssignments(from: snapshot.assignments)
                + RoomPKFixtures.opponentAssignments
        case .endPK:
            guard case .pk = snapshot.roomMode else { throw RoomCommandError.unsupported }
            nextMode = snapshotBeforePK?.roomMode ?? .party
            nextAudienceState = snapshotBeforePK?.audienceSeatState ?? .enabled
            nextAssignments = snapshotBeforePK?.assignments
                ?? snapshot.assignments.filter { $0.roomSide == .current }
            snapshotBeforePK = nil
        }
        snapshot = RoomStageSnapshot(
            revision: snapshot.revision + 1,
            roomMode: nextMode,
            audienceSeatState: nextAudienceState,
            // Mock 服务端像真实后台一样返回目标玩法的完整确定性阵容。
            assignments: nextAssignments,
            capabilities: RoomCapability.defaults(for: nextMode)
        )
        return snapshot
    }
}
