//
//  GiftSheetView+Interaction.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension GiftSheetView {

    /// 切换指定用户的收礼选择并通知宿主最新选择列表。
    func selectRecipient(_ recipient: SeatAssignment) {
        guard
            let userID = recipient.userID,
            viewModel.toggleRecipient(userID: userID)
        else { return }
        updateButtons()
        recipientDidSelect?(selectedRecipients)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 切换当前用户列表的全选状态并刷新按钮及选择回调。
    func toggleAllRecipients() {
        viewModel.toggleAllRecipients()
        updateButtons()
        recipientDidSelect?(selectedRecipients)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 更新礼物选择，并在选择发生变化时刷新面板及通知宿主。
    func selectGift(_ gift: Gift) {
        guard viewModel.selectGift(id: gift.id) else { return }
        updateButtons(reloadsGifts: true)
        giftDidSelect?(gift)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 尝试选择指定赠送数量，并返回是否被当前预设接受。
    @discardableResult
    func setSelectedGiftQuantity(_ quantity: Int) -> Bool {
        guard viewModel.selectGiftQuantity(quantity) else { return false }
        updateButtons()
        return true
    }

    /// 更新赠送数量并刷新数量按钮和发送信息。
    func selectGiftQuantity(_ quantity: Int) {
        guard setSelectedGiftQuantity(quantity) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 切换礼物栏目，刷新网格并安排所选栏目滚动到可见中心。
    func selectCategory(_ category: GiftCategory) {
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

    /// 在栏目布局可用时完成待处理的居中滚动，并限制滚动边界。
    func centerPendingGiftCategoryIfNeeded() {
        guard
            let category = categoryPendingCentering,
            let index = GiftCategory.allCases.firstIndex(of: category),
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

    /// 返回栏目按钮在栏目滚动内容坐标系中的矩形。
    func giftCategoryButtonContentFrame(
        _ button: CapsuleTextButton
    ) -> CGRect {
        // UIScrollView 的 bounds.origin 已包含 contentOffset，转换结果就是内容坐标。
        button.convert(button.bounds, to: categoryCarouselScrollView)
    }

    /// 校验当前选择并提交发送回调，成功后应用业务层确认的余额。
    func sendSelectedGift() {
        let request: GiftSendRequest
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

    /// 返回礼物飞行起点在指定视图坐标系中的位置；视图不可用时为 `nil`。
    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        guard sendButton.window != nil else { return nil }
        return sendButton.convert(
            CGPoint(x: sendButton.bounds.midX, y: sendButton.bounds.midY),
            to: view
        )
    }

    /// 按收礼人列表顺序解析出的已选麦位绑定。
    var selectedRecipients: [SeatAssignment] {
        viewModel.selectedRecipients
    }

    /// 将零基麦位位置转换为当前用户标识后更新收礼人选择。
    func setSelectedRecipientSeatIDs(_ seatIDs: Set<Int>) {
        let userIDs = Set(recipients.compactMap { recipient in
            seatIDs.contains(recipient.position.rawValue)
                ? recipient.userID
                : nil
        })
        setSelectedRecipientUserIDs(userIDs)
    }

    /// 按稳定用户标识更新收礼人选择并同步面板显示。
    func setSelectedRecipientUserIDs(_ userIDs: Set<RoomUserID>) {
        viewModel.setSelectedRecipientUserIDs(userIDs)
        updateButtons()
        recipientDidSelect?(selectedRecipients)
    }

    /// 显示收礼人选择提示，并提供触觉、播报及就地动画反馈。
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

    /// 清除选择收礼人的提示状态。
    func clearRecipientRequiredPrompt() {
        viewModel.clearRecipientRequiredPrompt()
    }

    /// 显示余额错误反馈，并将所需余额交给宿主处理充值导航。
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

    /// 清除余额不足的提示状态。
    func clearInsufficientBalancePrompt() {
        viewModel.clearInsufficientBalancePrompt()
    }
}
