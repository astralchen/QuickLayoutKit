//
//  SeatStageTransitionTests.swift
//  DemoTests
//
//  VoiceRoom MVVM feature tests.
//

import CoreGraphics
import QuickLayoutKit
import Testing
import UIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct SeatStageTransitionTests {

    @Test(arguments: [CGFloat(320), 402, 768], [AudienceSeatState.enabled, .disabled])
    func hostNameDoesNotExpandWhenReturningToParty(width: CGFloat, audienceState: AudienceSeatState) async throws {
        let viewModel = VoiceRoomViewModel()
        #expect(viewModel.consumeStageSnapshot(VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2, roomMode: .individual, audienceSeatState: audienceState)))
        let controller = VoiceRoomViewController(viewModel: viewModel)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: width, height: 900))
        defer { window.isHidden = true }
        let stage = controller.seatStageView
        try await waitForSeatUpdates(stage)
        let host = try #require(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let name = try #require(host.allSubviews(of: UILabel.self).first { $0.accessibilityIdentifier == "liveRoom.seat.name.0" })
        let avatar = try #require(host.allSubviews(of: UIImageView.self).first { $0.accessibilityIdentifier == "liveRoom.seat.avatar.0" })
        let score = try #require(host.allSubviews(of: UILabel.self).first { $0.accessibilityIdentifier == "liveRoom.seat.score.0" })
        let sourceSizes = [name.bounds.size, score.bounds.size]
        let sourceHostHeight = host.bounds.height
        #expect(viewModel.consumeStageSnapshot(VoiceRoomViewModel.makeDefaultStageSnapshot(revision: 3)))
        controller.view.layoutIfNeeded()
        var intermediateFrames = 0
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(16))
            let root = try #require(window.layer.presentation())
            let nameLayer = try #require(name.layer.presentation())
            let avatarLayer = try #require(avatar.layer.presentation())
            let scoreLayer = try #require(score.layer.presentation())
            let nameFrame = nameLayer.convert(nameLayer.bounds, to: root)
            let avatarFrame = avatarLayer.convert(avatarLayer.bounds, to: root)
            let scoreFrame = scoreLayer.convert(scoreLayer.bounds, to: root)
            #expect(abs(nameFrame.midX - avatarFrame.midX) < 1)
            #expect(nameFrame.minY >= scoreFrame.maxY)
            for (label, sourceSize) in zip([name, score], sourceSizes) {
                let size = try #require(label.layer.presentation()).bounds.size
                #expect(size.width <= max(sourceSize.width, label.bounds.width) + 0.75)
                #expect(size.height <= max(sourceSize.height, label.bounds.height) + 0.75)
                #expect(size.height >= min(sourceSize.height, label.bounds.height) - 0.75)
            }
            let visibleHeight = try #require(host.layer.presentation()).bounds.height
            if abs(visibleHeight - sourceHostHeight) > 0.5,
               abs(visibleHeight - host.bounds.height) > 0.5 {
                intermediateFrames += 1
            }
        }
        #expect(intermediateFrames > 0, "必须检查实际过渡帧，不能只验证最终昵称")
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)) === host)
        #expect(name.bounds.size == name.layer.presentation()?.bounds.size)
    }

    @Test(arguments: [CGFloat(320), 390, 768])
    func hostAvatarStaysCircularDuringRoomModeTransitions(width: CGFloat) async throws {
        let controller = UIViewController()
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: width, height: 700))
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(
            rootViewController: controller,
            size: CGSize(width: width, height: 900)
        )
        defer { window.isHidden = true }
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot()))
        try await waitForSeatUpdates(stage)

        for mode: RoomMode in [.individual, .party] {
            let host = try #require(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
            let avatar = try #require(host.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.avatar.0"
            })
            let sourceFrame = host.layer.frame
            let roundedViews = host.allSubviews(of: UIView.self).filter { $0.layer.cornerRadius > 0 }
            #expect(roundedViews.contains(avatar))
            #expect(roundedViews.count >= 5)
            stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
                roomMode: mode, audienceSeatState: .enabled)), animated: true)
            var intermediateFrames = 0
            var imageData: Data?
            for frame in 0..<8 {
                try await Task.sleep(for: .milliseconds(20))
                for view in roundedViews {
                    let layer = try #require(view.layer.presentation())
                    let radius = min(layer.bounds.width, layer.bounds.height) / 2
                    #expect(abs(layer.cornerRadius - radius) < 0.75,
                        "0 号麦圆角必须跟随实际尺寸：radius=\(layer.cornerRadius), size=\(layer.bounds.size)")
                }
                if frame == 3 {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                        (window.layer.presentation() ?? window.layer).render(in: context.cgContext)
                    }
                    imageData = image.pngData()
                }
                let visibleFrame = try #require(host.layer.presentation()).frame
                if abs(visibleFrame.height - sourceFrame.height) > 0.5,
                   abs(visibleFrame.height - host.layer.frame.height) > 0.5 {
                    intermediateFrames += 1
                }
            }
            #expect(intermediateFrames > 0, "必须检查过渡帧，不能只验证最终状态")
            try await waitForSeatUpdates(stage)
            #expect(abs(avatar.layer.cornerRadius - avatar.bounds.width / 2) < 0.5)
            Attachment.record(try #require(imageData), named: "host-\(mode)-\(Int(width))-transition.png")
        }
    }

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

    @Test func nativeUpdatesPreserveIdentityAndDeletionGeometry() async throws {
        let fixture = try SeatUpdateFixture()
        defer { fixture.window.isHidden = true }
        let source = makeLayoutTestSection(count: 3)
        await fixture.apply(source)
        let oldFrames = try (0..<3).map {
            try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame)
        }
        let entrant = makeLayoutTestSection(count: 4).items[3]
        let reordered = [source.items[2], source.items[0], entrant].enumerated().map { index, item in
            SeatLayoutItem(identifier: item.identifier, slotID: item.slotID, position: .init(rawValue: index),
                roomSide: item.roomSide, styleID: item.styleID)
        }
        let target = SeatLayoutSection(layoutID: .partyNine, layoutFamily: .partyGrid,
            items: reordered, metrics: .regular)
        await fixture.apply(target, animated: true)
        let deleted = try #require(fixture.layout.disappearing[IndexPath(item: 1, section: 0)]?.last)
        #expect(deleted.alpha == 0)
        #expect(deleted.transform.a == 0.96)
        deleted.transform = .identity
        #expect(deleted.frame == oldFrames[1])
        let movedFrom = try #require(fixture.movementOrigins[source.items[2].identifier])
        #expect(movedFrom == CGPoint(x: oldFrames[2].midX, y: oldFrames[2].midY))
        let inserted = try #require(fixture.layout.appearing[IndexPath(item: 2, section: 0)]?.last)
        #expect(inserted.alpha == 0 && inserted.transform.a == 0.96)
        let current = try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
        #expect(current.frame != oldFrames[2])
        #expect(current.alpha == 1 && current.transform == .identity)
        // 后续更新必须从刚刚完成的目标几何开始，不能复用第一轮缓存。
        let latestFrame = current.frame
        await fixture.apply(source, animated: true)
        #expect(fixture.movementOrigins[source.items[2].identifier] == CGPoint(x: latestFrame.midX, y: latestFrame.midY))
    }

    @Test func sameIdentityBatchUpdatesAnimateGeometryAndMeasurementIsPure() async throws {
        let fixture = try SeatUpdateFixture()
        defer { fixture.window.isHidden = true }
        let source = makeLayoutTestSection(count: 3)
        await fixture.apply(source)
        let oldFrame = try #require(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame)
        let target = SeatLayoutSection(layoutID: .individualAudience, layoutFamily: .individualAudience,
            items: source.items, metrics: .regular)
        let size = fixture.layout.sizeThatFits(fixture.collection.bounds.size, for: target, layoutDirection: .leftToRight)
        #expect(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == oldFrame)
        let host = try #require(fixture.collection.cellForItem(at: IndexPath(item: 0, section: 0)))
        var animatedSourceSize: CGSize?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fixture.collection.performBatchUpdates {
                fixture.layout.invalidateLayout()
                fixture.section = target
            } completion: { _ in continuation.resume() }
            CATransaction.flush()
            if let animation = host.layer.animation(forKey: "bounds.size") as? CABasicAnimation,
               let value = animation.fromValue as? NSValue {
                let start = value.cgSizeValue
                animatedSourceSize = animation.isAdditive
                    ? CGSize(width: host.bounds.width + start.width, height: host.bounds.height + start.height)
                    : start
            }
        }
        #expect(animatedSourceSize == oldFrame.size)
        #expect(fixture.layout.collectionViewContentSize == size)
        #expect(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame != oldFrame)
        fixture.layout.finishUpdates()
        fixture.layout.finishUpdates()
        await fixture.apply(source)
        #expect(fixture.layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame == oldFrame)
    }

    @Test func roomModeTransitionsKeepOnlyCurrentSnapshotAttributes() async throws {
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
            stage.apply(presentation: destination, animated: offset != 0)
            try await waitForSeatUpdates(stage)
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

    @Test func dataOnlyChangesDoNotRequestGeometryAnimation() throws {
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

    @Test func layoutVariantAndUserSlotChangesRequireGeometryAnimation() throws {
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

    @Test func rapidGeometricReplacementCommitsOnlyLatestTarget() async throws {
        let controller = UIViewController()
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        let source = try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot())
        stage.apply(presentation: source)
        try await waitForSeatUpdates(stage)
        let originalClipping = stage.seatCollectionView.clipsToBounds
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2, roomMode: .individual, audienceSeatState: .disabled)), animated: true)
        #expect(stage.isApplyingUpdate)
        #expect(!stage.seatCollectionView.isUserInteractionEnabled)
        #expect(!stage.seatCollectionView.clipsToBounds)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 3, roomMode: .pk(styleID: "room.nine"))), animated: true)
        stage.apply(presentation: source, animated: true)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 9)
        #expect(stage.allSubviews(of: RoomPKDecorationView.self).isEmpty)
        #expect(stage.seatCollectionView.isUserInteractionEnabled)
        #expect(!stage.accessibilityElementsHidden)
        #expect(stage.seatCollectionView.clipsToBounds == originalClipping)
        #expect(stage.seatCollectionView.visibleCells.count == 9)
        #expect(stage.seatCollectionView.visibleCells.allSatisfy { $0.allSubviews(of: SeatView.self).count == 1 })
    }

    @Test(arguments: [false, true])
    func reducedMotionAndDisabledAnimationsCommitDirectly(reducedMotion: Bool) async throws {
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot()))
        try await waitForSeatUpdates(stage)
        stage.isReduceMotionEnabled = { reducedMotion }
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(reducedMotion)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            roomMode: .individual, audienceSeatState: .disabled)), animated: true)
        UIView.setAnimationsEnabled(animationsEnabled)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 1)
        #expect(stage.seatCollectionView.isUserInteractionEnabled)
        #expect(stage.seatCollectionView.visibleCells.allSatisfy { ($0.layer.animationKeys() ?? []).isEmpty })
    }

    @Test func geometryOnlyStageUpdateAndContentRefreshKeepOneSeatView() async throws {
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        let source = try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            roomMode: .individual, audienceSeatState: .disabled))
        stage.apply(presentation: source)
        try await waitForSeatUpdates(stage)
        let firstCell = try #require(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let oldSize = firstCell.bounds.size
        let slots = source.slots.map { slot in
            SeatSlotPresentation(slotID: slot.slotID, position: slot.position, assignment: slot.assignment,
                role: slot.role, styleID: .standardHost, isVisible: slot.isVisible, interaction: slot.interaction)
        }
        let target = SeatStagePresentation(revision: 2, layoutID: source.layoutID, variant: source.variant,
            layoutFamily: .partyGrid, slots: slots, decorations: source.decorations)
        stage.apply(presentation: target, animated: true)
        #expect(stage.isApplyingUpdate)
        let changedSlots = slots.map { slot in
            SeatSlotPresentation(slotID: slot.slotID, position: slot.position,
                assignment: slot.assignment.map { seat in
                    SeatAssignment(seatID: seat.seatID, slotID: seat.slotID, position: seat.position,
                        occupant: seat.occupant, audioState: .muted, score: 123)
                }, role: slot.role, styleID: slot.styleID, isVisible: slot.isVisible, interaction: slot.interaction)
        }
        stage.apply(presentation: SeatStagePresentation(revision: 3, layoutID: target.layoutID,
            variant: target.variant, layoutFamily: target.layoutFamily, slots: changedSlots, decorations: target.decorations))
        #expect(stage.isApplyingUpdate)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)) === firstCell)
        #expect(firstCell.bounds.size != oldSize)
        #expect(firstCell.allSubviews(of: SeatView.self).count == 1)
        #expect(firstCell.allSubviews(of: UILabel.self).contains { $0.text == SeatDisplayContent(presentation: changedSlots[0]).scoreText })
        let hostID = try #require(source.visibleAssignments.first?.userID)
        #expect(stage.giftTargetPoint(forUserID: hostID, in: controller.view) != nil)
    }

    @Test func swappingAndVacatingSeatsPreservesUserCellsAndVisibleGiftAnchors() async throws {
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        let snapshot = VoiceRoomViewModel.makeDefaultStageSnapshot()
        stage.apply(presentation: try presentation(for: snapshot))
        try await waitForSeatUpdates(stage)
        let hostCell = try #require(stage.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        let userID = try #require(snapshot.assignments[0].userID)
        var assignments = snapshot.assignments
        assignments[0] = replacingOccupant(in: snapshot.assignments[0], with: snapshot.assignments[1].occupant)
        assignments[1] = replacingOccupant(in: snapshot.assignments[1], with: snapshot.assignments[0].occupant)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2, assignments: assignments)), animated: true)
        // 动画中头像图片和背景中心相同；实际表示层位置必须与送礼锚点一致。
        try await Task.sleep(for: .milliseconds(30))
        let avatar = try #require(hostCell.allSubviews(of: UIImageView.self).first {
            $0.accessibilityIdentifier?.hasPrefix("liveRoom.seat.avatar.") == true
        })
        let avatarLayer = avatar.layer.presentation() ?? avatar.layer
        let rootLayer = controller.view.layer.presentation() ?? controller.view.layer
        let visibleCenter = avatarLayer.convert(CGPoint(x: avatarLayer.bounds.midX, y: avatarLayer.bounds.midY), to: rootLayer)
        let anchor = try #require(stage.giftTargetPoint(forUserID: userID, in: controller.view))
        #expect(hypot(anchor.x - visibleCenter.x, anchor.y - visibleCenter.y) < 1)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.cellForItem(at: IndexPath(item: 1, section: 0)) === hostCell)
        let seat = assignments[1]
        assignments[1] = SeatAssignment(seatID: seat.seatID, slotID: seat.slotID, position: seat.position,
            occupant: nil, audioState: .unavailable, score: 0)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 3, assignments: assignments)), animated: true)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 9)
        #expect(stage.giftTargetPoint(forUserID: userID, in: controller.view) == nil)
    }

    @Test func pageMovesPublicChatImmediatelyWithoutSceneAnimator() async throws {
        let viewModel = VoiceRoomViewModel()
        let controller = VoiceRoomViewController(viewModel: viewModel)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        try await waitForSeatUpdates(controller.seatStageView)
        controller.view.layoutIfNeeded()
        let oldFrame = controller.messagesView.frame
        let hostCell = try #require(controller.seatStageView.seatCollectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        #expect(viewModel.consumeStageSnapshot(VoiceRoomViewModel.makeDefaultStageSnapshot(
            revision: 2, roomMode: .individual, audienceSeatState: .disabled)))
        controller.view.layoutIfNeeded()
        let newFrame = controller.messagesView.frame
        CATransaction.flush()
        #expect(controller.seatStageView.isApplyingUpdate)
        #expect(!(hostCell.layer.animationKeys() ?? []).isEmpty)
        #expect(newFrame != oldFrame)
        #expect((controller.messagesView.layer.animationKeys() ?? []).isEmpty)
        try await waitForSeatUpdates(controller.seatStageView)
        controller.view.layoutIfNeeded()
        #expect(controller.messagesView.frame == newFrame)
    }

    @Test func hiddenStageCommitsWithoutGeometryAnimation() async throws {
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot()))
        try await waitForSeatUpdates(stage)
        controller.view.isHidden = true
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            roomMode: .individual, audienceSeatState: .disabled)), animated: true)
        #expect(stage.seatCollectionView.isUserInteractionEnabled)
        #expect(!stage.accessibilityElementsHidden)
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 1)
        #expect(stage.seatCollectionView.visibleCells.allSatisfy { ($0.layer.animationKeys() ?? []).isEmpty })
    }

    @Test func repeatedPageDirectionChangesUpdateCollectionAndSeatContent() async throws {
        let controller = VoiceRoomViewController(viewModel: VoiceRoomViewModel())
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 402, height: 874))
        defer { window.isHidden = true }
        try await waitForSeatUpdates(controller.seatStageView)
        var originalFrames: [CGRect] = []
        for direction: UIUserInterfaceLayoutDirection in [.leftToRight, .rightToLeft, .leftToRight] {
            window.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
            controller.reloadLayoutDirection(direction)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await waitForSeatUpdates(controller.seatStageView)
            let collection = controller.seatStageView.seatCollectionView
            #expect(collection.effectiveUserInterfaceLayoutDirection == direction)
            let frames = try (0..<9).map { try #require(collection.collectionViewLayout
                .layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame) }
            if originalFrames.isEmpty { originalFrames = frames }
            for (source, current) in zip(originalFrames, frames) {
                let expectedX = direction == .rightToLeft ? collection.bounds.width - source.maxX : source.minX
                #expect(abs(current.minX - expectedX) < 0.5)
            }
            for cell in collection.visibleCells {
                #expect(cell.effectiveUserInterfaceLayoutDirection == direction)
                #expect(cell.allSubviews(of: SeatView.self).allSatisfy { $0.effectiveUserInterfaceLayoutDirection == direction })
            }
        }
    }

    @Test func environmentChangeAndRemovalSettleLatestSnapshot() async throws {
        let stage = SeatStageView(frame: CGRect(x: 0, y: 0, width: 360, height: 450))
        let controller = UIViewController()
        controller.view.addSubview(stage)
        let window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        defer { window.isHidden = true }
        let source = try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot())
        stage.apply(presentation: source)
        try await waitForSeatUpdates(stage)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            roomMode: .individual, audienceSeatState: .disabled)), animated: true)
        stage.apply(presentation: source, animated: true)
        stage.frame.size.width = 700
        controller.view.semanticContentAttribute = .forceRightToLeft
        stage.setCompactPresentation(true)
        stage.setNeedsLayout()
        stage.layoutIfNeeded()
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 9)
        #expect(stage.seatCollectionView.isUserInteractionEnabled)
        let frames = try (0..<9).map { try #require(stage.seatCollectionView.collectionViewLayout
            .layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame) }
        #expect(frames[1].minX > frames[4].minX)
        #expect(abs(frames[0].midX - stage.seatCollectionView.bounds.width / 2) < 0.5)
        stage.apply(presentation: try presentation(for: VoiceRoomViewModel.makeDefaultStageSnapshot(
            roomMode: .individual, audienceSeatState: .disabled)), animated: true)
        stage.apply(presentation: source, animated: true)
        stage.removeFromSuperview()
        try await waitForSeatUpdates(stage)
        #expect(stage.seatCollectionView.numberOfItems(inSection: 0) == 9)
        #expect(stage.seatCollectionView.isUserInteractionEnabled)
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
    window.makeKeyAndVisible()
    rootViewController.view.frame = window.bounds
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
func waitForSeatUpdates(_ stage: SeatStageView) async throws {
    let deadline = Date().addingTimeInterval(3)
    while stage.isApplyingUpdate && Date() < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!stage.isApplyingUpdate, "麦位更新必须完成并恢复交互")
    stage.setNeedsLayout()
    stage.layoutIfNeeded()
    // UIKit completion 与渲染服务提交最后一帧之间可能相差一帧。
    CATransaction.flush()
    try await Task.sleep(for: .milliseconds(40))
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

/// 记录 UIKit 实际调用的动画属性，避免 finalize 后再查询已经清空的旧事务。
@MainActor
private final class RecordingSeatLayout: SeatCollectionLayout {
    var appearing: [IndexPath: [UICollectionViewLayoutAttributes]] = [:]
    var disappearing: [IndexPath: [UICollectionViewLayoutAttributes]] = [:]

    override func prepare(forCollectionViewUpdates updates: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updates)
        // 多次失效不得覆盖最初保存的源几何。
        invalidateLayout()
        invalidateLayout()
    }

    override func initialLayoutAttributesForAppearingItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let value = super.initialLayoutAttributesForAppearingItem(at: indexPath)
        if let copy = value?.copy() as? UICollectionViewLayoutAttributes {
            appearing[indexPath, default: []].append(copy)
        }
        return value
    }

    override func finalLayoutAttributesForDisappearingItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let value = super.finalLayoutAttributesForDisappearingItem(at: indexPath)
        if let copy = value?.copy() as? UICollectionViewLayoutAttributes {
            disappearing[indexPath, default: []].append(copy)
        }
        return value
    }
}

@MainActor
private final class SeatUpdateFixture {
    var section: SeatLayoutSection?
    lazy var layout = RecordingSeatLayout { [weak self] _, _ in self?.section }
    lazy var collection = UICollectionView(frame: CGRect(x: 0, y: 0, width: 360, height: 600), collectionViewLayout: layout)
    let window: UIWindow
    var source: UICollectionViewDiffableDataSource<Int, SeatCollectionItemID>!
    var movementOrigins: [SeatCollectionItemID: CGPoint] = [:]

    init() throws {
        let controller = UIViewController()
        window = try makeTransitionTestWindow(rootViewController: controller, size: CGSize(width: 390, height: 844))
        controller.view.addSubview(collection)
        collection.contentInsetAdjustmentBehavior = .never
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        source = UICollectionViewDiffableDataSource(collectionView: collection) { collection, index, _ in
            collection.dequeueReusableCell(withReuseIdentifier: "cell", for: index)
        }
        layout.itemIdentifierProvider = { [weak self] in self?.source.itemIdentifier(for: $0) }
    }

    func apply(_ next: SeatLayoutSection, animated: Bool = false) async {
        collection.layoutIfNeeded()
        layout.finishUpdates()
        layout.appearing.removeAll()
        layout.disappearing.removeAll()
        movementOrigins.removeAll()
        section = next
        var snapshot = NSDiffableDataSourceSnapshot<Int, SeatCollectionItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(next.itemIdentifiers)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            source.apply(snapshot, animatingDifferences: animated) { continuation.resume() }
            CATransaction.flush()
            for cell in collection.visibleCells {
                guard let index = collection.indexPath(for: cell), let id = source.itemIdentifier(for: index),
                      let animation = cell.layer.animation(forKey: "position") as? CABasicAnimation,
                      let value = animation.fromValue as? NSValue else { continue }
                let start = value.cgPointValue
                movementOrigins[id] = animation.isAdditive
                    ? CGPoint(x: cell.layer.position.x + start.x, y: cell.layer.position.y + start.y)
                    : start
            }
        }
        collection.layoutIfNeeded()
        layout.finishUpdates()
        // 首次 Snapshot 完成可能同步回调；先提交首帧，下一轮才有可动画的源 Cell。
        CATransaction.flush()
        try? await Task.sleep(for: .milliseconds(40))
        #expect(collection.visibleCells.count == next.items.count)
    }
}
