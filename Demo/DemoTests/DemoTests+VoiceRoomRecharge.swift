import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomRechargeViewModelCommitsConfirmedTransaction() throws {
        let viewModel = RechargeViewModel(
            currentBalance: 100,
            requiredBalance: 5_000
        )
        #expect(viewModel.selectedPackageAmount == 6_000)

        let transaction = try #require(
            viewModel.performRecharge { creditedAmount in
                100 + creditedAmount
            }
        )
        #expect(transaction.previousBalance == 100)
        #expect(transaction.creditedAmount == 6_300)
        #expect(transaction.updatedBalance == 6_400)
        #expect(viewModel.currentBalance == 6_400)
    }

    @Test func voiceRoomRechargeBalanceCardPreservesCompleteTextLines() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = RechargeViewController(
            currentBalance: 12_048,
            requiredBalance: 88_888
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.rechargeView.scrollView.layoutIfNeeded()

        let balanceCardView = viewController.rechargeView
            .contentView.balanceCardView
        let balanceLabels = [
            balanceCardView.captionLabel,
            balanceCardView.valueLabel,
            balanceCardView.requirementLabel,
        ]
        #expect(balanceLabels.allSatisfy { label in
            label.bounds.height + 1 >= label.font.lineHeight
        })

        let minimumCardHeight = balanceLabels.reduce(CGFloat.zero) {
            $0 + $1.font.lineHeight
        } + 18 + 36
        #expect(
            balanceCardView.backgroundView.bounds.height + 1
                >= minimumCardHeight
        )
        let statusLabel = viewController.rechargeView
            .contentView.footerView.statusLabel
        let footerView = viewController.rechargeView.contentView.footerView
        #expect(statusLabel.text?.isEmpty != false)
        // 空状态标签不绘制文本，但仍保留状态槽位，避免确认按钮随消息出现跳动。
        let initialButtonFrame = footerView.rechargeButton.frame
        #expect(initialButtonFrame.minY >= 20 + 18 - 1)
        viewController.rechargeView.showSuccessStatus("充值成功")
        layout(viewController, in: navigationController)
        viewController.rechargeView.scrollView.layoutIfNeeded()
        #expect(statusLabel.bounds.height + 1 >= statusLabel.font.lineHeight)
        #expect(abs(footerView.rechargeButton.frame.minY - initialButtonFrame.minY) < 1)
    }

    @Test func voiceRoomRechargePackageGridAdaptsToContainerAndPackageCount() {
        let packageSectionView = RechargePackageSectionView(frame: .zero)
        let allPackages = (1...9).map {
            RechargePackage(amount: $0 * 1_000, bonus: $0 * 100)
        }

        for (availableWidth, columns) in [
            (CGFloat(200), 1),
            (CGFloat(284), 2),
            (CGFloat(354), 3),
            (CGFloat(460), 4),
            (CGFloat(620), 5),
        ] {
            for count in [9, 2, 0, 4, 5, 1, 6, 7] {
                let packages = Array(allPackages.prefix(count))
                packageSectionView.configure(
                    title: "选择充值档位",
                    packages: packages,
                    selectedAmount: packages.first?.amount ?? 0
                )
                let fittedSize = packageSectionView.sizeThatFits(
                    CGSize(width: availableWidth, height: 1_000)
                )
                packageSectionView.frame = CGRect(
                    origin: .zero,
                    size: CGSize(
                        width: availableWidth,
                        height: fittedSize.height
                    )
                )
                packageSectionView.layoutIfNeeded()

                #expect(packageSectionView.packageButtons.count == count)
                #expect(packageSectionView.packageButtons.allSatisfy {
                    $0.superview === packageSectionView
                })
                #expect(packageSectionView.subviews.compactMap {
                    $0 as? RechargePackageButton
                }.count == count)

                guard count > 0 else { continue }
                let expectedWidth = (
                    availableWidth - CGFloat(columns - 1) * 10
                ) / CGFloat(columns)
                #expect(packageSectionView.packageButtons.allSatisfy {
                    abs($0.frame.width - expectedWidth) < 1
                        && abs($0.frame.height - 88) < 1
                }, "width: \(availableWidth), count: \(count), frames: \(packageSectionView.packageButtons.map(\.frame))")

                let rowOrigins = Set(packageSectionView.packageButtons.map {
                    Int($0.frame.minY.rounded())
                })
                #expect(
                    rowOrigins.count
                        == (count + columns - 1) / columns
                )
            }
        }
    }
}
