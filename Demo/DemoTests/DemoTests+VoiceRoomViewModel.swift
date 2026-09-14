import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomViewModelOwnsMessageGiftAndBalanceBusinessState() throws {
        let viewModel = VoiceRoomViewModel(initialGiftBalance: 1_000)

        #expect(!viewModel.sendPublicMessage("   \n"))
        #expect(viewModel.sendPublicMessage("  你好  "))
        #expect(viewModel.sentPublicMessages == ["你好"])

        let recipient = try #require(
            viewModel.state.displayedSeats.first(where: { $0.isOccupied })
        )
        let gift = try #require(
            Gift.catalog.first(where: { $0.id == "heart" })
        )
        let request = GiftSendRequest(
            gift: gift,
            recipients: [recipient],
            quantity: 10,
            totalCost: 100
        )

        #expect(viewModel.processGiftSendRequest(request) == 900)
        #expect(viewModel.giftBalance == 900)

        let invalidRequest = GiftSendRequest(
            gift: gift,
            recipients: [recipient],
            quantity: 10,
            totalCost: 99
        )
        #expect(viewModel.processGiftSendRequest(invalidRequest) == nil)
        #expect(viewModel.giftBalance == 900)
        #expect(viewModel.recharge(by: 100) == 1_000)
    }

    @Test func voiceRoomFollowRequestCommitsOnlyAfterSuccess() async {
        let requestHandler = ControlledFollowRequestHandler()
        let viewModel = VoiceRoomViewModel(
            isFollowing: false,
            followRequestHandler: requestHandler
        )

        let followTask = Task { await viewModel.toggleFollowing() }
        #expect(
            await waitForCondition {
                requestHandler.requestedStates == [true]
            }
        )
        #expect(!viewModel.state.isFollowing)
        #expect(viewModel.state.pendingFollowingState == true)
        #expect(!(await viewModel.toggleFollowing()))
        #expect(requestHandler.requestedStates == [true])

        requestHandler.succeed()
        #expect(await followTask.value)
        #expect(viewModel.state.isFollowing)
        #expect(viewModel.state.pendingFollowingState == nil)

        let unfollowTask = Task { await viewModel.toggleFollowing() }
        #expect(
            await waitForCondition {
                requestHandler.requestedStates == [true, false]
            }
        )
        #expect(viewModel.state.isFollowing)
        #expect(viewModel.state.pendingFollowingState == false)

        requestHandler.fail()
        #expect(!(await unfollowTask.value))
        #expect(viewModel.state.isFollowing)
        #expect(viewModel.state.pendingFollowingState == nil)
    }

    @Test func voiceRoomAudienceViewModelNormalizesServerSnapshot() {
        let members = [
            AudienceMember(
                id: 8,
                displayName: "收听用户",
                avatarImageID: .two,
                themeIndex: 2,
                contributionScore: 9_999,
                presence: .listening
            ),
            AudienceMember(
                id: 2,
                displayName: "麦上用户",
                avatarImageID: .host,
                themeIndex: 0,
                contributionScore: 100,
                presence: .onMicrophone(seatNumber: 1)
            ),
            AudienceMember(
                id: 2,
                displayName: "重复用户",
                avatarImageID: .one,
                themeIndex: 1,
                contributionScore: 20_000,
                presence: .listening
            ),
        ]

        let viewModel = AudienceSheetViewModel(
            totalCount: 1,
            members: members
        )

        #expect(viewModel.state.totalCount == 2)
        #expect(viewModel.state.members.map(\.id) == [2, 8])
    }

    @Test func voiceRoomGiftSheetViewModelKeepsSelectionAndSendRules() throws {
        let recipients = VoiceRoomViewModel().state.displayedSeats
            .filter(\.isOccupied)
        let viewModel = GiftSheetViewModel(
            recipients: recipients,
            gifts: Gift.catalog,
            initiallySelectedRecipientSeatIDs: [],
            initialBalance: 1_000
        )

        #expect(viewModel.selectedRecipientIDs.isEmpty)
        guard case .recipientRequired = viewModel.makeSendDecision() else {
            Issue.record("未选择收礼人时不应生成赠送请求")
            return
        }
        #expect(viewModel.showsRecipientRequiredPrompt)

        let recipient = try #require(recipients.first)
        #expect(viewModel.toggleRecipient(id: recipient.id))
        #expect(viewModel.selectGiftQuantity(10))
        guard case let .ready(request) = viewModel.makeSendDecision() else {
            Issue.record("有效选择应生成赠送请求")
            return
        }
        #expect(request.quantity == 10)
        #expect(request.recipients.map(\.id) == [recipient.id])
        #expect(request.totalCost == 100)
    }

    @Test func voiceRoomGiftRecipientsUpdateByStableUserID() throws {
        let recipients = VoiceRoomViewModel().state.visibleRecipients
        let first = try #require(recipients.first)
        let second = try #require(recipients.dropFirst().first)
        let firstUserID = try #require(first.userID)
        let secondUserID = try #require(second.userID)
        let viewModel = GiftSheetViewModel(
            recipients: recipients,
            gifts: Gift.catalog,
            initiallySelectedRecipientUserIDs: [firstUserID, secondUserID],
            initialBalance: 8_888
        )
        #expect(viewModel.selectGiftQuantity(66))
        let selectedGiftID = viewModel.selectedGiftID

        let movedSecond = SeatAssignment(
            seatID: SeatID(rawValue: "seat.moved"),
            slotID: .audience(4),
            position: .init(rawValue: 4),
            occupant: second.occupant,
            audioState: second.audioState,
            score: second.score
        )
        viewModel.updateRecipients([movedSecond])

        #expect(viewModel.recipients == [movedSecond])
        #expect(viewModel.selectedRecipientUserIDs == [secondUserID])
        #expect(!viewModel.selectedRecipientUserIDs.contains(firstUserID))
        #expect(viewModel.selectedGiftID == selectedGiftID)
        #expect(viewModel.selectedGiftQuantity == 66)
        #expect(viewModel.giftBalance == 8_888)
    }

    @Test func voiceRoomStageSnapshotsDriveBusinessLayouts() async {
        let viewModel = VoiceRoomViewModel()
        let initialPartyAssignments = viewModel.state.snapshot.assignments
        let hostUserID = initialPartyAssignments.first?.userID

        #expect(viewModel.state.snapshot.roomMode == .party)
        #expect(viewModel.state.displayedSeats.count == 9)
        #expect(
            viewModel.state.displayedSeats.map(\.position.rawValue)
                == Array(0..<9)
        )
        let occupiedSeats = viewModel.state.displayedSeats.filter(\.isOccupied)
        let avatarImageIDs = occupiedSeats.compactMap(\.avatarImageID)
        #expect(occupiedSeats.count == 7)
        #expect(
            avatarImageIDs
                == [.host, .one, .two, .three, .four, .six, .seven]
        )
        #expect(Set(avatarImageIDs).count == occupiedSeats.count)
        #expect(occupiedSeats.allSatisfy { $0.avatarImage != nil })
        #expect(
            occupiedSeats.allSatisfy {
                $0.occupantNameKey?.hasPrefix("liveRoom.user.") == true
            }
        )
        #expect(
            viewModel.state.displayedSeats
                .filter { !$0.isOccupied }
                .map(\.position.rawValue) == [5, 8]
        )
        #expect(
            viewModel.state.displayedSeats
                .filter { !$0.isOccupied }
                .allSatisfy { $0.avatarImageID == nil }
        )

        #expect(
            await viewModel.performBusinessCommand(
                .switchRoomType(.individual)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 1)
        #expect(viewModel.state.snapshot.audienceSeatState == .disabled)
        #expect(viewModel.state.snapshot.assignments.count == 5)
        #expect(viewModel.state.snapshot.assignments.first?.userID == hostUserID)
        #expect(
            viewModel.state.snapshot.assignments.dropFirst().compactMap(\.userID)
                .map(\.rawValue)
                == (1...4).map { "individual.user.\($0)" }
        )

        #expect(
            await viewModel.performBusinessCommand(
                .setAudienceSeatsEnabled(true)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 5)
        #expect(
            viewModel.state.displayedSeats.compactMap(\.avatarImageID)
                == [.host, .five, .eight, .six, .seven]
        )
        #expect(
            viewModel.state.displayedSeats.compactMap(\.occupantNameKey)
                == [
                    "liveRoom.user.host",
                    "liveRoom.user.individual.1",
                    "liveRoom.user.individual.2",
                    "liveRoom.user.individual.3",
                    "liveRoom.user.individual.4",
                ]
        )

        #expect(
            await viewModel.performBusinessCommand(
                .setAudienceSeatsEnabled(false)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 1)

        #expect(
            await viewModel.performBusinessCommand(.switchRoomType(.party))
        )
        #expect(viewModel.state.displayedSeats.count == 9)
        #expect(viewModel.state.snapshot.assignments == initialPartyAssignments)
    }

    @Test func voiceRoomInitialIndividualSnapshotCanRestorePartyFixture() async {
        let viewModel = VoiceRoomViewModel(
            stageSnapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: .individual,
                audienceSeatState: .disabled
            )
        )

        #expect(viewModel.state.snapshot.assignments.count == 5)
        #expect(
            await viewModel.performBusinessCommand(.switchRoomType(.party))
        )
        #expect(
            viewModel.state.snapshot.assignments
                == VoiceRoomViewModel.partyAssignments
        )
        #expect(viewModel.state.displayedSeats.count == 9)
    }

    @Test func voiceRoomSeatMetricsRespondToWidthAndHeight() {
        let regularMinimumWidth = SeatLayoutMetrics
            .regularMinimumStageWidth

        #expect(regularMinimumWidth == 346)
        let regularMetrics = SeatLayoutMetrics.resolve(
            availableWidth: regularMinimumWidth,
            prefersCompactHeight: false
        )
        let narrowMetrics = SeatLayoutMetrics.resolve(
            availableWidth: regularMinimumWidth - 1,
            prefersCompactHeight: false
        )
        let shortMetrics = SeatLayoutMetrics.resolve(
            availableWidth: 620,
            prefersCompactHeight: true
        )
        let expandedMetrics = SeatLayoutMetrics.resolve(
            availableWidth: 620,
            prefersCompactHeight: false
        )
        let distributedPhoneMetrics = SeatLayoutMetrics.resolve(
            availableWidth: 402,
            prefersCompactHeight: false
        )

        #expect(regularMetrics.sizeClass == .regular)
        #expect(narrowMetrics.sizeClass == .compact)
        #expect(shortMetrics.sizeClass == .compact)
        #expect(expandedMetrics.sizeClass == .expanded)
        #expect(distributedPhoneMetrics.partyHorizontalSpacing == 28)
        #expect(
            distributedPhoneMetrics.partyHorizontalSpacing
                > SeatLayoutMetrics.regular
                    .partyHorizontalSpacing
        )
        #expect(expandedMetrics.partyHorizontalSpacing == 44)
    }

    @Test func voiceRoomResolverMapsBusinessModeAndZeroBasedPositions() throws {
        let assignments = VoiceRoomViewModel.partyAssignments
        let party = try SeatLayoutResolver.resolve(
            snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: .party,
                audienceSeatState: .enabled,
                assignments: assignments
            )
        ).get()
        #expect(party.layoutID == .partyNine)
        #expect(party.variant == .standard)
        #expect(party.visibleSlots.count == 9)
        #expect(party.visibleSlots.map(\.position.rawValue) == Array(0..<9))
        #expect(party.visibleSlots[0].styleID == .standardHost)

        let collapsed = try SeatLayoutResolver.resolve(
            snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: .individual,
                audienceSeatState: .disabled,
                assignments: VoiceRoomViewModel.individualAssignments
            )
        ).get()
        #expect(collapsed.layoutID == .individualAudience)
        #expect(collapsed.variant == .collapsed)
        #expect(collapsed.visibleSlots.map(\.position.rawValue) == [0])
        #expect(collapsed.visibleSlots[0].styleID == .emphasizedHost)

        let expanded = try SeatLayoutResolver.resolve(
            snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: .individual,
                audienceSeatState: .enabled,
                assignments: Array(
                    VoiceRoomViewModel.individualAssignments.reversed()
                )
            )
        ).get()
        #expect(expanded.variant == .expanded)
        #expect(expanded.visibleSlots.map(\.position.rawValue) == Array(0..<5))
        #expect(
            expanded.visibleAssignments.map(\.position.rawValue) == Array(0..<5)
        )
    }

    @Test func voiceRoomViewModelRejectsStaleAndUnsupportedSnapshots() {
        let viewModel = VoiceRoomViewModel()
        let initial = viewModel.state

        #expect(!viewModel.consumeStageSnapshot(initial.snapshot))
        #expect(
            !viewModel.consumeStageSnapshot(
                RoomStageSnapshot(
                    revision: initial.snapshot.revision + 1,
                    roomMode: .unsupported(rawValue: "future.video"),
                    audienceSeatState: .enabled,
                    assignments: initial.snapshot.assignments,
                    capabilities: []
                )
            )
        )
        #expect(viewModel.state.stagePresentation == initial.stagePresentation)
        #expect(viewModel.state.snapshot == initial.snapshot)
    }

    @Test func voiceRoomBackendSnapshotStreamDrivesSeatUsers() async throws {
        let provider = TestVoiceRoomStageSnapshotProvider()
        let viewModel = VoiceRoomViewModel(stageSnapshotProvider: provider)
        var assignments = VoiceRoomViewModel.partyAssignments
        let previous = assignments[1]
        let backendUser = SeatOccupant(
            userID: RoomUserID(rawValue: "backend.user.9527"),
            nameKey: "liveRoom.user.party.4",
            avatarImageID: .four,
            symbolName: "person.crop.circle.fill",
            themeIndex: 7
        )
        assignments[1] = SeatAssignment(
            seatID: previous.seatID,
            slotID: previous.slotID,
            position: previous.position,
            occupant: backendUser,
            audioState: .muted,
            score: 9_527
        )

        viewModel.startObservingStageSnapshots()
        provider.yield(
            VoiceRoomViewModel.makeDefaultStageSnapshot(
                revision: viewModel.state.snapshot.revision + 1,
                assignments: Array(assignments.reversed())
            )
        )

        #expect(
            await waitForCondition {
                viewModel.state.snapshot.revision == 2
            }
        )
        let renderedSeat = try #require(
            viewModel.state.displayedSeats.first {
                $0.position.rawValue == 1
            }
        )
        #expect(renderedSeat.userID == backendUser.userID)
        #expect(renderedSeat.avatarImageID == .four)
        #expect(renderedSeat.score == 9_527)
        #expect(renderedSeat.audioState == .muted)
        #expect(
            viewModel.state.displayedSeats.map(\.position.rawValue)
                == Array(0..<9)
        )

        provider.finish()
        viewModel.stopObservingStageSnapshots()
    }

    @Test func voiceRoomResolverRejectsDuplicateAndInvalidPositions() {
        let assignments = VoiceRoomViewModel.partyAssignments
        var duplicatePositions = assignments
        let source = assignments[1]
        duplicatePositions[1] = SeatAssignment(
            seatID: source.seatID,
            slotID: source.slotID,
            position: .init(rawValue: 0),
            occupant: source.occupant,
            audioState: source.audioState,
            score: source.score
        )
        let duplicateSnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot(
            assignments: duplicatePositions
        )
        #expect(
            SeatLayoutResolver.resolve(snapshot: duplicateSnapshot)
                == .failure(.duplicatePosition)
        )

        var overflowingPositions = assignments
        let last = assignments[8]
        overflowingPositions[8] = SeatAssignment(
            seatID: last.seatID,
            slotID: last.slotID,
            position: .init(rawValue: 9),
            occupant: last.occupant,
            audioState: last.audioState,
            score: last.score
        )
        #expect(
            SeatLayoutResolver.resolve(
                snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                    assignments: overflowingPositions
                )
            ) == .failure(.capacityExceeded)
        )
        #expect(
            SeatLayoutResolver.resolve(
                snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                    roomMode: .individual,
                    assignments: assignments
                )
            ) == .failure(.capacityExceeded)
        )
    }

    @Test func voiceRoomResolverRejectsInvalidOccupantAndVacancyData() throws {
        let assignments = VoiceRoomViewModel.partyAssignments
        let occupied = assignments[1]
        let occupant = try #require(occupied.occupant)

        var emptyNameAssignments = assignments
        emptyNameAssignments[1] = SeatAssignment(
            seatID: occupied.seatID,
            slotID: occupied.slotID,
            position: occupied.position,
            occupant: SeatOccupant(
                userID: occupant.userID,
                nameKey: "  ",
                avatarImageID: occupant.avatarImageID,
                symbolName: occupant.symbolName,
                themeIndex: occupant.themeIndex
            ),
            audioState: occupied.audioState,
            score: occupied.score
        )
        #expect(
            SeatLayoutResolver.resolve(
                snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                    assignments: emptyNameAssignments
                )
            ) == .failure(.invalidOccupantName)
        )

        var invalidVacancyAssignments = assignments
        let vacancy = assignments[5]
        invalidVacancyAssignments[5] = SeatAssignment(
            seatID: vacancy.seatID,
            slotID: vacancy.slotID,
            position: vacancy.position,
            occupant: nil,
            audioState: .active,
            score: 100
        )
        #expect(
            SeatLayoutResolver.resolve(
                snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                    assignments: invalidVacancyAssignments
                )
            ) == .failure(.invalidVacancyState)
        )

        var invalidIDAssignments = assignments
        invalidIDAssignments[1] = SeatAssignment(
            seatID: SeatID(rawValue: ""),
            slotID: occupied.slotID,
            position: occupied.position,
            occupant: occupied.occupant,
            audioState: occupied.audioState,
            score: occupied.score
        )
        #expect(
            SeatLayoutResolver.resolve(
                snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                    assignments: invalidIDAssignments
                )
            ) == .failure(.invalidStableID)
        )
    }
}

/// 测试专用的后台麦位流，不向生产默认数据写入任何状态。
private final class TestVoiceRoomStageSnapshotProvider:
    RoomStageSnapshotProviding,
    @unchecked Sendable {

    private let stream: AsyncStream<RoomStageSnapshot>
    private let continuation: AsyncStream<RoomStageSnapshot>.Continuation

    init() {
        let pair = AsyncStream<RoomStageSnapshot>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func stageSnapshots() async -> AsyncStream<RoomStageSnapshot> {
        stream
    }

    func yield(_ snapshot: RoomStageSnapshot) {
        continuation.yield(snapshot)
    }

    func finish() {
        continuation.finish()
    }
}
