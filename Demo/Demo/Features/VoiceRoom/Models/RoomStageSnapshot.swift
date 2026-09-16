//
//  RoomStageSnapshot.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 服务端声明的直播间业务模式。
nonisolated enum RoomMode: Equatable, Sendable {
    case party
    case individual
    case pk(styleID: String)
    case unsupported(rawValue: String)
}

/// 个播房中观众席的开放状态。
nonisolated enum AudienceSeatState: Equatable, Sendable {
    case disabled
    case enabled
}

/// 服务端允许当前主播执行的业务操作。
nonisolated enum RoomCapability: Hashable, Sendable {
    case switchRoomType
    case toggleAudienceSeats
    case startPK
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
    let revision: Int64
    let roomMode: RoomMode
    let audienceSeatState: AudienceSeatState
    let assignments: [SeatAssignment]
    let capabilities: Set<RoomCapability>
}

/// 持续提供后台舞台快照的接口。
///
/// 网络层负责把长连接、轮询或事件总线转换为按 revision 递增的 AsyncStream；
/// ViewModel 只负责校验和提交快照。
nonisolated protocol RoomStageSnapshotProviding: Sendable {
    func stageSnapshots() async -> AsyncStream<RoomStageSnapshot>
}

/// 主播从生产菜单发起的业务命令。
///
/// 命令本身不会直接修改布局；只有服务端确认后返回的新快照可以提交 UI 状态。
nonisolated enum RoomCommand: Equatable, Sendable {
    case switchRoomType(RoomMode)
    case setAudienceSeatsEnabled(Bool)
    case startPK(styleID: String)
    case endPK
}

/// 发送直播间业务命令并等待服务端确认快照的接口。
nonisolated protocol RoomCommandHandling: Sendable {
    func send(_ command: RoomCommand) async throws
        -> RoomStageSnapshot
}

nonisolated enum RoomCommandError: LocalizedError {
    case unsupported

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

    private var snapshot: RoomStageSnapshot
    private var snapshotBeforePK: RoomStageSnapshot?
    private let partyAssignments: [SeatAssignment]
    private let individualAssignments: [SeatAssignment]

    init(
        snapshot: RoomStageSnapshot,
        partyAssignments: [SeatAssignment],
        individualAssignments: [SeatAssignment]
    ) {
        self.snapshot = snapshot
        self.partyAssignments = partyAssignments
        self.individualAssignments = individualAssignments
    }

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
