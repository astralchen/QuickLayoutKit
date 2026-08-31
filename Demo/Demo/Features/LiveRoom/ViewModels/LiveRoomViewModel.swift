//
//  LiveRoomViewModel.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation
import OSLog

/// 直播间关注接口抽象。
///
/// ViewModel 只在接口成功后提交最终关注状态；请求期间通过页面状态驱动加载 UI，
/// 避免按钮先乐观切换后又因失败回滚造成闪烁。
@MainActor
protocol LiveRoomFollowRequestHandling: AnyObject {
    func updateFollowing(_ isFollowing: Bool) async throws
}

/// Demo 默认关注接口，使用短延迟模拟真实网络往返。
@MainActor
final class LiveRoomMockFollowRequestHandler: LiveRoomFollowRequestHandling {

    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 600_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func updateFollowing(_ isFollowing: Bool) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

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
        let isFollowing: Bool
        /// 非空时表示关注接口正在提交该目标状态。
        let pendingFollowingState: Bool?

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
    /// 主播在派对房与个播房之间保持同一业务身份，保证 Cell 连续移动。
    static let hostAssignment = occupiedAssignment(
        position: 0,
        userID: "host.user",
        nameKey: "liveRoom.user.host",
        avatarImageID: .host,
        symbolName: "person.crop.circle.fill",
        themeIndex: 0,
        score: 5_548
    )

    /// 派对房确定性阵容：7 位用户、5 号普通空麦和专属座空麦。
    static let partyAssignments = [
        hostAssignment,
        occupiedAssignment(
            position: 1,
            userID: "party.user.1",
            nameKey: "liveRoom.user.party.1",
            avatarImageID: .one,
            symbolName: "person.crop.circle.badge.checkmark",
            themeIndex: 1,
            score: 3_820
        ),
        occupiedAssignment(
            position: 2,
            userID: "party.user.2",
            nameKey: "liveRoom.user.party.2",
            avatarImageID: .two,
            symbolName: "person.crop.circle.fill",
            themeIndex: 2,
            score: 3_164
        ),
        occupiedAssignment(
            position: 3,
            userID: "party.user.3",
            nameKey: "liveRoom.user.party.3",
            avatarImageID: .three,
            symbolName: "person.crop.circle.fill",
            themeIndex: 3,
            score: 2_906,
            isMuted: true
        ),
        occupiedAssignment(
            position: 4,
            userID: "party.user.4",
            nameKey: "liveRoom.user.party.4",
            avatarImageID: .four,
            symbolName: "person.crop.circle.badge.plus",
            themeIndex: 4,
            score: 2_711
        ),
        vacantAssignment(position: 5),
        occupiedAssignment(
            position: 6,
            userID: "party.user.5",
            nameKey: "liveRoom.user.party.5",
            avatarImageID: .six,
            symbolName: "person.crop.circle",
            themeIndex: 6,
            score: 1_666
        ),
        occupiedAssignment(
            position: 7,
            userID: "party.user.6",
            nameKey: "liveRoom.user.party.6",
            avatarImageID: .seven,
            symbolName: "person.crop.circle",
            themeIndex: 7,
            score: 1_314
        ),
        vacantAssignment(position: 8),
    ]

    /// 个播房独立阵容；只有主播与派对房共享 `userID`。
    static let individualAssignments = [
        hostAssignment,
        occupiedAssignment(
            position: 1,
            userID: "individual.user.1",
            nameKey: "liveRoom.user.individual.1",
            avatarImageID: .five,
            symbolName: "person.crop.circle.fill",
            themeIndex: 5,
            score: 1_888
        ),
        occupiedAssignment(
            position: 2,
            userID: "individual.user.2",
            nameKey: "liveRoom.user.individual.2",
            avatarImageID: .eight,
            symbolName: "person.crop.circle.fill",
            themeIndex: 8,
            score: 1_520
        ),
        occupiedAssignment(
            position: 3,
            userID: "individual.user.3",
            nameKey: "liveRoom.user.individual.3",
            avatarImageID: .six,
            symbolName: "person.crop.circle.fill",
            themeIndex: 6,
            score: 1_314
        ),
        occupiedAssignment(
            position: 4,
            userID: "individual.user.4",
            nameKey: "liveRoom.user.individual.4",
            avatarImageID: .seven,
            symbolName: "person.crop.circle.fill",
            themeIndex: 7,
            score: 952
        ),
    ]

    static func fixtureAssignments(
        for businessMode: LiveRoomBusinessMode
    ) -> [LiveRoomSeatAssignment] {
        switch businessMode {
        case .individual:
            return individualAssignments
        case .party, .pk, .unsupported:
            return partyAssignments
        }
    }

    static func makeDefaultStageSnapshot(
        revision: Int64 = 1,
        businessMode: LiveRoomBusinessMode = .party,
        audienceSeatState: LiveRoomAudienceSeatState = .enabled,
        assignments: [LiveRoomSeatAssignment]? = nil
    ) -> LiveRoomStageSnapshot {
        let resolvedAssignments = assignments
            ?? fixtureAssignments(for: businessMode)
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

    private static func occupiedAssignment(
        position: Int,
        userID: String,
        nameKey: String,
        avatarImageID: LiveRoomAvatarImageID,
        symbolName: String,
        themeIndex: Int,
        score: Int,
        isMuted: Bool = false
    ) -> LiveRoomSeatAssignment {
        LiveRoomSeatAssignment(
            seatID: LiveRoomSeatID(rawValue: "seat.\(position)"),
            slotID: position == 0 ? .host : .audience(position),
            position: LiveRoomSeatPosition(rawValue: position),
            occupant: LiveRoomSeatOccupant(
                userID: LiveRoomUserID(rawValue: userID),
                nameKey: nameKey,
                avatarImageID: avatarImageID,
                symbolName: symbolName,
                themeIndex: themeIndex
            ),
            audioState: isMuted ? .muted : .active,
            score: score
        )
    }

    private static func vacantAssignment(
        position: Int
    ) -> LiveRoomSeatAssignment {
        LiveRoomSeatAssignment(
            seatID: LiveRoomSeatID(rawValue: "seat.\(position)"),
            slotID: position == 0 ? .host : .audience(position),
            position: LiveRoomSeatPosition(rawValue: position),
            occupant: nil,
            audioState: .unavailable,
            score: 0
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
    private let followRequestHandler: any LiveRoomFollowRequestHandling
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
        isFollowing: Bool = false,
        roomInformation: LiveRoomInformation = LiveRoomInformation(
            roomID: "9527",
            hostDisplayName: "星河"
        ),
        businessCommandHandler: (any LiveRoomBusinessCommandHandling)? = nil,
        followRequestHandler: (any LiveRoomFollowRequestHandling)? = nil,
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
            audienceMembers: resolvedAudienceMembers,
            isFollowing: isFollowing,
            pendingFollowingState: nil
        )
        self.businessCommandHandler = businessCommandHandler
            ?? LiveRoomMockBusinessCommandHandler(
                snapshot: initialSnapshot,
                partyAssignments: Self.partyAssignments,
                individualAssignments: Self.individualAssignments
            )
        self.followRequestHandler = followRequestHandler
            ?? LiveRoomMockFollowRequestHandler()
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

    /// 请求切换当前用户对直播间的关注状态。
    ///
    /// 请求开始时只发布目标状态供 UI 展示加载态；接口成功后才提交
    /// `isFollowing`。失败或任务取消会清除加载态并保留请求前状态。
    @discardableResult
    func toggleFollowing() async -> Bool {
        guard state.pendingFollowingState == nil else { return false }
        let targetState = !state.isFollowing
        updateFollowingState(
            isFollowing: state.isFollowing,
            pendingFollowingState: targetState
        )
        do {
            try await followRequestHandler.updateFollowing(targetState)
            updateFollowingState(
                isFollowing: targetState,
                pendingFollowingState: nil
            )
            return true
        } catch {
            Self.logger.error(
                "Follow request failed: \(String(describing: error), privacy: .public)"
            )
            updateFollowingState(
                isFollowing: state.isFollowing,
                pendingFollowingState: nil
            )
            return false
        }
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
            audienceMembers: state.audienceMembers,
            isFollowing: state.isFollowing,
            pendingFollowingState: state.pendingFollowingState
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
            audienceMembers: state.audienceMembers,
            isFollowing: state.isFollowing,
            pendingFollowingState: state.pendingFollowingState
        )
        stateHandler?(state)
    }

    private func updateFollowingState(
        isFollowing: Bool,
        pendingFollowingState: Bool?
    ) {
        state = State(
            snapshot: state.snapshot,
            stagePresentation: state.stagePresentation,
            pendingBusinessCommand: state.pendingBusinessCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers,
            isFollowing: isFollowing,
            pendingFollowingState: pendingFollowingState
        )
        stateHandler?(state)
    }
}
