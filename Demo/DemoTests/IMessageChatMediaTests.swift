//
//  IMessageChatMediaTests.swift
//  DemoTests
//
//  验证 UIKit 照片、视频消息及输入栏联动行为。
//

import CoreGraphics
import Foundation
import Testing
import UIKit
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct IMessageChatMediaTests {
    @Test func mediaGroupAndFollowupTextPublishAtomically() throws {
        let fixture = try MediaFixture(itemCount: 5, videoIndices: [2])
        defer { fixture.remove() }
        let viewModel = makeViewModel()
        var reasons: [IMessageChatViewModel.UpdateReason] = []
        viewModel.bind { _, reason in reasons.append(reason) }

        #expect(
            viewModel.sendMediaGroup(
                fixture.group,
                followedByText: "  caption  "
            )
        )

        let messages = messagePresentations(in: viewModel.state)
        let media = try #require(messages.first(where: { $0.id == 3 }))
        let text = try #require(messages.first(where: { $0.id == 4 }))
        #expect(media.mediaGroup == fixture.group)
        #expect(media.deliveryText == "localized.imessage.status.sending")
        #expect(text.text == "  caption  ")
        #expect(text.deliveryText == "localized.imessage.status.sending")
        #expect(!viewModel.state.isTyping)
        #expect(viewModel.state.isProcessingMessages)
        #expect(reasons == [.initial, .sentMessage])
        viewModel.cancelPendingReply()
    }

    @Test func mediaGroupWithoutTextOwnsDeliveryStatus() throws {
        let fixture = try MediaFixture(itemCount: 1)
        defer { fixture.remove() }
        let viewModel = makeViewModel()

        #expect(
            viewModel.sendMediaGroup(
                fixture.group,
                followedByText: " \n "
            )
        )

        let sent = try #require(
            messagePresentations(in: viewModel.state)
                .first(where: { $0.id == 3 })
        )
        #expect(sent.mediaGroup == fixture.group)
        #expect(sent.deliveryText == "localized.imessage.status.sending")
        #expect(!messagePresentations(in: viewModel.state).contains { $0.id == 4 })
        viewModel.cancelPendingReply()
    }

    @Test func twentyMediaItemsRemainOneOrderedMessage() throws {
        let fixture = try MediaFixture(itemCount: 20, videoIndices: [3, 19])
        defer { fixture.remove() }
        let viewModel = makeViewModel()

        #expect(viewModel.sendMediaGroup(fixture.group, followedByText: ""))
        let sent = try #require(
            messagePresentations(in: viewModel.state)
                .first(where: { $0.id == 3 })
        )
        #expect(sent.mediaGroup?.items.count == 20)
        #expect(sent.mediaGroup?.items.map(\.id) == fixture.group.items.map(\.id))
        viewModel.cancelPendingReply()
    }

    @Test func mediaValidationRejectsInvalidGroupsWithoutPartialMessages() throws {
        let fixture = try MediaFixture(itemCount: 1)
        defer { fixture.remove() }
        let viewModel = makeViewModel()
        let originalTimeline = viewModel.state.timeline

        #expect(
            !viewModel.sendMediaGroup(
                IMessageChatMediaGroupAttachment(items: []),
                followedByText: "must remain"
            )
        )
        let tooMany = IMessageChatMediaGroupAttachment(
            items: Array(repeating: fixture.group.items[0], count: 21)
        )
        #expect(!viewModel.sendMediaGroup(tooMany, followedByText: "must remain"))

        let missingItem = IMessageChatMediaItem(
            assetIdentifier: nil,
            originalFileURL: fixture.directory.appendingPathComponent("missing.jpg"),
            thumbnailFileURL: fixture.group.items[0].thumbnailFileURL,
            pixelSize: CGSize(width: 100, height: 100),
            kind: .image
        )
        #expect(
            !viewModel.sendMediaGroup(
                IMessageChatMediaGroupAttachment(items: [missingItem]),
                followedByText: "must remain"
            )
        )
        let invalidVideo = IMessageChatMediaItem(
            assetIdentifier: nil,
            originalFileURL: fixture.group.items[0].originalFileURL,
            thumbnailFileURL: fixture.group.items[0].thumbnailFileURL,
            pixelSize: CGSize(width: 100, height: 100),
            kind: .video(duration: 0)
        )
        #expect(
            !viewModel.sendMediaGroup(
                IMessageChatMediaGroupAttachment(items: [invalidVideo]),
                followedByText: "must remain"
            )
        )
        #expect(viewModel.state.timeline == originalTimeline)
    }

    @Test func mediaDraftRequiresEveryOrderedImportToFinish() throws {
        let fixture = try MediaFixture(itemCount: 2, videoIndices: [1])
        defer { fixture.remove() }
        let ready = fixture.group.items.map {
            IMessageChatMediaDraftItemPresentation(
                id: $0.id,
                assetIdentifier: $0.assetIdentifier,
                content: .ready($0)
            )
        }
        let importing = IMessageChatMediaDraftPresentation(
            groupID: fixture.group.id,
            items: [
                ready[0],
                IMessageChatMediaDraftItemPresentation(
                    id: ready[1].id,
                    assetIdentifier: ready[1].assetIdentifier,
                    content: .importing
                ),
            ]
        )
        #expect(!importing.canSend)
        #expect(importing.attachment == nil)

        let complete = IMessageChatMediaDraftPresentation(
            groupID: fixture.group.id,
            items: ready
        )
        #expect(complete.canSend)
        #expect(complete.attachment?.items.map(\.id) == fixture.group.items.map(\.id))
    }

    @Test func mediaDraftItemWidthFollowsAttachmentAspectRatioWithinLimits() {
        #expect(
            IMessageChatMediaDraftLayoutPolicy.itemSize(
                for: CGSize(width: 900, height: 1600)
            ) == CGSize(width: 80, height: 120)
        )
        #expect(
            IMessageChatMediaDraftLayoutPolicy.itemSize(
                for: CGSize(width: 1000, height: 1000)
            ) == CGSize(width: 120, height: 120)
        )
        #expect(
            IMessageChatMediaDraftLayoutPolicy.itemSize(
                for: CGSize(width: 1600, height: 900)
            ) == CGSize(width: 160, height: 120)
        )
        #expect(
            IMessageChatMediaDraftLayoutPolicy.itemSize(for: .zero)
                == CGSize(width: 80, height: 120)
        )
    }

    @Test func composerRendersScaledDraftItemsAnimatedBadgeAndHairline() throws {
        let fixture = try MediaFixture(
            itemCount: 3,
            pixelSizes: [
                CGSize(width: 900, height: 1600),
                CGSize(width: 1000, height: 1000),
                CGSize(width: 1600, height: 900),
            ],
            animatedIndices: [1]
        )
        defer { fixture.remove() }
        let draft = IMessageChatMediaDraftPresentation(
            groupID: fixture.group.id,
            items: fixture.group.items.map {
                IMessageChatMediaDraftItemPresentation(
                    id: $0.id,
                    assetIdentifier: $0.assetIdentifier,
                    content: .ready($0)
                )
            }
        )
        let composer = IMessageChatComposerView(
            frame: CGRect(x: 0, y: 0, width: 402, height: 60)
        )
        composer.configure(
            strings: IMessageChatPreviewData.composerStrings,
            mediaStrings: mediaStrings
        )
        composer.applyMediaDraft(draft)
        composer.frame.size.height = composer.intrinsicContentSize.height
        composer.setNeedsQuickLayout()
        composer.layoutIfNeeded()

        let itemFrames = composer.mediaDraftStripView.renderedItemFrames
        #expect(itemFrames.map(\.size) == [
            CGSize(width: 80, height: 120),
            CGSize(width: 120, height: 120),
            CGSize(width: 160, height: 120),
        ])
        #expect(itemFrames[1].minX - itemFrames[0].maxX == 4)
        #expect(itemFrames[2].minX - itemFrames[1].maxX == 4)
        #expect(
            composer.mediaDraftStripView.animatedBadgeItemIDs
                == [fixture.group.items[1].id]
        )

        let stripFrame = composer.mediaDraftStripView.convert(
            composer.mediaDraftStripView.bounds,
            to: composer
        )
        let separatorFrame = composer.mediaDraftSeparatorView.convert(
            composer.mediaDraftSeparatorView.bounds,
            to: composer
        )
        let textFrame = composer.textView.convert(
            composer.textView.bounds,
            to: composer
        )
        #expect(
            abs(
                separatorFrame.height
                    - 1 / max(1, composer.traitCollection.displayScale)
            ) < 0.01
        )
        #expect(separatorFrame.minY >= stripFrame.maxY + 3.9)
        #expect(separatorFrame.maxY < textFrame.minY)
        #expect(abs(separatorFrame.minX - 84) < 0.5)
        #expect(abs(separatorFrame.maxX - 370) < 0.5)
    }

    @Test func fiveItemRenderOrderRotatesWithoutMutatingModelOrder() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        let originalIDs = fixture.group.items.map(\.id)
        #expect(IMessageChatMediaStackPolicy.renderOrder(frontIndex: 0, itemCount: 5) == [0, 1, 2, 3, 4])
        #expect(IMessageChatMediaStackPolicy.renderOrder(frontIndex: 1, itemCount: 5) == [1, 2, 3, 4, 0])
        #expect(IMessageChatMediaStackPolicy.renderOrder(frontIndex: 2, itemCount: 5) == [2, 3, 4, 0, 1])
        #expect(IMessageChatMediaStackPolicy.renderOrder(frontIndex: 3, itemCount: 5) == [3, 4, 0, 1, 2])
        #expect(IMessageChatMediaStackPolicy.renderOrder(frontIndex: 4, itemCount: 5) == [4, 0, 1, 2, 3])
        #expect(fixture.group.items.map(\.id) == originalIDs)
    }

    @Test func fiveItemStackDistributesCardsAcrossTheCurrentCover() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        let view = IMessageChatMediaMessageView()

        func configure(frontIndex: Int) {
            view.configure(
                messageID: 7,
                direction: .outgoing,
                group: fixture.group,
                frontIndex: frontIndex,
                strings: mediaStrings
            )
            view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }

        #expect(IMessageChatMediaStackPolicy.visibleIndices(frontIndex: 0, itemCount: 5) == [0, 1, 2, 3, 4])
        #expect(IMessageChatMediaStackPolicy.visibleIndices(frontIndex: 2, itemCount: 5) == [0, 1, 2, 3, 4])
        #expect(IMessageChatMediaStackPolicy.visibleIndices(frontIndex: 4, itemCount: 5) == [0, 1, 2, 3, 4])
        #expect(
            IMessageChatMediaStackPolicy.visibleIndices(
                frontIndex: 10,
                itemCount: 20
            ) == [8, 9, 10, 11, 12]
        )
        #expect(
            IMessageChatMediaStackPolicy.visibleIndices(
                frontIndex: 19,
                itemCount: 20
            ) == [15, 16, 17, 18, 19]
        )

        configure(frontIndex: 0)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minX == 0)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minX == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minY == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minY == 56)

        configure(frontIndex: 2)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minX == 0)
        #expect(view.visibleCardFrame(forMediaIndex: 2)?.minX == 16)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minX == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minY == 44)
        #expect(view.visibleCardFrame(forMediaIndex: 2)?.minY == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minY == 44)
        #expect(view.visibleCardZPosition(forMediaIndex: 2) == 30)
        #expect(view.visibleCardZPosition(forMediaIndex: 1) == 29)
        #expect(view.visibleCardZPosition(forMediaIndex: 0) == 28)
        let previousAngle = view.visibleCardRestingTransform(forMediaIndex: 0)
            .map { atan2($0.b, $0.a) } ?? 0
        let nextAngle = view.visibleCardRestingTransform(forMediaIndex: 4)
            .map { atan2($0.b, $0.a) } ?? 0
        #expect(previousAngle > 0)
        #expect(nextAngle < 0)

        configure(frontIndex: 4)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minX == 0)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minX == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minY == 56)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minY == 32)

        view.semanticContentAttribute = .forceRightToLeft
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(view.visibleCardFrame(forMediaIndex: 0)?.minX == 32)
        #expect(view.visibleCardFrame(forMediaIndex: 4)?.minX == 0)
        let mirroredPreviousAngle = view.visibleCardRestingTransform(forMediaIndex: 0)
            .map { atan2($0.b, $0.a) } ?? 0
        #expect(mirroredPreviousAngle < 0)
    }

    @Test func twentyItemStackCapsVisibleLayersAtFiveAndReusesStableCards() throws {
        let fixture = try MediaFixture(itemCount: 20)
        defer { fixture.remove() }
        let view = IMessageChatMediaMessageView()

        view.configure(
            messageID: 8,
            direction: .outgoing,
            group: fixture.group,
            frontIndex: 2,
            strings: mediaStrings
        )
        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutIfNeeded()
        let stableCardIDs = Dictionary(
            uniqueKeysWithValues: (1...4).compactMap { index in
                view.visibleCardObjectIdentifier(forMediaIndex: index).map {
                    (index, $0)
                }
            }
        )

        #expect(view.visibleCardCount == 5)
        #expect(view.intrinsicContentSize == CGSize(width: 248, height: 356))

        view.configure(
            messageID: 8,
            direction: .outgoing,
            group: fixture.group,
            frontIndex: 3,
            strings: mediaStrings
        )
        view.setNeedsLayout()
        view.layoutIfNeeded()

        #expect(view.visibleCardCount == 5)
        for index in 1...4 {
            #expect(
                view.visibleCardObjectIdentifier(forMediaIndex: index)
                    == stableCardIDs[index]
            )
        }
        #expect(view.visibleCardFrame(forMediaIndex: 1)?.minX == 0)
        #expect(view.visibleCardFrame(forMediaIndex: 3)?.minX == 16)
        #expect(view.visibleCardFrame(forMediaIndex: 5)?.minX == 32)
    }

    @Test func stackGesturePolicyUsesPhysicalDirectionsThresholdsAndBoundaries() {
        #expect(IMessageChatMediaStackPolicy.isHorizontalPan(velocity: CGPoint(x: 121, y: 100)))
        #expect(!IMessageChatMediaStackPolicy.isHorizontalPan(velocity: CGPoint(x: 120, y: 100)))
        #expect(IMessageChatMediaStackPolicy.targetIndex(frontIndex: 2, itemCount: 5, translationX: -50, velocityX: 0) == 3)
        #expect(IMessageChatMediaStackPolicy.targetIndex(frontIndex: 2, itemCount: 5, translationX: 50, velocityX: 0) == 1)
        #expect(IMessageChatMediaStackPolicy.targetIndex(frontIndex: 0, itemCount: 5, translationX: 50, velocityX: 0) == nil)
        #expect(IMessageChatMediaStackPolicy.targetIndex(frontIndex: 4, itemCount: 5, translationX: -50, velocityX: 0) == nil)
        #expect(IMessageChatMediaStackPolicy.shouldCommit(translationX: 130, velocityX: 0, isReordered: true))
        #expect(!IMessageChatMediaStackPolicy.shouldCommit(translationX: 43, velocityX: 549, isReordered: false))
        #expect(IMessageChatMediaStackPolicy.shouldCommit(translationX: -2, velocityX: -550, isReordered: false))
        #expect(!IMessageChatMediaStackPolicy.shouldCommit(translationX: -2, velocityX: 700, isReordered: false))
    }

    /// 换层后略微回拖越过同一临界值即恢复，越过起点后重新计算另一侧候选。
    @Test func stackPreviewReordersReversiblyWithoutChangingItsStartIndex() {
        var state = IMessageChatMediaStackPolicy.Interaction(startIndex: 2, itemCount: 5, cardWidth: 200)
        for (distance, reordered) in [(-119.0, false), (-120, true), (-119.9, false),
                                       (-120, true), (-119.9, false), (-112, false),
                                       (-108, false), (-107, false), (-150, true), (-80, false)] {
            state.update(translationX: distance)
            #expect(state.isReordered == reordered)
            #expect(state.startIndex == 2)
            #expect(state.candidateIndex == 3)
            #expect(state.committedIndex(velocityX: 0) == (reordered ? 3 : nil))
        }
        state.update(translationX: 40)
        #expect(state.candidateIndex == 1)
        #expect(!state.isReordered)
        state.update(translationX: 120)
        #expect(state.committedIndex(velocityX: 0) == 1)
        state.update(translationX: 0)
        #expect(state.candidateIndex == nil)
        #expect(!state.isReordered)
    }

    /// 左右两个方向均在同一距离恢复真实卡片层级，且松手取消不发布索引。
    @Test func stackRestoresLayerImmediatelyBelowTheReorderThreshold() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        for sign in [CGFloat(-1), CGFloat(1)] {
            let view = makeStackView(fixture.group, frontIndex: 2)
            let candidate = sign < 0 ? 3 : 1
            let width = try #require(view.visibleCardFrame(forMediaIndex: 2)?.width)
            let threshold = width * 0.60
            var changeCount = 0
            view.frontIndexDidChange = { _, _ in changeCount += 1 }
            view.handlePan(state: .began, translationX: 0, velocityX: sign * 100)
            for _ in 0..<3 {
                view.handlePan(state: .changed, translationX: sign * threshold, velocityX: 0)
                #expect(view.visibleCardZPosition(forMediaIndex: candidate)! > view.visibleCardZPosition(forMediaIndex: 2)!)
                view.handlePan(state: .changed, translationX: sign * (threshold - 0.1), velocityX: 0)
                #expect(view.visibleCardZPosition(forMediaIndex: 2)! > view.visibleCardZPosition(forMediaIndex: candidate)!)
                #expect(view.frontMediaIndex == 2)
                #expect(changeCount == 0)
            }
            view.handlePan(state: .ended, translationX: sign * (threshold - 0.1), velocityX: 0, animated: false)
            #expect(view.frontMediaIndex == 2)
            #expect(changeCount == 0)
        }
    }

    /// 阈值取自实际宽度，速度仅用于松手判定，边界不会被快速甩动穿透。
    @Test func stackReleaseUsesActualWidthVelocityAndCollectionBoundaries() {
        for width in [120.0, 216.0] {
            var state = IMessageChatMediaStackPolicy.Interaction(startIndex: 0, itemCount: 2, cardWidth: width)
            state.update(translationX: -width * 0.61)
            #expect(state.isReordered)
            #expect(state.progress == 1)
            state.update(translationX: -width * 0.50)
            #expect(state.committedIndex(velocityX: 0) == nil)
            state.update(translationX: -2)
            #expect(!state.isReordered)
            #expect(state.committedIndex(velocityX: -550) == 1)
            #expect(state.committedIndex(velocityX: -549) == nil)
            #expect(state.committedIndex(velocityX: 700) == nil)
            state.update(translationX: 200)
            #expect(state.progress == 0)
            #expect(state.displayedTranslationX == 18)
            #expect(state.committedIndex(velocityX: 900) == nil)
        }
        var last = IMessageChatMediaStackPolicy.Interaction(startIndex: 19, itemCount: 20, cardWidth: 216)
        last.update(translationX: -200)
        #expect(last.displayedTranslationX == -18)
        #expect(last.committedIndex(velocityX: -900) == nil)
    }

    /// 一次手势可多次换层，普通重新配置和布局不能提前提交或清除预览。
    @Test func stackDraggingPreservesIdentityAndCommitsOnlyAtRelease() throws {
        let fixture = try MediaFixture(itemCount: 5, videoIndices: [0])
        defer { fixture.remove() }
        let view = makeStackView(fixture.group)
        let cardID = view.visibleCardObjectIdentifier(forMediaIndex: 0)
        let size = view.intrinsicContentSize
        var changes: [(Int, Int)] = []
        view.frontIndexDidChange = { changes.append(($0, $1)) }
        view.handlePan(state: .began, translationX: 0, velocityX: -100)
        view.handlePan(state: .changed, translationX: -140, velocityX: 0)
        #expect(view.frontMediaIndex == 0)
        #expect(changes.isEmpty)
        #expect(view.visibleCardZPosition(forMediaIndex: 1)! > view.visibleCardZPosition(forMediaIndex: 0)!)
        let transform = try #require(view.visibleCardTransform(forMediaIndex: 0))
        #expect(abs(hypot(transform.a, transform.b) - 0.72) < 0.001)
        let center = view.visibleCardCenter(forMediaIndex: 0)
        view.configure(messageID: 8, direction: .outgoing, group: fixture.group, frontIndex: 0, strings: mediaStrings)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(view.visibleCardTransform(forMediaIndex: 0) == transform)
        #expect(view.visibleCardCenter(forMediaIndex: 0) == center)
        #expect(view.visibleCardObjectIdentifier(forMediaIndex: 0) == cardID)
        #expect(view.mediaIndex(at: .zero) == nil)
        view.handlePan(state: .changed, translationX: -100, velocityX: 0)
        #expect(view.visibleCardZPosition(forMediaIndex: 0)! > view.visibleCardZPosition(forMediaIndex: 1)!)
        view.handlePan(state: .changed, translationX: -140, velocityX: 0)
        #expect(changes.isEmpty)
        view.handlePan(state: .ended, translationX: -140, velocityX: 0, animated: false)
        #expect(view.frontMediaIndex == 1)
        #expect(changes.count == 1)
        #expect(changes.first?.0 == 8 && changes.first?.1 == 1)
        #expect(view.visibleCardObjectIdentifier(forMediaIndex: 0) == cardID)
        #expect(view.intrinsicContentSize == size)
        #expect(view.visibleCardTransform(forMediaIndex: 0) == view.visibleCardRestingTransform(forMediaIndex: 0))
        #expect(view.visibleCardZPosition(forMediaIndex: 1) == 30)
    }

    /// 未过阈值、越界后回拖和系统取消均完整恢复所有卡片，而非只恢复原封面。
    @Test func stackCancellationRestoresEveryCard() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        for terminal in [UIGestureRecognizer.State.ended, .cancelled, .failed] {
            let view = makeStackView(fixture.group, frontIndex: 2)
            var changeCount = 0
            view.frontIndexDidChange = { _, _ in changeCount += 1 }
            let centers = (0..<5).map { view.visibleCardCenter(forMediaIndex: $0) }
            view.handlePan(state: .began, translationX: 0, velocityX: -100)
            view.handlePan(state: .changed, translationX: -150, velocityX: 0)
            if terminal == .ended {
                view.handlePan(state: .changed, translationX: -60, velocityX: 0)
            }
            view.handlePan(state: terminal, translationX: terminal == .ended ? -60 : -150,
                           velocityX: terminal == .ended ? 0 : -900, animated: false)
            #expect(view.frontMediaIndex == 2)
            #expect(changeCount == 0)
            for index in 0..<5 {
                #expect(view.visibleCardTransform(forMediaIndex: index) == view.visibleCardRestingTransform(forMediaIndex: index))
                #expect(view.visibleCardCenter(forMediaIndex: index) == centers[index])
                #expect(view.visibleCardZPosition(forMediaIndex: index) == CGFloat(30 - abs(index - 2)))
            }
        }
    }

    /// 大组窗口只在提交后移动；拖动中的方向、窄屏和边界复用共享同一逻辑。
    @Test func stackWindowAndGeometryChangesKeepConfirmedState() throws {
        let fixture = try MediaFixture(itemCount: 20)
        defer { fixture.remove() }
        for direction in [IMessageChatDirection.incoming, .outgoing] {
            for semantic in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
                let view = makeStackView(fixture.group, frontIndex: 2, direction: direction)
                view.semanticContentAttribute = semantic
                view.frame.size.width = 180
                view.setNeedsLayout()
                view.layoutIfNeeded()
                let width = try #require(view.visibleCardFrame(forMediaIndex: 2)?.width)
                let stableIDs = (1...4).map { view.visibleCardObjectIdentifier(forMediaIndex: $0) }
                view.handlePan(state: .began, translationX: 0, velocityX: -100)
                view.handlePan(state: .changed, translationX: -width * 0.7, velocityX: 0)
                #expect(view.visibleCardCount == 5)
                #expect(view.visibleCardObjectIdentifier(forMediaIndex: 5) == nil)
                view.handlePan(state: .ended, translationX: -width * 0.7, velocityX: 0, animated: false)
                #expect(view.frontMediaIndex == 3)
                #expect(view.visibleCardCount == 5)
                for index in 1...4 {
                    #expect(view.visibleCardObjectIdentifier(forMediaIndex: index) == stableIDs[index - 1])
                }
                view.handlePan(state: .began, translationX: 0, velocityX: 100)
                view.handlePan(state: .ended, translationX: width * 0.7, velocityX: 0, animated: false)
                #expect(view.frontMediaIndex == 2)
                for index in 1...4 {
                    #expect(view.visibleCardObjectIdentifier(forMediaIndex: index) == stableIDs[index - 1])
                }
                view.handlePan(state: .began, translationX: 0, velocityX: -100)
                view.handlePan(state: .changed, translationX: -140, velocityX: 0)
                view.frame.size.width = 160
                view.setNeedsLayout()
                view.layoutIfNeeded()
                view.handlePan(state: .ended, translationX: -140, velocityX: -900, animated: false)
                #expect(view.frontMediaIndex == 2)
                #expect(view.visibleCardTransform(forMediaIndex: 2) == .identity)
                view.handlePan(state: .began, translationX: -140, velocityX: -100)
                view.semanticContentAttribute = semantic == .forceLeftToRight ? .forceRightToLeft : .forceLeftToRight
                view.setNeedsLayout()
                view.layoutIfNeeded()
                view.handlePan(state: .ended, translationX: -140, velocityX: 0, animated: false)
                #expect(view.frontMediaIndex == 2)
                #expect(view.visibleCardTransform(forMediaIndex: 2) == .identity)
            }
        }
    }

    /// 收尾阻止重入；复用和同 ID 媒体内容替换后旧完成回调不得写入新绑定。
    @Test func stackAnimationPublishesOnceAndRejectsStaleCompletion() async throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        let view = makeStackView(fixture.group)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(view)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        var changes: [Int] = []
        view.frontIndexDidChange = { _, index in changes.append(index) }
        view.handlePan(state: .began, translationX: 0, velocityX: -100)
        view.handlePan(state: .ended, translationX: -2, velocityX: -600)
        #expect(view.frontMediaIndex == 1)
        #expect(changes == [1])
        view.accessibilityIncrement()
        view.handlePan(state: .began, translationX: -150, velocityX: -900)
        #expect(changes == [1])
        view.reset()
        let replacement = IMessageChatMediaGroupAttachment(id: fixture.group.id, items: Array(fixture.group.items.prefix(2)))
        view.configure(messageID: 99, direction: .incoming, group: replacement, frontIndex: 0, strings: mediaStrings)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        #expect(view.frontMediaIndex == 0)
        #expect(changes == [1])
        #expect(view.visibleCardCount == 2)
        #expect(view.visibleCardTransform(forMediaIndex: 0) == .identity)
    }

    /// 旋转卡片外接矩形的空角不应误选媒体，交互阶段不解析预览目标。
    @Test func stackTapUsesTransformedCardCoordinates() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        let view = makeStackView(fixture.group)
        let center = try #require(view.visibleCardCenter(forMediaIndex: 0))
        #expect(view.mediaIndex(at: center) == 0)
        let back = try #require(view.visibleCardFrame(forMediaIndex: 4))
        let transform = try #require(view.visibleCardTransform(forMediaIndex: 4))
        let enclosingRect = CGRect(x: -back.width / 2, y: -back.height / 2, width: back.width, height: back.height)
            .applying(transform).offsetBy(dx: back.midX, dy: back.midY)
        let emptyCorner = CGPoint(x: enclosingRect.maxX - 0.1, y: enclosingRect.maxY - 0.1)
        #expect(view.mediaIndex(at: emptyCorner) == nil)
        view.handlePan(state: .began, translationX: 0, velocityX: -100)
        #expect(view.mediaIndex(at: center) == nil)
        view.handlePan(state: .ended, translationX: -140, velocityX: 0, animated: false)
        #expect(view.mediaIndex(at: try #require(view.visibleCardCenter(forMediaIndex: 1))) == 1)
    }

    /// 提交回调可以同步复用视图；旧路径不得覆盖新组或继续旧动画。
    @Test func stackCommitCanSynchronouslyReconfigureTheView() throws {
        let fixture = try MediaFixture(itemCount: 5)
        defer { fixture.remove() }
        let view = makeStackView(fixture.group)
        var changeCount = 0
        view.frontIndexDidChange = { _, _ in
            changeCount += 1
            view.configure(messageID: 99, direction: .incoming, group: fixture.group, frontIndex: 4, strings: mediaStrings)
        }
        defer { view.frontIndexDidChange = nil }
        view.handlePan(state: .began, translationX: 0, velocityX: -100)
        view.handlePan(state: .ended, translationX: -150, velocityX: 0, animated: false)
        view.layoutIfNeeded()
        #expect(view.frontMediaIndex == 4)
        #expect(changeCount == 1)
        #expect(view.visibleCardZPosition(forMediaIndex: 4) == 30)
    }

    /// 在真实窗口捕获五个交互阶段，检查整张视频卡片和下一条消息的稳定位置。
    @Test func stackInteractionRendersReferenceStagesInRealWindow() async throws {
        let fixture = try MediaFixture(itemCount: 5, videoIndices: [0])
        defer { fixture.remove() }
        let colors: [UIColor] = [.systemOrange, .systemBlue, .systemGreen, .systemPurple, .systemPink]
        for (index, item) in fixture.group.items.enumerated() {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 432, height: 600)).image { context in
                colors[index].setFill()
                context.fill(CGRect(x: 0, y: 0, width: 432, height: 600))
                ("\(index + 1)" as NSString).draw(at: CGPoint(x: 35, y: 35), withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 100), .foregroundColor: UIColor.white
                ])
            }
            try image.pngData()?.write(to: item.thumbnailFileURL)
        }
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIViewController()
        window.rootViewController = host
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        canvas.backgroundColor = .systemBackground
        host.view.addSubview(canvas)
        let cell = IMessageChatMediaBubbleCell(frame: .zero)
        canvas.addSubview(cell)
        cell.configure(.init(id: 8, direction: .outgoing, attachment: .mediaGroup(fixture.group), deliveryText: "Delivered"),
                       group: fixture.group, frontIndex: 0, strings: mediaStrings)
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: 402, height: 52)
        cell.frame = CGRect(origin: CGPoint(x: 0, y: 170), size: cell.preferredLayoutAttributesFitting(attributes).size)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let next = UILabel(frame: CGRect(x: 24, y: cell.frame.maxY + 30, width: 330, height: 50))
        next.text = "下一条消息保持原位"
        canvas.addSubview(next)
        let nextFrame = next.frame
        let cellSize = cell.frame.size
        let view = cell.mediaView
        try await Task.sleep(for: .milliseconds(200))
        func capture(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: canvas.bounds).image { _ in
                canvas.drawHierarchy(in: canvas.bounds, afterScreenUpdates: true)
            }
            Attachment.record(image, named: "media-stack-\(name).png")
            #expect(cell.frame.size == cellSize)
            #expect(next.frame == nextFrame)
        }
        capture("01-resting")
        view.handlePan(state: .began, translationX: 0, velocityX: -100)
        view.handlePan(state: .changed, translationX: -110, velocityX: 0)
        capture("02-dragging")
        view.handlePan(state: .changed, translationX: -140, velocityX: 0)
        capture("03-reordered")
        view.handlePan(state: .changed, translationX: -90, velocityX: 0)
        capture("04-returned")
        view.handlePan(state: .ended, translationX: -140, velocityX: 0, animated: false)
        capture("05-committed")
        #expect(view.frontMediaIndex == 1)
    }

    /// 创建使用真实布局宽度的媒体堆叠，供交互回归复用。
    private func makeStackView(
        _ group: IMessageChatMediaGroupAttachment,
        frontIndex: Int = 0,
        direction: IMessageChatDirection = .outgoing
    ) -> IMessageChatMediaMessageView {
        let view = IMessageChatMediaMessageView()
        view.configure(messageID: 8, direction: direction, group: group, frontIndex: frontIndex, strings: mediaStrings)
        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutIfNeeded()
        return view
    }

    @Test func stackStateSurvivesReuseAndPrunesDeletedMessages() {
        let store = IMessageChatMediaStackStateStore()
        #expect(store.index(for: 10, itemCount: 5) == 0)
        store.setIndex(3, for: 10, itemCount: 5)
        store.setIndex(1, for: 11, itemCount: 2)
        #expect(store.index(for: 10, itemCount: 5) == 3)
        store.retainMessages([11])
        #expect(store.index(for: 10, itemCount: 5) == 0)
        #expect(store.index(for: 11, itemCount: 2) == 1)
    }

    @Test func mediaDraftFilesCommitOrDiscardAsOneAttachment() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("IMessageChatMediaStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = IMessageChatPageAttachmentStore(parentDirectory: parent)
        let fixture = try MediaFixture(itemCount: 2, parentDirectory: store.directoryURL)
        let attachment = IMessageChatAttachment.mediaGroup(fixture.group)
        store.registerDraft(attachment)
        #expect(store.commitDraft(id: fixture.group.id))
        #expect(fixture.group.localFileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        store.removeAll()
        #expect(fixture.group.localFileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func outgoingMediaGroupFitsInsideIPhone16ProMessageRow() throws {
        let fixture = try MediaFixture(itemCount: 3)
        defer { fixture.remove() }
        let cell = IMessageChatMediaBubbleCell(frame: .zero)
        cell.configure(
            IMessageChatMessagePresentation(
                id: 3,
                direction: .outgoing,
                attachment: .mediaGroup(fixture.group),
                deliveryText: "Delivered"
            ),
            group: fixture.group,
            frontIndex: 0,
            strings: mediaStrings
        )
        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: 0, section: 0)
        )
        attributes.size = CGSize(width: 402, height: 52)
        let fitted = cell.preferredLayoutAttributesFitting(attributes)
        cell.frame = CGRect(origin: .zero, size: fitted.size)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()

        let frame = cell.mediaView.convert(cell.mediaView.bounds, to: cell)
        #expect(frame.width == 232)
        #expect(frame.height == 344)
        #expect(frame.minX >= 12)
        #expect(frame.maxX <= 390)
        #expect(abs(frame.maxX - 390) < 1)
        #expect(fitted.size.height >= frame.height + 20)
        #expect(fitted.size.height <= frame.height + 40)
        #expect(frame.maxY < fitted.size.height)
    }

    @Test func bottomObstructionExcludesTheContainerSafeArea() {
        #expect(
            IMessageChatBottomObstructionCoordinator.contentObstruction(
                containerMaxY: 874,
                obstructionMinY: 540,
                safeAreaBottom: 34
            ) == 300
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.contentObstruction(
                containerMaxY: 874,
                obstructionMinY: 874,
                safeAreaBottom: 34
            ) == 0
        )
    }

    @Test func photoSheetFollowsBothDirectionsAndStopsAtLatestKeyboardHeight() {
        for (pickerHeight, limit, expected): (CGFloat, CGFloat, CGFloat) in [
            (0, 300, 0), (120, 300, 120), (300, 300, 300),
            (760, 300, 300), (180, 300, 180), (0, 300, 0),
            (760, 336, 336), (300, 200, 200), (-20, 300, 0),
        ] {
            #expect(
                IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                    keyboardHeight: 760,
                    pickerHeight: pickerHeight,
                    maximumPickerHeight: limit
                ) == expected
            )
        }
    }

    @Test func photoSheetGeometryTracksItsContainerAndIgnoresKeyboardHide() throws {
        let window = try makeObstructionTestWindow()
        let hostView = UIView(frame: window.bounds)
        let sheetContainer = UIView(frame: window.bounds)
        let picker = UIViewController()
        picker.view = UIView(frame: window.bounds)
        window.addSubview(hostView)
        window.addSubview(sheetContainer)
        sheetContainer.addSubview(picker.view)
        let coordinator = IMessageChatBottomObstructionCoordinator(hostView: hostView)
        defer { coordinator.stop() }
        coordinator.trackPicker(picker)
        #expect(!coordinator.updateKeyboard(.hidden))

        // 模拟系统通过父容器移动 Sheet，确保读取的是宿主坐标中的实际位置。
        for height: CGFloat in [0, 120, 300, 650, 180, 0] {
            sheetContainer.transform = CGAffineTransform(
                translationX: 0,
                y: hostView.bounds.maxY - hostView.safeAreaInsets.bottom - height
            )
            coordinator.refreshGeometry()
            #expect(abs(coordinator.currentHeight - min(height, 300)) < 0.5)
        }
        coordinator.stopTrackingPicker()
        #expect(coordinator.currentHeight == 0)
    }

    @Test func latestFullKeyboardFrameUpdatesPhotoCapWithoutCachingDismissal() throws {
        let window = try makeObstructionTestWindow()
        let hostView = UIView(frame: window.bounds)
        window.addSubview(hostView)
        let coordinator = IMessageChatBottomObstructionCoordinator(hostView: hostView)
        defer { coordinator.stop() }

        func update(height: CGFloat, downwardOffset: CGFloat = 0) throws {
            let frame = CGRect(x: 0, y: 844 - height + downwardOffset, width: 390, height: height)
            let notification = Notification(
                name: UIResponder.keyboardWillChangeFrameNotification,
                object: window.screen,
                userInfo: [
                    UIResponder.keyboardFrameEndUserInfoKey:
                        window.convert(frame, to: window.screen.coordinateSpace),
                    UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
                ]
            )
            coordinator.updateKeyboard(try #require(
                QuickLayoutKeyboardContext(notification: notification)
            ))
        }
        try update(height: 334)
        #expect(coordinator.storedKeyboardContentHeight == 334 - hostView.safeAreaInsets.bottom)
        try update(height: 370)
        #expect(coordinator.storedKeyboardContentHeight == 370 - hostView.safeAreaInsets.bottom)
        try update(height: 240)
        #expect(coordinator.storedKeyboardContentHeight == 240 - hostView.safeAreaInsets.bottom)
        try update(height: 240, downwardOffset: 100)
        coordinator.updateKeyboard(.hidden)
        #expect(coordinator.storedKeyboardContentHeight == 240 - hostView.safeAreaInsets.bottom)

        // 复现键盘进入照片面板后，附件菜单关闭又报告较小键盘高度的顺序。
        let picker = UIViewController()
        coordinator.trackPicker(picker)
        try update(height: 210)
        #expect(coordinator.storedKeyboardContentHeight == 240 - hostView.safeAreaInsets.bottom)
        coordinator.updateKeyboard(.hidden)
        #expect(coordinator.storedKeyboardContentHeight == 240 - hostView.safeAreaInsets.bottom)

        // 用户切回键盘后，新高度重新成为后续照片面板的上限。
        coordinator.beginKeyboardHandoff()
        try update(height: 370)
        #expect(coordinator.storedKeyboardContentHeight == 370 - hostView.safeAreaInsets.bottom)
    }

    @Test func keyboardToPhotoPresentationHoldsHeightThenTracksCalibratedGeometry() throws {
        let window = try makeObstructionTestWindow()
        let host = UIView(frame: window.bounds)
        window.addSubview(host)
        let coordinator = IMessageChatBottomObstructionCoordinator(hostView: host)
        defer { coordinator.stop() }
        let keyboardFrame = CGRect(x: 0, y: 510, width: 390, height: 334)
        let notification = Notification(
            name: UIResponder.keyboardWillShowNotification,
            object: window.screen,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey:
                    window.convert(keyboardFrame, to: window.screen.coordinateSpace),
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
            ]
        )
        coordinator.updateKeyboard(try #require(QuickLayoutKeyboardContext(notification: notification)))
        let keyboardHeight = coordinator.storedKeyboardContentHeight
        let picker = UIViewController()
        picker.view = UIView(frame: window.bounds)
        window.addSubview(picker.view)

        func setPickerHeight(_ height: CGFloat) {
            picker.view.frame.origin.y = host.bounds.maxY - host.safeAreaInsets.bottom - height
            coordinator.refreshGeometry()
        }
        setPickerHeight(-34)
        coordinator.trackPicker(picker)
        coordinator.updateKeyboard(.hidden)
        // 面板入场时即使逐帧经过屏幕外和中间高度，输入栏也始终保持键盘等高。
        for height in [-34, 60, 180, keyboardHeight - 6] {
            setPickerHeight(height)
            #expect(abs(coordinator.currentHeight - keyboardHeight) < 0.5)
        }
        // 完成回调不能产生小幅下移；后续拖动仍生效，且受同一键盘高度上限约束。
        coordinator.finishPickerPresentation(picker)
        #expect(abs(coordinator.currentHeight - keyboardHeight) < 0.5)
        setPickerHeight(600)
        #expect(abs(coordinator.currentHeight - keyboardHeight) < 0.5)
        setPickerHeight(180)
        #expect(abs(coordinator.currentHeight - 186) < 0.5)
        coordinator.finishPickerPresentation(UIViewController())
        #expect(abs(coordinator.currentHeight - 186) < 0.5)
        // 关闭时校准量也必须随面板完全离屏归零，不能残留到关闭完成才突变。
        setPickerHeight(-34)
        #expect(coordinator.currentHeight == 0)
        coordinator.stopTrackingPicker()
        #expect(coordinator.currentHeight == 0)
    }

    /// 复用测试宿主的场景创建隐藏窗口，独立验证几何且不抢占页面焦点。
    private func makeObstructionTestWindow() throws -> UIWindow {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        return window
    }

    @Test func photoSheetOwnsComposerUntilKeyboardHandoffBegins() {
        #expect(
            !IMessageChatBottomObstructionCoordinator.shouldApplyKeyboardLayout(
                isPickerPresented: true,
                isAwaitingKeyboard: false
            )
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.shouldApplyKeyboardLayout(
                isPickerPresented: true,
                isAwaitingKeyboard: true
            )
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.shouldApplyKeyboardLayout(
                isPickerPresented: false,
                isAwaitingKeyboard: false
            )
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.shouldTrackGeometry(
                isPickerPresented: true,
                isAwaitingKeyboard: false,
                keyboardIsVisible: false
            )
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.shouldTrackGeometry(
                isPickerPresented: true,
                isAwaitingKeyboard: true,
                keyboardIsVisible: true
            )
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.shouldTrackGeometry(
                isPickerPresented: false,
                isAwaitingKeyboard: false,
                keyboardIsVisible: true
            )
        )
        #expect(
            !IMessageChatBottomObstructionCoordinator.shouldTrackGeometry(
                isPickerPresented: false,
                isAwaitingKeyboard: false,
                keyboardIsVisible: false
            )
        )
    }

    @Test func keyboardAndPhotoHandoffsKeepOneStableObstructionHeight() {
        #expect(
            IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                keyboardHeight: 96,
                pickerHeight: 300,
                maximumPickerHeight: 300
            ) == 300
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                keyboardHeight: 24,
                pickerHeight: 300,
                maximumPickerHeight: 300
            ) == 300
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                keyboardHeight: 18,
                pickerHeight: nil,
                maximumPickerHeight: 300,
                isAwaitingKeyboard: true,
                keyboardHandoffStartHeight: 300,
                keyboardHandoffTargetHeight: nil
            ) == 300
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                keyboardHeight: 84,
                pickerHeight: 300,
                maximumPickerHeight: 300,
                isAwaitingKeyboard: true,
                keyboardHandoffStartHeight: 300,
                keyboardHandoffTargetHeight: 336
            ) == 336
        )
        #expect(
            IMessageChatBottomObstructionCoordinator.resolvedObstruction(
                keyboardHeight: 336,
                pickerHeight: nil,
                maximumPickerHeight: 300
            ) == 336
        )
    }

    @Test func mediaGroupTitleMirrorsWithSemanticOuterEdge() throws {
        let fixture = try MediaFixture(itemCount: 3)
        defer { fixture.remove() }
        let view = IMessageChatMediaMessageView()
        view.configure(
            messageID: 3,
            direction: .outgoing,
            group: fixture.group,
            frontIndex: 0,
            strings: mediaStrings
        )
        view.frame = CGRect(origin: .zero, size: view.intrinsicContentSize)
        view.layoutIfNeeded()
        #expect(abs(view.itemCountLabel.frame.maxX - view.bounds.maxX) < 1)

        view.semanticContentAttribute = .forceRightToLeft
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(abs(view.itemCountLabel.frame.minX - 22) < 1)
    }

    private func makeViewModel() -> IMessageChatViewModel {
        IMessageChatViewModel(
            localizer: Localizer { key, _ in "localized.\(key)" },
            clock: { Date(timeIntervalSince1970: 1_800_000_000) },
            sleeper: { duration in try await Task.sleep(for: duration) }
        )
    }

    private func messagePresentations(
        in state: IMessageChatViewModel.State
    ) -> [IMessageChatMessagePresentation] {
        state.timeline.compactMap { item in
            guard case .message(let message) = item.content else { return nil }
            return message
        }
    }

    private var mediaStrings: IMessageChatMediaStrings {
        IMessageChatMediaStrings(
            photo: "Photos",
            itemsFormat: "%d items",
            image: "Image",
            animatedImage: "Animated image",
            video: "Video",
            videoDurationFormat: "Video, duration %@",
            importing: "Importing",
            remove: "Remove",
            play: "Play",
            openPreview: "Open preview",
            close: "Close",
            firstItem: "First",
            lastItem: "Last",
            positionFormat: "%d of %d"
        )
    }
}

private final class MediaFixture {
    let directory: URL
    let group: IMessageChatMediaGroupAttachment

    init(
        itemCount: Int,
        videoIndices: Set<Int> = [],
        pixelSizes: [CGSize]? = nil,
        animatedIndices: Set<Int> = [],
        parentDirectory: URL? = nil
    ) throws {
        directory = parentDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("IMessageChatMediaFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var items: [IMessageChatMediaItem] = []
        for index in 0..<itemCount {
            let original = directory.appendingPathComponent("original-\(index).dat")
            let thumbnail = directory.appendingPathComponent("thumbnail-\(index).jpg")
            try Data([UInt8(index % 255)]).write(to: original)
            try Data([UInt8((index + 1) % 255)]).write(to: thumbnail)
            items.append(
                IMessageChatMediaItem(
                    assetIdentifier: "asset-\(index)",
                    originalFileURL: original,
                    thumbnailFileURL: thumbnail,
                    pixelSize: pixelSizes?[safe: index]
                        ?? CGSize(width: 1200 + index, height: 1600),
                    kind: videoIndices.contains(index)
                        ? .video(duration: TimeInterval(index + 1))
                        : .image,
                    isAnimatedImage: animatedIndices.contains(index)
                )
            )
        }
        group = IMessageChatMediaGroupAttachment(items: items)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
