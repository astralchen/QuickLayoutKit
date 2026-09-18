//
//  SeatStageTransitionTests.swift
//  DemoTests
//
//  VoiceRoom MVVM feature tests.
//

import CoreGraphics
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct SeatStageTransitionTests {

    @Test func invalidationReplacesGeometryBeforePrepare() throws {
        var section = makeLayoutTestSection(count: 18)
        let layout = SeatCollectionLayout { _, _ in section }
        let collection = SeatLayoutCountTestCollectionView(frame: CGRect(x: 0, y: 0, width: 700, height: 600), collectionViewLayout: layout)
        collection.snapshotCounts = [18]
        layout.prepare()
        let sourceFrame = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 8, section: 0))?.frame)
        section = SeatLayoutSection(layoutID: section.layoutID, layoutFamily: section.layoutFamily,
            items: Array(section.items.prefix(9).reversed()), metrics: section.metrics)
        layout.invalidateLayout()
        #expect(layout.layoutAttributesForElements(in: .infinite)?.count == 9)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 9, section: 0)) == nil)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == sourceFrame)
        withExtendedLifetime(collection) {}
    }

    @Test func layoutQueriesRespectSnapshotCountsBetweenPrepareCalls() throws {
        let layout = SeatCollectionLayout(section: makeLayoutTestSection(count: 18))
        let collection = SeatLayoutCountTestCollectionView(frame: CGRect(x: 0, y: 0, width: 700, height: 600), collectionViewLayout: layout)
        collection.snapshotCounts = [18]
        layout.prepare()
        for count in [18, 9, 5, 1, 0, 18] {
            collection.snapshotCounts = [count]
            let attributes = try #require(layout.layoutAttributesForElements(in: .infinite))
            #expect(Set(attributes.map(\.indexPath)) == Set((0..<count).map { IndexPath(item: $0, section: 0) }))
            for item in 0..<18 {
                #expect((layout.layoutAttributesForItem(at: IndexPath(item: item, section: 0)) != nil) == (item < count))
            }
        }
        collection.snapshotCounts = []
        #expect(layout.layoutAttributesForElements(in: .infinite)?.isEmpty == true)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) == nil)
        withExtendedLifetime(collection) {}
    }

    @Test func layoutUsesCurrentSnapshotIdentityDuringReordering() throws {
        var section = makeLayoutTestSection(count: 5)
        var identifiers = section.itemIdentifiers
        let layout = SeatCollectionLayout { _, _ in section }
        let collection = SeatLayoutCountTestCollectionView(frame: CGRect(x: 0, y: 0, width: 700, height: 600), collectionViewLayout: layout)
        collection.snapshotCounts = [5]
        layout.itemIdentifierProvider = { identifiers[$0.item] }
        let old = try (0..<5).map { try #require(layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame) }
        section = SeatLayoutSection(layoutID: section.layoutID, layoutFamily: section.layoutFamily,
            items: Array(section.items.reversed()), metrics: section.metrics)
        layout.invalidateLayout()
        // 描述已重排，Snapshot 还没提交：仍按当前身份返回原几何。
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == old[0])
        identifiers.reverse()
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == old[4])
        layout.itemIdentifierProvider = { _ in nil }
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) == nil)
        withExtendedLifetime(collection) {}
    }

    @Test func layoutRespondsToBoundsDirectionMetricsAndEmptyProvider() throws {
        var section: SeatLayoutSection? = makeLayoutTestSection(count: 9)
        var receivedWidths: [CGFloat] = []
        let layout = SeatCollectionLayout { index, environment in
            #expect(index == 0)
            receivedWidths.append(environment.effectiveContentSize.width)
            return section
        }
        let collection = SeatLayoutCountTestCollectionView(frame: .zero, collectionViewLayout: layout)
        collection.contentInsetAdjustmentBehavior = .never
        collection.snapshotCounts = [9]
        _ = layout.collectionViewContentSize
        for width in [CGFloat(700), 760] {
            collection.bounds.size.width = width
            let host = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            #expect(abs(host.frame.midX - width / 2) < 0.5)
            #expect(layout.collectionViewContentSize.width == width)
        }
        let left = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame)
        collection.semanticContentAttribute = .forceRightToLeft
        let right = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame)
        #expect(abs(right.minX - (760 - left.maxX)) < 0.5)
        let previous = try #require(section)
        section = SeatLayoutSection(layoutID: previous.layoutID, layoutFamily: previous.layoutFamily,
            items: previous.items, metrics: .compact)
        layout.invalidateLayout()
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame.width < right.width)
        #expect(receivedWidths.contains(0) && receivedWidths.contains(700) && receivedWidths.contains(760))
        section = nil
        layout.invalidateLayout()
        #expect(layout.itemIdentifiers.isEmpty)
        #expect(layout.collectionViewContentSize == .zero)
        #expect(layout.layoutAttributesForElements(in: .infinite)?.isEmpty == true)
        withExtendedLifetime(collection) {}
    }

    @Test func transitionInterpolatesAndMeasurementDoesNotMutateLayout() throws {
        var section = makeLayoutTestSection(count: 5)
        let shared = section.items[0]
        let moved = SeatLayoutItem(identifier: shared.identifier, slotID: shared.slotID,
            position: SeatPosition(rawValue: 1), roomSide: shared.roomSide, styleID: shared.styleID)
        let entrant = SeatLayoutItem(identifier: .user(.init(rawValue: "new-user")), slotID: .init(rawValue: "new-slot"),
            position: SeatPosition(rawValue: 0), roomSide: .current, styleID: .standardHost)
        let destination = SeatLayoutSection(layoutID: .individualAudience, layoutFamily: .individualAudience,
            items: [entrant, moved], metrics: .compact)
        let layout = SeatCollectionLayout { _, _ in section }
        let collection = SeatLayoutCountTestCollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 700), collectionViewLayout: layout)
        collection.snapshotCounts = [5]
        let original = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame)
        let targetSize = layout.sizeThatFits(collection.bounds.size, for: destination, layoutDirection: .leftToRight)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == original)
        layout.beginTransition(to: destination)
        collection.snapshotCounts = [6]
        #expect(layout.itemIdentifiers == destination.itemIdentifiers + Array(section.itemIdentifiers.dropFirst()))
        let start = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(start.frame == original)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.alpha == 0)
        layout.transitionProgress = 1
        let end = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(layout.collectionViewContentSize == targetSize)
        layout.transitionProgress = 0.5
        let mid = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0)))
        #expect(abs(mid.frame.midX - (start.frame.midX + end.frame.midX) / 2) < 0.001)
        #expect(abs(mid.frame.height - (start.frame.height + end.frame.height) / 2) < 0.001)
        for index in [0, 2] {
            let faded = try #require(layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0)))
            #expect(faded.alpha == 0.5)
            #expect(abs(faded.transform.a - 0.93) < 0.001)
        }
        _ = layout.sizeThatFits(CGSize(width: 760, height: 0), for: destination, layoutDirection: .rightToLeft)
        #expect(layout.transitionProgress == 0.5)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))?.frame == mid.frame)
        layout.transitionProgress = 2
        #expect(layout.transitionProgress == 1)
        section = destination
        layout.finishTransition()
        collection.snapshotCounts = [2]
        #expect(layout.itemIdentifiers == destination.itemIdentifiers)
        #expect(layout.collectionViewContentSize == targetSize)
        #expect(layout.layoutAttributesForElements(in: .infinite)?.allSatisfy { $0.alpha == 1 && $0.transform == .identity } == true)
        layout.transitionProgress = 0.5
        #expect(layout.transitionProgress == 0)
        withExtendedLifetime(collection) {}
    }

    @Test func finishingTransitionRequeriesProviderEvenWhenSourceIsUnchanged() throws {
        let source = makeLayoutTestSection(count: 1)
        let layout = SeatCollectionLayout(section: source)
        let collection = SeatLayoutCountTestCollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
        collection.snapshotCounts = [1]
        layout.beginTransition(to: makeLayoutTestSection(count: 9))
        #expect(layout.itemIdentifiers.count == 9)
        layout.finishTransition()
        #expect(layout.itemIdentifiers == source.itemIdentifiers)
        #expect(layout.layoutAttributesForElements(in: .infinite)?.count == 1)
        withExtendedLifetime(collection) {}
    }

    @Test func roomModeTransitionsKeepOnlyCurrentSnapshotAttributes() throws {
        let controller = UIViewController()
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(
            rootViewController: controller,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }
        let modes: [(RoomMode, AudienceSeatState, Int)] = [
            (.pk(styleID: "room.nine"), .enabled, 18),
            (.party, .enabled, 9),
            (.individual, .enabled, 5),
            (.individual, .disabled, 1),
            (.pk(styleID: "room.nine"), .enabled, 18),
            (.party, .enabled, 9)
        ]
        for (offset, entry) in modes.enumerated() {
            let destination = try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: entry.0,
                audienceSeatState: entry.1
            ))
            if offset == 0 {
                stage.apply(presentation: destination)
            } else {
                #expect(stage.prepareTransition(to: destination))
                stage.animatePreparedTransition()
                let collection = stage.seatCollectionView
                let attributes = try #require(collection.collectionViewLayout.layoutAttributesForElements(in: .infinite))
                #expect(attributes.allSatisfy {
                    $0.indexPath.section == 0 && $0.indexPath.item < collection.numberOfItems(inSection: 0)
                })
                stage.completePreparedTransition()
            }
            stage.layoutIfNeeded()
            let collection = stage.seatCollectionView
            let layout = collection.collectionViewLayout
            #expect(collection.numberOfItems(inSection: 0) == entry.2)
            let attributes = try #require(layout.layoutAttributesForElements(in: .infinite))
            #expect(Set(attributes.map(\.indexPath)) == Set((0..<entry.2).map {
                IndexPath(item: $0, section: 0)
            }))
            #expect(attributes.allSatisfy { $0.alpha == 1 && $0.transform == .identity })
            #expect(layout.layoutAttributesForItem(at: IndexPath(item: entry.2, section: 0)) == nil)
            let hostID = try #require(VoiceRoomViewModel.hostAssignment.userID)
            #expect(stage.giftTargetPoint(forUserID: hostID, in: controller.view) != nil)
        }
    }

    @Test func collectionItemIdentitySeparatesUsersFromVacancies() throws {
        let resolvedPresentation = try presentation(
            for: VoiceRoomViewModel.makeDefaultStageSnapshot()
        )
        let items = resolvedPresentation.visibleSlots.map(
            SeatCollectionItem.init
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
            for: VoiceRoomViewModel.makeDefaultStageSnapshot()
        )
        let items = resolvedPresentation.visibleSlots.map(
            SeatCollectionItem.init
        )
        let availableWidth: CGFloat = 370
        let leftToRight = seatLayoutTestGeometry(
            presentation: resolvedPresentation,
            items: items,
            metrics: .regular,
            availableWidth: availableWidth,
            direction: .leftToRight
        )
        let rightToLeft = seatLayoutTestGeometry(
            presentation: resolvedPresentation,
            items: items,
            metrics: .regular,
            availableWidth: availableWidth,
            direction: .rightToLeft
        )

        #expect(leftToRight.itemIDs == rightToLeft.itemIDs)
        #expect(leftToRight.contentSize == rightToLeft.contentSize)
        for itemID in leftToRight.itemIDs {
            let leftFrame = try #require(leftToRight.frames[itemID])
            let rightFrame = try #require(rightToLeft.frames[itemID])
            #expect(abs(rightFrame.minX - (availableWidth - leftFrame.maxX)) < 0.5)
            #expect(abs(rightFrame.minY - leftFrame.minY) < 0.5)
            #expect(rightFrame.size == leftFrame.size)
        }
    }

    @Test func seatRowsCenterWithinWideContainers() throws {
        let containerWidth: CGFloat = 760
        let partyPresentation = try presentation(
            for: VoiceRoomViewModel.makeDefaultStageSnapshot()
        )
        let partyMetrics = SeatLayoutMetrics.resolve(
            availableWidth: containerWidth,
            prefersCompactHeight: false
        )
        let availableWidth = containerWidth
            - partyMetrics.stageHorizontalPadding * 2
        let partyConfiguration = seatLayoutTestGeometry(
            presentation: partyPresentation,
            items: partyPresentation.visibleSlots.map(
                SeatCollectionItem.init
            ),
            metrics: partyMetrics,
            availableWidth: availableWidth,
            direction: .leftToRight
        )

        try expectRowsCentered(
            positions: [0],
            presentation: partyPresentation,
            configuration: partyConfiguration,
            availableWidth: availableWidth
        )
        try expectRowsCentered(
            positions: [1, 2, 3, 4],
            presentation: partyPresentation,
            configuration: partyConfiguration,
            availableWidth: availableWidth
        )
        try expectRowsCentered(
            positions: [5, 6, 7, 8],
            presentation: partyPresentation,
            configuration: partyConfiguration,
            availableWidth: availableWidth
        )

        let individualPresentation = try presentation(
            for: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: .individual,
                audienceSeatState: .enabled
            )
        )
        let individualConfiguration =
            seatLayoutTestGeometry(
                presentation: individualPresentation,
                items: individualPresentation.visibleSlots.map(
                    SeatCollectionItem.init
                ),
                metrics: partyMetrics,
                availableWidth: availableWidth,
                direction: .leftToRight
            )
        try expectRowsCentered(
            positions: [0],
            presentation: individualPresentation,
            configuration: individualConfiguration,
            availableWidth: availableWidth
        )
        try expectRowsCentered(
            positions: [1, 2, 3, 4],
            presentation: individualPresentation,
            configuration: individualConfiguration,
            availableWidth: availableWidth
        )
    }

    @Test func containerWidthChangesRecomputeFramesWithinSameMetrics() throws {
        let initialWidth: CGFloat = 700
        let resizedWidth: CGFloat = 760
        #expect(
            SeatLayoutMetrics.resolve(
                availableWidth: initialWidth,
                prefersCompactHeight: false
            )
                == SeatLayoutMetrics.resolve(
                    availableWidth: resizedWidth,
                    prefersCompactHeight: false
                )
        )

        let resolvedPresentation = try presentation(
            for: VoiceRoomViewModel.makeDefaultStageSnapshot()
        )
        let stageView = SeatStageView(
            frame: CGRect(x: 0, y: 0, width: initialWidth, height: 1_000)
        )
        stageView.apply(presentation: resolvedPresentation)
        stageView.layoutIfNeeded()
        let initialCollectionWidth = stageView.seatCollectionView.bounds.width
        let initialHostFrame = try collectionFrame(
            at: 0,
            in: stageView.seatCollectionView
        )

        stageView.frame.size.width = resizedWidth
        stageView.setNeedsLayout()
        stageView.layoutIfNeeded()
        let resizedCollectionWidth = stageView.seatCollectionView.bounds.width
        let resizedHostFrame = try collectionFrame(
            at: 0,
            in: stageView.seatCollectionView
        )
        let firstGuestRowFrames = try (1...4).map {
            try collectionFrame(at: $0, in: stageView.seatCollectionView)
        }

        #expect(resizedCollectionWidth > initialCollectionWidth)
        #expect(
            abs(initialHostFrame.midX - initialCollectionWidth / 2) < 0.5
        )
        #expect(
            abs(resizedHostFrame.midX - resizedCollectionWidth / 2) < 0.5
        )
        #expect(resizedHostFrame.midX > initialHostFrame.midX)
        let rowMinX = try #require(firstGuestRowFrames.map(\.minX).min())
        let rowMaxX = try #require(firstGuestRowFrames.map(\.maxX).max())
        #expect(
            abs((rowMinX + rowMaxX) / 2 - resizedCollectionWidth / 2) < 0.5
        )
    }

    @Test func dataOnlyChangesDoNotCreateSceneTransition() throws {
        let sourceSnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot()
        let changedAssignments = sourceSnapshot.assignments.map { assignment in
            let isOccupied = assignment.occupant != nil
            return SeatAssignment(
                seatID: assignment.seatID,
                slotID: assignment.slotID,
                position: assignment.position,
                occupant: assignment.occupant,
                audioState: isOccupied
                    ? (assignment.audioState == .active ? .muted : .active)
                    : .unavailable,
                score: isOccupied ? assignment.score + 100 : 0
            )
        }
        let destinationSnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2,
            assignments: changedAssignments
        )

        let descriptor = SeatTransitionDescriptor(
            from: try presentation(for: sourceSnapshot),
            to: try presentation(for: destinationSnapshot)
        )

        #expect(!descriptor.requiresTransition)
    }

    @Test func layoutVariantAndUserSlotChangesCreateSceneTransition() throws {
        let partySnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot()
        let individualSnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2,
            roomMode: .individual,
            audienceSeatState: .disabled
        )
        let partyPresentation = try presentation(for: partySnapshot)
        let individualPresentation = try presentation(for: individualSnapshot)

        #expect(
            SeatTransitionDescriptor(
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
        let movedSnapshot = VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 3,
            assignments: movedAssignments
        )

        #expect(
            SeatTransitionDescriptor(
                from: partyPresentation,
                to: try presentation(for: movedSnapshot)
            ).requiresTransition
        )
    }

    @Test func sharedHostAndStageUseTheSameInteractiveTimeline() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = VoiceRoomViewModel()
        let viewController = VoiceRoomViewController(viewModel: viewModel)
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
                VoiceRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    roomMode: .individual,
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

    @Test func rapidGeometricReplacementCommitsLatestStateWithoutSecondAnimation() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = VoiceRoomViewModel()
        let viewController = VoiceRoomViewController(viewModel: viewModel)
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
        let initialPoint = try #require(
            viewController.seatStageView.giftTargetPoint(
                forUserID: hostID,
                in: viewController.view
            )
        )

        #expect(
            viewModel.consumeStageSnapshot(
                VoiceRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    roomMode: .individual,
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
                VoiceRoomViewModel.makeDefaultStageSnapshot(
                    revision: 3,
                    roomMode: .party,
                    audienceSeatState: .enabled
                )
            )
        )
        let latestPoint = try #require(
            viewController.seatStageView.giftTargetPoint(
                forUserID: hostID,
                in: viewController.view
            )
        )

        #expect(viewController.seatTransitionCoordinator.testingAnimator == nil)
        #expect(!viewController.seatTransitionCoordinator.isTransitioning)
        #expect(
            viewController.seatTransitionCoordinator.testingActiveUserIDs.isEmpty
        )
        #expect(
            distance(initialPoint, latestPoint) <= 1.5,
            "初始最终点 \(initialPoint)，最新 revision 最终点 \(latestPoint)"
        )
        #expect(distance(interruptedPoint, latestPoint) > 1.5)
        #expect(viewModel.state.snapshot.revision == 3)
    }

    @Test func reduceMotionUsesSceneCrossfadeWithoutSeatTransforms() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewModel = VoiceRoomViewModel()
        let viewController = VoiceRoomViewController(viewModel: viewModel)
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
                VoiceRoomViewModel.makeDefaultStageSnapshot(
                    revision: 2,
                    roomMode: .individual,
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
    for snapshot: RoomStageSnapshot
) throws -> SeatStagePresentation {
    switch SeatLayoutResolver.resolve(snapshot: snapshot) {
    case let .success(presentation):
        return presentation
    case let .failure(error):
        Issue.record("无法解析测试舞台：\(error)")
        throw error
    }
}

private func expectRowsCentered(
    positions: [Int],
    presentation: SeatStagePresentation,
    configuration: SeatLayoutTestGeometry,
    availableWidth: CGFloat
) throws {
    let frames = try positions.map { position in
        let slot = try #require(
            presentation.visibleSlots.first {
                $0.position.rawValue == position
            }
        )
        let itemID = SeatCollectionItem(slot: slot).id
        return try #require(configuration.frames[itemID])
    }
    let minX = try #require(frames.map(\.minX).min())
    let maxX = try #require(frames.map(\.maxX).max())
    #expect(abs((minX + maxX) / 2 - availableWidth / 2) < 0.5)
}

/// 在主 Actor 完成集合布局后读取测试目标位置。
@MainActor
private func collectionFrame(
    at item: Int,
    in collectionView: UICollectionView
) throws -> CGRect {
    collectionView.layoutIfNeeded()
    return try #require(
        collectionView.collectionViewLayout.layoutAttributesForItem(
            at: IndexPath(item: item, section: 0)
        )?.frame
    )
}

private func replacingOccupant(
    in assignment: SeatAssignment,
    with occupant: SeatOccupant?
) -> SeatAssignment {
    SeatAssignment(
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
    in viewController: VoiceRoomViewController,
    isReduceMotionEnabled: Bool
) {
    viewController.seatTransitionCoordinator =
        SeatStageTransitionCoordinator(
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

/// 控制 UIKit 当前可见的 Snapshot 数量，精确覆盖 prepare() 之间的查询窗口。
@MainActor
private final class SeatLayoutCountTestCollectionView: UICollectionView {
    var snapshotCounts: [Int] = []

    override var numberOfSections: Int { snapshotCounts.count }

    override func numberOfItems(inSection section: Int) -> Int {
        snapshotCounts[section]
    }
}

@MainActor
private func makeLayoutTestSection(count: Int) -> SeatLayoutSection {
    SeatLayoutSection(layoutID: .partyNine, layoutFamily: .partyGrid,
        items: (0..<count).map { index in
            SeatLayoutItem(identifier: .user(.init(rawValue: "layout-test-\(index)")),
                slotID: .init(rawValue: "layout-slot-\(index)"), position: .init(rawValue: index),
                roomSide: .current, styleID: index == 0 ? .standardHost : .standardGuest)
        }, metrics: .regular)
}

/// 测试通过真实 Layout 的属性接口读取结果，不调用内部几何计算器。
struct SeatLayoutTestGeometry: Equatable {
    let itemIDs: [SeatCollectionItemID]
    let frames: [SeatCollectionItemID: CGRect]
    let contentSize: CGSize
}

@MainActor
func seatLayoutTestGeometry(
    presentation: SeatStagePresentation,
    items: [SeatCollectionItem],
    metrics: SeatLayoutMetrics,
    availableWidth: CGFloat,
    direction: UIUserInterfaceLayoutDirection
) -> SeatLayoutTestGeometry {
    let section = SeatLayoutSection(layoutID: presentation.layoutID, layoutFamily: presentation.layoutFamily,
        items: items.map(SeatLayoutItem.init), metrics: metrics)
    let layout = SeatCollectionLayout(section: section)
    let collection = SeatLayoutCountTestCollectionView(
        frame: CGRect(x: 0, y: 0, width: availableWidth, height: 1_000), collectionViewLayout: layout)
    collection.contentInsetAdjustmentBehavior = .never
    collection.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
    collection.snapshotCounts = [items.count]
    let frames = Dictionary(uniqueKeysWithValues: items.enumerated().compactMap { index, item -> (SeatCollectionItemID, CGRect)? in
        guard let frame = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame else { return nil }
        return (item.id, frame)
    })
    let result = SeatLayoutTestGeometry(itemIDs: layout.itemIdentifiers, frames: frames, contentSize: layout.collectionViewContentSize)
    withExtendedLifetime(collection) {}
    return result
}
