import Foundation
import Testing
@testable import Demo

@MainActor
struct VoiceRoomDataConsistencyTests {
    @Test func ordinaryPushKeepsCommandPendingAndRejectsConcurrentCommand() async {
        let handler = ControlledStageCommandHandler()
        let vm = VoiceRoomViewModel(roomCommandHandler: handler)
        let command = RoomCommand.switchRoomType(.individual)
        let task = Task { await vm.performBusinessCommand(command) }
        await handler.waitUntilRequested()

        #expect(vm.consumeStageSnapshot(snapshot(revision: 2)))
        #expect(vm.state.pendingRoomCommand == command)
        #expect(!(await vm.performBusinessCommand(.startPK(styleID: "room.nine"))))
        #expect(await handler.requestCount == 1)

        await handler.succeed(snapshot(revision: 3, mode: .individual))
        #expect(await task.value)
        #expect(vm.state.pendingRoomCommand == nil)
        #expect(vm.state.snapshot.roomMode == .individual)
    }

    @Test(arguments: [false, true])
    func commandConfirmationSucceedsAfterPushWithoutRollingBack(newerPush: Bool) async {
        let handler = ControlledStageCommandHandler()
        let vm = VoiceRoomViewModel(roomCommandHandler: handler)
        let task = Task { await vm.performBusinessCommand(.switchRoomType(.individual)) }
        await handler.waitUntilRequested()
        let confirmation = snapshot(revision: 2, mode: .individual)
        let latest = newerPush ? snapshot(revision: 3) : confirmation
        #expect(vm.consumeStageSnapshot(latest))
        #expect(vm.state.pendingRoomCommand != nil)
        await handler.succeed(confirmation)
        #expect(await task.value)
        #expect(vm.state.snapshot == latest)
        #expect(vm.state.pendingRoomCommand == nil)
    }

    @Test func failedCommandClearsPendingAndKeepsLatestPush() async {
        let handler = ControlledStageCommandHandler()
        let vm = VoiceRoomViewModel(roomCommandHandler: handler)
        let task = Task { await vm.performBusinessCommand(.switchRoomType(.individual)) }
        await handler.waitUntilRequested()
        let latest = snapshot(revision: 2)
        #expect(vm.consumeStageSnapshot(latest))
        await handler.fail()
        #expect(!(await task.value))
        #expect(vm.state.pendingRoomCommand == nil)
        #expect(vm.state.snapshot == latest)
        // The failed request must release the serial entry for a later command.
        let next = Task { await vm.performBusinessCommand(.switchRoomType(.individual)) }
        await handler.waitUntilRequested()
        await handler.succeed(snapshot(revision: 3, mode: .individual))
        #expect(await next.value)
    }

    @Test(arguments: [false, true])
    func invalidOrStaleCommandResponseIsRejected(invalid: Bool) async {
        let handler = ControlledStageCommandHandler()
        let vm = VoiceRoomViewModel(roomCommandHandler: handler)
        let original = vm.state.snapshot
        let task = Task { await vm.performBusinessCommand(.switchRoomType(.individual)) }
        await handler.waitUntilRequested()
        await handler.succeed(invalid
            ? snapshot(revision: 2, mode: .unsupported(rawValue: "future"))
            : original)
        #expect(!(await task.value))
        #expect(vm.state.pendingRoomCommand == nil)
        #expect(vm.state.snapshot == original)
    }

    @Test func audiencePresenceFollowsUserAcrossMovesVacanciesAndRoomSides() throws {
        let original = VoiceRoomViewModel.partyAssignments[1]
        let userID = try #require(original.userID)
        let member = AudienceMember(
            id: userID, displayName: "用户", avatarImageID: .one,
            themeIndex: 1, contributionScore: 100, presence: .listening
        )
        let vm = VoiceRoomViewModel(audienceMembers: [member])
        #expect(vm.state.audienceMembers[0].presence == .onMicrophone(address: original.address))
        let moved = SeatAssignment(
            seatID: .init(rawValue: "new.audio.seat"), slotID: .audience(4),
            position: .init(rawValue: 4), occupant: original.occupant,
            audioState: .muted, score: 100
        )
        #expect(vm.consumeStageSnapshot(snapshot(revision: 2, assignments: [moved])))
        #expect(vm.state.audienceMembers[0].id == userID)
        #expect(vm.state.audienceMembers[0].presence == .onMicrophone(address: moved.address))
        let opponent = SeatAssignment(
            seatID: .init(rawValue: "opponent.audio.seat"),
            slotID: .roomPK(.opponent, position: 4), position: .init(rawValue: 4),
            occupant: original.occupant, audioState: .active, score: 100, roomSide: .opponent
        )
        #expect(vm.consumeStageSnapshot(snapshot(revision: 3, mode: .pk(styleID: "room.nine"), assignments: [opponent])))
        #expect(vm.state.audienceMembers[0].presence == .listening)
        #expect(vm.consumeStageSnapshot(snapshot(revision: 4, assignments: [])))
        #expect(vm.state.audienceMembers[0].presence == .listening)
    }

    @Test func defaultAudienceMatchesAssignmentsAcrossRoomTypes() async {
        let vm = VoiceRoomViewModel()
        #expect(onMicrophoneIDs(vm) == Set(vm.state.snapshot.assignments.compactMap(\.userID)))
        #expect(await vm.performBusinessCommand(.switchRoomType(.individual)))
        #expect(onMicrophoneIDs(vm) == Set(vm.state.snapshot.assignments.compactMap(\.userID)))
        #expect(vm.consumeStageSnapshot(snapshot(revision: 3, assignments: [])))
        #expect(onMicrophoneIDs(vm).isEmpty)
    }

    @Test func audiencePanelsAcceptUpdatedPresenceAndPreserveProfileIdentity() throws {
        let vm = VoiceRoomViewModel()
        let host = try #require(vm.state.audienceMembers.first)
        let sheet = AudienceSheetViewModel(totalCount: 18, members: vm.state.audienceMembers)
        let profile = AudienceProfileViewModel(member: host)
        #expect(vm.consumeStageSnapshot(snapshot(revision: 2, assignments: [])))
        sheet.update(totalCount: 18, members: vm.state.audienceMembers)
        let updatedHost = try #require(vm.state.audienceMembers.first)
        profile.update(member: updatedHost)
        #expect(sheet.state.members.allSatisfy { $0.presence == .listening })
        #expect(profile.state.member.presence == .listening)
        #expect(profile.state.member.id == host.id)
        profile.update(member: vm.state.audienceMembers[1])
        #expect(profile.state.member.id == host.id)
    }

    @Test func duplicateGiftRecipientsAreRejectedWithoutDeductingBalance() throws {
        let vm = VoiceRoomViewModel(initialGiftBalance: 1_000)
        let first = try #require(vm.state.visibleRecipients.first)
        let second = try #require(vm.state.visibleRecipients.dropFirst().first)
        let gift = Gift(id: "heart", titleKey: "heart", symbolName: "heart.fill",
                        price: 10, themeIndex: 0, effectStyle: .trail)
        let duplicate = GiftSendRequest(gift: gift, recipients: [first, first], quantity: 1, totalCost: 20)
        #expect(vm.processGiftSendRequest(duplicate) == nil)
        #expect(vm.giftBalance == 1_000)
        let valid = GiftSendRequest(gift: gift, recipients: [first, second], quantity: 1, totalCost: 20)
        #expect(vm.processGiftSendRequest(valid) == 980)
    }

    private func onMicrophoneIDs(_ vm: VoiceRoomViewModel) -> Set<RoomUserID> {
        Set(vm.state.audienceMembers.compactMap { member in
            if case .onMicrophone = member.presence { return member.id }
            return nil
        })
    }

    private func snapshot(
        revision: Int64, mode: RoomMode = .party, assignments: [SeatAssignment]? = nil
    ) -> RoomStageSnapshot {
        VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: revision, roomMode: mode, assignments: assignments
        )
    }
}

private actor ControlledStageCommandHandler: RoomCommandHandling {
    private var response: CheckedContinuation<RoomStageSnapshot, any Error>?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private(set) var requestCount = 0

    func send(_ command: RoomCommand) async throws -> RoomStageSnapshot {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            response = continuation
            requestWaiter?.resume()
            requestWaiter = nil
        }
    }

    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }

    func succeed(_ snapshot: RoomStageSnapshot) {
        let pending = response
        response = nil
        pending?.resume(returning: snapshot)
    }

    func fail() {
        let pending = response
        response = nil
        pending?.resume(throwing: RoomCommandError.unsupported)
    }
}
