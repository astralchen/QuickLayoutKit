import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomGiftFlowSelectsOccupiedRecipientAndCompletesFlight() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let backdropGradientView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutLinearGradientView.self)
                .first
        )
        let backdropShapeView = try #require(
            backdropGradientView
                .allSubviews(of: QuickLayoutShapeView.self)
                .first
        )
        #expect(backdropGradientView.layer is CAGradientLayer)
        #expect(backdropShapeView.layer is CAShapeLayer)
        #expect((backdropShapeView.layer as? CAShapeLayer)?.path != nil)
        let giftButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.button"
            }
        )
        activate(giftButton)

        let giftSheet = try #require(
            viewController.giftSheetViewController
        )
        giftSheet.loadViewIfNeeded()
        giftSheet.view.frame = window.bounds
        giftSheet.view.setNeedsLayout()
        giftSheet.view.layoutIfNeeded()

        #expect(viewController.presentedGiftRecipientSeatIDs == [0, 1, 2, 3, 4, 6, 7])
        #expect(viewController.presentedViewController == nil)
        #expect(giftSheet.parent === viewController)
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
        #expect(giftSheet.selectedGiftID == "heart")
        #expect(giftSheet.giftCount == 18)
        #expect(giftSheet.visibleGiftCount == 18)
        #expect(giftSheet.selectedGiftCategoryID == "all")
        #expect(viewController.giftBalance == 12_800)
        #expect(giftSheet.giftBalance == 12_800)
        #expect(
            giftSheet.balanceStatusText
                == Localization.text("liveRoom.gift.balance", 12_800)
        )
        #expect(giftSheet.giftColumnCount == 4)
        let giftScrollView = giftSheet.giftScrollView
        let recipientScrollView = giftSheet.recipientScrollView
        let categoryScrollView = giftSheet.giftCategoryScrollView
        giftScrollView.layoutIfNeeded()
        recipientScrollView.layoutIfNeeded()
        categoryScrollView.layoutIfNeeded()
        #expect(giftSheet.view.allSubviews(of: UIScrollView.self).count == 3)
        #expect(giftScrollView.contentSize.height > giftScrollView.bounds.height)
        #expect(recipientScrollView.alwaysBounceHorizontal)
        #expect(!recipientScrollView.showsHorizontalScrollIndicator)
        #expect(!categoryScrollView.alwaysBounceHorizontal)
        #expect(!categoryScrollView.showsHorizontalScrollIndicator)
        #expect(categoryScrollView.contentSize.width > categoryScrollView.bounds.width)
        #expect(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).filter {
                $0.accessibilityIdentifier?.hasPrefix(
                    "liveRoom.gift.category."
                ) == true
            }.count == 7
        )
        #expect(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.5"
            } == nil
        )

        let luxuryCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.luxury"
            }
        )
        let allCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.all"
            }
        )
        let collectionCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.gift.category.collection"
            }
        )
        let partyCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.party"
            }
        )
        activate(luxuryCategoryButton)
        #expect(giftSheet.selectedGiftCategoryID == "luxury")
        #expect(giftSheet.visibleGiftCount == 4)
        #expect(giftSheet.selectedGiftID == "galaxy")
        activate(allCategoryButton)
        #expect(giftSheet.selectedGiftCategoryID == "all")
        #expect(giftSheet.visibleGiftCount == 18)
        activate(collectionCategoryButton)
        giftSheet.view.layoutIfNeeded()
        #expect(giftSheet.selectedGiftCategoryID == "collection")
        #expect(giftSheet.visibleGiftCount == 6)
        let collectionFrame = collectionCategoryButton.convert(
            collectionCategoryButton.bounds,
            to: categoryScrollView
        )
        // 栏目槽位保留按钮两侧的自然留白；末尾应滚到内容边界且按钮完整可见。
        #expect(categoryScrollView.bounds.contains(collectionFrame))
        #expect(abs(
            categoryScrollView.bounds.maxX
                - categoryScrollView.contentSize.width
                - categoryScrollView.adjustedContentInset.right
        ) < 1)
        activate(partyCategoryButton)
        giftSheet.view.layoutIfNeeded()
        #expect(giftSheet.selectedGiftCategoryID == "party")
        #expect(giftSheet.visibleGiftCount == 6)
        let partyCategoryFrame = partyCategoryButton.convert(
            partyCategoryButton.bounds,
            to: categoryScrollView
        )
        #expect(
            abs(partyCategoryFrame.midX - categoryScrollView.bounds.midX) < 1
        )
        activate(allCategoryButton)
        giftSheet.view.layoutIfNeeded()
        #expect(giftSheet.selectedGiftCategoryID == "all")
        let allCategoryFrame = allCategoryButton.convert(
            allCategoryButton.bounds,
            to: categoryScrollView
        )
        #expect(categoryScrollView.bounds.contains(allCategoryFrame))
        #expect(abs(
            categoryScrollView.contentOffset.x
                + categoryScrollView.adjustedContentInset.left
        ) < 1)

        let giftCollectionView = try #require(
            giftScrollView as? UICollectionView
        )
        #expect(giftCollectionView.layer.cornerRadius == 0)
        giftCollectionView.scrollToItem(
            at: IndexPath(item: 17, section: 0),
            at: .bottom,
            animated: false
        )
        giftCollectionView.layoutIfNeeded()
        #expect(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).contains {
                $0.accessibilityIdentifier == "liveRoom.gift.item.universe"
            }
        )
        giftCollectionView.scrollToItem(
            at: IndexPath(item: 5, section: 0),
            at: .centeredVertically,
            animated: false
        )
        giftCollectionView.layoutIfNeeded()

        let recipientButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.3"
            }
        )
        let rocketButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.item.rocket"
            }
        )
        let secondRecipientButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.4"
            }
        )
        let sendButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.send"
            }
        )
        let selectAllButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.selectAll"
            }
        )
        let recipientAvatarView = try #require(
            recipientButton.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.avatar"
            }
        )
        let selectionBadgeView = try #require(
            recipientButton.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.gift.recipient.selectionBadge"
            }
        )
        #expect(recipientAvatarView.layer.borderWidth == 1.5)
        #expect((recipientAvatarView.layer.borderColor?.alpha ?? 0) >= 0.45)
        #expect(selectionBadgeView.isHidden)
        activate(sendButton)
        #expect(viewController.giftDeliveryCount == 0)
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
        #expect(
            giftSheet.recipientStatusText
                == Localization.text("liveRoom.gift.recipient.required")
        )
        activate(selectAllButton)
        #expect(giftSheet.selectedRecipientSeatIDs == [0, 1, 2, 3, 4, 6, 7])
        #expect(
            giftSheet.recipientStatusText
                == Localization.text("liveRoom.gift.recipient.count", 7)
        )
        giftSheet.view.layoutIfNeeded()
        #expect(recipientButton.layer.borderWidth == 0)
        #expect(recipientAvatarView.layer.borderWidth == 3)
        #expect(!selectionBadgeView.isHidden)
        #expect(selectAllButton.bounds.width > selectAllButton.bounds.height)
        #expect(
            abs(
                selectAllButton.layer.cornerRadius
                    - selectAllButton.bounds.height / 2
            ) < 1
        )
        #expect(
            (selectAllButton as? GiftSelectAllButton)?.displayedTitle
                == Localization.text("liveRoom.gift.selectAll")
        )
        #expect(!selectAllButton.isDescendant(of: recipientScrollView))
        let recipientFadeView = try #require(
            giftSheet.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipientFog"
            }
        )
        #expect(!recipientFadeView.isUserInteractionEnabled)
        #expect(recipientFadeView.frame.intersects(recipientScrollView.frame))
        activate(selectAllButton)
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
        #expect(recipientAvatarView.layer.borderWidth == 1.5)
        #expect(selectionBadgeView.isHidden)
        activate(recipientButton)
        activate(secondRecipientButton)
        activate(rocketButton)

        #expect(giftSheet.selectedRecipientSeatIDs == [3, 4])
        #expect(giftSheet.selectedGiftID == "rocket")
        activate(sendButton)

        #expect(await waitForCondition {
            viewController.lastGiftRecipientSeatIDs == [3, 4]
                && viewController.lastGiftID == "rocket"
                && viewController.giftDeliveryCount == 1
        })
        #expect(viewController.giftBalance == 12_424)
        #expect(giftSheet.giftBalance == 12_424)
        #expect(
            giftSheet.balanceStatusText
                == Localization.text("liveRoom.gift.balance", 12_424)
        )
        #expect(viewController.giftSheetViewController === giftSheet)
        #expect(viewController.isGiftSheetVisible)
        #expect(viewController.giftEffectContainerView.subviews.count == 2)
        let animationOrigin = try #require(
            viewController.lastGiftAnimationOrigin
        )
        let targetPoints = viewController.lastGiftAnimationTargetPoints
        #expect(targetPoints.count == 2)
        #expect(
            viewController.giftEffectContainerView.bounds.contains(
                animationOrigin
            )
        )
        #expect(targetPoints.allSatisfy {
            viewController.giftEffectContainerView.bounds.contains($0)
        })
        #expect(targetPoints.allSatisfy { animationOrigin.y > $0.y })

        activate(sendButton)
        #expect(await waitForCondition {
            viewController.giftDeliveryCount == 2
                && viewController.lastGiftRecipientSeatIDs == [3, 4]
                && viewController.lastGiftID == "rocket"
        })
        #expect(viewController.giftBalance == 12_048)
        #expect(giftSheet.giftBalance == 12_048)
        #expect(viewController.giftSheetViewController === giftSheet)
        #expect(sendButton.isEnabled)
        #expect(await waitForCondition {
            viewController.activeGiftFlightCount == 0
        })

        giftCollectionView.scrollToItem(
            at: IndexPath(item: 17, section: 0),
            at: .bottom,
            animated: false
        )
        giftCollectionView.layoutIfNeeded()
        let universeButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.item.universe"
            }
        )
        activate(universeButton)
        #expect(giftSheet.selectedGiftID == "universe")
        activate(sendButton)

        #expect(viewController.giftDeliveryCount == 2)
        #expect(viewController.giftBalance == 12_048)
        #expect(giftSheet.giftBalance == 12_048)
        #expect(
            giftSheet.balanceStatusText
                == Localization.text(
                    "liveRoom.gift.balance.insufficient",
                    12_048
                )
        )
        #expect(viewController.activeGiftFlightCount == 0)

        let rechargeAlert = try #require(
            viewController.presentedViewController as? UIAlertController
        )
        #expect(
            rechargeAlert.title
                == Localization.text("liveRoom.recharge.alert.title")
        )
        #expect(rechargeAlert.actions.count == 2)
        #expect(
            rechargeAlert.actions.last?.title
                == Localization.text("liveRoom.recharge.alert.action")
        )
        viewController.proceedToRecharge()
        #expect(await waitForCondition {
            viewController.giftSheetViewController == nil
                && viewController.presentedViewController == nil
                && navigationController.topViewController
                    is RechargeViewController
                && navigationController.transitionCoordinator == nil
        })

        let rechargeViewController = try #require(
            navigationController.topViewController
                as? RechargeViewController
        )
        layout(rechargeViewController, in: navigationController)
        #expect(rechargeViewController.currentBalance == 12_048)
        #expect(rechargeViewController.selectedPackageAmount == 30_000)
        let rechargeBackgroundView = try #require(
            rechargeViewController.view
                .allSubviews(of: QuickLayoutLinearGradientView.self)
                .first
        )
        #expect(rechargeBackgroundView.layer is CAGradientLayer)
        #expect(rechargeBackgroundView.layer.frame == rechargeBackgroundView.bounds)
        #expect(rechargeBackgroundView.gradient.stops.count == 3)
        #expect(
            rechargeBackgroundView.gradient.stops.map(\.location)
                == [0, 0.56, 1]
        )
        let rechargePackageButtons = rechargeViewController.view
            .allSubviews(of: RechargePackageButton.self)
            .filter {
                $0.accessibilityIdentifier?.hasPrefix(
                    "liveRoom.recharge.package."
                ) == true
            }
            .sorted {
                ($0.accessibilityIdentifier ?? "")
                    < ($1.accessibilityIdentifier ?? "")
            }
        #expect(rechargePackageButtons.count == 6)
        let initialPackageFrames = rechargePackageButtons.map {
            $0.convert($0.bounds, to: rechargeViewController.view)
        }
        let packageWidths = initialPackageFrames.map(\.width)
        let packageHeights = initialPackageFrames.map(\.height)
        #expect((packageWidths.max() ?? 0) - (packageWidths.min() ?? 0) < 1)
        #expect((packageHeights.max() ?? 0) - (packageHeights.min() ?? 0) < 1)
        #expect(packageHeights.allSatisfy { abs($0 - 88) < 1 })
        #expect(rechargePackageButtons.allSatisfy { button in
            button.allSubviews(of: UILabel.self).allSatisfy {
                $0.numberOfLines == 1
                    && $0.frame.height <= $0.font.lineHeight + 1
            }
        })

        let largestPackageButton = try #require(
            rechargePackageButtons.first {
                $0.accessibilityIdentifier
                    == "liveRoom.recharge.package.64800"
            }
        )
        let recommendedPackageButton = try #require(
            rechargePackageButtons.first {
                $0.accessibilityIdentifier
                    == "liveRoom.recharge.package.30000"
            }
        )
        activate(largestPackageButton)
        rechargeViewController.view.layoutIfNeeded()
        let selectedPackageFrames = rechargePackageButtons.map {
            $0.convert($0.bounds, to: rechargeViewController.view)
        }
        #expect(zip(selectedPackageFrames, initialPackageFrames).allSatisfy {
            abs($0.minX - $1.minX) < 1
                && abs($0.minY - $1.minY) < 1
                && abs($0.width - $1.width) < 1
                && abs($0.height - $1.height) < 1
        })
        activate(recommendedPackageButton)
        rechargeViewController.view.layoutIfNeeded()
        #expect(rechargeViewController.selectedPackageAmount == 30_000)
        let rechargeBalanceLabel = try #require(
            rechargeViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.recharge.balance"
            }
        )
        let navigationBarFrame = navigationController.navigationBar.convert(
            navigationController.navigationBar.bounds,
            to: rechargeViewController.view
        )
        let rechargeBalanceFrame = rechargeBalanceLabel.convert(
            rechargeBalanceLabel.bounds,
            to: rechargeViewController.view
        )
        #expect(rechargeBalanceFrame.minY >= navigationBarFrame.maxY - 1)
        let rechargeButton = try #require(
            rechargeViewController.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.recharge.confirm"
            }
        )
        UIView.setAnimationsEnabled(true)
        activate(rechargeButton)
        #expect(rechargeViewController.currentBalance == 44_448)
        #expect(viewController.giftBalance == 44_448)
        #expect(rechargeViewController.rechargeSuccessAnimationCount == 1)
        #expect(
            rechargeViewController.rechargeStatusText
                == Localization.text("liveRoom.recharge.success", 32_400)
        )
        if !UIAccessibility.isReduceMotionEnabled {
            #expect(rechargeViewController.isRechargeSuccessAnimationVisible)
            #expect(!rechargeButton.isEnabled)
            #expect(await waitForCondition {
                !rechargeViewController.isRechargeSuccessAnimationVisible
                    && rechargeButton.isEnabled
            })
        }
        #expect(
            rechargeBalanceLabel.text
                == Localization.text(
                    "liveRoom.recharge.balance.value",
                    44_448
                )
        )
        UIView.setAnimationsEnabled(false)

        navigationController.popViewController(animated: false)
        #expect(navigationController.topViewController === viewController)
        activate(giftButton)
        let reopenedGiftSheet = try #require(
            viewController.giftSheetViewController
        )
        #expect(reopenedGiftSheet.giftBalance == 44_448)
        #expect(
            reopenedGiftSheet.balanceStatusText
                == Localization.text("liveRoom.gift.balance", 44_448)
        )
    }

    @Test func voiceRoomGiftCategoriesStayVisibleAndCenterAfterRepeatedDirectionChanges() throws {
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            Localization.setLocale(identifier: "en-US")
        }

        let viewModel = VoiceRoomViewModel()
        let giftSheet = GiftSheetViewController(
            recipients: viewModel.state.displayedSeats.filter(\.isOccupied)
        )
        let window = try makeVisibleTestWindow(
            rootViewController: giftSheet,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        for language in ["zh-Hans", "ar", "zh-Hans"] {
            Localization.setLocale(identifier: language)
            let direction: UIUserInterfaceLayoutDirection = language == "ar"
                ? .rightToLeft : .leftToRight
            window.semanticContentAttribute = direction == .rightToLeft
                ? .forceRightToLeft : .forceLeftToRight
            giftSheet.reloadLocalizedContent()
            giftSheet.reloadLayoutDirection(direction)
            giftSheet.view.setNeedsLayout()
            giftSheet.view.layoutIfNeeded()
            let scrollView = giftSheet.giftCategoryScrollView
            #expect(scrollView.effectiveUserInterfaceLayoutDirection == direction)
            #expect(scrollView.contentSize.width > scrollView.bounds.width)

            for category in ["collection", "party", "all", "party", "collection"] {
                let button = try #require(
                    giftSheet.view.allSubviews(of: CapsuleTextButton.self).first {
                        $0.accessibilityIdentifier == "liveRoom.gift.category.\(category)"
                    }
                )
                activate(button)
                giftSheet.view.layoutIfNeeded()
                scrollView.layoutIfNeeded()
                let frame = button.convert(button.bounds, to: scrollView)
                #expect(giftSheet.selectedGiftCategoryID == category)
                #expect(scrollView.bounds.contains(frame), "\(language): \(category)")
                if category == "party" {
                    #expect(abs(frame.midX - scrollView.bounds.midX) < 1,
                            "\(language): 中间栏目应在连续滚动后仍居中")
                }
            }
        }
    }

    @Test func voiceRoomGiftQuantityMenuUpdatesCostBalanceAndLayout() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        viewController.presentGiftSheet(
            initiallySelectedRecipientSeatIDs: [0, 1]
        )
        layout(viewController, in: navigationController)

        let giftSheet = try #require(
            viewController.giftSheetViewController
        )
        let quantityButton = try #require(
            giftSheet.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.quantity"
            }
        )
        let sendButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.send"
            }
        )

        #expect(giftSheet.selectedGiftQuantity == 1)
        #expect(
            giftSheet.giftQuantityValues
                == [1, 10, 30, 66, 188, 520, 1_314]
        )
        #expect(quantityButton.configuration?.title == "×1")
        #expect(sendButton.accessibilityLabel == "赠送")
        #expect(quantityButton.showsMenuAsPrimaryAction)
        let initialQuantityActions = try #require(
            quantityButton.menu?.children as? [UIAction]
        )
        #expect(initialQuantityActions.count == 7)
        #expect(
            initialQuantityActions.map(\.title) == [
                "1  一心一意",
                "10  十全十美",
                "30  闪闪发光",
                "66  一切顺利",
                "188  要抱抱",
                "520  我爱你",
                "1314  一生一世",
            ]
        )
        #expect(initialQuantityActions.first?.state == .on)
        #expect(!giftSheet.setSelectedGiftQuantity(2))
        #expect(giftSheet.selectedGiftQuantity == 1)

        #expect(giftSheet.setSelectedGiftQuantity(10))
        layout(viewController, in: navigationController)
        #expect(giftSheet.selectedGiftQuantity == 10)
        #expect(quantityButton.configuration?.title == "×10")
        #expect(sendButton.accessibilityLabel == "赠送")
        let selectedQuantityActions = try #require(
            quantityButton.menu?.children as? [UIAction]
        )
        #expect(
            selectedQuantityActions.first {
                $0.title.hasPrefix("10 ")
            }?.state == .on
        )

        let quantityFrame = quantityButton.convert(
            quantityButton.bounds,
            to: giftSheet.view
        )
        let sendFrame = sendButton.convert(
            sendButton.bounds,
            to: giftSheet.view
        )
        #expect(sendFrame.minX - quantityFrame.maxX >= 5)
        #expect(sendFrame.minX - quantityFrame.maxX <= 9)
        // 赠送按钮保持内容宽度，剩余空间由余额区域吸收。
        #expect(sendFrame.width < giftSheet.view.bounds.width * 0.50)

        activate(sendButton)
        #expect(viewController.giftDeliveryCount == 1)
        #expect(viewController.lastGiftQuantity == 10)
        #expect(viewController.lastGiftRecipientSeatIDs == [0, 1])
        #expect(viewController.giftBalance == 12_600)
        #expect(giftSheet.giftBalance == 12_600)
        #expect(
            giftSheet.balanceStatusText
                == Localization.text("liveRoom.gift.balance", 12_600)
        )

        #expect(giftSheet.setSelectedGiftQuantity(1_314))
        activate(sendButton)
        #expect(viewController.giftDeliveryCount == 1)
        #expect(viewController.giftBalance == 12_600)
        #expect(giftSheet.giftBalance == 12_600)
        #expect(
            giftSheet.balanceStatusText
                == Localization.text(
                    "liveRoom.gift.balance.insufficient",
                    12_600
                )
        )
        #expect(viewController.presentedViewController is UIAlertController)
    }

    @Test func voiceRoomGiftSheetMotionMovesFullyBelowContainer() {
        #expect(
            GiftSheetMotionMetrics.offscreenTranslation(
                sheetHeight: 420,
                safeAreaBottom: 0
            ) == 432
        )
        #expect(
            GiftSheetMotionMetrics.offscreenTranslation(
                sheetHeight: 520,
                safeAreaBottom: 34
            ) == 566
        )
    }

    @Test func voiceRoomGiftSheetFitsIPhoneSEAndCurrentFiveSeatState() async throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        applyVoiceRoomSnapshot(
            to: viewController,
            roomMode: .individual,
            audienceSeatState: .disabled
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 320, height: 568)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let giftButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.button"
            }
        )
        activate(giftButton)

        let giftSheet = try #require(
            viewController.giftSheetViewController
        )
        giftSheet.loadViewIfNeeded()
        giftSheet.view.frame = window.bounds
        giftSheet.view.setNeedsLayout()
        giftSheet.view.layoutIfNeeded()
        let sheetView = try #require(
            giftSheet.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.sheet"
            }
        )
        let sheetFrame = sheetView.convert(sheetView.bounds, to: window)
        let sheetBackgroundView = try #require(
            sheetView.allSubviews(of: QuickLayoutLinearGradientView.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.gift.sheet.backgroundGradient"
            }
        )
        #expect(viewController.presentedGiftRecipientSeatIDs == [0])
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
        #expect(giftSheet.giftColumnCount == 4)
        #expect(abs(sheetFrame.minX - window.bounds.minX) < 1)
        #expect(abs(sheetFrame.maxX - window.bounds.maxX) < 1)
        #expect(sheetFrame.minY >= window.bounds.minY)
        #expect(abs(sheetFrame.maxY - window.bounds.maxY) < 1)
        #expect(sheetBackgroundView.frame == sheetView.bounds)
        #expect(sheetBackgroundView.layer is CAGradientLayer)
        #expect(giftSheet.view.allSubviews(of: UIScrollView.self).count == 3)
        #expect(
            giftSheet.giftScrollView.contentSize.height
                > giftSheet.giftScrollView.bounds.height
        )

        #expect(
            giftSheet.view.allSubviews(of: UIControl.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.close"
            } == nil
        )
        let backdropButton = try #require(
            giftSheet.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.backdrop"
            }
        )
        let hostRecipientButton = try #require(
            giftSheet.view.allSubviews(of: GiftRecipientButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.0"
            }
        )
        activate(hostRecipientButton)
        #expect(giftSheet.selectedRecipientSeatIDs == [0])
        activate(hostRecipientButton)
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
        activate(backdropButton)
        #expect(await waitForCondition {
            viewController.giftSheetViewController == nil
                && giftSheet.parent == nil
        })
    }

    @Test func voiceRoomGiftRecipientListScrollsWhenUsersExceedViewport() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let recipients = (0..<12).map { index in
            SeatAssignment(
                id: index,
                nameKey: "liveRoom.user.host",
                avatarImageID: AvatarImageID.fixtures[
                    index % AvatarImageID.fixtures.count
                ],
                symbolName: "person.crop.circle.fill",
                themeIndex: index,
                score: 1_000 + index,
                isMuted: false,
                isOccupied: true
            )
        }
        let giftSheet = GiftSheetViewController(
            recipients: recipients
        )
        let window = try makeVisibleTestWindow(
            rootViewController: giftSheet,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        giftSheet.loadViewIfNeeded()
        giftSheet.view.frame = window.bounds
        giftSheet.view.setNeedsLayout()
        giftSheet.view.layoutIfNeeded()

        let recipientScrollView = giftSheet.recipientScrollView
        recipientScrollView.layoutIfNeeded()
        let selectAllButton = try #require(
            giftSheet.view.allSubviews(of: GiftSelectAllButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.selectAll"
            }
        )
        let lastRecipientButton = try #require(
            giftSheet.view.allSubviews(of: GiftRecipientButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipient.11"
            }
        )

        #expect(
            recipientScrollView.contentSize.width
                > recipientScrollView.bounds.width
        )
        #expect(!selectAllButton.isDescendant(of: recipientScrollView))
        #expect(lastRecipientButton.isDescendant(of: recipientScrollView))
        #expect(selectAllButton.isEnabled)

        let maximumOffsetX = max(
            -recipientScrollView.adjustedContentInset.left,
            recipientScrollView.contentSize.width
                - recipientScrollView.bounds.width
                + recipientScrollView.adjustedContentInset.right
        )
        recipientScrollView.setContentOffset(
            CGPoint(x: maximumOffsetX, y: 0),
            animated: false
        )
        #expect(recipientScrollView.contentOffset.x > 0)
    }

    @Test func voiceRoomGiftSheetAcceptsExternalRecipientSelection() throws {
        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        viewController.presentGiftSheet(
            initiallySelectedRecipientSeatIDs: [4, 2, 99, 4]
        )
        let giftSheet = try #require(
            viewController.giftSheetViewController
        )

        // 初始值与动态更新都只接受当前可送礼用户，并按麦位顺序输出。
        #expect(giftSheet.selectedRecipientSeatIDs == [2, 4])
        giftSheet.setSelectedRecipientSeatIDs([3, 99])
        #expect(giftSheet.selectedRecipientSeatIDs == [3])
        giftSheet.setSelectedRecipientSeatIDs([])
        #expect(giftSheet.selectedRecipientSeatIDs.isEmpty)
    }

    @Test func voiceRoomGiftGridExpandsColumnsInsideIPadContainer() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 768, height: 1_024)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let giftButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.button"
            }
        )
        activate(giftButton)

        let giftSheet = try #require(
            viewController.giftSheetViewController
        )
        giftSheet.loadViewIfNeeded()
        giftSheet.view.frame = window.bounds
        giftSheet.view.setNeedsLayout()
        giftSheet.view.layoutIfNeeded()

        #expect(giftSheet.giftCount == 18)
        #expect(giftSheet.giftColumnCount == 6)
        #expect(giftSheet.view.allSubviews(of: UIScrollView.self).count == 3)
        let categoryScrollView = giftSheet.giftCategoryScrollView
        let allCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: CapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.all"
            }
        )
        let allCategoryFrame = allCategoryButton.convert(
            allCategoryButton.bounds,
            to: categoryScrollView
        )
        #expect(
            categoryScrollView.contentSize.width
                <= categoryScrollView.bounds.width + 1
        )
        #expect(categoryScrollView.contentInset == .zero)
        #expect(categoryScrollView.contentOffset.x == 0)
        #expect(allCategoryFrame.midX < categoryScrollView.bounds.midX)
        #expect(
            giftSheet.giftScrollView.contentSize.height
                > giftSheet.giftScrollView.bounds.height
        )
    }

    @Test func voiceRoomGiftGridUsesFiveColumnsInsideMediumContainer() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = VoiceRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 500, height: 900)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let giftButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.button"
            }
        )
        activate(giftButton)

        let giftSheet = try #require(
            viewController.giftSheetViewController
        )
        giftSheet.loadViewIfNeeded()
        giftSheet.view.frame = window.bounds
        giftSheet.view.setNeedsLayout()
        giftSheet.view.layoutIfNeeded()

        #expect(giftSheet.giftColumnCount == 5)
        #expect(giftSheet.giftScrollView.contentSize.height > 0)
    }
}
