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

    @Test func layoutConfigurationReplacesCachedAttributesBeforePrepare() throws {
        let layout = SeatCollectionLayout()
        let collectionView = SeatLayoutCountTestCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.snapshotCounts = [18]
        let source = makeLayoutTestConfiguration(count: 18)
        layout.apply(source)
        layout.prepare()
        #expect(layout.layoutAttributesForElements(in: .infinite)?.count == 18)

        // 模拟转场收尾：配置先收敛，UIKit 尚未再次调用 prepare()。
        let destination = SeatCollectionLayoutConfiguration(
            itemIDs: Array(source.itemIDs.prefix(9).reversed()),
            states: source.states,
            contentSize: source.contentSize
        )
        layout.apply(destination)
        let attributes = try #require(layout.layoutAttributesForElements(in: .infinite))
        #expect(attributes.count == 9)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 9, section: 0)) == nil)
        let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(first.frame == source.states[source.itemIDs[8]]?.frame)
        withExtendedLifetime(collectionView) {}
    }

    @Test func layoutQueriesRespectSnapshotCountsBetweenPrepareCalls() throws {
        let layout = SeatCollectionLayout()
        let collectionView = SeatLayoutCountTestCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.snapshotCounts = [18]
        layout.apply(makeLayoutTestConfiguration(count: 18))
        layout.prepare()

        // 配置/缓存仍是并集时，当前 Snapshot 的合法范围也必须约束查询结果。
        for count in [9, 5, 1, 0, 18] {
            collectionView.snapshotCounts = [count]
            let attributes = try #require(layout.layoutAttributesForElements(in: .infinite))
            #expect(Set(attributes.map(\.indexPath)) == Set((0..<count).map {
                IndexPath(item: $0, section: 0)
            }))
            for item in 0..<18 {
                #expect((layout.layoutAttributesForItem(at: IndexPath(item: item, section: 0)) != nil)
                    == (item < count))
            }
        }
        collectionView.snapshotCounts = []
        #expect(layout.layoutAttributesForElements(in: .infinite)?.isEmpty == true)
        #expect(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) == nil)
        withExtendedLifetime(collectionView) {}
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
        let leftToRight = SeatCollectionGeometry.configuration(
            presentation: resolvedPresentation,
            items: items,
            metrics: .regular,
            availableWidth: availableWidth,
            direction: .leftToRight
        )
        let rightToLeft = SeatCollectionGeometry.configuration(
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
        let partyConfiguration = SeatCollectionGeometry.configuration(
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
            SeatCollectionGeometry.configuration(
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
    configuration: SeatCollectionLayoutConfiguration,
    availableWidth: CGFloat
) throws {
    let frames = try positions.map { position in
        let slot = try #require(
            presentation.visibleSlots.first {
                $0.position.rawValue == position
            }
        )
        let itemID = SeatCollectionItem(slot: slot).id
        return try #require(configuration.states[itemID]?.frame)
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
private func makeLayoutTestConfiguration(count: Int) -> SeatCollectionLayoutConfiguration {
    let itemIDs = (0..<count).map { SeatCollectionItemID.user(.init(rawValue: "layout-test-\($0)")) }
    let states = Dictionary(uniqueKeysWithValues: itemIDs.enumerated().map { index, itemID in
        (itemID, SeatCollectionLayoutState(
            frame: CGRect(x: index * 40, y: 0, width: 30, height: 50),
            alpha: index >= 9 ? 0 : 1,
            transform: index >= 9 ? CGAffineTransform(scaleX: 0.86, y: 0.86) : .identity
        ))
    })
    return SeatCollectionLayoutConfiguration(
        itemIDs: itemIDs,
        states: states,
        contentSize: CGSize(width: count * 40, height: 50)
    )
}
