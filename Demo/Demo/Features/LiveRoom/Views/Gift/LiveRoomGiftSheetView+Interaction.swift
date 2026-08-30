//
//  LiveRoomGiftSheetView+Interaction.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension LiveRoomGiftSheetView {

    func selectRecipient(_ recipient: LiveRoomSeat) {
        guard
            let userID = recipient.userID,
            viewModel.toggleRecipient(userID: userID)
        else { return }
        updateButtons()
        recipientDidSelect?(selectedRecipients)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func toggleAllRecipients() {
        viewModel.toggleAllRecipients()
        updateButtons()
        recipientDidSelect?(selectedRecipients)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectGift(_ gift: LiveRoomGift) {
        guard viewModel.selectGift(id: gift.id) else { return }
        updateButtons(reloadsGifts: true)
        giftDidSelect?(gift)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @discardableResult
    func setSelectedGiftQuantity(_ quantity: Int) -> Bool {
        guard viewModel.selectGiftQuantity(quantity) else { return false }
        updateButtons()
        return true
    }

    func selectGiftQuantity(_ quantity: Int) {
        guard setSelectedGiftQuantity(quantity) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectCategory(_ category: LiveRoomGiftCategory) {
        guard selectedCategory != category else { return }
        // ViewModel 负责维持“当前礼物必须属于当前栏目”的状态不变量。
        if let selectedGift = viewModel.selectCategory(category) {
            giftDidSelect?(selectedGift)
        }
        giftCollectionView.setContentOffset(
            CGPoint(x: -giftCollectionView.adjustedContentInset.left, y: 0),
            animated: false
        )
        updateButtons(reloadsGifts: true)
        categoryPendingCentering = category
        setNeedsQuickLayout()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func centerPendingGiftCategoryIfNeeded() {
        guard
            let category = categoryPendingCentering,
            let index = LiveRoomGiftCategory.allCases.firstIndex(of: category),
            categoryButtons.indices.contains(index),
            categoryCarouselScrollView.bounds.width > 0
        else { return }
        categoryPendingCentering = nil
        guard categoryCarouselScrollView.contentSize.width
            > categoryCarouselScrollView.bounds.width + 1
        else {
            // 内容不足一屏时保持自然排列，不产生无意义的滚动或固定效果。
            return
        }

        let button = categoryButtons[index]
        let buttonFrame = giftCategoryButtonContentFrame(button)
        let minimumOffsetX = -categoryCarouselScrollView.adjustedContentInset.left
        let maximumOffsetX = max(
            minimumOffsetX,
            categoryCarouselScrollView.contentSize.width
                - categoryCarouselScrollView.bounds.width
                + categoryCarouselScrollView.adjustedContentInset.right
        )
        let centeredOffsetX = min(
            maximumOffsetX,
            max(
                minimumOffsetX,
                buttonFrame.midX
                    - categoryCarouselScrollView.bounds.width / 2
            )
        )
        // 只有左右内容足够时才能居中；首尾栏目会自然钳制在对应边缘，不制造空白。
        categoryCarouselScrollView.setContentOffset(
            CGPoint(
                x: centeredOffsetX,
                y: categoryCarouselScrollView.contentOffset.y
            ),
            animated: UIView.areAnimationsEnabled && window != nil
        )
    }

    func giftCategoryButtonContentFrame(
        _ button: LiveRoomTextButton
    ) -> CGRect {
        // convert(to:) 返回视口坐标，补回 contentOffset 后才是稳定的内容坐标。
        button.convert(button.bounds, to: categoryCarouselScrollView)
            .offsetBy(
                dx: categoryCarouselScrollView.contentOffset.x,
                dy: categoryCarouselScrollView.contentOffset.y
            )
    }

    func sendSelectedGift() {
        let request: LiveRoomGiftSendRequest
        switch viewModel.makeSendDecision() {
        case .recipientRequired:
            showRecipientRequiredPrompt()
            return
        case let .insufficientBalance(requiredBalance, _):
            showInsufficientBalancePrompt(requiredBalance: requiredBalance)
            return
        case let .ready(sendRequest):
            request = sendRequest
        }
        sendButton.isEnabled = false
        let updatedBalance = sendDidTap?(request)
        sendButton.isEnabled = true
        guard let updatedBalance else { return }
        // 余额以业务层确认后的结果为准，防止面板状态与真实交易状态产生偏差。
        viewModel.applyConfirmedBalance(updatedBalance)
        updateButtons()
        UIView.animate(
            withDuration: 0.10,
            animations: {
                self.sendButton.transform = CGAffineTransform(
                    scaleX: 0.96,
                    y: 0.96
                )
            },
            completion: { _ in
                UIView.animate(withDuration: 0.14) {
                    self.sendButton.transform = .identity
                }
            }
        )
    }

    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        guard sendButton.window != nil else { return nil }
        return sendButton.convert(
            CGPoint(x: sendButton.bounds.midX, y: sendButton.bounds.midY),
            to: view
        )
    }

    var selectedRecipients: [LiveRoomSeat] {
        viewModel.selectedRecipients
    }

    func setSelectedRecipientSeatIDs(_ seatIDs: Set<Int>) {
        let userIDs = Set(recipients.compactMap { recipient in
            seatIDs.contains(recipient.position.rawValue)
                ? recipient.userID
                : nil
        })
        setSelectedRecipientUserIDs(userIDs)
    }

    func setSelectedRecipientUserIDs(_ userIDs: Set<LiveRoomUserID>) {
        viewModel.setSelectedRecipientUserIDs(userIDs)
        updateButtons()
        recipientDidSelect?(selectedRecipients)
    }

    func showRecipientRequiredPrompt() {
        updateRecipientStatusLabel()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(
            notification: .announcement,
            argument: recipientTitleLabel.text
        )

        // 错误提示聚焦到收礼人区域，不使用系统 Alert，避免打断连续选礼流程。
        UIView.animateKeyframes(
            withDuration: 0.34,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            UIView.addKeyframe(
                withRelativeStartTime: 0,
                relativeDuration: 0.25
            ) {
                self.recipientCarouselScrollView.transform =
                    CGAffineTransform(translationX: 6, y: 0)
                self.selectAllButton.transform =
                    CGAffineTransform(translationX: 6, y: 0)
            }
            UIView.addKeyframe(
                withRelativeStartTime: 0.25,
                relativeDuration: 0.35
            ) {
                self.recipientCarouselScrollView.transform =
                    CGAffineTransform(translationX: -5, y: 0)
                self.selectAllButton.transform =
                    CGAffineTransform(translationX: -5, y: 0)
            }
            UIView.addKeyframe(
                withRelativeStartTime: 0.60,
                relativeDuration: 0.40
            ) {
                self.recipientCarouselScrollView.transform = .identity
                self.selectAllButton.transform = .identity
            }
        }
    }

    func clearRecipientRequiredPrompt() {
        viewModel.clearRecipientRequiredPrompt()
    }

    func showInsufficientBalancePrompt(requiredBalance: Int) {
        updateBalanceLabel()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAccessibility.post(
            notification: .announcement,
            argument: balanceLabel.text
        )
        // 面板先呈现就地错误反馈，再把充值决策交给业务控制器，避免视图层直接导航。
        insufficientBalanceDidOccur?(requiredBalance, giftBalance)
        UIView.animateKeyframes(
            withDuration: 0.30,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.3) {
                self.balanceLabel.transform = CGAffineTransform(
                    translationX: 5,
                    y: 0
                )
            }
            UIView.addKeyframe(withRelativeStartTime: 0.3, relativeDuration: 0.3) {
                self.balanceLabel.transform = CGAffineTransform(
                    translationX: -4,
                    y: 0
                )
            }
            UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                self.balanceLabel.transform = .identity
            }
        }
    }

    func clearInsufficientBalancePrompt() {
        viewModel.clearInsufficientBalancePrompt()
    }
}
