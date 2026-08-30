//
//  LiveRoomRechargeView+Animation.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension LiveRoomRechargeView {

    func playSuccessAnimation(
        from previousBalance: Int,
        to updatedBalance: Int,
        creditedAmount: Int
    ) {
        successAnimationCount += 1
        successOverlayView.configure(
            message: DemoLocalization.text(
                "liveRoom.recharge.success",
                creditedAmount
            )
        )

        let balanceCardView = contentView.balanceCardView
        let rechargeButton = contentView.footerView.rechargeButton
        balanceDisplayLink?.invalidate()
        balanceDisplayLink = nil
        successOverlayView.layer.removeAllAnimations()
        balanceCardView.backgroundView.layer.removeAllAnimations()
        rechargeButton.layer.removeAllAnimations()

        guard UIView.areAnimationsEnabled,
            !UIAccessibility.isReduceMotionEnabled
        else {
            balanceCardView.updateBalance(
                DemoLocalization.text(
                    "liveRoom.recharge.balance.value",
                    updatedBalance
                )
            )
            successOverlayView.isHidden = true
            successOverlayView.alpha = 0
            rechargeButton.isEnabled = true
            return
        }

        rechargeButton.isEnabled = false
        successOverlayView.prepareForAnimation()
        successOverlayView.isHidden = false
        successOverlayView.alpha = 0
        successOverlayView.transform = CGAffineTransform(
            translationX: 0,
            y: 24
        ).scaledBy(x: 0.78, y: 0.78)

        startBalanceCountAnimation(from: previousBalance, to: updatedBalance)
        successOverlayView.playDecorativeAnimation()

        UIView.animateKeyframes(
            withDuration: 1.55,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.18) {
                self.successOverlayView.alpha = 1
                self.successOverlayView.transform = CGAffineTransform(
                    scaleX: 1.05,
                    y: 1.05
                )
                balanceCardView.transform = CGAffineTransform(
                    scaleX: 1.015,
                    y: 1.015
                )
                balanceCardView.backgroundView.layer.borderColor =
                    UIColor.systemYellow.withAlphaComponent(0.70).cgColor
                rechargeButton.transform = CGAffineTransform(
                    scaleX: 0.97,
                    y: 0.97
                )
            }
            UIView.addKeyframe(
                withRelativeStartTime: 0.18,
                relativeDuration: 0.20
            ) {
                self.successOverlayView.transform = .identity
                balanceCardView.transform = .identity
                rechargeButton.transform = .identity
            }
            UIView.addKeyframe(
                withRelativeStartTime: 0.76,
                relativeDuration: 0.24
            ) {
                self.successOverlayView.alpha = 0
                self.successOverlayView.transform = CGAffineTransform(
                    translationX: 0,
                    y: -22
                ).scaledBy(x: 0.96, y: 0.96)
            }
        } completion: { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.successOverlayView.isHidden = true
                self.successOverlayView.alpha = 0
                self.successOverlayView.transform = .identity
                balanceCardView.transform = .identity
                balanceCardView.backgroundView.layer.borderColor = UIColor.white
                    .withAlphaComponent(0.14).cgColor
                rechargeButton.transform = .identity
                rechargeButton.isEnabled = true
            }
        }
    }

    private func startBalanceCountAnimation(from: Int, to: Int) {
        balanceAnimationFrom = from
        balanceAnimationTo = to
        balanceAnimationStartTime = CACurrentMediaTime()
        contentView.balanceCardView.updateBalance(
            DemoLocalization.text("liveRoom.recharge.balance.value", from)
        )
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateBalanceCountAnimation)
        )
        balanceDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func updateBalanceCountAnimation(
        _ displayLink: CADisplayLink
    ) {
        let elapsed = displayLink.timestamp - balanceAnimationStartTime
        let progress = min(max(elapsed / 0.88, 0), 1)
        let easedProgress = 1 - pow(1 - progress, 3)
        let difference = Double(balanceAnimationTo - balanceAnimationFrom)
        let displayedBalance = balanceAnimationFrom
            + Int((difference * easedProgress).rounded())
        contentView.balanceCardView.updateBalance(
            DemoLocalization.text(
                "liveRoom.recharge.balance.value",
                displayedBalance
            )
        )
        guard progress >= 1 else { return }
        displayLink.invalidate()
        if balanceDisplayLink === displayLink {
            balanceDisplayLink = nil
        }
        contentView.balanceCardView.updateBalance(
            DemoLocalization.text(
                "liveRoom.recharge.balance.value",
                balanceAnimationTo
            )
        )
    }
}
