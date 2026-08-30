//
//  LiveRoomViewController+GiftCoordinator.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension LiveRoomViewController {

    func presentGiftSheet(
        initiallySelectedRecipientUserIDs: [LiveRoomUserID] = []
    ) {
        guard
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }
        let recipients = viewModel.state.visibleRecipients
        guard !recipients.isEmpty else { return }
        let giftSheet = LiveRoomGiftSheetViewController(
            recipients: recipients,
            initiallySelectedRecipientUserIDs:
                initiallySelectedRecipientUserIDs,
            initialBalance: giftBalance
        )
        giftSheet.giftSendRequest = { [weak self] request in
            self?.processGiftSendRequest(request)
        }
        giftSheet.insufficientBalanceDidOccur = { [weak self] required, balance in
            self?.presentRechargePrompt(
                requiredBalance: required,
                currentBalance: balance
            )
        }
        giftSheet.closeDidRequest = { [weak self, weak giftSheet] in
            guard let giftSheet else { return }
            self?.closeGiftSheet(giftSheet)
        }
        // 这里使用子控制器而不是 present，发送后面板可以保留，特效层也不会被遮挡。
        let giftSheetHost = QuickLayoutViewControllerRepresentable(
            giftSheet,
            parent: self
        )
        giftSheetViewController = giftSheet
        self.giftSheetHost = giftSheetHost
        setNeedsQuickLayout()
        quickLayoutIfNeeded()
        giftSheet.animateIn()
    }

    /// Demo 调试入口：把零基麦位位置转换为稳定 userID 后再打开面板。
    func presentGiftSheet(initiallySelectedRecipientSeatIDs: [Int]) {
        let positions = Set(initiallySelectedRecipientSeatIDs)
        presentGiftSheet(
            initiallySelectedRecipientUserIDs: viewModel.state
                .visibleRecipients.compactMap { recipient in
                    positions.contains(recipient.position.rawValue)
                        ? recipient.userID
                        : nil
                }
        )
    }

    func closeGiftSheet(
        _ giftSheet: LiveRoomGiftSheetViewController,
        completion: (() -> Void)? = nil
    ) {
        guard giftSheetViewController === giftSheet else { return }
        giftSheet.animateOut { [weak self, weak giftSheet] in
            guard
                let self,
                self.giftSheetViewController === giftSheet
            else { return }
            // 必须先结束退场动画，再拆除 containment 和视图，防止生命周期与画面不同步。
            self.giftSheetHost?.dismantleViewController()
            self.giftSheetHost = nil
            self.giftSheetViewController = nil
            self.setNeedsQuickLayout()
            self.quickLayoutIfNeeded()
            UIAccessibility.post(
                notification: .screenChanged,
                argument: self.actionBarView
            )
            completion?()
        }
    }

    func presentRechargePrompt(
        requiredBalance: Int,
        currentBalance: Int
    ) {
        guard presentedViewController == nil else { return }
        pendingRechargeRequiredBalance = max(0, requiredBalance)
        let alert = UIAlertController(
            title: DemoLocalization.text("liveRoom.recharge.alert.title"),
            message: DemoLocalization.text(
                "liveRoom.recharge.alert.message",
                currentBalance,
                requiredBalance
            ),
            preferredStyle: .alert
        )
        alert.view.accessibilityIdentifier = "liveRoom.recharge.alert"
        alert.addAction(
            UIAlertAction(
                title: DemoLocalization.text("liveRoom.recharge.alert.cancel"),
                style: .cancel
            ) { [weak self] _ in
                self?.pendingRechargeRequiredBalance = nil
            }
        )
        alert.addAction(
            UIAlertAction(
                title: DemoLocalization.text("liveRoom.recharge.alert.action"),
                style: .default
            ) { [weak self] _ in
                self?.proceedToRecharge()
            }
        )
        present(alert, animated: true)
    }

    /// 余额不足弹窗确认后的唯一跳转入口，测试与系统 Alert 共用同一条业务路径。
    func proceedToRecharge() {
        guard let requiredBalance = pendingRechargeRequiredBalance else {
            return
        }
        pendingRechargeRequiredBalance = nil
        let closeGiftSheetThenShowPage: () -> Void = { [weak self] in
            guard let self else { return }
            let showRechargePage: () -> Void = { [weak self] in
                guard let self else { return }
                self.showRechargePage(requiredBalance: requiredBalance)
            }
            if let giftSheetViewController = self.giftSheetViewController {
                self.closeGiftSheet(
                    giftSheetViewController,
                    completion: showRechargePage
                )
            } else {
                showRechargePage()
            }
        }
        if presentedViewController is UIAlertController {
            // 先等待系统弹窗完全退场，再关闭底部面板和推进页面，避免三层转场同时发生。
            dismiss(animated: true, completion: closeGiftSheetThenShowPage)
        } else {
            closeGiftSheetThenShowPage()
        }
    }

    func showRechargePage(requiredBalance: Int) {
        let rechargeViewController = LiveRoomRechargeViewController(
            currentBalance: giftBalance,
            requiredBalance: requiredBalance
        )
        rechargeViewController.balanceDidRecharge = { [weak self] amount in
            self?.viewModel.recharge(by: amount)
        }
        self.rechargeViewController = rechargeViewController
        if let navigationController {
            navigationController.pushViewController(
                rechargeViewController,
                animated: true
            )
        } else {
            let navigationController = UINavigationController(
                rootViewController: rechargeViewController
            )
            navigationController.modalPresentationStyle = .fullScreen
            present(navigationController, animated: true)
        }
    }

    func deliver(
        gift: LiveRoomGift,
        to recipients: [LiveRoomSeat],
        quantity: Int
    ) {
        let visibleRecipientsByUserID = Dictionary(
            uniqueKeysWithValues: viewModel.state.visibleRecipients
                .compactMap { recipient in
                    recipient.userID.map { ($0, recipient) }
                }
        )
        let currentRecipients = recipients.compactMap { recipient in
            recipient.userID.flatMap { visibleRecipientsByUserID[$0] }
        }
        guard !currentRecipients.isEmpty else { return }

        lastGiftID = gift.id
        lastGiftRecipientSeatIDs = currentRecipients.map(\.id)
        lastGiftQuantity = quantity
        giftDeliveryCount += 1
        view.layoutIfNeeded()
        giftEffectOverlayView.layoutIfNeeded()
        announceGift(
            gift,
            quantity: quantity,
            recipients: currentRecipients
        )
        // 起点和终点统一转换到共享特效容器，避免安全区、RTL 或 iPad 尺寸造成偏移。
        guard let origin = giftSheetViewController?
            .giftAnimationOrigin(in: giftEffectOverlayView)
            ?? actionBarView.giftAnimationOrigin(
                in: giftEffectOverlayView
            ) else {
            return
        }
        lastGiftAnimationOrigin = origin
        lastGiftAnimationTargetPoints = []

        let color = LiveRoomTheme.giftColor(at: gift.themeIndex)
        let centerIndex = CGFloat(currentRecipients.count - 1) / 2
        for (index, recipient) in currentRecipients.enumerated() {
            guard let userID = recipient.userID else { continue }
            let endPoint = if seatTransitionCoordinator.isTransitioning {
                seatTransitionCoordinator.giftTargetPoint(
                    for: userID,
                    in: giftEffectOverlayView
                )
            } else {
                seatStageView.giftTargetPoint(
                    forUserID: userID,
                    in: giftEffectOverlayView
                )
            }
            guard let endPoint else { continue }
            lastGiftAnimationTargetPoints.append(endPoint)
            let startPoint = CGPoint(
                x: origin.x + (CGFloat(index) - centerIndex) * 5,
                y: origin.y
            )
            let animator = LiveRoomGiftFlightAnimator(
                containerView: giftEffectOverlayView
            )
            giftFlightAnimators[animator.id] = animator
            animator.start(
                gift: gift,
                quantity: quantity,
                from: startPoint,
                to: endPoint,
                delay: Double(index) * 0.10,
                showsCelebration: index == 0,
                arrival: { [weak self] in
                    self?.seatStageView.playGiftArrival(
                        forUserID: userID,
                        gift: gift,
                        color: color
                    )
                },
                completion: { [weak self, weak animator] in
                    guard let animator else { return }
                    self?.giftFlightAnimators[animator.id] = nil
                }
            )
        }
    }

    func processGiftSendRequest(
        _ request: LiveRoomGiftSendRequest
    ) -> Int? {
        guard let updatedBalance = viewModel.processGiftSendRequest(request)
        else { return nil }
        // ViewModel 完成校验与扣款后，控制器才协调送礼动画和麦位反馈。
        deliver(
            gift: request.gift,
            to: request.recipients,
            quantity: request.quantity
        )
        return updatedBalance
    }

    func announceGift(
        _ gift: LiveRoomGift,
        quantity: Int,
        recipients: [LiveRoomSeat]
    ) {
        let recipientNames = recipients
            .map { DemoLocalization.text($0.nameKey) }
            .joined(separator: DemoLocalization.text("liveRoom.gift.name.separator"))
        UIAccessibility.post(
            notification: .announcement,
            argument: DemoLocalization.text(
                "liveRoom.gift.sent.quantity",
                DemoLocalization.text(gift.titleKey),
                quantity,
                recipientNames
            )
        )
    }
}
