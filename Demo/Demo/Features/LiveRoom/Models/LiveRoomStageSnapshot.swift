//
//  LiveRoomStageSnapshot.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

/// 服务端声明的直播间业务模式。
nonisolated enum LiveRoomBusinessMode: Equatable, Sendable {
    case party
    case individual
    case pk(styleID: String)
    case unsupported(rawValue: String)
}

/// 个播房中观众席的开放状态。
nonisolated enum LiveRoomAudienceSeatState: Equatable, Sendable {
    case disabled
    case enabled
}

/// 服务端允许当前主播执行的业务操作。
nonisolated enum LiveRoomBusinessCapability: Hashable, Sendable {
    case switchRoomType
    case toggleAudienceSeats
    case startPK
    case endPK

    /// Demo 服务端针对业务模式返回的默认能力集合。
    static func defaults(
        for businessMode: LiveRoomBusinessMode
    ) -> Set<Self> {
        switch businessMode {
        case .party:
            return [.switchRoomType]
        case .individual:
            return [.switchRoomType, .toggleAudienceSeats]
        case .pk:
            return [.endPK]
        case .unsupported:
            return []
        }
    }
}

/// 服务端下发的一次完整舞台业务快照。
///
/// `revision` 必须单调递增。客户端只提交比当前 revision 更新且校验通过的快照，
/// 从而避免网络乱序让舞台回退到旧状态。
nonisolated struct LiveRoomStageSnapshot: Equatable, Sendable {
    let revision: Int64
    let businessMode: LiveRoomBusinessMode
    let audienceSeatState: LiveRoomAudienceSeatState
    let assignments: [LiveRoomSeatAssignment]
    let capabilities: Set<LiveRoomBusinessCapability>
}

/// 持续提供后台舞台快照的接口。
///
/// 网络层负责把长连接、轮询或事件总线转换为按 revision 递增的 AsyncStream；
/// ViewModel 只负责校验和提交快照。
nonisolated protocol LiveRoomStageSnapshotProviding: Sendable {
    func stageSnapshots() async -> AsyncStream<LiveRoomStageSnapshot>
}

/// 主播从生产菜单发起的业务命令。
///
/// 命令本身不会直接修改布局；只有服务端确认后返回的新快照可以提交 UI 状态。
nonisolated enum LiveRoomBusinessCommand: Equatable, Sendable {
    case switchRoomType(LiveRoomBusinessMode)
    case setAudienceSeatsEnabled(Bool)
    case startPK(styleID: String)
    case endPK
}

/// 发送直播间业务命令并等待服务端确认快照的接口。
nonisolated protocol LiveRoomBusinessCommandHandling: Sendable {
    func send(_ command: LiveRoomBusinessCommand) async throws
        -> LiveRoomStageSnapshot
}

nonisolated enum LiveRoomBusinessCommandError: LocalizedError {
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
actor LiveRoomMockBusinessCommandHandler:
    LiveRoomBusinessCommandHandling {

    private var snapshot: LiveRoomStageSnapshot
    private let allAssignments: [LiveRoomSeatAssignment]

    init(snapshot: LiveRoomStageSnapshot) {
        self.snapshot = snapshot
        allAssignments = snapshot.assignments
    }

    func send(_ command: LiveRoomBusinessCommand) async throws
        -> LiveRoomStageSnapshot {
        let nextMode: LiveRoomBusinessMode
        let nextAudienceState: LiveRoomAudienceSeatState

        switch command {
        case let .switchRoomType(mode):
            guard mode == .party || mode == .individual else {
                throw LiveRoomBusinessCommandError.unsupported
            }
            nextMode = mode
            nextAudienceState = mode == .individual
                ? .disabled
                : .enabled
        case let .setAudienceSeatsEnabled(isEnabled):
            guard snapshot.businessMode == .individual else {
                throw LiveRoomBusinessCommandError.unsupported
            }
            nextMode = snapshot.businessMode
            nextAudienceState = isEnabled ? .enabled : .disabled
        case .startPK:
            // 首期只保留 PK 命令边界，未注册布局家族前不生成不可渲染快照。
            throw LiveRoomBusinessCommandError.unsupported
        case .endPK:
            nextMode = .party
            nextAudienceState = .enabled
        }

        let capacity = nextMode == .individual ? 5 : 9
        snapshot = LiveRoomStageSnapshot(
            revision: snapshot.revision + 1,
            businessMode: nextMode,
            audienceSeatState: nextAudienceState,
            // Mock 服务端按目标房型返回对应的零基位置集合，客户端不裁剪后台数据。
            assignments: allAssignments.filter {
                $0.position.rawValue < capacity
            },
            capabilities: LiveRoomBusinessCapability.defaults(for: nextMode)
        )
        return snapshot
    }
}
