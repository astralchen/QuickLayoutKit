//
//  VoiceRoomViewController+GiftCoordinator.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension VoiceRoomViewController {

    func presentGiftSheet(
        initiallySelectedRecipientUserIDs: [RoomUserID] = []
    ) {
        guard
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }
        let recipients = viewModel.state.visibleRecipients
        guard !recipients.isEmpty else { return }
        let giftSheet = GiftSheetViewController(
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
        _ giftSheet: GiftSheetViewController,
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
            title: Localization.text("liveRoom.recharge.alert.title"),
            message: Localization.text(
                "liveRoom.recharge.alert.message",
                currentBalance,
                requiredBalance
            ),
            preferredStyle: .alert
        )
        alert.view.accessibilityIdentifier = "liveRoom.recharge.alert"
        alert.addAction(
            UIAlertAction(
                title: Localization.text("liveRoom.recharge.alert.cancel"),
                style: .cancel
            ) { [weak self] _ in
                self?.pendingRechargeRequiredBalance = nil
            }
        )
        alert.addAction(
            UIAlertAction(
                title: Localization.text("liveRoom.recharge.alert.action"),
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
        let rechargeViewController = RechargeViewController(
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
        gift: Gift,
        to recipients: [SeatAssignment],
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
        // 单项原生礼物保留即时飞行；远程或组合礼物按整份赠送进入串行队列。
        if gift.effects.count == 1, case .native(let style) = gift.effects.first {
            _ = playNativeGift(gift, style: style, to: currentRecipients, quantity: quantity) { _ in }
        } else {
            lastGiftAnimationOrigin = nil
            lastGiftAnimationTargetPoints = []
            giftMainEffectCoordinator.enqueue(gift: gift, quantity: quantity) { [weak self] in
                GiftNativeEffectPlayer { [weak self] style, item, quantity, completion in
                    guard let self else {
                        completion(.failure(GiftMainEffectPlaybackError.unavailable))
                        return {}
                    }
                    let userIDs = Set(currentRecipients.compactMap(\.userID))
                    let recipients = self.viewModel.state.visibleRecipients.filter {
                        $0.userID.map(userIDs.contains) ?? false
                    }
                    return self.playNativeGift(item, style: style, to: recipients, quantity: quantity, completion: completion)
                }
            }
        }
    }

    /// 在原生效果真正开始时查询麦位坐标；返回的清理只取消本项动画，不影响其他赠送。
    /// 全部收礼人的动画结束才完成该效果；取消后不再触发到达反馈或完成通知。
    private func playNativeGift(
        _ gift: Gift, style: GiftEffectStyle, to currentRecipients: [SeatAssignment], quantity: Int,
        completion: @escaping GiftPlaybackOperation.Completion
    ) -> GiftPlaybackOperation.Cleanup {
        view.layoutIfNeeded()
        giftEffectOverlayView.layoutIfNeeded()
        // 起点和终点统一转换到共享特效容器，避免安全区、RTL 或 iPad 尺寸造成偏移。
        guard let origin = giftSheetViewController?
            .giftAnimationOrigin(in: giftEffectOverlayView)
            ?? actionBarView.giftAnimationOrigin(
                in: giftEffectOverlayView
            ) else {
            completion(.failure(GiftMainEffectPlaybackError.unavailable))
            return {}
        }
        lastGiftAnimationOrigin = origin
        lastGiftAnimationTargetPoints = []

        let color = VoiceRoomTheme.giftColor(at: gift.themeIndex)
        guard !currentRecipients.isEmpty else {
            completion(.failure(GiftMainEffectPlaybackError.unavailable))
            return {}
        }
        var isCancelled = false
        var isStarting = true
        var remaining = 0
        var animators: [GiftFlightAnimator] = []
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
            let animator = GiftFlightAnimator(
                containerView: giftEffectOverlayView
            )
            giftFlightAnimators[animator.id] = animator
            animators.append(animator)
            remaining += 1
            animator.start(
                gift: gift,
                style: style,
                quantity: quantity,
                from: startPoint,
                to: endPoint,
                delay: Double(index) * 0.10,
                showsCelebration: index == 0,
                arrival: { [weak self] in
                    guard !isCancelled else { return }
                    self?.seatStageView.playGiftArrival(
                        forUserID: userID,
                        gift: gift,
                        color: color,
                        style: style
                    )
                },
                completion: { [weak self, weak animator] in
                    guard let animator else { return }
                    self?.giftFlightAnimators[animator.id] = nil
                    guard !isCancelled else { return }
                    remaining -= 1
                    if remaining == 0, !isStarting { completion(.success(())) }
                }
            )
        }
        isStarting = false
        if remaining == 0 { completion(animators.isEmpty ? .failure(GiftMainEffectPlaybackError.unavailable) : .success(())) }
        return { [weak self] in
            isCancelled = true
            for animator in animators {
                animator.cancel()
                self?.giftFlightAnimators[animator.id] = nil
            }
        }
    }

    func processGiftSendRequest(
        _ request: GiftSendRequest
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
        _ gift: Gift,
        quantity: Int,
        recipients: [SeatAssignment]
    ) {
        let recipientNames = recipients
            .map { Localization.text($0.nameKey) }
            .joined(separator: Localization.text("liveRoom.gift.name.separator"))
        UIAccessibility.post(
            notification: .announcement,
            argument: Localization.text(
                "liveRoom.gift.sent.quantity",
                gift.localizedTitle,
                quantity,
                recipientNames
            )
        )
    }
}
