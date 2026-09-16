import AppLocalization
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct RoomPKTests {
    private func snapshot(revision: Int64 = 1, assignments: [SeatAssignment]? = nil) -> RoomStageSnapshot {
        VoiceRoomViewModel.makeDefaultStageSnapshot(revision: revision, roomMode: .pk(styleID: "room.nine"), assignments: assignments)
    }

    @Test func resolvesBothRoomsWithIndependentZeroBasedPositions() throws {
        let snapshot = snapshot(assignments: Array(snapshot().assignments.reversed()))
        let presentation = try SeatLayoutResolver.resolve(snapshot: snapshot).get()
        #expect(presentation.layoutID == .roomPKNine)
        #expect(presentation.visibleSlots.count == 18)
        #expect(Set(presentation.visibleSlots.map(\.slotID)).count == 18)
        for side in SeatRoomSide.allCases {
            let slots = presentation.visibleSlots.filter { $0.roomSide == side }
            #expect(slots.map(\.position.rawValue) == Array(0..<9))
            #expect(slots.allSatisfy { $0.assignment?.address == $0.address })
        }
        #expect(Set(presentation.visibleSlots.map(SeatCollectionItem.init).map(\.id)).count == 18)
    }

    @Test func missingSeatsRemainVacantAndDuplicatePositionsAreScopedToRoom() throws {
        let host = VoiceRoomViewModel.hostAssignment
        let presentation = try SeatLayoutResolver.resolve(snapshot: snapshot(assignments: [host])).get()
        #expect(presentation.visibleSlots.count == 18)
        #expect(presentation.visibleSlots.filter { $0.assignment == nil }.count == 17)
        var assignments = snapshot().assignments
        let original = assignments[1]
        assignments[1] = SeatAssignment(seatID: original.seatID, slotID: original.slotID,
            position: host.position, occupant: original.occupant, audioState: original.audioState, score: original.score)
        #expect(SeatLayoutResolver.resolve(snapshot: snapshot(assignments: assignments)) == .failure(.duplicatePosition))
    }

    @Test func rejectsForeignRoomInSingleRoomAndInvalidPKSnapshots() throws {
        let opponent = try #require(RoomPKFixtures.opponentAssignments.first)
        let single = VoiceRoomViewModel.makeDefaultStageSnapshot(assignments: [opponent])
        #expect(SeatLayoutResolver.resolve(snapshot: single) == .failure(.slotPositionMismatch))
        let outOfRange = SeatAssignment(seatID: opponent.seatID, slotID: opponent.slotID,
            position: .init(rawValue: 9), occupant: opponent.occupant, audioState: .active, score: 1, roomSide: .opponent)
        #expect(SeatLayoutResolver.resolve(snapshot: snapshot(assignments: [outOfRange])) == .failure(.capacityExceeded))
        let mismatchedSlot = SeatAssignment(seatID: opponent.seatID, slotID: .host,
            position: .init(rawValue: 0), occupant: opponent.occupant, audioState: .active, score: 1, roomSide: .opponent)
        #expect(SeatLayoutResolver.resolve(snapshot: snapshot(assignments: [mismatchedSlot])) == .failure(.slotPositionMismatch))
        let vm = VoiceRoomViewModel(stageSnapshot: snapshot(revision: 4))
        #expect(!vm.consumeStageSnapshot(snapshot(revision: 3)))
        #expect(!vm.consumeStageSnapshot(snapshot(revision: 5, assignments: [outOfRange])))
        #expect(vm.state.snapshot.revision == 4)
    }

    @Test func duplicateUserAcrossRoomsIsRejected() {
        let host = VoiceRoomViewModel.hostAssignment
        let opponent = SeatAssignment(seatID: .init(rawValue: "opponent.host"), slotID: .roomPK(.opponent, position: 0),
            position: host.position, occupant: host.occupant, audioState: .active, score: 1, roomSide: .opponent)
        #expect(SeatLayoutResolver.resolve(snapshot: snapshot(assignments: [host, opponent])) == .failure(.duplicateUserID))
    }

    @Test func menuCommandsEnterSwitchAndRestoreOriginalRoom() async throws {
        for mode in [RoomMode.party, .individual] {
            let initial = VoiceRoomViewModel.makeDefaultStageSnapshot(roomMode: mode, audienceSeatState: .disabled)
            let vm = VoiceRoomViewModel(stageSnapshot: initial)
            #expect(await vm.performBusinessCommand(.startPK(styleID: "room.nine")))
            #expect(vm.state.stagePresentation.visibleSlots.count == 18)
            let current = vm.state.snapshot.assignments.filter { $0.roomSide == .current }
            #expect(current.map(\.seatID) == initial.assignments.map(\.seatID))
            #expect(current.map(\.userID) == initial.assignments.map(\.userID))
            #expect(current.map(\.address) == initial.assignments.map(\.address))
            #expect(current.map(\.audioState) == initial.assignments.map(\.audioState))
            #expect(current.map(\.score) == initial.assignments.map(\.score))
            let occupied = vm.state.snapshot.assignments.filter(\.isOccupied)
            let avatars = occupied.compactMap(\.avatarImageID)
            #expect(avatars.count == occupied.count)
            #expect(Set(avatars).count == occupied.count)
            #expect(avatars.allSatisfy { UIImage(named: $0.rawValue) != nil })
            let revision = vm.state.snapshot.revision
            #expect(await vm.performBusinessCommand(.startPK(styleID: "room.nine")))
            #expect(vm.state.snapshot.revision == revision)
            #expect(await vm.performBusinessCommand(.endPK))
            #expect(vm.state.snapshot.roomMode == initial.roomMode)
            #expect(vm.state.snapshot.assignments == initial.assignments)
            #expect(vm.state.snapshot.audienceSeatState == initial.audienceSeatState)
            #expect(vm.state.snapshot.revision == revision + 1)
            #expect(await vm.performBusinessCommand(.startPK(styleID: "room.nine")))
            #expect(await vm.performBusinessCommand(.switchRoomType(.individual)))
            #expect(vm.state.snapshot.roomMode == .individual)
            #expect(await vm.performBusinessCommand(.switchRoomType(.party)))
            #expect(vm.state.displayedSeats.count == 9)
        }
    }

    @Test func giftSelectionAndValidationOnlyAllowCurrentRoom() throws {
        let vm = VoiceRoomViewModel(initialGiftBalance: 1_000, stageSnapshot: snapshot())
        #expect(vm.state.visibleRecipients.count == 7)
        #expect(vm.state.visibleRecipients.allSatisfy { $0.roomSide == .current && $0.isOccupied })
        let gift = try #require(Gift.catalog.first { $0.id == "heart" })
        let opponent = try #require(vm.state.displayedSeats.first { $0.roomSide == .opponent && $0.isOccupied })
        let current = try #require(vm.state.visibleRecipients.first)
        let illegal = GiftSendRequest(gift: gift, recipients: [opponent], quantity: 1, totalCost: 10)
        #expect(vm.processGiftSendRequest(illegal) == nil)
        #expect(vm.giftBalance == 1_000)
        let legal = GiftSendRequest(gift: gift, recipients: [current], quantity: 1, totalCost: 10)
        #expect(vm.processGiftSendRequest(legal) == 990)
        let remaining = vm.state.snapshot.assignments.filter { $0.userID != current.userID }
        #expect(vm.consumeStageSnapshot(snapshot(revision: 2, assignments: remaining)))
        #expect(vm.processGiftSendRequest(legal) == nil)
        #expect(vm.giftBalance == 990)
    }

    @Test(arguments: [CGFloat(268), 300, 350, 390, 728])
    func geometryFitsAndPreservesPhysicalSidesInRTL(width: CGFloat) throws {
        let presentation = try SeatLayoutResolver.resolve(snapshot: snapshot()).get()
        let items = presentation.visibleSlots.map(SeatCollectionItem.init)
        let lhs = SeatCollectionGeometry.configuration(presentation: presentation, items: items,
            metrics: .regular, availableWidth: width, direction: .leftToRight)
        let rhs = SeatCollectionGeometry.configuration(presentation: presentation, items: items,
            metrics: .regular, availableWidth: width, direction: .rightToLeft)
        #expect(lhs == rhs)
        #expect(lhs.states.count == 18)
        let frames = try items.map { try #require(lhs.states[$0.id]?.frame) }
        for (index, frame) in frames.enumerated() {
            #expect(frame.minX >= 0 && frame.maxX <= width + 0.5)
            #expect(frame.minY >= 0 && frame.maxY <= lhs.contentSize.height)
            for other in frames.dropFirst(index + 1) { #expect(!frame.intersects(other)) }
        }
        for side in SeatRoomSide.allCases {
            let sideFrames = try items.filter { $0.slot.roomSide == side }.map { try #require(lhs.states[$0.id]?.frame) }
            #expect(sideFrames[0].width > sideFrames[1].width)
            #expect(sideFrames[1...4].allSatisfy { $0.minY == sideFrames[1].minY })
            #expect(sideFrames[5...8].allSatisfy { $0.minY == sideFrames[5].minY })
            #expect(sideFrames.allSatisfy { side == .current ? $0.maxX < width / 2 : $0.minX > width / 2 })
        }
    }

    @Test func stageResizeUpdatesCellsWithoutOverlappingAvatarOrScore() throws {
        let presentation = try SeatLayoutResolver.resolve(snapshot: snapshot()).get()
        let stage = SeatStageView()
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeVisibleTestWindow(rootViewController: controller, size: CGSize(width: 768, height: 1024))
        defer { window.isHidden = true }
        stage.apply(presentation: presentation)
        let environments: [(CGFloat, UISemanticContentAttribute, Bool)] = [
            (288, .forceLeftToRight, false),
            (358, .forceRightToLeft, false),
            (736, .forceRightToLeft, false),
            (288, .forceRightToLeft, true)
        ]
        for (width, direction, compact) in environments {
            controller.view.semanticContentAttribute = direction
            stage.setCompactPresentation(compact)
            stage.frame = CGRect(x: 0, y: 0, width: width, height: 500)
            stage.setNeedsLayout()
            stage.layoutIfNeeded()
            let decoration = try #require(stage.allSubviews(of: RoomPKDecorationView.self).first)
            decoration.layoutIfNeeded()
            #expect(decoration.frame == stage.seatCollectionView.frame)
            let labels = decoration.allSubviews(of: UILabel.self)
            let currentLabel = try #require(labels.first { $0.text == Localization.text("liveRoom.pk.current") })
            let opponentLabel = try #require(labels.first { $0.text == Localization.text("liveRoom.pk.opponent") })
            let pkLabel = try #require(labels.first { $0.text == "PK" })
            #expect(currentLabel.frame.maxX < decoration.bounds.midX)
            #expect(opponentLabel.frame.minX > decoration.bounds.midX)
            #expect(abs(pkLabel.center.x - decoration.bounds.midX) < 0.5)
            #expect(pkLabel.frame.minY > currentLabel.frame.maxY)
            let seats = stage.allSubviews(of: SeatView.self)
            #expect(seats.count == 18)
            #expect(Set(seats.compactMap(\.accessibilityIdentifier)).count == 18)
            for seat in seats {
                seat.layoutIfNeeded()
                let scores = seat.allSubviews(of: UILabel.self).filter { $0.accessibilityIdentifier?.hasPrefix("liveRoom.seat.score.") == true }
                for label in scores {
                    let frame = label.convert(label.bounds, to: seat)
                    #expect(frame.minX >= -0.5 && frame.maxX <= seat.bounds.width + 0.5)
                    #expect(frame.maxY <= seat.bounds.height + 0.5)
                }
            }
        }
    }

    @Test func selectAllAndLiveRecipientRefreshExcludeOpponentAndDepartedUsers() throws {
        let vm = VoiceRoomViewModel(stageSnapshot: snapshot())
        let opponentID = try #require(RoomPKFixtures.opponentAssignments.first?.userID)
        let sheet = GiftSheetViewModel(recipients: vm.state.visibleRecipients, gifts: Gift.catalog,
            initiallySelectedRecipientUserIDs: [opponentID], initialBalance: 1_000)
        #expect(sheet.selectedRecipients.isEmpty)
        #expect(!sheet.toggleRecipient(userID: opponentID))
        sheet.toggleAllRecipients()
        #expect(sheet.selectedRecipients.count == 7)
        #expect(sheet.selectedRecipients.allSatisfy { $0.roomSide == .current })
        let departing = try #require(vm.state.visibleRecipients.first?.userID)
        #expect(vm.consumeStageSnapshot(snapshot(revision: 2, assignments: snapshot().assignments.filter { $0.userID != departing })))
        sheet.updateRecipients(vm.state.visibleRecipients)
        #expect(sheet.selectedRecipients.count == 6)
        #expect(!sheet.selectedRecipientUserIDs.contains(departing))
    }

    @Test(arguments: [false, true])
    func rapidTransitionsAndReducedMotionKeepLatestLayoutAndGiftAnchor(reducedMotion: Bool) throws {
        let controller = UIViewController()
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 360))
        let messages = RoomPublicChatView(frame: CGRect(x: 0, y: 370, width: 360, height: 100))
        controller.view.addSubview(stage)
        controller.view.addSubview(messages)
        let window = try makeVisibleTestWindow(rootViewController: controller)
        defer { window.isHidden = true }
        let coordinator = SeatStageTransitionCoordinator(stageView: stage, messagesView: messages,
            isReduceMotionEnabled: { reducedMotion })
        let party = try SeatLayoutResolver.resolve(snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot()).get()
        let pk = try SeatLayoutResolver.resolve(snapshot: snapshot()).get()
        stage.apply(presentation: party)
        stage.layoutIfNeeded()
        coordinator.transition(to: pk, animated: true, in: controller.view) { stage.layoutIfNeeded() }
        coordinator.transition(to: party, animated: true, in: controller.view) { stage.layoutIfNeeded() }
        coordinator.finishImmediately()
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 9)
        #expect(stage.allSubviews(of: RoomPKDecorationView.self).isEmpty)
        coordinator.transition(to: pk, animated: true, in: controller.view) { stage.layoutIfNeeded() }
        coordinator.finishImmediately()
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 18)
        #expect(!coordinator.isTransitioning)
        let hostID = try #require(VoiceRoomViewModel.hostAssignment.userID)
        let anchor = try #require(stage.giftTargetPoint(forUserID: hostID, in: controller.view))
        #expect(anchor.x < stage.frame.midX)
        let decoration = try #require(stage.allSubviews(of: RoomPKDecorationView.self).first)
        #expect(decoration.alpha == 1)
    }

    @Test func pkDataOnlyUpdatesDoNotStartGeometryTransition() throws {
        let source = try SeatLayoutResolver.resolve(snapshot: snapshot()).get()
        let original = snapshot().assignments
        let updated = original.map { seat in
            SeatAssignment(seatID: seat.seatID, slotID: seat.slotID, position: seat.position,
                occupant: seat.occupant, audioState: seat.isOccupied ? .muted : .unavailable,
                score: seat.isOccupied ? seat.score + 1 : 0, roomSide: seat.roomSide)
        }
        let destination = try SeatLayoutResolver.resolve(snapshot: snapshot(revision: 2, assignments: updated)).get()
        #expect(!SeatTransitionDescriptor(from: source, to: destination).requiresTransition)
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        stage.apply(presentation: try SeatLayoutResolver.resolve(snapshot: VoiceRoomViewModel.makeDefaultStageSnapshot()).get())
        #expect(stage.prepareTransition(to: source))
        stage.applyDataUpdate(presentation: destination)
        stage.finishTransitionImmediately()
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 18)
        #expect(stage.transitioningUserIDs.isEmpty)
    }

    @Test func cardsIdentifyRoomAndStageShowsOccupiedZeroScore() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }
        let presentation = try SeatLayoutResolver.resolve(snapshot: snapshot()).get()
        for side in SeatRoomSide.allCases {
            let slot = try #require(presentation.slots.first { $0.roomSide == side && $0.position.rawValue == 1 })
            let seat = try #require(slot.assignment)
            let card = SeatUserCardView()
            card.configure(seat: seat, showsRoom: true)
            card.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
            card.layoutIfNeeded()
            let label = try #require(card.allSubviews(of: UILabel.self).first { $0.accessibilityIdentifier == "liveRoom.userCard.seat" })
            #expect(label.text == "\(side == .current ? "本房" : "对方") · 1 号麦")
            if side == .opponent {
                let view = SeatView(frame: CGRect(x: 0, y: 0, width: 40, height: 70))
                view.configure(assignment: seat, presentation: slot)
                view.layoutIfNeeded()
                let score = try #require(view.allSubviews(of: UILabel.self).first { $0.accessibilityIdentifier == "liveRoom.seat.score.opponent.1" })
                #expect(score.text == "0")
            }
        }
    }
}
