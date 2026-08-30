//
//  LiveRoomSeatStageTransitionTests.swift
//  DemoTests
//
//  LiveRoom MVVM feature tests.
//

import CoreGraphics
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct LiveRoomSeatStageTransitionTests {

    @Test func collectionItemIdentitySeparatesUsersFromVacancies() throws {
        let assignments = LiveRoomViewModel.defaultAssignments.map {
            assignment in
            guard assignment.position.rawValue == 8 else {
                return assignment
            }
            return LiveRoomSeatAssignment(
                seatID: assignment.seatID,
                slotID: assignment.slotID,
                position: assignment.position,
                occupant: nil,
                audioState: .unavailable,
                score: 0
            )
        }
        let resolvedPresentation = try presentation(
            for: LiveRoomViewModel.makeDefaultStageSnapshot(
                assignments: assignments
            )
        )
        let items = resolvedPresentation.visibleSlots.map(
            LiveRoomSeatCollectionItem.init
        )
        let occupiedSlot = try #require(
            resolvedPresentation.visibleSlots.first {
                $0.assignment?.userID != nil
            }
        )
        let vacantSlot = try #require(
            resolvedPresentation.visibleSlots.first {
                $0.assignment?.userID == nil
            }
        )
        let occupiedUserID = try #require(occupiedSlot.assignment?.userID)

        #expect(
            items.first { $0.slot.slotID == occupiedSlot.slotID }?.id
                == .user(occupiedUserID)
        )
        #expect(
            items.first { $0.slot.slotID == vacantSlot.slotID }?.id
                == .vacancy(vacantSlot.slotID)
        )
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func collectionGeometryMirrorsRTLWithoutChangingIdentity() throws {
        let resolvedPresentation = try presentation(
            for: LiveRoomViewModel.makeDefaultStageSnapshot()
        )
        let items = resolvedPresentation.visibleSlots.map(
            LiveRoomSeatCollectionItem.init
        )
        let availableWidth: CGFloat = 370
        let leftToRight = LiveRoomSeatCollectionGeometry.configuration(
            presentation: resolvedPresentation,
            items: items,
            metrics: .regular,
            availableWidth: availableWidth,
            direction: .leftToRight
        )
        let rightToLeft = LiveRoomSeatCollectionGeometry.configuration(
            presentation: resolvedPresentation,
            items: items,
            metrics: .regular,
            availableWidth: availableWidth,
            direction: .rightToLeft
        )

        #expect(leftToRight.itemIDs == rightToLeft.itemIDs)
        #expect(leftToRight.contentSize == rightToLeft.contentSize)
        for itemID in leftToRight.itemIDs {
            let leftFrame = try #require(leftToRight.states[itemID]?.frame)
            let rightFrame = try #require(rightToLeft.states[itemID]?.frame)
            #expect(abs(rightFrame.minX - (availableWidth - leftFrame.maxX)) < 0.5)
            #expect(abs(rightFrame.minY - leftFrame.minY) < 0.5)
            #expect(rightFrame.size == leftFrame.size)
        }
    }

    @Test func dataOnlyChangesDoNotCreateSceneTransition() throws {
        let sourceSnapshot = LiveRoomViewModel.makeDefaultStageSnapshot()
        let changedAssignments = sourceSnapshot.assignments.map { assignment in
            LiveRoomSeatAssignment(
                seatID: assignment.seatID,
                slotID: assignment.slotID,
                position: assignment.position,
                occupant: assignment.occupant,
                audioState: assignment.audioState == .active ? .muted : .active,
                score: assignment.score + 100
            )
        }
        let destinationSnapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
            revision: 2,
            assignments: changedAssignments
        )

        let descriptor = LiveRoomSeatTransitionDescriptor(
            from: try presentation(for: sourceSnapshot),
            to: try presentation(for: destinationSnapshot)
        )

        #expect(!descriptor.requiresTransition)
    }

    @Test func layoutVariantAndUserSlotChangesCreateSceneTransition() throws {
        let partySnapshot = LiveRoomViewModel.makeDefaultStageSnapshot()
        let individualSnapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
            revision: 2,
            businessMode: .individual,
            audienceSeatState: .disabled
        )
        let partyPresentation = try presentation(for: partySnapshot)
        let individualPresentation = try presentation(for: individualSnapshot)

        #expect(
            LiveRoomSeatTransitionDescriptor(
                from: partyPresentation,
                to: individualPresentation
            ).requiresTransition
        )

        var movedAssignments = partySnapshot.assignments
        let first = movedAssignments[0]
        let second = movedAssignments[1]
        movedAssignments[0] = replacingOccupant(
            in: first,
            with: second.occupant
        )
        movedAssignments[1] = replacingOccupant(
            in: second,
            with: first.occupant
        )
        let movedSnapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
            revision: 3,
            assignments: movedAssignments
        )

        #expect(
            LiveRoomSeatTransitionDescriptor(
                from: partyPresentation,
                to: try presentation(for: movedSnapshot)
            ).requiresTransition
        )
    }

    @Test func sharedHostAndStageUseTheSameInteractiveTimeline() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = LiveRoomViewModel()
        let viewController = LiveRoomViewController(viewModel: viewModel)
        installTransitionCoordinator(
            in: viewController,
            isReduceMotionEnabled: false
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeTransitionTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer {
            viewController.seatTransitionCoordinator.finishImmediately()
            window.isHidden = true
        }

        let hostID = try #require(
            viewModel.state.displayedSeats.first?.userID
        )
        let sourcePoint = try #require(
            viewController.seatStageView.giftTargetPoint(
                forUserID: hostID,
                in: viewController.view
            )
        )

        #expect(
            viewModel.consumeStageSnapshot(
                LiveRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    businessMode: .individual,
                    audienceSeatState: .disabled
                )
            )
        )
        let animator = try #require(
            viewController.seatTransitionCoordinator.testingAnimator
        )
        animator.pauseAnimation()
        animator.fractionComplete = 0.5

        let middlePoint = try #require(
            viewController.seatTransitionCoordinator.giftTargetPoint(
                for: hostID,
                in: viewController.view
            )
        )
        #expect(viewController.seatTransitionCoordinator.isTransitioning)
        #expect(
            viewController.seatTransitionCoordinator.testingActiveUserIDs
                .contains(hostID)
        )
        viewController.seatTransitionCoordinator.finishImmediately()
        let destinationPoint = try #require(
            viewController.seatStageView.giftTargetPoint(
                forUserID: hostID,
                in: viewController.view
            )
        )
        #expect(
            pointLiesBetween(
                middlePoint,
                sourcePoint,
                destinationPoint,
                tolerance: 2
            )
        )
        #expect(!viewController.seatStageView.seatCollectionView.isScrollEnabled)
    }

    @Test func rapidReplacementStartsFromCurrentPresentationPosition() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = LiveRoomViewModel()
        let viewController = LiveRoomViewController(viewModel: viewModel)
        installTransitionCoordinator(
            in: viewController,
            isReduceMotionEnabled: false
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeTransitionTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer {
            viewController.seatTransitionCoordinator.finishImmediately()
            window.isHidden = true
        }
        let hostID = try #require(
            viewModel.state.displayedSeats.first?.userID
        )

        #expect(
            viewModel.consumeStageSnapshot(
                LiveRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    businessMode: .individual,
                    audienceSeatState: .disabled
                )
            )
        )
        let firstAnimator = try #require(
            viewController.seatTransitionCoordinator.testingAnimator
        )
        firstAnimator.pauseAnimation()
        firstAnimator.fractionComplete = 0.4
        let interruptedPoint = try #require(
            viewController.seatTransitionCoordinator.giftTargetPoint(
                for: hostID,
                in: viewController.view
            )
        )

        #expect(
            viewModel.consumeStageSnapshot(
                LiveRoomViewModel.makeDefaultStageSnapshot(
                    revision: 3,
                    businessMode: .party,
                    audienceSeatState: .enabled
                )
            )
        )
        let replacementAnimator = try #require(
            viewController.seatTransitionCoordinator.testingAnimator
        )
        replacementAnimator.pauseAnimation()
        replacementAnimator.fractionComplete = 0
        let replacementStartPoint = try #require(
            viewController.seatTransitionCoordinator.giftTargetPoint(
                for: hostID,
                in: viewController.view
            )
        )

        #expect(
            viewController.seatTransitionCoordinator.testingActiveUserIDs
                .contains(hostID)
        )
        #expect(
            distance(interruptedPoint, replacementStartPoint) <= 1.5,
            "中断点 \(interruptedPoint)，替换动画起点 \(replacementStartPoint)"
        )
        #expect(viewController.seatTransitionCoordinator.isTransitioning)
        #expect(viewModel.state.snapshot.revision == 3)
    }

    @Test func reduceMotionUsesSceneCrossfadeWithoutSeatTransforms() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = LiveRoomViewModel()
        let viewController = LiveRoomViewController(viewModel: viewModel)
        installTransitionCoordinator(
            in: viewController,
            isReduceMotionEnabled: true
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeTransitionTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer {
            viewController.seatTransitionCoordinator.finishImmediately()
            window.isHidden = true
        }

        #expect(
            viewModel.consumeStageSnapshot(
                LiveRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    businessMode: .individual,
                    audienceSeatState: .disabled
                )
            )
        )
        let animator = try #require(
            viewController.seatTransitionCoordinator.testingAnimator
        )
        animator.pauseAnimation()
        animator.fractionComplete = 0.5

        #expect(abs(animator.duration - 0.15) <= 0.001)
        #expect(
            viewController.seatTransitionCoordinator
                .testingUsesReducedMotionTransition
        )
        #expect(
            viewController.seatTransitionCoordinator
                .testingActiveUserIDs.isEmpty
        )
        #expect(viewController.seatStageView.transform == .identity)
        #expect(viewController.messagesView.transform == .identity)
    }
}

@MainActor
private func presentation(
    for snapshot: LiveRoomStageSnapshot
) throws -> LiveRoomSeatStagePresentation {
    switch LiveRoomSeatLayoutResolver.resolve(snapshot: snapshot) {
    case let .success(presentation):
        return presentation
    case let .failure(error):
        Issue.record("无法解析测试舞台：\(error)")
        throw error
    }
}

private func replacingOccupant(
    in assignment: LiveRoomSeatAssignment,
    with occupant: LiveRoomSeatOccupant?
) -> LiveRoomSeatAssignment {
    LiveRoomSeatAssignment(
        seatID: assignment.seatID,
        slotID: assignment.slotID,
        position: assignment.position,
        occupant: occupant,
        audioState: assignment.audioState,
        score: assignment.score
    )
}

@MainActor
private func makeTransitionTestWindow(
    rootViewController: UIViewController,
    size: CGSize
) throws -> UIWindow {
    let windowScene = try #require(
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    )
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(origin: .zero, size: size)
    window.rootViewController = rootViewController
    window.isHidden = false
    rootViewController.view.frame = window.bounds
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
private func installTransitionCoordinator(
    in viewController: LiveRoomViewController,
    isReduceMotionEnabled: Bool
) {
    viewController.seatTransitionCoordinator =
        LiveRoomSeatStageTransitionCoordinator(
            stageView: viewController.seatStageView,
            messagesView: viewController.messagesView,
            isReduceMotionEnabled: { isReduceMotionEnabled }
        )
}

private func pointLiesBetween(
    _ point: CGPoint,
    _ first: CGPoint,
    _ second: CGPoint,
    tolerance: CGFloat
) -> Bool {
    let bounds = CGRect(
        x: min(first.x, second.x) - tolerance,
        y: min(first.y, second.y) - tolerance,
        width: abs(first.x - second.x) + tolerance * 2,
        height: abs(first.y - second.y) + tolerance * 2
    )
    return bounds.contains(point)
}

private func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
    hypot(first.x - second.x, first.y - second.y)
}
