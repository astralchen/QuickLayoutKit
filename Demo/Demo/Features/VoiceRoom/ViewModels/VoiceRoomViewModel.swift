//
//  VoiceRoomViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation
import OSLog

/// 直播间关注接口抽象。
///
/// ViewModel 只在接口成功后提交最终关注状态；请求期间通过页面状态驱动加载 UI，
/// 避免按钮先乐观切换后又因失败回滚造成闪烁。
@MainActor
protocol FollowRequestHandling: AnyObject {
    /// 提交目标关注状态，并在接口确认后结束等待。
    ///
    /// - Parameter isFollowing: 请求设置的关注状态。
    /// - Throws: 请求失败或等待取消时抛出的错误。
    func updateFollowing(_ isFollowing: Bool) async throws
}

/// Demo 默认关注接口，使用短延迟模拟真实网络往返。
@MainActor
final class MockFollowRequestHandler: FollowRequestHandling {

    /// 模拟关注请求的等待时长，单位为纳秒。
    private let delayNanoseconds: UInt64

    /// 创建具有指定模拟延迟的关注接口；默认延迟为 600 毫秒。
    ///
    /// - Parameter delayNanoseconds: 模拟网络等待时间，单位为纳秒。
    init(delayNanoseconds: UInt64 = 600_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    /// 通过可取消的延迟模拟关注请求成功。
    ///
    /// - Parameter isFollowing: 调用方请求的目标状态；模拟器不持久化该值。
    /// - Throws: 等待期间任务取消时抛出的 `CancellationError`。
    func updateFollowing(_ isFollowing: Bool) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }
}

/// 管理直播间快照、业务命令、关注状态和会话余额。
@MainActor
final class VoiceRoomViewModel {

    /// 直播间页面可以直接渲染的只读状态。
    ///
    /// 麦位用户、音频状态和业务模式全部来自 `snapshot`。View 不得补充、替换
    /// 或按麦位数量推断后台数据。
    struct State: Equatable {
        /// 最近一次通过版本和结构校验的服务端舞台快照。
        let snapshot: RoomStageSnapshot
        /// 由已确认快照解析的舞台展示数据。
        let stagePresentation: SeatStagePresentation
        /// 正在等待确认的业务命令；没有请求时为 `nil`。
        let pendingRoomCommand: RoomCommand?
        /// 房间当前显示的在线人数。
        let audienceCount: Int
        /// 已加载并根据当前快照更新在麦状态的观众列表。
        let audienceMembers: [AudienceMember]
        /// 一个布尔值，指示当前用户是否已关注房间。
        let isFollowing: Bool
        /// 非空时表示关注接口正在提交该目标状态。
        let pendingFollowingState: Bool?

        /// 当前舞台可见位置中的麦位绑定。
        var displayedSeats: [SeatAssignment] {
            stagePresentation.visibleAssignments
        }

        /// 当前可见且有人占用的本房麦位；不包含 PK 对方用户。
        var visibleRecipients: [SeatAssignment] {
            displayedSeats.filter { $0.roomSide == .current && $0.occupant != nil }
        }
    }

    /// 接收完整房间状态的回调类型。
    typealias StateHandler = (State) -> Void

    /// 记录当前组件诊断信息的日志记录器。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QuickLayoutKit.Demo",
        category: "VoiceRoomStage"
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

    /// 返回指定房间模式的确定性演示阵容。
    static func fixtureAssignments(
        for roomMode: RoomMode
    ) -> [SeatAssignment] {
        switch roomMode {
        case .individual:
            return individualAssignments
        case .pk:
            return RoomPKFixtures.currentAssignments(from: partyAssignments)
                + RoomPKFixtures.opponentAssignments
        case .party, .unsupported:
            return partyAssignments
        }
    }

    /// 使用指定业务状态创建演示快照；未提供阵容时按房型选择固定数据。
    static func makeDefaultStageSnapshot(
        revision: Int64 = 1,
        roomMode: RoomMode = .party,
        audienceSeatState: AudienceSeatState = .enabled,
        assignments: [SeatAssignment]? = nil
    ) -> RoomStageSnapshot {
        let resolvedAssignments = assignments
            ?? fixtureAssignments(for: roomMode)
        return RoomStageSnapshot(
            revision: revision,
            roomMode: roomMode,
            audienceSeatState: audienceSeatState,
            assignments: resolvedAssignments,
            capabilities: RoomCapability.defaults(
                for: roomMode
            )
        )
    }

    /// 使用稳定用户身份创建一个有人占用的演示麦位。
    private static func occupiedAssignment(
        position: Int,
        userID: String,
        nameKey: String,
        avatarImageID: AvatarImageID,
        symbolName: String,
        themeIndex: Int,
        score: Int,
        isMuted: Bool = false
    ) -> SeatAssignment {
        SeatAssignment(
            seatID: SeatID(rawValue: "seat.\(position)"),
            slotID: position == 0 ? .host : .audience(position),
            position: SeatPosition(rawValue: position),
            occupant: SeatOccupant(
                userID: RoomUserID(rawValue: userID),
                nameKey: nameKey,
                avatarImageID: avatarImageID,
                symbolName: symbolName,
                themeIndex: themeIndex
            ),
            audioState: isMuted ? .muted : .active,
            score: score
        )
    }

    /// 创建音频不可用、积分为零的演示空麦。
    private static func vacantAssignment(
        position: Int
    ) -> SeatAssignment {
        SeatAssignment(
            seatID: SeatID(rawValue: "seat.\(position)"),
            slotID: position == 0 ? .host : .audience(position),
            position: SeatPosition(rawValue: position),
            occupant: nil,
            audioState: .unavailable,
            score: 0
        )
    }

    /// 与演示阵容共享用户身份的默认观众列表。
    private static let defaultAudienceMembers: [AudienceMember] = {
        let names = [
            "星河", "喜茶", "奈雪", "可可", "沐橙", "小满",
            "阿澈", "小满", "阿澈", "团子", "月见", "晚柠",
            "桃桃", "小鹿", "云朵", "栗子", "安安", "初夏",
        ]
        let avatarImageIDs = AvatarImageID.fixtures
        let contributions = [
            55_480, 38_200, 31_640, 29_060, 27_110, 18_880,
            16_660, 13_140, 9_900, 8_880, 7_770, 6_660,
            5_200, 3_880, 2_660, 1_880, 1_314, 520,
        ]
        let fixtureOccupants = partyAssignments.compactMap(\.occupant)
            + individualAssignments.dropFirst().compactMap(\.occupant)
        return names.indices.map { index in
            let occupant = index < fixtureOccupants.count ? fixtureOccupants[index] : nil
            return AudienceMember(
                id: occupant?.userID ?? RoomUserID(rawValue: "audience.user.\(index)"),
                displayName: names[index],
                avatarImageID: occupant?.avatarImageID ?? avatarImageIDs[index % avatarImageIDs.count],
                themeIndex: occupant?.themeIndex ?? index % 9,
                contributionScore: contributions[index],
                presence: .listening
            )
        }
    }()

    /// 接收后续状态变更的绑定回调；再次绑定会替换原回调。
    private var stateHandler: StateHandler?
    /// 负责提交房间业务命令并返回确认快照的接口。
    private let roomCommandHandler: any RoomCommandHandling
    /// 负责提交关注状态的接口。
    private let followRequestHandler: any FollowRequestHandling
    /// 提供持续舞台快照的接口；为 `nil` 时不创建订阅。
    private let stageSnapshotProvider: (any RoomStageSnapshotProviding)?
    /// 当前舞台快照消费任务；停止订阅后为 `nil`。
    private var stageSnapshotTask: Task<Void, Never>?

    /// 房间号和主播名称等基础资料。
    let roomInformation: RoomInformation

    /// 直播间会话余额由 ViewModel 统一持有，控制器只负责页面导航与动画协调。
    private(set) var giftBalance: Int
    /// 本次会话中已通过空白校验的公屏消息。
    private(set) var sentPublicMessages: [String] = []

    /// 最近一次提交的界面状态。
    private(set) var state: State

    /// 创建语音房会话并校验初始舞台快照。
    ///
    /// 初始快照无效时回退到内置派对九麦状态。未注入的命令和关注接口使用演示实现；未提供快照源时不订阅持续更新。
    init(
        initialGiftBalance: Int = 12_800,
        stageSnapshot: RoomStageSnapshot? = nil,
        audienceCount: Int = 1_280,
        audienceMembers: [AudienceMember]? = nil,
        isFollowing: Bool = false,
        roomInformation: RoomInformation = RoomInformation(
            roomID: "9527",
            hostDisplayName: "星河"
        ),
        roomCommandHandler: (any RoomCommandHandling)? = nil,
        followRequestHandler: (any FollowRequestHandling)? = nil,
        stageSnapshotProvider: (any RoomStageSnapshotProviding)? = nil
    ) {
        let requestedSnapshot = stageSnapshot
            ?? Self.makeDefaultStageSnapshot()
        let initialSnapshot: RoomStageSnapshot
        let initialPresentation: SeatStagePresentation
        switch SeatLayoutResolver.resolve(snapshot: requestedSnapshot) {
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
            switch SeatLayoutResolver.resolve(snapshot: fallback) {
            case let .success(presentation):
                initialPresentation = presentation
            case .failure:
                preconditionFailure("The built-in VoiceRoom layout must resolve.")
            }
        }

        let resolvedAudienceMembers = audienceMembers
            ?? Self.defaultAudienceMembers
        self.roomInformation = roomInformation
        giftBalance = max(0, initialGiftBalance)
        state = State(
            snapshot: initialSnapshot,
            stagePresentation: initialPresentation,
            pendingRoomCommand: nil,
            audienceCount: max(
                max(0, audienceCount),
                resolvedAudienceMembers.count
            ),
            audienceMembers: resolvedAudienceMembers.map {
                $0.resolvingPresence(in: initialSnapshot.assignments)
            },
            isFollowing: isFollowing,
            pendingFollowingState: nil
        )
        self.roomCommandHandler = roomCommandHandler
            ?? MockRoomCommandHandler(
                snapshot: initialSnapshot,
                partyAssignments: Self.partyAssignments,
                individualAssignments: Self.individualAssignments
            )
        self.followRequestHandler = followRequestHandler
            ?? MockFollowRequestHandler()
        self.stageSnapshotProvider = stageSnapshotProvider
    }

    /// 取消舞台快照订阅，结束对服务端数据流的消费。
    deinit {
        stageSnapshotTask?.cancel()
    }

    /// 设置会话金币余额；负值按零处理。
    func configureGiftBalance(_ balance: Int) {
        giftBalance = max(0, balance)
    }

    /// 替换状态回调，并立即同步发送当前完整状态。
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

    /// 取消当前快照订阅并清除任务引用，允许稍后重新订阅。
    func stopObservingStageSnapshots() {
        stageSnapshotTask?.cancel()
        stageSnapshotTask = nil
    }

    /// 校验并提交版本更新的服务端舞台快照。
    ///
    /// 过期版本或无效结构会被拒绝，并保留最后一个有效舞台。成功提交不会清除正在等待响应的业务命令。
    ///
    /// - Parameter snapshot: 服务端推送的完整快照。
    /// - Returns: 快照通过版本与布局校验并已提交时为 `true`；否则为 `false`。
    @discardableResult
    func consumeStageSnapshot(_ snapshot: RoomStageSnapshot) -> Bool {
        guard snapshot.revision > state.snapshot.revision else {
            Self.logger.notice(
                "Ignored stale revision \(snapshot.revision, privacy: .public)."
            )
            return false
        }
        switch SeatLayoutResolver.resolve(snapshot: snapshot) {
        case let .success(presentation):
            commit(
                snapshot: snapshot,
                presentation: presentation
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

    /// 提交房间业务命令，并等待有效的确认快照。
    ///
    /// 已有请求时拒绝新的命令。确认版本必须高于请求开始时的版本；若该响应已经被推送应用或被更新推送覆盖，仍确认成功，但不会回退舞台。
    ///
    /// - Parameter command: 请求执行的房间业务操作。
    /// - Returns: 命令已确认，或所请求房型与当前模式相同时为 `true`；请求被拒绝或处理失败时为 `false`。
    @discardableResult
    func performBusinessCommand(_ command: RoomCommand) async
        -> Bool {
        guard state.pendingRoomCommand == nil else { return false }
        switch command {
        case let .switchRoomType(mode) where mode == state.snapshot.roomMode:
            return true
        case let .startPK(styleID) where state.snapshot.roomMode == .pk(styleID: styleID):
            return true
        default: break
        }
        let startingRevision = state.snapshot.revision
        updatePendingBusinessCommand(command)
        // 单个请求持有等待状态直到响应结束；推送不能释放此串行入口。
        defer { updatePendingBusinessCommand(nil) }
        do {
            let snapshot = try await roomCommandHandler.send(command)
            guard snapshot.revision > startingRevision,
                case .success = SeatLayoutResolver.resolve(snapshot: snapshot)
            else { return false }
            // 成功响应可能已通过推送应用，甚至被更新的推送覆盖。
            // 命令确认与是否需要提交舞台分开，既不误报失败也不回退状态。
            if snapshot.revision > state.snapshot.revision {
                consumeStageSnapshot(snapshot)
            }
            return true
        } catch {
            Self.logger.error(
                "Business command failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// 去除首尾空白后保存公屏消息。
    ///
    /// - Returns: 消息非空并已保存时为 `true`；纯空白消息返回 `false`。
    @discardableResult
    func sendPublicMessage(_ message: String) -> Bool {
        let trimmedMessage = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedMessage.isEmpty else { return false }
        sentPublicMessages.append(trimmedMessage)
        return true
    }

    /// 请求切换当前用户对房间的关注状态。
    ///
    /// 请求期间只发布目标状态供 UI 展示加载态；接口成功后提交最终状态。接口抛出错误时清除等待状态并保留已确认状态。
    ///
    /// - Returns: 接口成功确认时为 `true`；已有在途请求或接口抛出错误时为 `false`。
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

    /// 校验一次赠送请求并原子扣除会话金币。
    ///
    /// 校验数量预设、总价、整数溢出、用户唯一性和最新本房可见麦位。只有成功返回后才能播放赠送效果。
    ///
    /// - Parameter request: 礼物面板形成的待确认请求。
    /// - Returns: 扣款后的金币余额；任何校验失败时为 `nil`，且不改变余额。
    func processGiftSendRequest(_ request: GiftSendRequest) -> Int? {
        let (expectedCost, overflow) = request.gift.totalCost(
            quantity: request.quantity,
            recipientCount: request.recipients.count
        )
        let currentRecipients = Dictionary(
            uniqueKeysWithValues: state.visibleRecipients.compactMap { seat in
                seat.userID.map { ($0, seat) }
            }
        )

        // 此处是扣款边界：重新校验面板请求，不能信任打开面板时保存的余额和收礼快照。
        guard
            !overflow,
            request.quantity > 0,
            GiftQuantityOption.presets.contains(
                where: { $0.value == request.quantity }
            ),
            request.gift.price >= 0,
            !request.recipients.isEmpty,
            Set(request.recipients.compactMap(\.userID)).count
                == request.recipients.count,
            request.totalCost >= 0,
            expectedCost == request.totalCost,
            request.totalCost <= giftBalance,
            request.recipients.allSatisfy({ recipient in
                guard let userID = recipient.userID else { return false }
                // 发送瞬间再次解析最新 assignment，拒绝已经离麦或被隐藏的收礼人。
                return recipient.roomSide == .current
                    && currentRecipients[userID]?.seatID == recipient.seatID
            })
        else { return nil }

        giftBalance -= request.totalCost
        return giftBalance
    }

    /// 将正数金币增量原子计入当前会话余额。
    ///
    /// - Parameter amount: 已确认入账的金币数，必须大于零。
    /// - Returns: 入账后的余额；增量非正数或整数加法溢出时为 `nil`，且不改变余额。
    func recharge(by amount: Int) -> Int? {
        let (updatedBalance, overflow) = giftBalance
            .addingReportingOverflow(amount)
        guard !overflow, amount > 0 else { return nil }
        giftBalance = updatedBalance
        return giftBalance
    }

    /// 更新业务命令等待状态，并向绑定方发布完整房间状态。
    private func updatePendingBusinessCommand(
        _ pendingRoomCommand: RoomCommand?
    ) {
        state = State(
            snapshot: state.snapshot,
            stagePresentation: state.stagePresentation,
            pendingRoomCommand: pendingRoomCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers,
            isFollowing: state.isFollowing,
            pendingFollowingState: state.pendingFollowingState
        )
        stateHandler?(state)
    }

    /// 提交已校验的快照和展示数据，同步观众在麦状态并保留在途命令。
    private func commit(
        snapshot: RoomStageSnapshot,
        presentation: SeatStagePresentation
    ) {
        state = State(
            snapshot: snapshot,
            stagePresentation: presentation,
            pendingRoomCommand: state.pendingRoomCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers.map {
                $0.resolvingPresence(in: snapshot.assignments)
            },
            isFollowing: state.isFollowing,
            pendingFollowingState: state.pendingFollowingState
        )
        stateHandler?(state)
    }

    /// 更新已确认和待确认的关注状态，并通知绑定方刷新界面。
    private func updateFollowingState(
        isFollowing: Bool,
        pendingFollowingState: Bool?
    ) {
        state = State(
            snapshot: state.snapshot,
            stagePresentation: state.stagePresentation,
            pendingRoomCommand: state.pendingRoomCommand,
            audienceCount: state.audienceCount,
            audienceMembers: state.audienceMembers,
            isFollowing: isFollowing,
            pendingFollowingState: pendingFollowingState
        )
        stateHandler?(state)
    }
}
