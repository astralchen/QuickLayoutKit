import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func composerGrowsToFiveLinesAndMirrorsDirection() {
        guard #available(iOS 26.0, *) else { return }
        let composer = ComposerView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 60)
        )
        composer.configure(strings: ConversationPreviewData.composerStrings)
        composer.layoutIfNeeded()

        #expect(!composer.sendButton.isUserInteractionEnabled)
        #expect(!composer.placeholderLabel.isHidden)
        #expect(composer.attachmentButton.menu?.children.count == 4)
        #expect(
            composer.attachmentButton.cornerConfiguration == .capsule()
        )
        #expect(
            composer.attachmentButton.configuration?.cornerStyle == .capsule
        )
        #expect(composer.sendButton.cornerConfiguration == .capsule())
        #expect(composer.audioSendButton.cornerConfiguration == .capsule())
        #expect(
            composer.attachmentButton.menu?.children.map(\.title)
                == ["Photos", "Audio", "文件", "链接"]
        )
        let singleLineHeight = composer.intrinsicContentSize.height

        composer.textView.text = "Send this message"
        composer.textViewDidChange(composer.textView)
        composer.frame.size.height = composer.intrinsicContentSize.height
        composer.layoutIfNeeded()
        let sendFrame = composer.sendButton.convert(
            composer.sendButton.bounds,
            to: composer
        )
        #expect(abs(sendFrame.width - 38) < 0.5)
        #expect(abs(sendFrame.height - 28) < 0.5)
        #expect(abs(sendFrame.maxX - 368) < 0.5)
        #expect(abs(sendFrame.maxY - 44) < 0.5)
        #expect(sendFrame.width > sendFrame.height)
        let expandedHitPoint = composer.sendButton.convert(
            CGPoint(x: composer.sendButton.bounds.maxX + 2, y: composer.sendButton.bounds.midY),
            to: composer
        )
        #expect(composer.hitTest(expandedHitPoint, with: nil) === composer.sendButton)

        composer.textView.text = "one\ntwo\nthree\nfour\nfive\nsix\nseven"
        composer.textViewDidChange(composer.textView)
        composer.frame.size.height = composer.intrinsicContentSize.height
        composer.layoutIfNeeded()

        let maximumExpectedHeight = ceil(
            (composer.textView.font ?? .preferredFont(forTextStyle: .body))
                .lineHeight * 5
        ) + composer.textView.textContainerInset.top
            + composer.textView.textContainerInset.bottom + 16
        #expect(composer.intrinsicContentSize.height > singleLineHeight)
        #expect(
            composer.intrinsicContentSize.height <= maximumExpectedHeight + 1
        )
        #expect(composer.textView.isScrollEnabled)
        #expect(composer.sendButton.isEnabled)
        let multilineSendFrame = composer.sendButton.convert(composer.sendButton.bounds, to: composer.inputGlassView)
        #expect(abs(composer.inputGlassView.bounds.maxY - multilineSendFrame.maxY
            - ComposerView.Metrics.textSendBottomPadding) < 0.5)

        var sentText: String?
        composer.actionRequested = { action in
            guard case .sendText(let text) = action else { return false }
            sentText = text
            return true
        }
        composer.sendButton.sendActions(for: .touchUpInside)
        #expect(sentText == "one\ntwo\nthree\nfour\nfive\nsix\nseven")
        #expect(composer.textView.text.isEmpty)
        #expect(!composer.sendButton.isUserInteractionEnabled)
        #expect(!composer.placeholderLabel.isHidden)

        composer.applyLayoutDirection(.rightToLeft)
        #expect(composer.semanticContentAttribute == .forceRightToLeft)
        #expect(composer.textView.semanticContentAttribute == .forceRightToLeft)
        #expect(composer.textView.textAlignment == .right)
        composer.applyLayoutDirection(.leftToRight)
        #expect(composer.semanticContentAttribute == .forceLeftToRight)
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func composerPreservesDraftAcrossAudioStates() {
        guard #available(iOS 26.0, *) else { return }
        let composer = ComposerView(
            frame: CGRect(x: 0, y: 0, width: 390, height: 60)
        )
        composer.configure(strings: ConversationPreviewData.composerStrings)
        composer.textView.text = "draft text"
        composer.textViewDidChange(composer.textView)
        let attachment = AudioAttachment(
            fileURL: URL(fileURLWithPath: "/tmp/preview.m4a"),
            duration: 4,
            waveform: [0.2, 0.8, 0.4]
        )

        composer.applyState(
            .recording(elapsed: 2, waveform: [0.3, 0.7])
        )
        composer.frame.size.height = composer.intrinsicContentSize.height
        composer.layoutIfNeeded()
        let recordingWaveformFrame = composer.recordingWaveformView.convert(
            composer.recordingWaveformView.bounds,
            to: composer
        )
        let recordingStopFrame = composer.recordingStopButton.convert(
            composer.recordingStopButton.bounds,
            to: composer
        )
        #expect(composer.textView.text == "draft text")
        #expect(composer.textView.superview != nil)
        #expect(composer.intrinsicContentSize.height == 80)
        #expect(abs(recordingWaveformFrame.minX - 44) < 0.5)
        #expect(abs(recordingWaveformFrame.minY - 25) < 0.5)
        #expect(abs(recordingWaveformFrame.maxY - 55) < 0.5)
        #expect(composer.recordingWaveformView.minimumBarHeight == 2)
        #expect(composer.recordingWaveformView.maximumBarHeight == 12)
        #expect(composer.recordingWaveformView.barWidth == 2)
        #expect(composer.recordingWaveformView.barSpacing == 2)
        #expect(composer.recordingWaveformView.fadedLeadingFraction == 0.28)
        #expect(abs(recordingStopFrame.maxX - 360) < 0.5)
        #expect(abs(recordingStopFrame.minY - 22) < 0.5)
        #expect(abs(recordingStopFrame.height - 36) < 0.5)
        #expect(abs(recordingStopFrame.midY - 40) < 0.5)
        #expect(
            composer.recordingStopButton.point(
                inside: CGPoint(x: -3, y: 18),
                with: nil
            )
        )

        var repeatedHeightChangeCount = 0
        composer.heightDidChange = { _ in
            repeatedHeightChangeCount += 1
        }
        composer.applyState(
            .recording(elapsed: 59, waveform: [0.1, 0.5, 0.9])
        )
        composer.layoutIfNeeded()
        let repeatedWaveformFrame = composer.recordingWaveformView.convert(
            composer.recordingWaveformView.bounds,
            to: composer
        )
        let repeatedStopFrame = composer.recordingStopButton.convert(
            composer.recordingStopButton.bounds,
            to: composer
        )
        #expect(repeatedHeightChangeCount == 0)
        #expect(repeatedWaveformFrame == recordingWaveformFrame)
        #expect(repeatedStopFrame == recordingStopFrame)

        composer.applyState(
            .recording(elapsed: 60, waveform: [0.9, 0.5, 0.1])
        )
        composer.layoutIfNeeded()
        #expect(repeatedHeightChangeCount == 0)
        #expect(
            composer.recordingWaveformView.convert(
                composer.recordingWaveformView.bounds,
                to: composer
            ) == recordingWaveformFrame
        )
        #expect(
            composer.recordingStopButton.convert(
                composer.recordingStopButton.bounds,
                to: composer
            ) == recordingStopFrame
        )

        composer.applyState(
            .audioPreview(
                attachment: attachment,
                isPlaying: false,
                progress: 0
            )
        )
        composer.frame.size.height = composer.intrinsicContentSize.height
        composer.layoutIfNeeded()
        #expect(composer.textView.text == "draft text")
        #expect(composer.textView.superview != nil)
        #expect(composer.intrinsicContentSize.height == 80)
        let audioSendFrame = composer.audioSendButton.convert(
            composer.audioSendButton.bounds,
            to: composer
        )
        let audioPlayFrame = composer.audioPlayButton.convert(
            composer.audioPlayButton.bounds,
            to: composer
        )
        #expect(abs(audioSendFrame.width - 38) < 0.5)
        #expect(abs(audioSendFrame.height - 28) < 0.5)
        #expect(abs(audioSendFrame.maxX - 360) < 0.5)
        #expect(abs(audioSendFrame.minY - 26) < 0.5)
        #expect(audioSendFrame.width > audioSendFrame.height)
        #expect(abs(audioPlayFrame.minX - 82) < 0.5)
        #expect(abs(audioPlayFrame.minY - 22) < 0.5)
        #expect(abs(audioPlayFrame.maxY - 58) < 0.5)
        #expect(composer.previewWaveformView.minimumBarHeight == 2)
        #expect(composer.previewWaveformView.maximumBarHeight == 12)
        #expect(composer.previewWaveformView.barWidth == 2)
        #expect(composer.previewWaveformView.barSpacing == 2)
        #expect(composer.previewWaveformView.fadedLeadingFraction == 0)
        #expect(
            composer.audioSendButton.point(
                inside: CGPoint(x: 19, y: -7),
                with: nil
            )
        )

        composer.applyState(.idle)
        #expect(composer.textView.text == "draft text")
        #expect(composer.sendButton.isEnabled)
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func rowsPinBubblesStatusAndTypingToSemanticEdges() throws {
        guard #available(iOS 26.0, *) else { return }
        let cellWidth: CGFloat = 390
        let horizontalInset: CGFloat = 12

        let incomingCell = BubbleCell(frame: .zero)
        incomingCell.configure(
            MessagePresentation(
                id: 1,
                direction: .incoming,
                text: "Short reply",
                deliveryText: nil
            )
        )
        layoutCell(incomingCell, width: cellWidth)
        let incomingFrame = incomingCell.bubbleView.convert(
            incomingCell.bubbleView.bounds,
            to: incomingCell
        )
        #expect(abs(incomingFrame.minX - horizontalInset) < 1)
        #expect(incomingFrame.width <= cellWidth * 0.75 + 1)

        let outgoingCell = BubbleCell(frame: .zero)
        outgoingCell.configure(
            MessagePresentation(
                id: 2,
                direction: .outgoing,
                text: "Short message",
                deliveryText: "Read"
            )
        )
        layoutCell(outgoingCell, width: cellWidth)
        let outgoingFrame = outgoingCell.bubbleView.convert(
            outgoingCell.bubbleView.bounds,
            to: outgoingCell
        )
        let deliveryFrame = outgoingCell.deliveryLabel.convert(
            outgoingCell.deliveryLabel.bounds,
            to: outgoingCell
        )
        #expect(
            abs(outgoingFrame.maxX - (cellWidth - horizontalInset)) < 1
        )
        #expect(abs(deliveryFrame.maxX - outgoingFrame.maxX) < 1)

        outgoingCell.semanticContentAttribute = .forceRightToLeft
        outgoingCell.setNeedsQuickLayout()
        outgoingCell.layoutIfNeeded()
        let rtlOutgoingFrame = outgoingCell.bubbleView.convert(
            outgoingCell.bubbleView.bounds,
            to: outgoingCell
        )
        #expect(abs(rtlOutgoingFrame.minX - horizontalInset) < 1)

        let typingCell = TypingCell(frame: .zero)
        typingCell.configure(accessibilityLabel: "Typing")
        layoutCell(typingCell, width: cellWidth)
        let typingFrame = typingCell.typingView.convert(
            typingCell.typingView.bounds,
            to: typingCell
        )
        #expect(abs(typingFrame.minX - horizontalInset) < 1)
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func audioRowsPinToSemanticEdgesAndUpdatePlayback() {
        guard #available(iOS 26.0, *) else { return }
        let attachment = AudioAttachment(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            fileURL: URL(fileURLWithPath: "/tmp/message.m4a"),
            duration: 8,
            waveform: [0.2, 0.7, 0.4, 0.9]
        )
        let cellWidth: CGFloat = 390
        let horizontalInset: CGFloat = 12
        let cell = AudioBubbleCell(frame: .zero)
        cell.configure(
            MessagePresentation(
                id: 7,
                direction: .outgoing,
                attachment: .audio(attachment),
                deliveryText: "Read"
            ),
            playback: .idle,
            playAccessibilityLabel: "Play",
            pauseAccessibilityLabel: "Pause"
        )
        layoutCell(cell, width: cellWidth)

        let ltrFrame = cell.bubbleView.convert(
            cell.bubbleView.bounds,
            to: cell
        )
        let ltrDeliveryFrame = cell.deliveryLabel.convert(
            cell.deliveryLabel.bounds,
            to: cell
        )
        #expect(abs(ltrFrame.maxX - (cellWidth - horizontalInset)) < 1)
        #expect(abs(ltrDeliveryFrame.maxX - ltrFrame.maxX) < 1)
        #expect(cell.bubbleView.waveformView.progress == 0)

        cell.updatePlayback(
            PlaybackState(
                messageID: 7,
                attachmentID: attachment.id,
                isPlaying: true,
                progress: 0.5
            ),
            playAccessibilityLabel: "Play",
            pauseAccessibilityLabel: "Pause"
        )
        #expect(cell.bubbleView.waveformView.progress == 0.5)
        #expect(cell.bubbleView.playButton.accessibilityLabel == "Pause")

        cell.semanticContentAttribute = .forceRightToLeft
        cell.setNeedsQuickLayout()
        cell.layoutIfNeeded()
        let rtlFrame = cell.bubbleView.convert(
            cell.bubbleView.bounds,
            to: cell
        )
        #expect(abs(rtlFrame.minX - horizontalInset) < 1)
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func waveformDoesNotHighlightBeforePlaybackStarts() {
        guard #available(iOS 26.0, *) else { return }
        let sampleCount = 36

        for index in 0 ..< sampleCount {
            #expect(
                !WaveformView.isSamplePlayed(
                    at: index,
                    count: sampleCount,
                    progress: 0
                )
            )
        }
        #expect(
            !WaveformView.isSamplePlayed(
                at: 0,
                count: sampleCount,
                progress: 0.01
            )
        )
        #expect(
            WaveformView.isSamplePlayed(
                at: 0,
                count: sampleCount,
                progress: 0.02
            )
        )
        #expect(
            WaveformView.isSamplePlayed(
                at: sampleCount - 1,
                count: sampleCount,
                progress: 1
            )
        )
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func conversationAlignsOutgoingTextAndAudioTrailingEdges()
        async throws {
        guard #available(iOS 26.0, *) else { return }
        let attachment = AudioAttachment(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            fileURL: URL(fileURLWithPath: "/tmp/alignment.m4a"),
            duration: 8,
            waveform: Array(repeating: 0.4, count: 36)
        )
        let textMessage = MessagePresentation(
            id: 1,
            direction: .outgoing,
            text: "Aligned text",
            deliveryText: nil
        )
        let audioMessage = MessagePresentation(
            id: 2,
            direction: .outgoing,
            attachment: .audio(attachment),
            deliveryText: "Read"
        )
        let state = ChatViewModel.State(
            timeline: [
                TimelineItem(
                    id: .message(textMessage.id),
                    content: .message(textMessage)
                ),
                TimelineItem(
                    id: .message(audioMessage.id),
                    content: .message(audioMessage)
                ),
            ],
            isTyping: false
        )
        let controller = UIViewController()
        let conversation = ConversationView(frame: .zero)
        conversation.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(conversation)
        NSLayoutConstraint.activate([
            conversation.leadingAnchor.constraint(
                equalTo: controller.view.leadingAnchor
            ),
            conversation.trailingAnchor.constraint(
                equalTo: controller.view.trailingAnchor
            ),
            conversation.topAnchor.constraint(
                equalTo: controller.view.topAnchor
            ),
            conversation.bottomAnchor.constraint(
                equalTo: controller.view.bottomAnchor
            ),
        ])
        let window = try makeVisibleTestWindow(
            rootViewController: controller,
            size: CGSize(width: 390, height: 300)
        )
        defer { window.isHidden = true }

        conversation.render(state, reason: .initial)
        for _ in 0..<20 {
            if conversation.collectionView.numberOfSections > 0,
               conversation.collectionView.numberOfItems(inSection: 0) >= 2 {
                break
            }
            await Task.yield()
        }
        controller.view.layoutIfNeeded()
        conversation.collectionView.layoutIfNeeded()

        let textCell = try #require(
            conversation.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? BubbleCell
        )
        let audioCell = try #require(
            conversation.collectionView.cellForItem(
                at: IndexPath(item: 1, section: 0)
            ) as? AudioBubbleCell
        )
        let textFrame = textCell.bubbleView.convert(
            textCell.bubbleView.bounds,
            to: conversation
        )
        let audioFrame = audioCell.bubbleView.convert(
            audioCell.bubbleView.bounds,
            to: conversation
        )
        let deliveryFrame = audioCell.deliveryLabel.convert(
            audioCell.deliveryLabel.bounds,
            to: conversation
        )
        #expect(abs(textFrame.maxX - audioFrame.maxX) < 1)
        #expect(abs(audioFrame.maxX - deliveryFrame.maxX) < 1)
        #expect(abs(audioFrame.maxX - 378) < 1)
    }

    @Test(.enabled(if: ChatTestAvailability.isSupported)) func contactTitleReportsCompleteNavigationSize() {
        guard #available(iOS 26.0, *) else { return }
        let titleView = ContactTitleView(frame: .zero)
        titleView.configure(subtitle: "iMessage")
        let size = titleView.intrinsicContentSize
        titleView.frame.size = size
        titleView.layoutIfNeeded()

        #expect(size.width > 80)
        #expect(size.height >= 30)
        #expect(titleView.avatarView.bounds.width == 30)
        #expect(titleView.nameLabel.bounds.width > 0)
        #expect(titleView.subtitleLabel.bounds.width > 0)
    }
}

@available(iOS 26.0, *)
@MainActor
private func layoutCell(
    _ cell: QuickLayoutCollectionViewCell,
    width: CGFloat
) {
    let attributes = UICollectionViewLayoutAttributes(
        forCellWith: IndexPath(item: 0, section: 0)
    )
    attributes.size = CGSize(width: width, height: 52)
    let fittedAttributes = cell.preferredLayoutAttributesFitting(attributes)
    cell.frame = CGRect(origin: .zero, size: fittedAttributes.size)
    cell.setNeedsLayout()
    cell.layoutIfNeeded()
}
