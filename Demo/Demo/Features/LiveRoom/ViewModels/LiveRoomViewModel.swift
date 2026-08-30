//
//  LiveRoomViewModel.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation
import OSLog

@MainActor
final class LiveRoomViewModel {

    /// 直播间页面可以直接渲染的只读状态。
    ///
    /// 麦位用户、音频状态和业务模式全部来自 `snapshot`。View 不得补充、替换
    /// 或按麦位数量推断后台数据。
    struct State: Equatable {
        let snapshot: LiveRoomStageSnapshot
        let stagePresentation: LiveRoomSeatStagePresentation
        let pendingBusinessCommand: LiveRoomBusinessCommand?
        let audienceCount: Int
        let audienceMembers: [LiveRoomAudienceMember]

        var displayedSeats: [LiveRoomSeatAssignment] {
            stagePresentation.visibleAssignments
        }

        var visibleRecipients: [LiveRoomSeatAssignment] {
            displayedSeats.filter { $0.occupant != nil }
        }
    }

    typealias StateHandler = (State) -> Void

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "LiveRoomStage"
    )

    /// Demo 的服务端 fixture。
    ///
    /// 图片资源标识只存在于 Mock/预览快照中，用于模拟后台头像 URL 映射结果；
    /// 生产 View 不会在本地创建或覆盖麦位用户。
    static let defaultAssignments = [
        LiveRoomSeatAssignment(
            id: 0,
            nameKey: "liveRoom.seat.host",
            avatarImageID: .host,
            symbolName: "person.crop.circle.fill",
            themeIndex: 0,
            score: 5_548,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 1,
            nameKey: "liveRoom.seat.one",
            avatarImageID: .one,
            symbolName: "person.crop.circle.badge.checkmark",
            themeIndex: 1,
            score: 3_820,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 2,
            nameKey: "liveRoom.seat.two",
            avatarImageID: .two,
            symbolName: "person.crop.circle.fill",
            themeIndex: 2,
            score: 3_164,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 3,
            nameKey: "liveRoom.seat.three",
            avatarImageID: .three,
            symbolName: "person.crop.circle.fill",
            themeIndex: 3,
            score: 2_906,
            isMuted: true,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 4,
            nameKey: "liveRoom.seat.four",
            avatarImageID: .four,
            symbolName: "person.crop.circle.badge.plus",
            themeIndex: 4,
            score: 2_711,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 5,
            nameKey: "liveRoom.seat.five",
            avatarImageID: .five,
            symbolName: "person.crop.circle",
            themeIndex: 5,
            score: 1_888,
            isMuted: true,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 6,
            nameKey: "liveRoom.seat.six",
            avatarImageID: .six,
            symbolName: "person.crop.circle",
            themeIndex: 6,
            score: 1_666,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 7,
            nameKey: "liveRoom.seat.seven",
            avatarImageID: .seven,
            symbolName: "person.crop.circle",
            themeIndex: 7,
            score: 1_314,
            isMuted: false,
            isOccupied: true
        ),
        LiveRoomSeatAssignment(
            id: 8,
            nameKey: "liveRoom.seat.eight",
            avatarImageID: .eight,
            symbolName: "sofa.fill",
            themeIndex: 8,
            score: 952,
            isMuted: true,
            isOccupied: true
        ),
    ]

    static func makeDefaultStageSnapshot(
        revision: Int64 = 1,
        businessMode: LiveRoomBusinessMode = .party,
        audienceSeatState: LiveRoomAudienceSeatState = .enabled,
        assignments: [LiveRoomSeatAssignment]? = nil
    ) -> LiveRoomStageSnapshot {
        let capacity = businessMode == .individual ? 5 : 9
        let resolvedAssignments = assignments ?? defaultAssignments.filter {
            $0.position.rawValue < capacity
        }
        return LiveRoomStageSnapshot(
            revision: revision,
            businessMode: businessMode,
            audienceSeatState: audienceSeatState,
            assignments: resolvedAssignments,
            capabilities: LiveRoomBusinessCapability.defaults(
                for: businessMode
            )
        )
    }

    private static let defaultAudienceMembers: [LiveRoomAudienceMember] = {
        let names = [
            "星河", "喜茶", "奈雪", "可可", "沐橙", "小满",
            "阿澈", "团子", "月见", "青禾", "南风", "晚柠",
            "桃桃", "小鹿", "云朵", "栗子", "安安", "初夏",
        ]
        let avatarImageIDs = LiveRoomAvatarImageID.fixtures
        let contributions = [
            55_480, 38_200, 31_640, 29_060, 27_110, 18_880,
            16_660, 13_140, 9_900, 8_880, 7_770, 6_660,
            5_200, 3_880, 2_660, 1_880, 1_314, 520,
        ]
        return names.indices.map { index in
            LiveRoomAudienceMember(
                id: index,
                displayName: names[index],
                avatarImageID: avatarImageIDs[index % avatarImageIDs.count],
                themeIndex: index % 9,
                contributionScore: contributions[index],
                presence: index < 5
                    ? .onMicrophone(seatNumber: index + 1)
                    : .listening
            )
        }
    }()

    private var stateHandler: StateHandler?
    private let businessCommandHandler: any LiveRoomBusinessCommandHandling
    private let stageSnapshotProvider: (any LiveRoomStageSnapshotProviding)?
    private var stageSnapshotTask: Task<Void, Never>?

    let roomInformation: LiveRoomInformation

    /// 直播间会话余额由 ViewModel 统一持有，控制器只负责页面导航与动画协调。
    private(set) var giftBalance: Int
    private(set) var sentPublicMessages: [String] = []

    private(set) var state: State

    init(
        initialGiftBalance: Int = 12_800,
        stageSnapshot: LiveRoomStageSnapshot? = nil,
        audienceCount: Int = 1_280,
        audienceMembers: [LiveRoomAudienceMember]? = nil,
        roomInformation: LiveRoomInformation = LiveRoomInformation(
            roomID: "9527",
            hostDisplayName: "星河"
        ),
        businessCommandHandler: (any LiveRoomBusinessCommandHandling)? = nil,
        stageSnapshotProvider: (any LiveRoomStageSnapshotProviding)? = nil
    ) {
        let requestedSnapshot = stageSnapshot
            ?? Self.makeDefaultStageSnapshot()
        let initialSnapshot: LiveRoomStageSnapshot
        let initialPresentation: LiveRoomSeatStagePresentation
        switch LiveRoomSeatLayoutResolver.resolve(snapshot: requestedSnapshot) {
        case let .success(presentation):
            initialSnapshot = requestedSnapshot
            initialPresentation = presentation
        case let .failure(error):
            // 首次快照不可渲染时使用受控的派对九麦回退，避免页面进入半配置状态。
            Self.logger.fault(
                "Initial snapshot rejected: \(String(describing: error), privacy: .public)"
            )
            let fallback = Self.makeDefaultStageSnapshot()
            initialSnapshot = fallback
            switch LiveRoomSeatLayoutResolver.resolve(snapshot: fallback) {
            case let .success(presentation):
                initialPresentation = presentation
            case .failure:
                preconditionFailure("The built-in LiveRoom layout must resolve.")
            }
        }

        let resolvedAudienceMembers = audienceMembers
            ?? Self.defaultAudienceMembers
        self.roomInformation = roomInformation
        giftBalance = max(0, initialGiftBalance)
        state = State(
            snapshot: initialSnapshot,
            stagePresentation: initialPresentation,
            pendingBusinessCommand: nil,
            audienceCount: max(
                max(0, audienceCount),
                resolvedAudienceMembers.count
            ),
            audienceMembers: resolvedAudienceMembers
        )
        self.businessCommandHandler = businessCommandHandler
            ?? LiveRoomMockBusinessCommandHandler(snapshot: initialSnapshot)
        self.stageSnapshotProvider = stageSnapshotProvider
    }

    deinit {
        stageSnapshotTask?.cancel()
    }

    func configureGiftBalance(_ balance: Int) {
        giftBalance = max(0, balance)
    }

    func bind(stateDidChange: @escaping StateHandler) {
        stateHandler = stateDidChange
        stateDidChange(state)
    }

    /// 开始消费后台持续推送的麦位用户和业务状态。
    ///
    /// 重复调用不会创建第二条订阅；页面退出时应调用
    /// `stopObservingStageSnapshots()` 结束流消费。
    func startObservingStageSnapshots() {
        guard
            stageSnapshotTask == nil,
            let stageSnapshotProvider
        else { return }
        stageSnapshotTask = Task { [weak self] in
            let snapshots = await stageSnapshotProvider.stageSnapshots()
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.consumeStageSnapshot(snapshot)
            }
        }
    }

    func stopObservingStageSnapshots() {
        stageSnapshotTask?.cancel()
        stageSnapshotTask = nil
    }

    /// 消费服务端推送的舞台快照。
    ///
    /// - Returns: 快照通过 revision 和布局校验并已提交时返回 `true`。
    @discardableResult
    func consumeStageSnapshot(_ snapshot: LiveRoomStageSnapshot) -> Bool {
        guard snapshot.revision > state.snapshot.revision else {
            Self.logger.notice(
                "Ignored stale revision \(snapshot.revision, privacy: .public)."
            )
            return false
        }
        switch LiveRoomSeatLayoutResolver.resolve(snapshot: snapshot) {
        case let .success(presentation):
            commit(
                snapshot: snapshot,
                presentation: presentation,
                pendingBusinessCommand: nil
            )
            return true
        case let .failure(error):
            // 校验失败不能覆盖最后一个有效舞台，避免未知业务灰度影响在线用户。
            Self.logger.fault(
                "Rejected revision \(snapshot.revision, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// 提交服务端业务命令，并等待新快照确认后再更新舞台。
    @discardableResult
    func performBusinessCommand(_ command: LiveRoomBusinessCommand) async
        -> Bool {
        guard state.pendingBusinessCommand == nil else { return false }
        updatePendingBusinessCommand(command)
        do {
            let snapshot = try await businessCommandHandler.send(command)
            guard consumeStageSnapshot(snapshot) else {
                updatePendingBusinessCommand(nil)
                return false
            }
            return true
        } catch {
            Self.logger.error(
                "Business command failed: \(String(describing: error), privacy: .public)"
            )
            updatePendingBusinessCommand(nil)
            return false
        }
    }

    @discardableResult
    func sendPublicMessage(_ message: String) -> Bool {
        let trimmedMessage = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedMessage.isEmpty else { return false }
        sentPublicMessages.append(trimmedMessage)
        return true
    }

    /// 校验赠送请求并原子扣款；UI 动画只能在该方法成功后执行。
    func processGiftSendRequest(_ request: LiveRoomGiftSendRequest) -> Int? {
        let (expectedCost, overflow) = request.gift.totalCost(
            quantity: request.quantity,
            recipientCount: request.recipients.count
        )
        let currentRecipients = Dictionary(
            uniqueKeysWithValues: state.visibleRecipients.compactMap { seat in
                seat.userID.map { ($0, seat) }
            }
        )

        guard
            !overflow,
            request.quantity > 0,
            LiveRoomGiftQuantityOption.presets.contains(
                where: { $0.value == request.quantity }
            ),
            request.gift.price >= 0,
            !request.recipients.isEmpty,
            request.totalCost >= 0,
            expectedCost == request.totalCost,
            request.totalCost <= giftBalance,
            request.recipients.allSatisfy({ recipient in
                guard let userID = recipient.userID else { return false }
                // 发送瞬间再次解析最新 assignment，拒绝已经离麦或被隐藏的收礼人。
                return currentRecipients[userID]?.seatID == recipient.seatID
            })
        else { return nil }

        giftBalance -= request.totalCost
        return giftBalance
    }

    /// 充值结果同样由 ViewModel 原子入账，避免多个页面分别维护余额副本。
    func recharge(by amount: Int) -> Int? {
        let (updatedBalance, overflow) = giftBalance
            .addingReportingOverflow(amount)
        guard !overflow, amount > 0 else { return nil }
        giftBalance = updatedBalance
        return giftBalance
    }

    private func updatePendingBusinessCommand(
        _ pendingBusinessCommand: LiveRoomBusinessCommand?
    ) {
        state = State(
            snapshot: state.snapshot,
            stagePresentation: state.stagePresentation,
            pendingBusinessCommand: pendingBusinessCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers
        )
        stateHandler?(state)
    }

    private func commit(
        snapshot: LiveRoomStageSnapshot,
        presentation: LiveRoomSeatStagePresentation,
        pendingBusinessCommand: LiveRoomBusinessCommand?
    ) {
        state = State(
            snapshot: snapshot,
            stagePresentation: presentation,
            pendingBusinessCommand: pendingBusinessCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers
        )
        stateHandler?(state)
    }
}
