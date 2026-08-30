//
//  DemoTests.swift
//  DemoTests
//
//  Created by Sondra on 2025/12/26.
//

import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@testable import Demo

@MainActor
@Suite(.serialized)
struct DemoTests {

    @Test func liveRoomViewModelOwnsMessageGiftAndBalanceBusinessState() throws {
        let viewModel = LiveRoomViewModel(initialGiftBalance: 1_000)

        #expect(!viewModel.sendPublicMessage("   \n"))
        #expect(viewModel.sendPublicMessage("  你好  "))
        #expect(viewModel.sentPublicMessages == ["你好"])

        let recipient = try #require(
            viewModel.state.displayedSeats.first(where: { $0.isOccupied })
        )
        let gift = try #require(
            LiveRoomGift.catalog.first(where: { $0.id == "heart" })
        )
        let request = LiveRoomGiftSendRequest(
            gift: gift,
            recipients: [recipient],
            quantity: 10,
            totalCost: 100
        )

        #expect(viewModel.processGiftSendRequest(request) == 900)
        #expect(viewModel.giftBalance == 900)

        let invalidRequest = LiveRoomGiftSendRequest(
            gift: gift,
            recipients: [recipient],
            quantity: 10,
            totalCost: 99
        )
        #expect(viewModel.processGiftSendRequest(invalidRequest) == nil)
        #expect(viewModel.giftBalance == 900)
        #expect(viewModel.recharge(by: 100) == 1_000)
    }

    @Test func liveRoomAudienceViewModelNormalizesServerSnapshot() {
        let members = [
            LiveRoomAudienceMember(
                id: 8,
                displayName: "收听用户",
                avatarImageID: .two,
                themeIndex: 2,
                contributionScore: 9_999,
                presence: .listening
            ),
            LiveRoomAudienceMember(
                id: 2,
                displayName: "麦上用户",
                avatarImageID: .host,
                themeIndex: 0,
                contributionScore: 100,
                presence: .onMicrophone(seatNumber: 1)
            ),
            LiveRoomAudienceMember(
                id: 2,
                displayName: "重复用户",
                avatarImageID: .one,
                themeIndex: 1,
                contributionScore: 20_000,
                presence: .listening
            ),
        ]

        let viewModel = LiveRoomAudienceViewModel(
            totalCount: 1,
            members: members
        )

        #expect(viewModel.state.totalCount == 2)
        #expect(viewModel.state.members.map(\.id) == [2, 8])
    }

    @Test func liveRoomGiftSheetViewModelKeepsSelectionAndSendRules() throws {
        let recipients = LiveRoomViewModel().state.displayedSeats
            .filter(\.isOccupied)
        let viewModel = LiveRoomGiftSheetViewModel(
            recipients: recipients,
            gifts: LiveRoomGift.catalog,
            initiallySelectedRecipientSeatIDs: [],
            initialBalance: 1_000
        )

        #expect(viewModel.selectedRecipientIDs.isEmpty)
        guard case .recipientRequired = viewModel.makeSendDecision() else {
            Issue.record("未选择收礼人时不应生成赠送请求")
            return
        }
        #expect(viewModel.showsRecipientRequiredPrompt)

        let recipient = try #require(recipients.first)
        #expect(viewModel.toggleRecipient(id: recipient.id))
        #expect(viewModel.selectGiftQuantity(10))
        guard case let .ready(request) = viewModel.makeSendDecision() else {
            Issue.record("有效选择应生成赠送请求")
            return
        }
        #expect(request.quantity == 10)
        #expect(request.recipients.map(\.id) == [recipient.id])
        #expect(request.totalCost == 100)
    }

    @Test func liveRoomGiftRecipientsUpdateByStableUserID() throws {
        let recipients = LiveRoomViewModel().state.visibleRecipients
        let first = try #require(recipients.first)
        let second = try #require(recipients.dropFirst().first)
        let firstUserID = try #require(first.userID)
        let secondUserID = try #require(second.userID)
        let viewModel = LiveRoomGiftSheetViewModel(
            recipients: recipients,
            gifts: LiveRoomGift.catalog,
            initiallySelectedRecipientUserIDs: [firstUserID, secondUserID],
            initialBalance: 8_888
        )
        #expect(viewModel.selectGiftQuantity(66))
        let selectedGiftID = viewModel.selectedGiftID

        let movedSecond = LiveRoomSeatAssignment(
            seatID: LiveRoomSeatID(rawValue: "seat.moved"),
            slotID: .audience(4),
            position: .init(rawValue: 4),
            occupant: second.occupant,
            audioState: second.audioState,
            score: second.score
        )
        viewModel.updateRecipients([movedSecond])

        #expect(viewModel.recipients == [movedSecond])
        #expect(viewModel.selectedRecipientUserIDs == [secondUserID])
        #expect(!viewModel.selectedRecipientUserIDs.contains(firstUserID))
        #expect(viewModel.selectedGiftID == selectedGiftID)
        #expect(viewModel.selectedGiftQuantity == 66)
        #expect(viewModel.giftBalance == 8_888)
    }

    @Test func liveRoomRechargeViewModelCommitsConfirmedTransaction() throws {
        let viewModel = LiveRoomRechargeViewModel(
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

    @Test func liveRoomRechargeBalanceCardPreservesCompleteTextLines() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomRechargeViewController(
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
        #expect(abs(statusLabel.bounds.height - 20) < 1)
    }

    @Test func liveRoomRechargePackageGridAdaptsToContainerAndPackageCount() {
        let packageSectionView = LiveRoomRechargePackageSectionView(frame: .zero)
        let allPackages = (1...9).map {
            LiveRoomRechargePackage(amount: $0 * 1_000, bonus: $0 * 100)
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
                    $0 as? LiveRoomRechargePackageButton
                }.count == count)

                guard count > 0 else { continue }
                let expectedWidth = (
                    availableWidth - CGFloat(columns - 1) * 10
                ) / CGFloat(columns)
                #expect(packageSectionView.packageButtons.allSatisfy {
                    abs($0.frame.width - expectedWidth) < 1
                        && abs($0.frame.height - 88) < 1
                })

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

    @Test func liveRoomStageSnapshotsDriveBusinessLayouts() async {
        let viewModel = LiveRoomViewModel()
        let initialPartyAssignments = viewModel.state.snapshot.assignments
        let hostUserID = initialPartyAssignments.first?.userID

        #expect(viewModel.state.snapshot.businessMode == .party)
        #expect(viewModel.state.displayedSeats.count == 9)
        #expect(
            viewModel.state.displayedSeats.map(\.position.rawValue)
                == Array(0..<9)
        )
        let occupiedSeats = viewModel.state.displayedSeats.filter(\.isOccupied)
        let avatarImageIDs = occupiedSeats.compactMap(\.avatarImageID)
        #expect(occupiedSeats.count == 7)
        #expect(
            avatarImageIDs
                == [.host, .one, .two, .three, .four, .six, .seven]
        )
        #expect(Set(avatarImageIDs).count == occupiedSeats.count)
        #expect(occupiedSeats.allSatisfy { $0.avatarImage != nil })
        #expect(
            occupiedSeats.allSatisfy {
                $0.occupantNameKey?.hasPrefix("liveRoom.user.") == true
            }
        )
        #expect(
            viewModel.state.displayedSeats
                .filter { !$0.isOccupied }
                .map(\.position.rawValue) == [5, 8]
        )
        #expect(
            viewModel.state.displayedSeats
                .filter { !$0.isOccupied }
                .allSatisfy { $0.avatarImageID == nil }
        )

        #expect(
            await viewModel.performBusinessCommand(
                .switchRoomType(.individual)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 1)
        #expect(viewModel.state.snapshot.audienceSeatState == .disabled)
        #expect(viewModel.state.snapshot.assignments.count == 5)
        #expect(viewModel.state.snapshot.assignments.first?.userID == hostUserID)
        #expect(
            viewModel.state.snapshot.assignments.dropFirst().compactMap(\.userID)
                .map(\.rawValue)
                == (1...4).map { "individual.user.\($0)" }
        )

        #expect(
            await viewModel.performBusinessCommand(
                .setAudienceSeatsEnabled(true)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 5)
        #expect(
            viewModel.state.displayedSeats.compactMap(\.avatarImageID)
                == [.host, .five, .eight, .six, .seven]
        )
        #expect(
            viewModel.state.displayedSeats.compactMap(\.occupantNameKey)
                == [
                    "liveRoom.user.host",
                    "liveRoom.user.individual.1",
                    "liveRoom.user.individual.2",
                    "liveRoom.user.individual.3",
                    "liveRoom.user.individual.4",
                ]
        )

        #expect(
            await viewModel.performBusinessCommand(
                .setAudienceSeatsEnabled(false)
            )
        )
        #expect(viewModel.state.displayedSeats.count == 1)

        #expect(
            await viewModel.performBusinessCommand(.switchRoomType(.party))
        )
        #expect(viewModel.state.displayedSeats.count == 9)
        #expect(viewModel.state.snapshot.assignments == initialPartyAssignments)
    }

    @Test func liveRoomInitialIndividualSnapshotCanRestorePartyFixture() async {
        let viewModel = LiveRoomViewModel(
            stageSnapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                businessMode: .individual,
                audienceSeatState: .disabled
            )
        )

        #expect(viewModel.state.snapshot.assignments.count == 5)
        #expect(
            await viewModel.performBusinessCommand(.switchRoomType(.party))
        )
        #expect(
            viewModel.state.snapshot.assignments
                == LiveRoomViewModel.partyAssignments
        )
        #expect(viewModel.state.displayedSeats.count == 9)
    }

    @Test func liveRoomSeatMetricsRespondToWidthAndHeight() {
        let regularMinimumWidth = LiveRoomSeatLayoutMetrics
            .regularMinimumStageWidth

        #expect(regularMinimumWidth == 346)
        let regularMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: regularMinimumWidth,
            prefersCompactHeight: false
        )
        let narrowMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: regularMinimumWidth - 1,
            prefersCompactHeight: false
        )
        let shortMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: 620,
            prefersCompactHeight: true
        )
        let expandedMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: 620,
            prefersCompactHeight: false
        )
        let distributedPhoneMetrics = LiveRoomSeatLayoutMetrics.resolve(
            availableWidth: 402,
            prefersCompactHeight: false
        )

        #expect(regularMetrics.presentation == .regular)
        #expect(narrowMetrics.presentation == .compact)
        #expect(shortMetrics.presentation == .compact)
        #expect(expandedMetrics.presentation == .expanded)
        #expect(distributedPhoneMetrics.partyHorizontalSpacing == 28)
        #expect(
            distributedPhoneMetrics.partyHorizontalSpacing
                > LiveRoomSeatLayoutMetrics.regular
                    .partyHorizontalSpacing
        )
        #expect(expandedMetrics.partyHorizontalSpacing == 44)
    }

    @Test func liveRoomResolverMapsBusinessModeAndZeroBasedPositions() throws {
        let assignments = LiveRoomViewModel.partyAssignments
        let party = try LiveRoomSeatLayoutResolver.resolve(
            snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                businessMode: .party,
                audienceSeatState: .enabled,
                assignments: assignments
            )
        ).get()
        #expect(party.layoutID == .partyNine)
        #expect(party.variant == .standard)
        #expect(party.visibleSlots.count == 9)
        #expect(party.visibleSlots.map(\.position.rawValue) == Array(0..<9))
        #expect(party.visibleSlots[0].styleID == .standardHost)

        let collapsed = try LiveRoomSeatLayoutResolver.resolve(
            snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                businessMode: .individual,
                audienceSeatState: .disabled,
                assignments: LiveRoomViewModel.individualAssignments
            )
        ).get()
        #expect(collapsed.layoutID == .individualAudience)
        #expect(collapsed.variant == .collapsed)
        #expect(collapsed.visibleSlots.map(\.position.rawValue) == [0])
        #expect(collapsed.visibleSlots[0].styleID == .emphasizedHost)

        let expanded = try LiveRoomSeatLayoutResolver.resolve(
            snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                businessMode: .individual,
                audienceSeatState: .enabled,
                assignments: Array(
                    LiveRoomViewModel.individualAssignments.reversed()
                )
            )
        ).get()
        #expect(expanded.variant == .expanded)
        #expect(expanded.visibleSlots.map(\.position.rawValue) == Array(0..<5))
        #expect(
            expanded.visibleAssignments.map(\.position.rawValue) == Array(0..<5)
        )
    }

    @Test func liveRoomViewModelRejectsStaleAndUnsupportedSnapshots() {
        let viewModel = LiveRoomViewModel()
        let initial = viewModel.state

        #expect(!viewModel.consumeStageSnapshot(initial.snapshot))
        #expect(
            !viewModel.consumeStageSnapshot(
                LiveRoomStageSnapshot(
                    revision: initial.snapshot.revision + 1,
                    businessMode: .unsupported(rawValue: "future.video"),
                    audienceSeatState: .enabled,
                    assignments: initial.snapshot.assignments,
                    capabilities: []
                )
            )
        )
        #expect(viewModel.state.stagePresentation == initial.stagePresentation)
        #expect(viewModel.state.snapshot == initial.snapshot)
    }

    @Test func liveRoomBackendSnapshotStreamDrivesSeatUsers() async throws {
        let provider = TestLiveRoomStageSnapshotProvider()
        let viewModel = LiveRoomViewModel(stageSnapshotProvider: provider)
        var assignments = LiveRoomViewModel.partyAssignments
        let previous = assignments[1]
        let backendUser = LiveRoomSeatOccupant(
            userID: LiveRoomUserID(rawValue: "backend.user.9527"),
            nameKey: "liveRoom.user.party.4",
            avatarImageID: .four,
            symbolName: "person.crop.circle.fill",
            themeIndex: 7
        )
        assignments[1] = LiveRoomSeatAssignment(
            seatID: previous.seatID,
            slotID: previous.slotID,
            position: previous.position,
            occupant: backendUser,
            audioState: .muted,
            score: 9_527
        )

        viewModel.startObservingStageSnapshots()
        provider.yield(
            LiveRoomViewModel.makeDefaultStageSnapshot(
                revision: viewModel.state.snapshot.revision + 1,
                assignments: Array(assignments.reversed())
            )
        )

        #expect(
            await waitForCondition {
                viewModel.state.snapshot.revision == 2
            }
        )
        let renderedSeat = try #require(
            viewModel.state.displayedSeats.first {
                $0.position.rawValue == 1
            }
        )
        #expect(renderedSeat.userID == backendUser.userID)
        #expect(renderedSeat.avatarImageID == .four)
        #expect(renderedSeat.score == 9_527)
        #expect(renderedSeat.audioState == .muted)
        #expect(
            viewModel.state.displayedSeats.map(\.position.rawValue)
                == Array(0..<9)
        )

        provider.finish()
        viewModel.stopObservingStageSnapshots()
    }

    @Test func liveRoomResolverRejectsDuplicateAndInvalidPositions() {
        let assignments = LiveRoomViewModel.partyAssignments
        var duplicatePositions = assignments
        let source = assignments[1]
        duplicatePositions[1] = LiveRoomSeatAssignment(
            seatID: source.seatID,
            slotID: source.slotID,
            position: .init(rawValue: 0),
            occupant: source.occupant,
            audioState: source.audioState,
            score: source.score
        )
        let duplicateSnapshot = LiveRoomViewModel.makeDefaultStageSnapshot(
            assignments: duplicatePositions
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(snapshot: duplicateSnapshot)
                == .failure(.duplicatePosition)
        )

        var overflowingPositions = assignments
        let last = assignments[8]
        overflowingPositions[8] = LiveRoomSeatAssignment(
            seatID: last.seatID,
            slotID: last.slotID,
            position: .init(rawValue: 9),
            occupant: last.occupant,
            audioState: last.audioState,
            score: last.score
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(
                snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                    assignments: overflowingPositions
                )
            ) == .failure(.capacityExceeded)
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(
                snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                    businessMode: .individual,
                    assignments: assignments
                )
            ) == .failure(.capacityExceeded)
        )
    }

    @Test func liveRoomResolverRejectsInvalidOccupantAndVacancyData() throws {
        let assignments = LiveRoomViewModel.partyAssignments
        let occupied = assignments[1]
        let occupant = try #require(occupied.occupant)

        var emptyNameAssignments = assignments
        emptyNameAssignments[1] = LiveRoomSeatAssignment(
            seatID: occupied.seatID,
            slotID: occupied.slotID,
            position: occupied.position,
            occupant: LiveRoomSeatOccupant(
                userID: occupant.userID,
                nameKey: "  ",
                avatarImageID: occupant.avatarImageID,
                symbolName: occupant.symbolName,
                themeIndex: occupant.themeIndex
            ),
            audioState: occupied.audioState,
            score: occupied.score
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(
                snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                    assignments: emptyNameAssignments
                )
            ) == .failure(.invalidOccupantName)
        )

        var invalidVacancyAssignments = assignments
        let vacancy = assignments[5]
        invalidVacancyAssignments[5] = LiveRoomSeatAssignment(
            seatID: vacancy.seatID,
            slotID: vacancy.slotID,
            position: vacancy.position,
            occupant: nil,
            audioState: .active,
            score: 100
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(
                snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                    assignments: invalidVacancyAssignments
                )
            ) == .failure(.invalidVacancyState)
        )

        var invalidIDAssignments = assignments
        invalidIDAssignments[1] = LiveRoomSeatAssignment(
            seatID: LiveRoomSeatID(rawValue: ""),
            slotID: occupied.slotID,
            position: occupied.position,
            occupant: occupied.occupant,
            audioState: occupied.audioState,
            score: occupied.score
        )
        #expect(
            LiveRoomSeatLayoutResolver.resolve(
                snapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                    assignments: invalidIDAssignments
                )
            ) == .failure(.invalidStableID)
        )
    }

    @Test func liveRoomSeatLayoutsExpandOnIPadWidth() throws {
        let viewController = LiveRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 768, height: 1_024)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let seatViews = try (0..<9).map { index in
            try #require(
                viewController.view.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier == "liveRoom.seat.\(index)"
                }
            )
        }
        let seatFrames = seatViews.map {
            $0.convert($0.bounds, to: viewController.view)
        }

        #expect(seatFrames.allSatisfy { abs($0.width - 104) < 1 })
        #expect(seatFrames.dropFirst().prefix(4).allSatisfy {
            abs($0.minY - seatFrames[1].minY) < 1
        })
        #expect(seatFrames.dropFirst(5).allSatisfy {
            abs($0.minY - seatFrames[5].minY) < 1
        })
        #expect(seatFrames[5].minY > seatFrames[1].minY)

        applyLiveRoomSnapshot(
            to: viewController,
            businessMode: .individual,
            audienceSeatState: .enabled
        )
        layout(viewController, in: navigationController)
        let fiveSeatViews = try (0..<5).map { index in
            try #require(
                viewController.view.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier == "liveRoom.seat.\(index)"
                }
            )
        }
        let fiveSeatFrames = fiveSeatViews.map {
            $0.convert($0.bounds, to: viewController.view)
        }

        #expect(abs(fiveSeatFrames[0].width - 192) < 1)
        #expect(fiveSeatFrames.dropFirst().allSatisfy {
            abs($0.width - 104) < 1
        })
        #expect(fiveSeatFrames.dropFirst().allSatisfy {
            abs($0.minY - fiveSeatFrames[1].minY) < 1
        })
        #expect(fiveSeatFrames[0].width > fiveSeatFrames[1].width)
    }

    @Test func liveRoomPublicChatMessagesFillAvailableWidthOnIPad() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 768, height: 1_024)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let scrollView = viewController.publicChatScrollView
        let firstMessageLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.publicChat.message.0"
            }
        )
        let scrollFrame = scrollView.convert(
            scrollView.bounds,
            to: viewController.view
        )
        let messageFrame = firstMessageLabel.convert(
            firstMessageLabel.bounds,
            to: viewController.view
        )

        #expect(firstMessageLabel.textAlignment == .natural)
        #expect(abs(messageFrame.minX - scrollFrame.minX - 14) < 1)
        #expect(abs(scrollFrame.maxX - messageFrame.maxX - 14) < 1)
        #expect(messageFrame.width > scrollFrame.width * 0.9)
        #expect(
            viewController.view.allSubviews(of: UIScrollView.self)
                .filter(\.isScrollEnabled).count == 1
        )
    }

    @Test func liveRoomOccupiedSeatPresentsUserCardAndEmptySeatDoesNot() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let occupiedSeatButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.button.1"
            }
        )
        let emptySeatButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.button.5"
            }
        )

        #expect(occupiedSeatButton.isEnabled)
        #expect(!emptySeatButton.isEnabled)

        activate(emptySeatButton)
        #expect(viewController.presentedViewController == nil)

        activate(occupiedSeatButton)

        #expect(viewController.presentedUserCardSeatID == 1)
        let presentedViewController = try #require(
            viewController.presentedViewController
        )
        presentedViewController.loadViewIfNeeded()
        presentedViewController.view.frame = window.bounds
        presentedViewController.view.setNeedsLayout()
        presentedViewController.view.layoutIfNeeded()
        let userCardView = try #require(
            presentedViewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.container"
            }
        )
        let nameLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.name"
            }
        )
        let scoreLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.score"
            }
        )
        let microphoneLabel = try #require(
            presentedViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.microphone"
            }
        )
        let closeButton = try #require(
            presentedViewController.view
                .allSubviews(of: LiveRoomSymbolButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.userCard.close"
            }
        )

        #expect(
            nameLabel.text
                == DemoLocalization.text("liveRoom.user.party.1")
        )
        #expect(
            scoreLabel.text
                == DemoLocalization.text("liveRoom.seat.score", 3_820)
        )
        #expect(
            microphoneLabel.text
                == DemoLocalization.text("liveRoom.seat.speaking")
        )
        let scoreIntrinsicSize = scoreLabel.sizeThatFits(
            CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        #expect(scoreLabel.bounds.width - scoreIntrinsicSize.width >= 27)
        #expect(scoreLabel.bounds.height - scoreIntrinsicSize.height >= 11)
        #expect(closeButton.layer.cornerCurve == .circular)
        #expect(closeButton.bounds.width >= 32)
        #expect(closeButton.bounds.height >= 32)
        #expect(closeButton.bounds.width < 44)
        #expect(closeButton.bounds.height < 44)
        #expect(abs(closeButton.bounds.width - closeButton.bounds.height) < 1)
        #expect(
            abs(
                closeButton.layer.cornerRadius
                    - min(closeButton.bounds.width, closeButton.bounds.height) / 2
            ) < 0.5
        )
        let pointOutsideVisualBounds = CGPoint(
            x: -1,
            y: closeButton.bounds.midY
        )
        #expect(!closeButton.bounds.contains(pointOutsideVisualBounds))
        #expect(
            closeButton.point(inside: pointOutsideVisualBounds, with: nil)
        )
        #expect(userCardView.bounds.width <= 340)
        #expect(
            userCardView.convert(userCardView.bounds, to: window).minX >= 24
        )
    }

    @Test func liveRoomAudienceButtonPresentsAdaptiveSheet() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let members = Array(LiveRoomViewModel().state.audienceMembers.prefix(7))
        let viewModel = LiveRoomViewModel(
            audienceCount: 42,
            audienceMembers: members
        )
        let viewController = LiveRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let audienceButton = try #require(
            viewController.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.button"
            }
        )
        #expect(audienceButton.accessibilityLabel == "42 人在线")
        #expect(audienceButton.accessibilityHint == "查看当前在线用户")
        #expect(audienceButton.layer.cornerCurve == .circular)
        #expect(
            abs(
                audienceButton.layer.cornerRadius
                    - min(
                        audienceButton.bounds.width,
                        audienceButton.bounds.height
                    ) / 2
            ) < 0.5
        )
        let audiencePointOutsideVisualBounds = CGPoint(
            x: audienceButton.bounds.midX,
            y: -1
        )
        #expect(
            audienceButton.point(
                inside: audiencePointOutsideVisualBounds,
                with: nil
            )
        )

        activate(audienceButton)

        let sheetViewController = try #require(
            viewController.presentedViewController
                as? LiveRoomAudienceSheetViewController
        )
        sheetViewController.loadViewIfNeeded()
        sheetViewController.view.setNeedsLayout()
        sheetViewController.view.layoutIfNeeded()
        let audienceHeaderView = try #require(
            sheetViewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.header"
            }
        )
        let headerFrame = audienceHeaderView.convert(
            audienceHeaderView.bounds,
            to: sheetViewController.view
        )
        let safeAreaFrame = sheetViewController.view.safeAreaLayoutGuide
            .layoutFrame

        #expect(viewController.presentedAudienceMemberCount == 7)
        #expect(sheetViewController.totalCount == 42)
        #expect(headerFrame.minY >= safeAreaFrame.minY - 0.5)
        #expect(
            sheetViewController.sheetPresentationController?.detents.count
                == 2
        )
        #expect(
            sheetViewController.audienceCollectionView.numberOfItems(
                inSection: 0
            ) == 7
        )
        #expect(
            sheetViewController.audienceCollectionView
                .collectionViewLayout.collectionViewContentSize.height > 0
        )
        #expect(
            sheetViewController.audienceCollectionView
                .contentInsetAdjustmentBehavior == .always
        )
    }

    @Test func liveRoomAudienceItemPushesUserProfile() async throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let members = Array(LiveRoomViewModel().state.audienceMembers.prefix(7))
        let viewModel = LiveRoomViewModel(
            audienceCount: 42,
            audienceMembers: members
        )
        let viewController = LiveRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let audienceButton = try #require(
            viewController.view.allSubviews(of: QuickLayoutButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.audience.button"
            }
        )
        activate(audienceButton)

        let sheetViewController = try #require(
            viewController.presentedViewController
                as? LiveRoomAudienceSheetViewController
        )
        sheetViewController.loadViewIfNeeded()
        sheetViewController.view.frame = window.bounds
        sheetViewController.view.setNeedsLayout()
        sheetViewController.view.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let selectedMember = try #require(
            sheetViewController.viewModel.state.members.first
        )
        let memberCell = try #require(
            sheetViewController.audienceCollectionView.cellForItem(
                at: indexPath
            ) as? LiveRoomAudienceMemberCell
        )
        #expect(memberCell.accessibilityTraits.contains(.button))
        #expect(memberCell.accessibilityHint == "查看该用户的主页")

        sheetViewController.audienceCollectionView.delegate?
            .collectionView?(
                sheetViewController.audienceCollectionView,
                didSelectItemAt: indexPath
            )
        // dismiss completion 由 UIKit 投递；让出主线程后再校验导航结果。
        await Task.yield()

        let profileViewController = try #require(
            navigationController.topViewController
                as? LiveRoomAudienceProfileViewController
        )
        profileViewController.loadViewIfNeeded()
        layout(profileViewController, in: navigationController)

        #expect(viewController.presentedViewController == nil)
        #expect(viewController.audienceSheetViewController == nil)
        #expect(
            viewController.pushedAudienceProfileViewController
                === profileViewController
        )
        #expect(profileViewController.memberID == selectedMember.id)
        #expect(profileViewController.displayName == selectedMember.displayName)
        #expect(profileViewController.title == "用户主页")
        #expect(!profileViewController.navigationItem.hidesBackButton)

        let scrollFrame = profileViewController.profileScrollView.convert(
            profileViewController.profileScrollView.bounds,
            to: profileViewController.view
        )
        let safeAreaFrame = profileViewController.view.safeAreaLayoutGuide
            .layoutFrame
        #expect(scrollFrame.minY >= safeAreaFrame.minY - 0.5)
        #expect(scrollFrame.maxY <= safeAreaFrame.maxY + 0.5)

        let memberIDLabel = try #require(
            profileViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.audience.profile.memberID"
            }
        )
        #expect(memberIDLabel.text == String(selectedMember.id))

        DemoLocalization.setLocale(identifier: "ar")
        profileViewController.applyLocalization(
            DemoLocalization.currentUIKitUpdate
        )
        #expect(profileViewController.title == "الملف الشخصي")
        #expect(!profileViewController.navigationItem.hidesBackButton)
        #expect(profileViewController.navigationItem.leftBarButtonItem == nil)
        #expect(
            profileViewController.navigationItem.rightBarButtonItem?
                .accessibilityIdentifier == "demo.language.menu"
        )
    }

    @Test func liveRoomAvatarPushesInformationController() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let roomInformation = LiveRoomInformation(
            roomID: "TEST-9527",
            hostDisplayName: "测试主播"
        )
        let viewModel = LiveRoomViewModel(
            audienceCount: 42,
            roomInformation: roomInformation
        )
        let viewController = LiveRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)
        let avatarButton = try #require(
            viewController.view
                .allSubviews(of: LiveRoomSymbolButton.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.room.avatar.button"
            }
        )
        #expect(avatarButton.bounds.width >= 44)
        #expect(avatarButton.bounds.height >= 44)
        #expect(
            abs(
                avatarButton.layer.cornerRadius
                    - min(avatarButton.bounds.width, avatarButton.bounds.height) / 2
            ) < 0.5
        )
        #expect(avatarButton.accessibilityLabel == "直播间头像")
        #expect(avatarButton.accessibilityHint == "查看直播间信息")

        activate(avatarButton)

        let informationViewController = try #require(
            navigationController.topViewController
                as? LiveRoomInformationViewController
        )
        informationViewController.loadViewIfNeeded()
        layout(informationViewController, in: navigationController)

        #expect(navigationController.viewControllers.count == 2)
        #expect(
            viewController.pushedRoomInformationViewController
                === informationViewController
        )
        #expect(informationViewController.roomID == "TEST-9527")
        #expect(informationViewController.audienceCount == 42)
        #expect(informationViewController.title == "直播间信息")
        #expect(!informationViewController.navigationItem.hidesBackButton)

        let scrollFrame = informationViewController.informationScrollView
            .convert(
                informationViewController.informationScrollView.bounds,
                to: informationViewController.view
            )
        let safeAreaFrame = informationViewController.view
            .safeAreaLayoutGuide.layoutFrame
        #expect(scrollFrame.minY >= safeAreaFrame.minY - 0.5)
        #expect(scrollFrame.maxY <= safeAreaFrame.maxY + 0.5)

        let roomIDLabel = try #require(
            informationViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "liveRoom.information.roomID"
            }
        )
        let audienceLabel = try #require(
            informationViewController.view.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.information.audience"
            }
        )
        #expect(roomIDLabel.text == "TEST-9527")
        #expect(audienceLabel.text == "42 人在线")

        let profileLabels = try [
            "星光音乐小屋",
            "唱歌 · 聊天 · 遇见有趣的人",
            "直播中"
        ].map { text in
            try #require(
                informationViewController.view
                    .allSubviews(of: UILabel.self)
                    .first { $0.text == text }
            )
        }
        let profileHostView = try #require(profileLabels.first?.superview)
        for label in profileLabels {
            #expect(label.superview === profileHostView)
            #expect(label.bounds.height >= label.intrinsicContentSize.height - 0.5)
            #expect(label.frame.minY >= -0.5)
            #expect(label.frame.maxY <= profileHostView.bounds.height + 0.5)
        }

        DemoLocalization.setLocale(identifier: "ar")
        informationViewController.applyLocalization(
            DemoLocalization.currentUIKitUpdate
        )
        #expect(!informationViewController.navigationItem.hidesBackButton)
        #expect(informationViewController.navigationItem.leftBarButtonItem == nil)
        #expect(
            informationViewController.navigationItem.rightBarButtonItem?
                .accessibilityIdentifier == "demo.language.menu"
        )

        let poppedViewController = navigationController.popViewController(
            animated: false
        )
        #expect(poppedViewController === informationViewController)
        #expect(navigationController.topViewController === viewController)
    }

    @Test func liveRoomGiftFlowSelectsOccupiedRecipientAndCompletesFlight() async throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
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

        #expect(viewController.presentedGiftRecipientSeatIDs == [0, 1, 2, 3, 4])
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
                == DemoLocalization.text("liveRoom.gift.balance", 12_800)
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
                .allSubviews(of: LiveRoomCapsuleTextButton.self).filter {
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
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.luxury"
            }
        )
        let allCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.category.all"
            }
        )
        let collectionCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.gift.category.collection"
            }
        )
        let partyCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
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
        #expect(
            abs(collectionFrame.maxX - categoryScrollView.bounds.maxX) < 1
        )
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
        #expect(abs(allCategoryFrame.minX - categoryScrollView.bounds.minX) < 1)

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
                == DemoLocalization.text("liveRoom.gift.recipient.required")
        )
        activate(selectAllButton)
        #expect(giftSheet.selectedRecipientSeatIDs == [0, 1, 2, 3, 4, 6, 7])
        #expect(
            giftSheet.recipientStatusText
                == DemoLocalization.text("liveRoom.gift.recipient.count", 7)
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
            (selectAllButton as? LiveRoomGiftSelectAllButton)?.displayedTitle
                == DemoLocalization.text("liveRoom.gift.selectAll")
        )
        #expect(!selectAllButton.isDescendant(of: recipientScrollView))
        let recipientFogView = try #require(
            giftSheet.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.recipientFog"
            }
        )
        #expect(!recipientFogView.isUserInteractionEnabled)
        #expect(recipientFogView.frame.intersects(recipientScrollView.frame))
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
                == DemoLocalization.text("liveRoom.gift.balance", 12_424)
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
                == DemoLocalization.text(
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
                == DemoLocalization.text("liveRoom.recharge.alert.title")
        )
        #expect(rechargeAlert.actions.count == 2)
        #expect(
            rechargeAlert.actions.last?.title
                == DemoLocalization.text("liveRoom.recharge.alert.action")
        )
        viewController.proceedToRecharge()
        #expect(await waitForCondition {
            viewController.giftSheetViewController == nil
                && viewController.presentedViewController == nil
                && navigationController.topViewController
                    is LiveRoomRechargeViewController
        })

        let rechargeViewController = try #require(
            navigationController.topViewController
                as? LiveRoomRechargeViewController
        )
        rechargeViewController.loadViewIfNeeded()
        rechargeViewController.view.frame = window.bounds
        rechargeViewController.view.setNeedsLayout()
        rechargeViewController.view.layoutIfNeeded()
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
            .allSubviews(of: LiveRoomRechargePackageButton.self)
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
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
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
                == DemoLocalization.text("liveRoom.recharge.success", 32_400)
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
                == DemoLocalization.text(
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
                == DemoLocalization.text("liveRoom.gift.balance", 44_448)
        )
    }

    @Test func liveRoomGiftQuantityMenuUpdatesCostBalanceAndLayout() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
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
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
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
                == DemoLocalization.text("liveRoom.gift.balance", 12_600)
        )

        #expect(giftSheet.setSelectedGiftQuantity(1_314))
        activate(sendButton)
        #expect(viewController.giftDeliveryCount == 1)
        #expect(viewController.giftBalance == 12_600)
        #expect(giftSheet.giftBalance == 12_600)
        #expect(
            giftSheet.balanceStatusText
                == DemoLocalization.text(
                    "liveRoom.gift.balance.insufficient",
                    12_600
                )
        )
        #expect(viewController.presentedViewController is UIAlertController)
    }

    @Test func liveRoomGiftSheetMotionMovesFullyBelowContainer() {
        #expect(
            LiveRoomGiftSheetMotionMetrics.offscreenTranslation(
                sheetHeight: 420,
                safeAreaBottom: 0
            ) == 432
        )
        #expect(
            LiveRoomGiftSheetMotionMetrics.offscreenTranslation(
                sheetHeight: 520,
                safeAreaBottom: 34
            ) == 566
        )
    }

    @Test func liveRoomGiftSheetFitsIPhoneSEAndCurrentFiveSeatState() async throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
        applyLiveRoomSnapshot(
            to: viewController,
            businessMode: .individual,
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
            giftSheet.view.allSubviews(of: LiveRoomGiftRecipientButton.self).first {
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

    @Test func liveRoomGiftRecipientListScrollsWhenUsersExceedViewport() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let recipients = (0..<12).map { index in
            LiveRoomSeat(
                id: index,
                nameKey: "liveRoom.user.host",
                avatarImageID: LiveRoomAvatarImageID.fixtures[
                    index % LiveRoomAvatarImageID.fixtures.count
                ],
                symbolName: "person.crop.circle.fill",
                themeIndex: index,
                score: 1_000 + index,
                isMuted: false,
                isOccupied: true
            )
        }
        let giftSheet = LiveRoomGiftSheetViewController(
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
            giftSheet.view.allSubviews(of: LiveRoomGiftSelectAllButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.gift.selectAll"
            }
        )
        let lastRecipientButton = try #require(
            giftSheet.view.allSubviews(of: LiveRoomGiftRecipientButton.self).first {
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

    @Test func liveRoomGiftSheetAcceptsExternalRecipientSelection() throws {
        let viewController = LiveRoomViewController()
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

    @Test func liveRoomGiftGridExpandsColumnsInsideIPadContainer() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
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
        #expect(giftSheet.view.allSubviews(of: UIScrollView.self).count == 2)
        let categoryScrollView = giftSheet.giftCategoryScrollView
        let allCategoryButton = try #require(
            giftSheet.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
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

    @Test func liveRoomGiftGridUsesFiveColumnsInsideMediumContainer() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        let viewController = LiveRoomViewController()
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

    @Test func liveRoomNineSeatSecondRowKeepsTextAtIdealSize() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewModel = LiveRoomViewModel(
            stageSnapshot: LiveRoomViewModel.makeDefaultStageSnapshot(
                assignments: liveRoomAssignments(vacating: 6)
            )
        )
        let viewController = LiveRoomViewController(viewModel: viewModel)
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        for seatID in 1...4 {
            let seatView = try #require(
                viewController.view.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier == "liveRoom.seat.\(seatID)"
                }
            )
            let scoreLabel = try #require(
                seatView.allSubviews(of: UILabel.self).first {
                    $0.accessibilityIdentifier
                        == "liveRoom.seat.score.\(seatID)"
                }
            )
            let nameLabel = try #require(
                seatView.allSubviews(of: UILabel.self).first {
                    $0.accessibilityIdentifier
                        == "liveRoom.seat.name.\(seatID)"
                }
            )
            let interactionButton = try #require(
                seatView.allSubviews(of: QuickLayoutButton.self).first {
                    $0.accessibilityIdentifier
                        == "liveRoom.seat.button.\(seatID)"
                }
            )
            let waveformView = try #require(
                seatView.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier
                        == "liveRoom.seat.waveform.\(seatID)"
                }
            )
            let scoreIdealSize = scoreLabel.sizeThatFits(
                CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )
            let nameIdealSize = nameLabel.sizeThatFits(
                CGSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            )

            #expect(scoreLabel.bounds.width >= scoreIdealSize.width - 1)
            #expect(scoreLabel.bounds.height >= scoreIdealSize.height - 1)
            #expect(nameLabel.bounds.width >= nameIdealSize.width - 1)
            #expect(nameLabel.bounds.height >= nameIdealSize.height - 1)
            #expect(interactionButton.frame == seatView.bounds)
            if seatID == 3 {
                #expect(waveformView.isHidden)
                #expect(
                    waveformView.layer.sublayers?.allSatisfy {
                        $0.animationKeys()?.isEmpty != false
                    } == true
                )
            } else {
                #expect(!waveformView.isHidden)
                #expect(waveformView.layer.sublayers?.count == 3)
                if !UIAccessibility.isReduceMotionEnabled {
                    #expect(
                        waveformView.layer.sublayers?.allSatisfy {
                            $0.animationKeys()?.isEmpty == false
                        } == true
                    )
                }
            }
        }

        let emptyWaveformView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.waveform.6"
            }
        )
        #expect(emptyWaveformView.isHidden)
        #expect(
            emptyWaveformView.layer.sublayers?.allSatisfy {
                $0.animationKeys()?.isEmpty != false
            } == true
        )
    }

    @Test func liveRoomSeatNamesSeparateOccupantsFromVacantSlots() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomViewController(
            viewModel: LiveRoomViewModel()
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        func seatName(at position: Int) throws -> String? {
            let nameLabel = try #require(
                viewController.view.allSubviews(of: UILabel.self).first {
                    $0.accessibilityIdentifier
                        == "liveRoom.seat.name.\(position)"
                }
            )
            return nameLabel.text
        }

        #expect(
            try seatName(at: 6)
                == DemoLocalization.text("liveRoom.user.party.5")
        )
        #expect(
            try seatName(at: 7)
                == DemoLocalization.text("liveRoom.user.party.6")
        )
        #expect(
            try seatName(at: 5)
                == DemoLocalization.text("liveRoom.userCard.guestSeat", 5)
        )
        #expect(
            try seatName(at: 8)
                == DemoLocalization.text("liveRoom.seat.eight")
        )
    }

    @Test func liveRoomFiveSeatLayoutUsesLargeHostAndFitsNarrowScreen() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomViewController()
        applyLiveRoomSnapshot(
            to: viewController,
            businessMode: .individual,
            audienceSeatState: .enabled
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

        #expect(viewController.displayedSeatCount == 5)
        let scrollViews = viewController.view.allSubviews(of: UIScrollView.self)
        #expect(scrollViews.count == 2)
        #expect(scrollViews.contains { $0 === viewController.publicChatScrollView })
        let seatCollectionView = try #require(
            scrollViews.first {
                $0.accessibilityIdentifier == "liveRoom.seat.collection"
            } as? UICollectionView
        )
        #expect(!seatCollectionView.isScrollEnabled)
        #expect(
            viewController.publicChatScrollView.bounds.height > 0,
            "view=\(viewController.view.bounds), safe=\(viewController.view.safeAreaInsets), chat=\(viewController.publicChatScrollView.frame)"
        )
        #expect(
            viewController.publicChatScrollView.contentSize.height
                > viewController.publicChatScrollView.bounds.height
        )
        let moreButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.more.button"
            }
        )
        #expect(moreButton.showsMenuAsPrimaryAction)
        #expect(moreButton.menu?.children.count == 2)
        let stageView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.stage"
            }
        )
        let chatView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.publicChat.container"
            }
        )
        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let stageFrame = stageView.convert(stageView.bounds, to: viewController.view)
        let chatFrame = chatView.convert(chatView.bounds, to: viewController.view)
        let actionBarFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )
        #expect(chatFrame.height >= 0)
        #expect(abs(chatFrame.minY - stageFrame.maxY - 10) < 1)
        #expect(abs(actionBarFrame.minY - chatFrame.maxY - 10) < 1)
        let bottomSpacing = viewController.view.bounds.maxY
            - viewController.view.safeAreaInsets.bottom
            - actionBarFrame.maxY
        let expectedBottomSpacing = LiveRoomViewController
            .actionBarBottomSpacing(
                for: viewController.view.safeAreaInsets.bottom
            )
        #expect(
            abs(bottomSpacing - expectedBottomSpacing) < 1,
            "stage=\(stageFrame), chat=\(chatFrame), action=\(actionBarFrame), bottom=\(bottomSpacing)"
        )
        let seatViews = try (0..<5).map { index in
            try #require(
                viewController.view.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier == "liveRoom.seat.\(index)"
                }
            )
        }
        let seatFrames = seatViews.map { seatView in
            seatView.convert(seatView.bounds, to: viewController.view)
        }

        #expect(seatFrames[0].width > seatFrames[1].width)
        #expect(seatFrames[0].width >= 116)
        #expect(seatFrames.dropFirst().allSatisfy { $0.width >= 60 })
        #expect(
            seatFrames.allSatisfy {
                $0.minX >= -1 && $0.maxX <= viewController.view.bounds.width + 1
            }
        )
        #expect(seatFrames.dropFirst().allSatisfy {
            abs($0.minY - seatFrames[1].minY) < 1
        })

        applyLiveRoomSnapshot(
            to: viewController,
            businessMode: .party,
            audienceSeatState: .enabled
        )
        layout(viewController, in: navigationController)
        let nineSeatViews = try (0..<2).map { index in
            try #require(
                viewController.view.allSubviews(of: UIView.self).first {
                    $0.accessibilityIdentifier == "liveRoom.seat.\(index)"
                }
            )
        }
        let nineSeatFrames = nineSeatViews.map { seatView in
            seatView.convert(seatView.bounds, to: viewController.view)
        }
        #expect(viewController.displayedSeatCount == 9)
        #expect(abs(nineSeatFrames[0].width - nineSeatFrames[1].width) < 1)
        #expect(abs(nineSeatFrames[0].height - nineSeatFrames[1].height) < 1)
    }

    @Test func liveRoomMessageButtonSendsScrollsAndRemovesComposer() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 402, height: 874)
        )
        defer { window.isHidden = true }
        viewController.overrideUserInterfaceStyle = .dark

        layout(viewController, in: navigationController)
        let initialLatestMessage = viewController.latestPublicChatMessage
        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let defaultActionBarHeight = actionBarView.bounds.height
        let defaultControlIdentifiers: Set<String> = [
            "liveRoom.message.button",
            "liveRoom.microphone.button",
            "liveRoom.gift.button",
            "liveRoom.more.button",
        ]
        let defaultControlViews = viewController.view
            .allSubviews(of: UIControl.self)
            .filter {
                guard let identifier = $0.accessibilityIdentifier else {
                    return false
                }
                return defaultControlIdentifiers.contains(identifier)
            }
        #expect(defaultControlViews.count == defaultControlIdentifiers.count)
        #expect(
            defaultControlViews.allSatisfy {
                abs($0.bounds.height - 35) < 1
            }
        )
        let hostSeatView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.seat.0"
            }
        )
        let messageButton = try #require(
            viewController.view
                .allSubviews(of: LiveRoomIconTitleButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.button"
            }
        )
        activate(messageButton)
        layout(viewController, in: navigationController)

        #expect(viewController.isShowingMessageComposer)
        #expect(abs(actionBarView.bounds.height - defaultActionBarHeight) < 1)
        let hostSeatWidthBeforeKeyboard = hostSeatView.bounds.width
        let seatStageHeightBeforeKeyboard = viewController
            .seatStageView.bounds.height
        let messagesHeightBeforeKeyboard = viewController
            .messagesView.bounds.height
        let textField = try #require(
            viewController.view.allSubviews(of: UITextField.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.input"
            }
        )
        let inputContainer = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier
                    == "liveRoom.message.input.container"
            }
        )
        let sendButton = try #require(
            viewController.view
                .allSubviews(of: LiveRoomCapsuleTextButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.send"
            }
        )
        let cancelButton = try #require(
            viewController.view
                .allSubviews(of: LiveRoomSymbolButton.self).first {
                $0.accessibilityIdentifier == "liveRoom.message.cancel"
            }
        )

        let keyboardFrameInWindow = CGRect(
            x: 0,
            y: 534,
            width: window.bounds.width,
            height: window.bounds.height - 534
        )
        let keyboardFrameInScreen = window.convert(
            keyboardFrameInWindow,
            to: nil
        )
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameBeginUserInfoKey: CGRect(
                    x: 0,
                    y: window.bounds.maxY,
                    width: window.bounds.width,
                    height: 0
                ),
                UIResponder.keyboardFrameEndUserInfoKey: keyboardFrameInScreen,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.0,
                UIResponder.keyboardAnimationCurveUserInfoKey:
                    UInt(UIView.AnimationCurve.easeInOut.rawValue),
            ]
        )
        layout(viewController, in: navigationController)

        let textFieldFrame = textField.convert(
            textField.bounds,
            to: viewController.view
        )
        let inputContainerFrame = inputContainer.convert(
            inputContainer.bounds,
            to: viewController.view
        )
        let sendButtonFrame = sendButton.convert(
            sendButton.bounds,
            to: viewController.view
        )
        let cancelButtonFrame = cancelButton.convert(
            cancelButton.bounds,
            to: viewController.view
        )
        let keyboardTop = viewController.view.convert(
            keyboardFrameInScreen,
            from: nil
        ).minY

        #expect(textField.borderStyle == .none)
        #expect(textField.backgroundColor == .clear)
        #expect(textField.textColor == .white)
        #expect(textField.keyboardAppearance == .dark)
        #expect(abs(inputContainer.layer.cornerRadius - 8) < 0.5)
        #expect(
            inputContainer.layer.cornerRadius
                < inputContainerFrame.height / 2
        )
        #expect(inputContainer.clipsToBounds)
        #expect(inputContainerFrame.height >= 35)
        #expect(
            abs(textFieldFrame.height - inputContainerFrame.height) < 1
        )
        #expect(abs(sendButtonFrame.height - 35) < 1)
        #expect(abs(cancelButtonFrame.height - 35) < 1)
        #expect(abs(sendButton.layer.cornerRadius - 17.5) < 0.5)
        #expect(textFieldFrame.width >= 96)
        #expect(sendButtonFrame.minX - textFieldFrame.maxX >= 7)
        #expect(cancelButtonFrame.minX - sendButtonFrame.maxX >= 7)
        #expect(abs(textFieldFrame.midY - sendButtonFrame.midY) < 1)
        #expect(abs(sendButtonFrame.midY - cancelButtonFrame.midY) < 1)
        #expect(cancelButtonFrame.maxY <= keyboardTop - 7)
        #expect(
            abs(hostSeatView.bounds.width - hostSeatWidthBeforeKeyboard) < 1
        )
        #expect(
            abs(
                viewController.seatStageView.bounds.height
                    - seatStageHeightBeforeKeyboard
            ) < 1
        )
        #expect(
            abs(
                viewController.messagesView.bounds.height
                    - messagesHeightBeforeKeyboard
            ) < 1
        )
        #expect(!sendButton.isEnabled)
        #expect(sendButton.layer.borderWidth == 1)
        #expect((sendButton.backgroundColor?.cgColor.alpha ?? 0) >= 0.1)

        textField.text = "   "
        textField.sendActions(for: .editingChanged)
        #expect(!sendButton.isEnabled)
        activate(sendButton)
        layout(viewController, in: navigationController)
        #expect(viewController.isShowingMessageComposer)
        #expect(viewController.latestPublicChatMessage == initialLatestMessage)

        textField.text = "  新消息已发送  "
        textField.sendActions(for: .editingChanged)
        #expect(sendButton.isEnabled)
        #expect((sendButton.backgroundColor?.cgColor.alpha ?? 0) == 1)
        activate(sendButton)
        layout(viewController, in: navigationController)

        #expect(!viewController.isShowingMessageComposer)
        #expect(viewController.latestPublicChatMessage == "我：新消息已发送")
        #expect(
            !viewController.view.allSubviews(of: UITextField.self).contains {
                $0.accessibilityIdentifier == "liveRoom.message.input"
            }
        )
        #expect(
            viewController.view.allSubviews(of: QuickLayoutButton.self).contains {
                $0.accessibilityIdentifier == "liveRoom.message.button"
            }
        )

        let scrollView = viewController.publicChatScrollView
        let bottomOffset = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.contentInset.bottom
        )
        #expect(abs(scrollView.contentOffset.y - bottomOffset) < 1)
        #expect(
            viewController.view.allSubviews(of: UIScrollView.self)
                .filter(\.isScrollEnabled).count == 1
        )
    }

    @Test func liveRoomActionBarKeepsBottomSpacingOnIPhoneSESize() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = LiveRoomViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 375, height: 667)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let actionBarView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.actionBar"
            }
        )
        let chatView = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "liveRoom.publicChat.container"
            }
        )
        let actionBarFrame = actionBarView.convert(
            actionBarView.bounds,
            to: viewController.view
        )
        let chatFrame = chatView.convert(
            chatView.bounds,
            to: viewController.view
        )
        let safeAreaBottom = viewController.view.bounds.maxY
            - viewController.view.safeAreaInsets.bottom
        let bottomSpacing = safeAreaBottom - actionBarFrame.maxY
        let screenBottomSpacing = viewController.view.bounds.maxY
            - actionBarFrame.maxY
        let expectedBottomSpacing = LiveRoomViewController
            .actionBarBottomSpacing(
                for: viewController.view.safeAreaInsets.bottom
            )

        #expect(
            LiveRoomViewController.actionBarBottomSpacing(for: 0) == 8
        )
        #expect(
            LiveRoomViewController.actionBarBottomSpacing(for: 34) == 0
        )
        #expect(abs(bottomSpacing - expectedBottomSpacing) < 1)
        #expect(
            abs(
                screenBottomSpacing
                    - viewController.view.safeAreaInsets.bottom
                    - expectedBottomSpacing
            ) < 1
        )
        #expect(abs(actionBarFrame.minY - chatFrame.maxY - 10) < 1)
        #expect(
            viewController.view.allSubviews(of: UIScrollView.self)
                .filter(\.isScrollEnabled).count == 1
        )
    }

    @Test func safeAreaPaddingDemoCoversQuickLayoutCombinations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = SafeAreaPaddingDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        func expectPageInsets(
            _ expected: UIEdgeInsets,
            sourceLocation: SourceLocation = #_sourceLocation
        ) {
            let frame = viewController.pageScrollView.convert(
                viewController.pageScrollView.bounds,
                to: viewController.view
            )
            let bounds = viewController.view.bounds
            #expect(
                abs(frame.minX - expected.left) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(frame.minY - expected.top) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(bounds.maxX - frame.maxX - expected.right) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(bounds.maxY - frame.maxY - expected.bottom) < 1,
                sourceLocation: sourceLocation
            )
            #expect(
                abs(
                    viewController.pageScrollView.contentOffset.y
                        + viewController.pageScrollView
                            .adjustedContentInset.top
                ) < 1,
                sourceLocation: sourceLocation
            )
        }

        #expect(viewController.scenarioCount == 10)
        expectPageInsets(.zero)

        let safeArea = viewController.view.safeAreaInsets
        let safeAreaGuideView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutShapeView.self)
                .first {
                    $0.accessibilityIdentifier == "safeAreaPadding.guide"
                }
        )
        let safeAreaGuideLayer = try #require(
            safeAreaGuideView.layer as? CAShapeLayer
        )
        let guidePathBounds = try #require(
            safeAreaGuideLayer.path?.boundingBoxOfPath
        )
        let expectedGuideBounds = safeAreaGuideView.bounds.inset(
            by: safeAreaGuideView.safeAreaInsets
        )
        #expect(guidePathBounds.approximatelyEquals(expectedGuideBounds))
        #expect(safeAreaGuideLayer.lineDashPattern?.map(\.intValue) == [6, 4])

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.zeroAll.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(safeArea)

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.nilAll.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(safeArea)

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.allSixteen.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: safeArea.top + 16,
                left: safeArea.left + 16,
                bottom: safeArea.bottom + 16,
                right: safeArea.right + 16
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .perEdgeInsets.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: safeArea.top + 8,
                left: safeArea.left + 12,
                bottom: safeArea.bottom + 20,
                right: safeArea.right + 24
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .separateEdges.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 16,
                bottom: safeArea.bottom + 24,
                right: safeArea.right + 16
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .repeatedLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 20,
                bottom: 0,
                right: 0
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .leadingThenNil.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left + 8,
                bottom: 0,
                right: 0
            )
        )

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .negativeLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: safeArea.left,
                bottom: 0,
                right: 0
            )
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario
                .repeatedLeading.rawValue
        )
        layout(viewController, in: navigationController)
        expectPageInsets(
            UIEdgeInsets(
                top: 0,
                left: 0,
                bottom: 0,
                right: safeArea.right + 20
            )
        )
    }

    @Test func safeAreaPaddingDemoFollowsLandscapeSafeAreaChanges() throws {
        let viewController = SafeAreaPaddingDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        viewController.selectScenario(
            at: SafeAreaPaddingDemoViewController.Scenario.allSixteen.rawValue
        )
        layout(viewController, in: navigationController)

        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 62,
            bottom: 20,
            right: 62
        )
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        navigationController.view.frame = window.bounds
        layout(viewController, in: navigationController)

        let safeArea = viewController.view.safeAreaInsets
        let frame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        #expect(viewController.view.bounds.width > viewController.view.bounds.height)
        #expect(safeArea.left >= 62)
        #expect(safeArea.right >= 62)
        #expect(abs(frame.minX - safeArea.left - 16) < 1)
        #expect(abs(viewController.view.bounds.maxX - frame.maxX - safeArea.right - 16) < 1)
        #expect(abs(frame.minY - safeArea.top - 16) < 1)
        #expect(abs(viewController.view.bounds.maxY - frame.maxY - safeArea.bottom - 16) < 1)
        #expect(viewController.pageScrollView.contentSize.height > 0)
    }

    @Test func contentMarginsDemoCoversSwiftUIPlacementCombinations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = ContentMarginsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        #expect(viewController.scenarioCount == 9)
        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .explicitContentWithAutomaticBottom.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .sameScrollContentPlacement.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 16, bottom: 24, right: 16)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == .zero
        )

        viewController.selectScenario(
            at: ContentMarginsDemoViewController.Scenario
                .explicitContentReplacesAutomatic.rawValue
        )
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        layout(viewController, in: navigationController)

        #expect(
            viewController.previewScrollView.contentInset
                == UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        )
        #expect(
            viewController.previewScrollView.verticalScrollIndicatorInsets
                == UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)
        )
    }

    @Test func contentMarginsDemoRemainsReachableInLandscape() throws {
        let viewController = ContentMarginsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let pageScrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first { $0 !== viewController.previewScrollView }
        )
        #expect(viewController.previewScrollView.bounds.width > 600)
        #expect(
            viewController.previewScrollView.contentSize.height
                > viewController.previewScrollView.bounds.height
        )
        #expect(
            pageScrollView.contentSize.height > pageScrollView.bounds.height
        )
    }

    @Test func viewThatFitsDemoCoversSwiftUISelectionContract() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = ViewThatFitsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        #expect(viewController.scenarioCount == 6)
        #expect(viewController.selectedCandidateIdentifier == "B")

        for scenario in ViewThatFitsDemoViewController.Scenario.allCases {
            viewController.selectScenario(at: scenario.rawValue)
            layout(viewController, in: navigationController)

            let expectedCandidate = try #require(
                scenario.expectedCandidate(for: scenario.proposedSize)
            )

            #expect(
                viewController.selectedCandidateIdentifier
                    == expectedCandidate.identifier
            )
            #expect(
                viewController.selectedCandidateSize
                    == expectedCandidate.size
            )
            #expect(
                viewController.expectedCandidateIdentifier
                    == expectedCandidate.identifier
            )
            #expect(
                viewController.expectedLabel.text
                    == DemoLocalization.text(
                        "viewThatFits.expected",
                        expectedCandidate.identifier
                    )
            )
            #expect(
                viewController.metricsLabel.text
                    == DemoLocalization.text(
                        "viewThatFits.selected",
                        expectedCandidate.identifier
                    )
            )
            #expect(
                viewController.previewView.bounds.size
                    == scenario.proposedSize
            )
        }

        viewController.selectScenario(
            at: ViewThatFitsDemoViewController.Scenario
                .defaultBothAxes.rawValue
        )
        viewController.setProposedSize(CGSize(width: 300, height: 140))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "A")
        #expect(viewController.expectedCandidateIdentifier == "A")
        #expect(
            viewController.expectedLabel.text
                == DemoLocalization.text("viewThatFits.expected", "A")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 260, height: 120)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 300, height: 140)
        )

        viewController.setProposedSize(CGSize(width: 200, height: 100))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "B")
        #expect(viewController.expectedCandidateIdentifier == "B")
        #expect(
            viewController.expectedLabel.text
                == DemoLocalization.text("viewThatFits.expected", "B")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 180, height: 90)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 200, height: 100)
        )

        viewController.setProposedSize(CGSize(width: 90, height: 50))
        layout(viewController, in: navigationController)
        #expect(viewController.selectedCandidateIdentifier == "C")
        #expect(viewController.expectedCandidateIdentifier == "C")
        #expect(
            viewController.expectedLabel.text
                == DemoLocalization.text("viewThatFits.expected", "C")
        )
        #expect(
            viewController.selectedCandidateSize
                == CGSize(width: 100, height: 60)
        )
        #expect(
            viewController.previewView.bounds.size
                == CGSize(width: 90, height: 50)
        )

        viewController.selectScenario(
            at: ViewThatFitsDemoViewController.Scenario
                .horizontalOnly.rawValue
        )
        viewController.setProposedSize(CGSize(width: 151, height: 200))
        layout(viewController, in: navigationController)
        #expect(viewController.expectedCandidateIdentifier == "B")
        #expect(viewController.selectedCandidateIdentifier == "B")
        #expect(
            viewController.expectedLabel.text
                == DemoLocalization.text("viewThatFits.expected", "B")
        )
        #expect(
            viewController.metricsLabel.text
                == DemoLocalization.text("viewThatFits.selected", "B")
        )
    }

    @Test func viewThatFitsDemoRemainsScrollableInLandscape() throws {
        let viewController = ViewThatFitsDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        let scrollView = viewController.pageScrollView
        #expect(scrollView.bounds.width > scrollView.bounds.height)
        #expect(scrollView.contentSize.height > scrollView.bounds.height)
        #expect(
            viewController.previewView.bounds.size
                == viewController.proposedSize
        )

        let maximumOffset = max(
            0,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: maximumOffset),
            animated: false
        )
        scrollView.layoutIfNeeded()

        #expect(maximumOffset > 0)
        #expect(scrollView.contentOffset.y > 0)
    }

    @Test func positionAndZIndexDemoUsesPhysicalPointsAndLayerOrdering() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let viewController = PositionAndZIndexDemoViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }

        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.positionCanvas.layoutIfNeeded()
        viewController.zIndexCanvas.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        #expect(scrollView.contentInset.bottom == 24)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 24)
        #expect(scrollView.automaticallyAdjustsScrollIndicatorInsets)

        #expect(viewController.positionCanvas.bounds.width > 0)
        #expect(
            center(
                of: viewController.positionCanvas.firstBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 60, y: 54))
        )
        #expect(
            center(
                of: viewController.positionCanvas.centerBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 144, y: 100))
        )
        #expect(
            center(
                of: viewController.positionCanvas.lastBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 228, y: 146))
        )
        #expect(
            [
                viewController.positionCanvas.firstBadge,
                viewController.positionCanvas.centerBadge,
                viewController.positionCanvas.lastBadge,
            ].allSatisfy {
                $0.bounds.width >= $0.intrinsicContentSize.width + 27
                    && $0.bounds.height >= $0.intrinsicContentSize.height + 15
            }
        )

        #expect(viewController.zIndexCanvas.backCard.layer.zPosition == 0)
        #expect(viewController.zIndexCanvas.middleCard.layer.zPosition == 1)
        #expect(viewController.zIndexCanvas.frontCard.layer.zPosition == 3)
        #expect(
            [
                viewController.zIndexCanvas.backCard,
                viewController.zIndexCanvas.middleCard,
                viewController.zIndexCanvas.frontCard,
            ].allSatisfy {
                $0.bounds.width >= $0.intrinsicContentSize.width + 35
                    && $0.bounds.height >= $0.intrinsicContentSize.height + 23
            }
        )

        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 62,
            bottom: 20,
            right: 62
        )
        window.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        navigationController.view.frame = window.bounds
        layout(viewController, in: navigationController)

        #expect(viewController.view.bounds.width > viewController.view.bounds.height)
        #expect(scrollView.safeAreaInsets.left >= 62)
        #expect(scrollView.safeAreaInsets.right >= 62)
        #expect(scrollView.contentInset.bottom == 24)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 24)
        #expect(scrollView.automaticallyAdjustsScrollIndicatorInsets)

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.positionCanvas.layoutIfNeeded()

        #expect(
            center(
                of: viewController.positionCanvas.centerBadge,
                in: viewController.positionCanvas
            ).approximatelyEquals(CGPoint(x: 144, y: 100))
        )
    }

    private func layout(
        _ viewController: DemoQuickLayoutHostingController,
        in navigationController: UINavigationController
    ) {
        navigationController.view.setNeedsLayout()
        navigationController.view.layoutIfNeeded()
        viewController.setNeedsQuickLayout()
        viewController.quickLayoutIfNeeded()
        viewController.view.layoutIfNeeded()
    }

    @Test func quickLayoutViewMeasuresHostedContent() {
        let label = UILabel()
        label.text = "QuickLayoutKit"
        label.font = .systemFont(ofSize: 17)

        let hostingView = QuickLayoutView {
            label
                .padding(.all, 12)
        }

        let measuredSize = hostingView.sizeThatFits(in: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude))

        #expect(measuredSize.width > 0)
        #expect(measuredSize.height > 17)
    }

    @Test func hostingControllerUsesReusableQuickLayoutView() {
        let label = UILabel()
        label.text = "Hosted"

        let viewController = QuickLayoutHostingController {
            label
                .padding(.all, 8)
        }

        viewController.loadViewIfNeeded()

        #expect(viewController.view is QuickLayoutView)
        #expect(viewController.sizeThatFits(in: CGSize(width: 200, height: CGFloat.greatestFiniteMagnitude)).height > 0)
    }

    @Test func dashboardPresentsRealContentAndScrollsOnCompactScreens() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 320, height: 568)
        )
        defer {
            window.isHidden = true
        }

        navigationController.view.setNeedsLayout()
        navigationController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let contentCards = [
            viewController.profileCardView,
            viewController.weeklyGoalCardView,
            viewController.activityCardView,
        ]

        #expect(viewController.dashboardMetricViews.count == 3)
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.superview != nil
                    && $0.bounds.width > 0
                    && $0.bounds.height >= 126
            }
        )
        let metricFrames = viewController.dashboardMetricViews
            .map { $0.convert($0.bounds, to: viewController.scrollView) }
            .sorted { $0.minX < $1.minX }
        let visibleMetricFrames = viewController.dashboardMetricBackgroundViews
            .map { $0.convert($0.bounds, to: viewController.scrollView) }
            .sorted { $0.minX < $1.minX }
        let profileFrame = viewController.profileCardView.convert(
            viewController.profileCardView.bounds,
            to: viewController.scrollView
        )
        let weeklyGoalFrame = viewController.weeklyGoalCardView.convert(
            viewController.weeklyGoalCardView.bounds,
            to: viewController.scrollView
        )
        #expect(abs(metricFrames[0].width - metricFrames[1].width) < 1)
        #expect(abs(metricFrames[1].width - metricFrames[2].width) < 1)
        #expect(abs(metricFrames[1].minX - metricFrames[0].maxX - 10) < 1)
        #expect(abs(metricFrames[2].minX - metricFrames[1].maxX - 10) < 1)
        #expect(abs(metricFrames[0].minX - profileFrame.minX) < 1)
        #expect(abs(metricFrames[2].maxX - profileFrame.maxX) < 1)
        #expect(abs(weeklyGoalFrame.minX - profileFrame.minX) < 1)
        #expect(abs(weeklyGoalFrame.maxX - profileFrame.maxX) < 1)
        #expect(
            zip(metricFrames, visibleMetricFrames).allSatisfy { pair in
                abs(pair.0.width - pair.1.width) < 1
                    && abs(pair.0.minX - pair.1.minX) < 1
                    && abs(pair.0.maxX - pair.1.maxX) < 1
            }
        )
        #expect(
            contentCards.allSatisfy {
                $0.superview != nil
                    && $0.bounds.width > 0
                    && $0.bounds.height > 0
            }
        )
        #expect(
            viewController.scrollView.contentSize.height
                > viewController.scrollView.bounds.height
        )
        #expect(viewController.weeklyProgressView.progress == 0.72)
        #expect(
            viewController.weeklyProgressLabel.text
                == DemoLocalization.text("dashboard.weekly.progress")
        )
        #expect(
            viewController.recentActivityLabel.text
                == DemoLocalization.text("dashboard.activity.title")
        )
    }

    @Test func dashboardMirrorsOwnedContentAndRecoversLTR() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
        }

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let rtlMetricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }
        #expect(
            viewController.scrollView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )
        #expect(
            viewController.weeklyGoalCardView
                .effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(
            viewController.weeklyProgressView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(viewController.weeklyProgressView.transform.a == -1)
        #expect(viewController.weeklyProgressView.transform.d == 1)
        #expect(rtlMetricFrames[0].minX > rtlMetricFrames[2].minX)

        window.semanticContentAttribute = .forceLeftToRight
        viewController.reloadLayoutDirection(.leftToRight)
        navigationController.view.layoutIfNeeded()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let ltrMetricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }
        #expect(
            viewController.scrollView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(
            viewController.dashboardMetricViews.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .leftToRight
            }
        )
        #expect(
            viewController.weeklyGoalCardView
                .effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(
            viewController.weeklyProgressView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(viewController.weeklyProgressView.transform == .identity)
        #expect(ltrMetricFrames[0].minX < ltrMetricFrames[2].minX)
    }

    @Test func dashboardStacksMetricsForAccessibilityTextSizes() throws {
        let viewController = DashboardViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 320, height: 568)
        )
        defer {
            window.isHidden = true
        }

        viewController.traitOverrides.preferredContentSizeCategory =
            .accessibilityExtraExtraExtraLarge
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let metricFrames = viewController.dashboardMetricViews.map {
            $0.convert($0.bounds, to: viewController.scrollView)
        }

        #expect(metricFrames[0].minY < metricFrames[1].minY)
        #expect(metricFrames[1].minY < metricFrames[2].minY)
        #expect(
            metricFrames.allSatisfy {
                abs($0.width - metricFrames[0].width) < 1
                    && abs($0.minX - metricFrames[0].minX) < 1
            }
        )
        #expect(
            viewController.scrollView.contentSize.height
                > viewController.scrollView.bounds.height
        )
    }

    @Test func scrollViewInitializerConfiguresContentAndIndicators() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.vertical, showsIndicators: false) {
            first.frame(height: 120)
            second.frame(height: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.layoutIfNeeded()
        scrollView.scrollTo(.bottom, animated: false)

        #expect(scrollView.axis == .vertical)
        #expect(first.superview === scrollView)
        #expect(second.superview === scrollView)
        #expect(!scrollView.showsVerticalScrollIndicator)
        #expect(!scrollView.showsHorizontalScrollIndicator)
        #expect(scrollView.contentSize.height >= 240)
        #expect(scrollView.contentOffset.y > 0)
    }

    @Test func verticalScrollViewCentersContentOnItsCrossAxis() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(.vertical) {
            item.frame(width: 40, height: 40)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.semanticContentAttribute = .forceRightToLeft

        scrollView.layoutIfNeeded()

        #expect(item.frame.midX == scrollView.bounds.midX)
        #expect(scrollView.contentSize.width == scrollView.bounds.width)
    }

    @Test func horizontalScrollViewAppliesViewportHeightOnItsCrossAxis() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            item.frame(width: 40, height: 40)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(item.frame.midY == scrollView.bounds.midY)
        #expect(scrollView.contentSize.height == scrollView.bounds.height)
    }

    @Test func directVerticalScrollViewStacksAndCentersMultipleRootElements() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.vertical) {
            first.frame(width: 30, height: 140)
            second.frame(width: 50, height: 90)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 7,
            left: 0,
            bottom: 13,
            right: 0
        )
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(first.frame.maxY == second.frame.minY)
        #expect(first.frame.midX == scrollView.bounds.midX)
        #expect(second.frame.midX == scrollView.bounds.midX)
        #expect(scrollView.contentSize == CGSize(width: 100, height: 230))

        scrollView.scrollTo(.top, animated: false)
        #expect(scrollView.contentOffset.y == -7)

        scrollView.scrollTo(.bottom, animated: false)
        #expect(scrollView.contentOffset.y == 143)
    }

    @Test func directHorizontalScrollViewStacksAndCentersMultipleRootElements() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 140, height: 30)
            second.frame(width: 90, height: 50)
        }
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = UIEdgeInsets(
            top: 0,
            left: 11,
            bottom: 0,
            right: 17
        )
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)

        scrollView.layoutIfNeeded()

        #expect(first.frame.maxX == second.frame.minX)
        #expect(first.frame.midY == scrollView.bounds.midY)
        #expect(second.frame.midY == scrollView.bounds.midY)
        #expect(scrollView.contentSize == CGSize(width: 230, height: 100))

        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == -11)

        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == 147)
    }

    @Test func scrollViewLayoutFunctionUpdatesExistingUIKitInstance() {
        let item = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        _ = ScrollView(scrollView, .horizontal, showsIndicators: false) {
            item.frame(width: 240)
        }
        scrollView.layoutIfNeeded()

        #expect(scrollView.axis == .horizontal)
        #expect(item.superview === scrollView)
        #expect(!scrollView.showsHorizontalScrollIndicator)
        #expect(scrollView.contentSize.width >= 240)
    }

    @Test func horizontalScrollEdgesFollowSemanticDirection() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.layoutIfNeeded()

        let leadingLTR = -scrollView.adjustedContentInset.left
        let trailingLTR = max(
            leadingLTR,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )

        scrollView.semanticContentAttribute = .forceLeftToRight
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == leadingLTR)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == trailingLTR)

        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)
        #expect(scrollView.contentOffset.x == trailingLTR)
        scrollView.scrollTo(.trailing, animated: false)
        #expect(scrollView.contentOffset.x == leadingLTR)
    }

    @Test func horizontalScrollViewAppliesRTLDirectionToContentLayout() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(.horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.semanticContentAttribute = .forceRightToLeft

        scrollView.layoutIfNeeded()

        #expect(first.frame.minX > second.frame.minX)
    }

    @Test func horizontalScrollViewDefersRTLBeginningUntilContentIsMeasured() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.axis = .horizontal
        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)

        _ = ScrollView(scrollView, .horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }
        scrollView.layoutIfNeeded()

        let expectedOffset = max(
            -scrollView.adjustedContentInset.left,
            scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
        )
        #expect(scrollView.contentOffset.x == expectedOffset)
    }

    @Test func horizontalScrollDemoStartsFromRightInRTL() {
        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let firstCardFrame = viewController.views[0].convert(
            viewController.views[0].bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )
        #expect(firstCardFrame.maxX <= visibleRect.maxX)
        #expect(firstCardFrame.maxX > visibleRect.maxX - 80)
    }

    @Test func pendingInitialScrollDoesNotAnimateInsideUIKitAnimationContext() {
        let first = UIView()
        let second = UIView()
        let scrollView = QuickLayoutScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.axis = .horizontal
        scrollView.semanticContentAttribute = .forceRightToLeft
        scrollView.scrollTo(.leading, animated: false)

        _ = ScrollView(scrollView, .horizontal) {
            first.frame(width: 120)
            second.frame(width: 120)
        }

        UIView.animate(withDuration: 0.25) {
            scrollView.layoutIfNeeded()
        }

        let animationKeys = scrollView.layer.animationKeys() ?? []

        #expect(!animationKeys.contains("bounds"))
        #expect(!animationKeys.contains("position"))
    }

    @Test func horizontalScrollDemoPreparesRTLStartBeforeAppearAnimation() {
        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLayoutDirection(.rightToLeft)

        viewController.beginAppearanceTransition(true, animated: true)
        viewController.endAppearanceTransition()

        #expect(viewController.scrollView.contentOffset.x > 0)
    }

    @Test func horizontalScrollDemoUsesViewportRelativeCards() {
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.pageScrollView.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let firstCard = viewController.views[0]
        let contentViewportWidth = viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.left
            - viewController.scrollView.adjustedContentInset.right
        let expectedWidth = HorizontalCarouselLayoutMetrics.cardWidth(
            for: contentViewportWidth
        )
        let expectedCornerRadius = min(24, max(12, expectedWidth * 0.08))
        let portraitHeight = firstCard.bounds.height
        let portraitCardHeights = viewController.views.map(\.bounds.height)
        let portraitNaturalHeight = viewController.views.map {
            $0.sizeThatFits(
                CGSize(width: $0.bounds.width, height: .infinity)
            ).height
        }.max() ?? 0
        let secondCard = viewController.views[1]
        let secondCardFrame = secondCard.convert(
            secondCard.bounds,
            to: viewController.scrollView
        )
        let visibleTrailingEdge = viewController.scrollView.contentOffset.x
            + viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.right
        let visibleSecondCardWidth = visibleTrailingEdge
            - secondCardFrame.minX

        #expect(viewController.scrollView.contentInset.left == 16)
        #expect(viewController.scrollView.contentInset.right == 16)
        #expect(viewController.scrollView.contentOffset.x == -16)
        #expect(
            HorizontalCarouselLayoutMetrics.visibleCardCount(
                for: contentViewportWidth
            ) == 1
        )
        #expect(abs(firstCard.bounds.width - expectedWidth) < 1)
        #expect(firstCard.bounds.width < contentViewportWidth)
        #expect(
            abs(
                visibleSecondCardWidth
                    - HorizontalCarouselLayoutMetrics.nextCardPreviewWidth
            ) < 1
        )
        #expect(portraitHeight > 0)
        #expect(
            (portraitCardHeights.max() ?? 0)
                - (portraitCardHeights.min() ?? 0) < 1
        )
        #expect((portraitCardHeights.min() ?? 0) >= portraitNaturalHeight - 1)
        #expect(
            viewController.views.allSatisfy { cardView in
                (cardView.subviews.map(\.frame.minY).min() ?? 0) < 1
            }
        )
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(abs(firstCard.layer.cornerRadius - expectedCornerRadius) < 1)

        viewController.view.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.pageScrollView.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let landscapeViewportWidth = viewController.scrollView.bounds.width
            - viewController.scrollView.adjustedContentInset.left
            - viewController.scrollView.adjustedContentInset.right
        let expectedLandscapeWidth = HorizontalCarouselLayoutMetrics.cardWidth(
            for: landscapeViewportWidth
        )
        let landscapeCardHeights = viewController.views.map(\.bounds.height)
        let landscapeNaturalHeight = viewController.views.map {
            $0.sizeThatFits(
                CGSize(width: $0.bounds.width, height: .infinity)
            ).height
        }.max() ?? 0

        #expect(
            HorizontalCarouselLayoutMetrics.visibleCardCount(
                for: landscapeViewportWidth
            ) == 2
        )
        #expect(abs(firstCard.bounds.width - expectedLandscapeWidth) < 1)
        #expect(firstCard.bounds.height > 0)
        #expect(
            (landscapeCardHeights.max() ?? 0)
                - (landscapeCardHeights.min() ?? 0) < 1
        )
        #expect(
            (landscapeCardHeights.min() ?? 0) >= landscapeNaturalHeight - 1
        )
        #expect(
            viewController.views.allSatisfy { cardView in
                (cardView.subviews.map(\.frame.minY).min() ?? 0) < 1
            }
        )
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(firstCard.layer.cornerRadius == 24)
        #expect(
            viewController.pageScrollView.contentSize.height
                > viewController.pageScrollView.bounds.height
        )
    }

    @Test func horizontalDestinationCardHeightFollowsItsContent() {
        let cardView = HorizontalDestinationCardView(palette: .lakeside)
        #expect(cardView.quickLayoutHorizontalFlexibility == .fullyFlexible)
        #expect(cardView.quickLayoutVerticalFlexibility == .fixedSize)
        let baseContent = HorizontalDestinationCardContent(
            tag: "2 day trip",
            title: "Lakeside weekend",
            location: "Hangzhou",
            summary: "A short destination summary.",
            rating: "4.9",
            price: "$120",
            priceCaption: "From",
            accessibilityHint: "Open destination"
        )
        cardView.configure(baseContent)

        let shortHeight = cardView.sizeThatFits(
            CGSize(width: 280, height: CGFloat.infinity)
        ).height

        cardView.configure(
            HorizontalDestinationCardContent(
                tag: baseContent.tag,
                title: "A lakeside weekend with a deliberately longer title",
                location: baseContent.location,
                summary: Array(
                    repeating: "Localized details should determine height.",
                    count: 5
                ).joined(separator: " "),
                rating: baseContent.rating,
                price: baseContent.price,
                priceCaption: baseContent.priceCaption,
                accessibilityHint: baseContent.accessibilityHint
            )
        )

        let longHeight = cardView.sizeThatFits(
            CGSize(width: 280, height: CGFloat.infinity)
        ).height

        #expect(shortHeight > 0)
        #expect(longHeight > shortHeight)
    }

    @Test func horizontalScrollDemoHasContentOnFirstNavigationLayout() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let rootViewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: rootViewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
        }

        let viewController = HorizontalScrollViewViewController()
        navigationController.pushViewController(
            viewController,
            animated: false
        )
        window.layoutIfNeeded()

        #expect(viewController.pageScrollView.bounds.width > 0)
        #expect(viewController.scrollView.bounds.height > 0)
        #expect(viewController.views.first?.bounds.height ?? 0 > 0)
    }

    @Test func horizontalScrollDemoKeepsLandscapeContentInsideSafeArea() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        viewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 47,
            bottom: 21,
            right: 59
        )
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 844, height: 390)
        )
        defer {
            window.isHidden = true
        }

        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let safeAreaInsets = viewController.view.safeAreaInsets
        let pageFrame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        let carouselFrame = viewController.scrollView.convert(
            viewController.scrollView.bounds,
            to: viewController.view
        )

        #expect(pageFrame.approximatelyEquals(viewController.view.bounds))
        #expect(abs(carouselFrame.minX - pageFrame.minX) < 1)
        #expect(abs(carouselFrame.maxX - pageFrame.maxX) < 1)
        #expect(
            viewController.scrollView.adjustedContentInset.left
                >= safeAreaInsets.left + 16
        )
        #expect(
            viewController.scrollView.adjustedContentInset.right
                >= safeAreaInsets.right + 16
        )

        let ltrFirstCard = try #require(viewController.views.first)
        let ltrFirstCardFrame = ltrFirstCard.convert(
            ltrFirstCard.bounds,
            to: viewController.view
        )
        #expect(ltrFirstCardFrame.minX >= safeAreaInsets.left + 16 - 1)

        let labels = viewController.view.allSubviews(of: UILabel.self)
        let headlineLabel = try #require(
            labels.first {
                $0.text == DemoLocalization.text("horizontal.explore.headline")
            }
        )
        let footerLabel = try #require(
            labels.first {
                $0.text == DemoLocalization.text("horizontal.explore.hint")
            }
        )
        let headlineFrame = headlineLabel.convert(
            headlineLabel.bounds,
            to: viewController.view
        )
        #expect(headlineFrame.minX >= safeAreaInsets.left + 20 - 1)
        #expect(
            headlineFrame.maxX
                <= viewController.view.bounds.maxX
                    - safeAreaInsets.right
                    - 20
                    + 1
        )

        viewController.pageScrollView.scrollTo(.bottom, animated: false)
        viewController.pageScrollView.layoutIfNeeded()
        let footerFrame = footerLabel.convert(
            footerLabel.bounds,
            to: viewController.view
        )
        #expect(footerFrame.minX >= safeAreaInsets.left + 20 - 1)
        #expect(
            footerFrame.maxY
                <= viewController.view.bounds.maxY
                    - safeAreaInsets.bottom
                    + 1
        )

        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let firstCard = try #require(viewController.views.first)
        let firstCardFrame = firstCard.convert(
            firstCard.bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )
        let expectedTrailingEdge = visibleRect.maxX
            - viewController.scrollView.adjustedContentInset.right
        let artworkView = try #require(
            firstCard.allSubviews(of: QuickLayoutLinearGradientView.self).first
        )
        let artworkFrame = artworkView.convert(artworkView.bounds, to: firstCard)

        #expect(firstCard.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(firstCardFrame.maxX <= expectedTrailingEdge + 1)
        #expect(firstCardFrame.maxX >= expectedTrailingEdge - 1)
        #expect(abs(artworkFrame.minX - firstCard.bounds.minX) < 1)
        #expect(abs(artworkFrame.width - firstCard.bounds.width) < 1)
        #expect(abs(artworkFrame.minY - firstCard.bounds.minY) < 1)

        let rtlPageFrame = viewController.pageScrollView.convert(
            viewController.pageScrollView.bounds,
            to: viewController.view
        )
        #expect(rtlPageFrame.approximatelyEquals(pageFrame))
    }

    @Test func horizontalScrollDemoModelsLocalizedDestinationDiscovery() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let viewController = HorizontalScrollViewViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 402, height: 874)
        )
        defer {
            window.isHidden = true
        }

        let firstCard = try #require(viewController.views.first)
        let englishLabels = viewController.view.allSubviews(of: UILabel.self)
        let measuredCardHeight = firstCard.sizeThatFits(
            CGSize(
                width: firstCard.bounds.width,
                height: CGFloat.infinity
            )
        ).height

        #expect(viewController.views.count == 5)
        #expect(firstCard.bounds.height > 146)
        #expect(abs(firstCard.bounds.height - measuredCardHeight) < 1)
        #expect(
            abs(
                viewController.scrollView.bounds.height
                    - (viewController.views.map(\.bounds.height).max() ?? 0)
            ) < 1
        )
        #expect(
            firstCard.accessibilityIdentifier
                == "horizontal.destination.lakeside"
        )
        #expect(firstCard.accessibilityTraits.contains(.button))
        #expect(
            firstCard.destinationTitle
                == DemoLocalization.text(
                    "horizontal.explore.destination.lakeside.title"
                )
        )
        #expect(
            englishLabels.contains {
                $0.text == DemoLocalization.text("horizontal.explore.headline")
            }
        )
        #expect(
            englishLabels.contains {
                $0.text == DemoLocalization.text(
                    "horizontal.explore.page",
                    1,
                    viewController.views.count
                )
            }
        )

        let secondCard = viewController.views[1]
        let secondCardFrame = secondCard.convert(
            secondCard.bounds,
            to: viewController.scrollView
        )
        viewController.scrollView.setContentOffset(
            CGPoint(
                x: secondCardFrame.midX
                    - viewController.scrollView.bounds.width / 2,
                y: viewController.scrollView.contentOffset.y
            ),
            animated: false
        )
        viewController.scrollViewDidScroll(viewController.scrollView)

        #expect(
            englishLabels.contains {
                $0.text == DemoLocalization.text(
                    "horizontal.explore.page",
                    2,
                    viewController.views.count
                )
            }
        )

        DemoLocalization.setLocale(identifier: "ar")
        window.semanticContentAttribute = .forceRightToLeft
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.scrollView.setNeedsLayout()
        viewController.views.forEach { $0.setNeedsLayout() }
        window.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        viewController.views.forEach { $0.layoutIfNeeded() }

        let firstCardFrame = viewController.views[0].convert(
            viewController.views[0].bounds,
            to: viewController.scrollView
        )
        let visibleRect = CGRect(
            origin: viewController.scrollView.contentOffset,
            size: viewController.scrollView.bounds.size
        )

        #expect(
            viewController.views[0].destinationTitle
                == DemoLocalization.text(
                    "horizontal.explore.destination.lakeside.title"
                )
        )
        #expect(
            viewController.views[0].effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(firstCardFrame.maxX <= visibleRect.maxX)
        #expect(firstCardFrame.maxX > visibleRect.maxX - 80)
    }

    @Test func counterDemoFallsBackToVerticalActionsWhenNarrow() {
        DemoLocalization.setLocale(identifier: "en-US")
        defer { DemoLocalization.setLocale(identifier: "en-US") }
        let viewController = CounterViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        #expect(
            abs(
                viewController.decrementButton.frame.midY
                    - viewController.incrementButton.frame.midY
            ) < 1
        )
        #expect(viewController.counterLabel.text == "3")
        #expect(
            viewController.incrementButton.accessibilityLabel == "Add glass"
        )
        #expect(
            viewController.decrementButton.accessibilityLabel == "Remove"
        )
        #expect(viewController.resetButton.isEnabled)

        viewController.incrementButton.performAction()
        #expect(viewController.counterLabel.text == "4")
        viewController.decrementButton.performAction()
        #expect(viewController.counterLabel.text == "3")

        viewController.view.frame = CGRect(x: 0, y: 0, width: 140, height: 500)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        #expect(
            viewController.decrementButton.frame.maxY
                < viewController.incrementButton.frame.minY
        )
    }

    @Test func mediaExamplesPreserveTheirAspectRatios() throws {
        let messageContentView = MessageContentView(frame: .zero)
        messageContentView.configure(MessageModel.mockData[0])
        let messageSize = messageContentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        messageContentView.frame = CGRect(origin: .zero, size: messageSize)
        messageContentView.layoutIfNeeded()

        let fitRow = ExampleRow2()
        fitRow.body.applyFrame(
            CGRect(x: 0, y: 0, width: 320, height: 72),
            alignment: .topLeading
        )
        let iconSize = try #require(fitRow.directionIconView.image?.size)
        let iconRatio = iconSize.width / iconSize.height
        let fittedRatio = fitRow.directionIconView.bounds.width
            / fitRow.directionIconView.bounds.height

        let fillRow = ExampleRow3()
        fillRow.body.applyFrame(
            CGRect(x: 0, y: 0, width: 320, height: 72),
            alignment: .topLeading
        )
        let fillImageSize = try #require(fillRow.imageView.image?.size)
        let fillImageRatio = fillImageSize.width / fillImageSize.height
        let filledRatio = fillRow.imageView.bounds.width
            / fillRow.imageView.bounds.height

        #expect(messageContentView.avatarView.bounds.size == CGSize(width: 40, height: 40))
        #expect(fitRow.directionIconView.bounds.width <= 24)
        #expect(fitRow.directionIconView.bounds.height <= 24)
        #expect(abs(fittedRatio - iconRatio) < 0.01)
        #expect(fillRow.imageView.bounds.width >= 40)
        #expect(fillRow.imageView.bounds.height >= 40)
        #expect(abs(filledRatio - fillImageRatio) < 0.01)
    }

    @Test func messageContentViewUpdatesAndSelfSizes() {
        let firstModel = MessageModel(
            title: "First",
            message: "Short message",
            imageName: "sun.max.fill",
            themeColor: .systemOrange
        )
        let contentView = MessageContentView(frame: .zero)
        contentView.configure(firstModel)

        #expect(contentView.titleLabel.text == firstModel.title)
        #expect(contentView.messageLabel.text == firstModel.message)

        let secondModel = MessageModel(
            title: "Updated",
            message: String(
                repeating: "A longer message that should wrap. ",
                count: 8
            ),
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        contentView.configure(secondModel)

        let wideSize = contentView.sizeThatFits(
            CGSize(
                width: 320,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        let narrowSize = contentView.sizeThatFits(
            CGSize(
                width: 180,
                height: CGFloat.greatestFiniteMagnitude
            )
        )

        #expect(contentView.titleLabel.text == secondModel.title)
        #expect(contentView.messageLabel.text == secondModel.message)
        #expect(narrowSize.height > wideSize.height)

        let cell = MessageCell(frame: .zero)
        cell.configure(firstModel)
        let initialCellContentView = cell.messageContentView
        #expect(initialCellContentView.titleLabel.text == firstModel.title)
        cell.isHighlighted = true
        #expect(initialCellContentView.alpha < 1)

        cell.prepareForReuse()
        #expect(initialCellContentView.titleLabel.text == nil)
        #expect(initialCellContentView.messageLabel.text == nil)
        #expect(initialCellContentView.alpha == 1)

        cell.configure(secondModel)
        let reusedCellContentView = cell.messageContentView
        #expect(reusedCellContentView === initialCellContentView)
        #expect(reusedCellContentView.titleLabel.text == secondModel.title)
        #expect(reusedCellContentView.messageLabel.text == secondModel.message)

        let attributes = UICollectionViewLayoutAttributes(
            forCellWith: IndexPath(item: 0, section: 0)
        )
        attributes.size = CGSize(width: 180, height: 80)
        let fittedAttributes = cell.preferredLayoutAttributesFitting(
            attributes
        )

        #expect(fittedAttributes.size == narrowSize)
    }

    @Test func tableMessageControllerUsesSelfSizingViews() throws {
        let fittingTolerance: CGFloat = 1.01
        let viewController = MessageTableViewController()
        viewController.loadViewIfNeeded()
        let tableView = try #require(viewController.tableView)
        tableView.estimatedRowHeight = 1
        tableView.estimatedSectionHeaderHeight = 1
        tableView.estimatedSectionFooterHeight = 1
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        tableView.reloadData()
        tableView.layoutIfNeeded()

        #expect(tableView.numberOfRows(inSection: 0) == 12)
        #expect(
            tableView.rectForRow(
                at: IndexPath(row: 0, section: 0)
            ).height > 60
        )
        #expect(tableView.rectForHeader(inSection: 0).height > 44)

        let cell = try #require(
            tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                as? MessageTableCell
        )
        let cellContentView = cell.messageContentView
        #expect(cellContentView.titleLabel.text?.isEmpty == false)
        let cellFittingSize = cell.systemLayoutSizeFitting(
            CGSize(width: cell.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(cell.bounds.height - cellFittingSize.height)
                <= fittingTolerance
        )

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        #expect(header.sectionContentView.titleLabel.text?.isEmpty == false)
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= fittingTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        let footer = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(footer.sectionContentView.titleLabel.text?.isEmpty == false)
        #expect(footer.bounds.height > 20)
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= fittingTolerance
        )
    }

    @Test func tableMessageSupplementariesStartRTLOnFirstAppearance() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = MessageTableListView()

        let model = MessageModel(
            title: "رسالة",
            message: "محتوى الرسالة",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            MessageListItem(
                id: MessageListItemID(group: 0, message: model.imageName),
                model: model
            )
        ]
        let headerText = "رسائل ذاتية التحجيم عند الظهور الأول"
        let detailText = "يجب أن يبدأ هذا الرأس من الحافة اليمنى مباشرة."
        let footerText = "يظهر هذا التذييل باتجاه صحيح وارتفاع مناسب من المرة الأولى."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: headerText,
                headerDetail: detailText,
                footerTitle: footerText,
                completion: { continuation.resume() }
            )
        }

        #expect(listView.bounds == .zero)
        #expect(listView.tableView.bounds == .zero)
        #expect(listView.window == nil)
        #expect(listView.tableView.headerView(forSection: 0) == nil)
        #expect(listView.tableView.footerView(forSection: 0) == nil)
        #expect(
            listView.tableView.semanticContentAttribute == .unspecified
        )

        let viewController = UIViewController()
        viewController.view = listView
        viewController.view.semanticContentAttribute = .forceRightToLeft
        listView.applyLayoutDirection(.rightToLeft)
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }
        listView.tableView.layoutIfNeeded()

        let header = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footer = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        let footerContent = footer.sectionContentView
        headerContent.layoutIfNeeded()
        footerContent.layoutIfNeeded()

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == headerText)
        #expect(headerDetail.text == detailText)
        #expect(footerTitle.text == footerText)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )
        let headerFittingSize = header.systemLayoutSizeFitting(
            CGSize(width: header.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = footer.systemLayoutSizeFitting(
            CGSize(width: footer.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        #expect(window.semanticContentAttribute == .unspecified)
        #expect(listView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            listView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            listView.tableView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(header.semanticContentAttribute == .forceRightToLeft)
        #expect(footer.semanticContentAttribute == .forceRightToLeft)
        #expect(
            headerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            footerContent.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(header.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(footer.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForHeader(inSection: 0).height
                    - header.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.rectForFooter(inSection: 0).height
                    - footer.bounds.height
            ) <= tolerance
        )
        #expect(
            abs(
                listView.tableView.contentOffset.y
                    + listView.tableView.adjustedContentInset.top
            ) <= tolerance
        )
    }

    @Test func tableMessageSupplementariesRelayoutImmediatelyAfterLocalizationAndDirectionChange() async throws {
        let edgePadding: CGFloat = 16
        let tolerance: CGFloat = 1.01
        let listView = MessageTableListView()
        let viewController = UIViewController()
        viewController.view = listView
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 640)
        )
        defer { window.isHidden = true }

        let model = MessageModel(
            title: "Message",
            message: "Body",
            imageName: "moon.stars.fill",
            themeColor: .systemIndigo
        )
        let items = [
            MessageListItem(
                id: MessageListItemID(group: 0, message: model.imageName),
                model: model
            )
        ]

        listView.applyLayoutDirection(.leftToRight)
        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: "Header",
                headerDetail: "Detail",
                footerTitle: "Footer",
                completion: { continuation.resume() }
            )
        }
        listView.tableView.layoutIfNeeded()

        let initialHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let initialFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let initialHeaderHeight = listView.tableView.rectForHeader(
            inSection: 0
        ).height
        let initialFooterHeight = listView.tableView.rectForFooter(
            inSection: 0
        ).height
        let initialContentOffset = listView.tableView.contentOffset

        let arabicHeader = "رسائل ذاتية التحجيم طويلة لاختبار الارتفاع"
        let arabicDetail = "يجب أن يتغير اتجاه هذا الرأس وارتفاعه فورًا من دون تمرير القائمة."
        let arabicFooter = "يجب أن يحدّث الرأس والتذييل الارتفاع مباشرة عند تبديل اللغة من الصينية إلى العربية من دون تمرير القائمة."

        await withCheckedContinuation { continuation in
            listView.render(
                items: items,
                headerTitle: arabicHeader,
                headerDetail: arabicDetail,
                footerTitle: arabicFooter,
                completion: { continuation.resume() }
            )
            // Match production ordering: localized content starts an
            // asynchronous ListKit apply before direction is updated.
            listView.applyLayoutDirection(.rightToLeft)
        }

        let updatedHeader = try #require(
            listView.tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let updatedFooter = try #require(
            listView.tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = updatedHeader.sectionContentView
        let footerContent = updatedFooter.sectionContentView

        let headerTitle = headerContent.titleLabel
        let headerDetail = headerContent.detailLabel
        let footerTitle = footerContent.titleLabel
        #expect(headerTitle.text == arabicHeader)
        #expect(headerDetail.text == arabicDetail)
        #expect(footerTitle.text == arabicFooter)
        let headerTitleFrame = headerTitle.convert(
            headerTitle.bounds,
            to: headerContent
        )
        let headerDetailFrame = headerDetail.convert(
            headerDetail.bounds,
            to: headerContent
        )
        let footerTitleFrame = footerTitle.convert(
            footerTitle.bounds,
            to: footerContent
        )

        #expect(updatedHeader === initialHeader)
        #expect(updatedFooter === initialFooter)
        #expect(
            listView.tableView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(headerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(footerContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            updatedHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            updatedFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            updatedHeader.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            updatedFooter.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == listView.tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                headerTitleFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                headerDetailFrame.maxX
                    - (headerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            abs(
                footerTitleFrame.maxX
                    - (footerContent.bounds.maxX - edgePadding)
            ) <= tolerance
        )
        #expect(
            listView.tableView.rectForHeader(inSection: 0).height
                > initialHeaderHeight
        )
        #expect(
            listView.tableView.rectForFooter(inSection: 0).height
                > initialFooterHeight
        )

        let headerFittingSize = updatedHeader.systemLayoutSizeFitting(
            CGSize(width: updatedHeader.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        let footerFittingSize = updatedFooter.systemLayoutSizeFitting(
            CGSize(width: updatedFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(updatedHeader.bounds.height - headerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(updatedFooter.bounds.height - footerFittingSize.height)
                <= tolerance
        )
        #expect(
            abs(listView.tableView.contentOffset.y - initialContentOffset.y)
                <= tolerance
        )
    }

    @Test func collectionMessageControllerReusesItsCellRegistration() throws {
        let viewController = MesssageViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 320,
            height: 640
        )
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        #expect(collectionView.numberOfItems(inSection: 0) == 4)
        #expect(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) is MessageCell
        )
    }

    @Test func dynamicScrollDemoFillsScreenAndProtectsItsOverlayAction() {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let buttonFrame = viewController.addButton.convert(
            viewController.addButton.bounds,
            to: viewController.view
        )
        let scrollFrame = viewController.scrollView.convert(
            viewController.scrollView.bounds,
            to: viewController.view
        )

        #expect(abs(scrollFrame.minX - viewController.view.bounds.minX) < 1)
        #expect(abs(scrollFrame.minY - viewController.view.bounds.minY) < 1)
        #expect(abs(scrollFrame.maxX - viewController.view.bounds.maxX) < 1)
        #expect(abs(scrollFrame.maxY - viewController.view.bounds.maxY) < 1)
        #expect(
            abs(buttonFrame.minY - viewController.view.safeAreaInsets.top) < 1
        )
        #expect(
            abs(
                buttonFrame.maxX
                    - viewController.view.bounds.maxX
                    + viewController.view.safeAreaInsets.right
                    + 16
            ) < 1
        )
        #expect(
            viewController.scrollView.adjustedContentInset.top
                >= buttonFrame.maxY - scrollFrame.minY + 7
        )
        #expect(viewController.scrollView.contentInset.left == 16)
        #expect(viewController.scrollView.contentInset.bottom == 8)
        #expect(viewController.scrollView.contentInset.right == 16)
        let indicatorInsets = viewController.scrollView
            .verticalScrollIndicatorInsets
        #expect(
            abs(
                indicatorInsets.top
                    - viewController.scrollView.contentInset.top
            ) < 1
        )
        #expect(
            abs(
                indicatorInsets.bottom
                    - viewController.scrollView.contentInset.bottom
            ) < 1
        )
    }

    @Test func dynamicScrollCardsExposeLocalizedDeletionAffordance() throws {
        let localizer = DemoLocalizer { key, arguments in
            guard !arguments.isEmpty else { return key }
            return key + ": "
                + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 2,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let titleLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hintLabel = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let accentIcon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let titleFrame = titleLabel.convert(titleLabel.bounds, to: card)
        let hintFrame = hintLabel.convert(hintLabel.bounds, to: card)
        let accentFrame = accentIcon.convert(accentIcon.bounds, to: card)
        let deleteFrame = deleteButton.convert(deleteButton.bounds, to: card)
        let titleCenter = titleLabel.convert(
            CGPoint(x: titleLabel.bounds.midX, y: titleLabel.bounds.midY),
            to: card
        )

        #expect(titleLabel.text == "dynamic.item.title: 1")
        #expect(hintLabel.text == "dynamic.item.deleteHint")
        #expect(accentIcon.image != nil)
        #expect(deleteButton.configuration?.image != nil)
        #expect(deleteButton.configuration?.cornerStyle == .capsule)
        #expect(card.bounds.height >= 80)
        #expect(deleteButton.bounds.width >= 44)
        #expect(deleteButton.bounds.height >= 44)
        #expect(card.bounds.contains(titleFrame))
        #expect(card.bounds.contains(hintFrame))
        #expect(card.bounds.contains(accentFrame))
        #expect(card.bounds.contains(deleteFrame))
        #expect(accentFrame.maxX <= min(titleFrame.minX, hintFrame.minX))
        #expect(max(titleFrame.maxX, hintFrame.maxX) <= deleteFrame.minX)

        #expect(!(card is UIControl))
        #expect(card.gestureRecognizers?.isEmpty ?? true)
        #expect(card.hitTest(titleCenter, with: nil) !== deleteButton)
        #expect(!card.isAccessibilityElement)
        #expect(titleLabel.isAccessibilityElement)
        #expect(titleLabel.accessibilityTraits.contains(.staticText))
        #expect(titleLabel.accessibilityLabel == "dynamic.item.title: 1")
        #expect(!hintLabel.isAccessibilityElement)
        #expect(!accentIcon.isAccessibilityElement)
        #expect(deleteButton.isAccessibilityElement)
        #expect(deleteButton.accessibilityTraits.contains(.button))
        #expect(
            deleteButton.accessibilityLabel
                == "dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "dynamic.item.deleteAccessibilityHint"
        )
    }

    @Test func dynamicScrollCachedCardMirrorsAndRelocalizesFromLTRToRTL() throws {
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, arguments in
            let suffix = arguments.isEmpty
                ? ""
                : ": " + arguments.map { String(describing: $0) }
                    .joined(separator: " | ")
            return prefix + key + suffix
        }
        let viewController = DynamicScrollViewController(
            viewModel: DynamicScrollViewModel(
                initialItemCount: 1,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let card = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let icon = try #require(
            card.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let title = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.title"
            }
        )
        let hint = try #require(
            card.allSubviews(of: UILabel.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.hint"
            }
        )
        let deleteButton = try #require(
            card.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        card.layoutIfNeeded()

        let ltrCardWidth = card.bounds.width
        let ltrIconFrame = icon.convert(icon.bounds, to: card)
        let ltrDeleteFrame = deleteButton.convert(deleteButton.bounds, to: card)

        #expect(ltrIconFrame.midX < ltrDeleteFrame.midX)
        #expect(title.text == "ltr.dynamic.item.title: 1")

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        card.layoutIfNeeded()

        let updatedCard = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0"
            }
        )
        let updatedIcon = try #require(
            updatedCard.allSubviews(of: UIImageView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.0.icon"
            }
        )
        let updatedDeleteButton = try #require(
            updatedCard.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.0.deleteButton"
            }
        )
        let rtlIconFrame = updatedIcon.convert(updatedIcon.bounds, to: updatedCard)
        let rtlDeleteFrame = updatedDeleteButton.convert(
            updatedDeleteButton.bounds,
            to: updatedCard
        )
        let mirroredIconMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrIconFrame.midX
        let mirroredDeleteMidX = updatedCard.bounds.minX
            + updatedCard.bounds.maxX
            - ltrDeleteFrame.midX

        #expect(updatedCard === card)
        #expect(updatedIcon === icon)
        #expect(updatedDeleteButton === deleteButton)
        #expect(updatedCard.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlIconFrame.midX > rtlDeleteFrame.midX)
        #expect(abs(rtlIconFrame.midX - mirroredIconMidX) < 1)
        #expect(abs(rtlDeleteFrame.midX - mirroredDeleteMidX) < 1)
        #expect(abs(updatedCard.bounds.width - ltrCardWidth) < 0.001)
        #expect(
            abs(rtlIconFrame.width - ltrIconFrame.width) < 0.001
                && abs(rtlIconFrame.height - ltrIconFrame.height) < 0.001
        )
        #expect(
            abs(rtlDeleteFrame.width - ltrDeleteFrame.width) < 0.001
                && abs(rtlDeleteFrame.height - ltrDeleteFrame.height) < 0.001
        )
        #expect(title.text == "rtl.dynamic.item.title: 1")
        #expect(hint.text == "rtl.dynamic.item.deleteHint")
        #expect(
            deleteButton.accessibilityLabel
                == "rtl.dynamic.item.deleteButton: 1"
        )
        #expect(
            deleteButton.accessibilityHint
                == "rtl.dynamic.item.deleteAccessibilityHint"
        )
    }

    @Test func dynamicScrollAdditionsFinishAtTheNewBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let initialLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.9"
            }
        )
        let initialLastFrame = initialLastItem.convert(
            initialLastItem.bounds,
            to: viewController.scrollView
        )
        let initialContentHeight = viewController.scrollView.contentSize.height
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        viewController.addButton.sendActions(for: .touchUpInside)
        viewController.addButton.sendActions(for: .touchUpInside)

        let scrollView = viewController.scrollView
        let newLastItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.11"
            }
        )
        let newLastFrame = newLastItem.convert(
            newLastItem.bounds,
            to: scrollView
        )
        let expectedHeightIncrease = newLastFrame.maxY - initialLastFrame.maxY
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(expectedHeightIncrease > 0)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    - expectedHeightIncrease
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)
    }

    @Test func dynamicScrollDeleteButtonRemovesAndClampsAtTheBottom() throws {
        let viewController = DynamicScrollViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let scrollView = viewController.scrollView
        scrollView.scrollTo(.bottom, animated: false)

        let itemViews = viewController.view.allSubviews(of: UIView.self)
        let previousItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let removedItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.4"
            }
        )
        let followingItem = try #require(
            itemViews.first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let deleteButton = try #require(
            removedItem.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier
                    == "dynamic.item.4.deleteButton"
            }
        )
        let previousFrame = previousItem.convert(previousItem.bounds, to: scrollView)
        let removedFrame = removedItem.convert(removedItem.bounds, to: scrollView)
        let followingFrame = followingItem.convert(followingItem.bounds, to: scrollView)
        let removedStride = followingFrame.minY - removedFrame.minY
        let initialContentHeight = scrollView.contentSize.height

        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }

        deleteButton.sendActions(for: .touchUpInside)

        let survivingPreviousItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.3"
            }
        )
        let survivingFollowingItem = try #require(
            viewController.view.allSubviews(of: UIView.self).first {
                $0.accessibilityIdentifier == "dynamic.item.5"
            }
        )
        let updatedPreviousFrame = survivingPreviousItem.convert(
            survivingPreviousItem.bounds,
            to: scrollView
        )
        let updatedFollowingFrame = survivingFollowingItem.convert(
            survivingFollowingItem.bounds,
            to: scrollView
        )
        let inset = scrollView.adjustedContentInset
        let expectedBottomOffset = max(
            -inset.top,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + inset.bottom
        )

        #expect(removedItem.superview == nil)
        #expect(survivingPreviousItem === previousItem)
        #expect(survivingFollowingItem === followingItem)
        #expect(removedFrame.height >= 80)
        #expect(removedStride > removedFrame.height)
        #expect(
            abs(
                scrollView.contentSize.height
                    - initialContentHeight
                    + removedStride
            ) < 1
        )
        #expect(abs(updatedPreviousFrame.minY - previousFrame.minY) < 1)
        #expect(
            abs(
                updatedFollowingFrame.minY
                    - followingFrame.minY
                    + removedStride
            ) < 1
        )
        #expect(abs(scrollView.contentOffset.y - expectedBottomOffset) < 1)

        let contentHeightAfterDeletion = scrollView.contentSize.height
        deleteButton.sendActions(for: .touchUpInside)
        #expect(
            abs(scrollView.contentSize.height - contentHeightAfterDeletion) < 1
        )
    }

    @Test func scrollExamplesUseContentMargins() throws {
        let examples: [(
            viewController: UIViewController,
            contentInsets: UIEdgeInsets,
            indicatorInsets: UIEdgeInsets
        )] = [
            (
                LocalizationOverviewViewController(),
                UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20),
                UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            ),
            (
                ProfileViewController(),
                UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16),
                .zero
            ),
            (
                ViewControllerRepresentableDemoViewController(),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            ),
            (
                ScrollViewWithKeyboardViewController(),
                UIEdgeInsets(top: 20, left: 20, bottom: 10, right: 20),
                UIEdgeInsets(top: 20, left: 20, bottom: 10, right: 20)
            ),
            (
                SemanticContentDemoViewController(),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16),
                UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
            ),
        ]

        for example in examples {
            let viewController = example.viewController
            viewController.loadViewIfNeeded()
            viewController.view.frame = CGRect(
                x: 0,
                y: 0,
                width: 390,
                height: 844
            )
            viewController.view.setNeedsLayout()
            viewController.view.layoutIfNeeded()

            let scrollView = try #require(
                viewController.view
                    .allSubviews(of: QuickLayoutScrollView.self)
                    .first
            )

            #expect(scrollView.contentInset == example.contentInsets)
            #expect(
                scrollView.verticalScrollIndicatorInsets
                    == example.indicatorInsets
            )
            #expect(
                scrollView.horizontalScrollIndicatorInsets
                    == .zero
            )
        }
    }

    @Test func keyboardContextParsesUIKitNotification() throws {
        let beginFrame = CGRect(x: 0, y: 844, width: 390, height: 0)
        let frame = CGRect(x: 0, y: 320, width: 390, height: 240)
        let notification = Notification(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameBeginUserInfoKey: beginFrame,
                UIResponder.keyboardFrameEndUserInfoKey: frame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0.25,
                UIResponder.keyboardAnimationCurveUserInfoKey: UInt(UIView.AnimationCurve.easeInOut.rawValue),
            ]
        )

        let context = try #require(QuickLayoutKeyboardContext(notification: notification))

        #expect(context.event == .willShow)
        #expect(context.beginFrame == beginFrame)
        #expect(context.endFrame == frame)
        #expect(context.height == 240)
        #expect(context.animationDuration == 0.25)
        #expect(context.isVisible)
    }

    @Test func keyboardContextMapsChangeAndHideEvents() throws {
        let didChange = Notification(
            name: UIResponder.keyboardDidChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 600, width: 390, height: 244),
            ]
        )
        let willHide = Notification(
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: CGRect(x: 0, y: 844, width: 390, height: 0),
            ]
        )

        let didChangeContext = try #require(QuickLayoutKeyboardContext(notification: didChange))
        let willHideContext = try #require(QuickLayoutKeyboardContext(notification: willHide))

        #expect(didChangeContext.event == .didChangeFrame)
        #expect(didChangeContext.isVisible)
        #expect(willHideContext.event == .willHide)
        #expect(!willHideContext.isVisible)
        #expect(willHideContext.height == 0)
    }

    @Test func keyboardContextResolvesVisibleIntersectionInTargetView() throws {
        let window = try makeVisibleTestWindow(
            rootViewController: UIViewController(),
            size: CGSize(width: 390, height: 844)
        )
        let fullScreenView = UIView(frame: window.bounds)
        let insetView = UIView(frame: CGRect(x: 0, y: 250, width: 390, height: 120))
        window.addSubview(fullScreenView)
        window.addSubview(insetView)

        let normalContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 600, width: 390, height: 244),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )
        let floatingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 40, y: 300, width: 220, height: 180),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )

        let normalResolved = normalContext.resolved(in: fullScreenView)
        let floatingResolved = floatingContext.resolved(in: insetView)

        #expect(normalResolved.height == 244)
        #expect(normalResolved.intersection == CGRect(x: 0, y: 600, width: 390, height: 244))
        #expect(!normalResolved.isFloatingOrSplitKeyboard)
        #expect(floatingResolved.keyboardFrameInView == CGRect(x: 40, y: 50, width: 220, height: 180))
        #expect(floatingResolved.intersection == CGRect(x: 40, y: 50, width: 220, height: 70))
        #expect(floatingResolved.height == 70)
        #expect(floatingResolved.height != floatingContext.endFrame.height)
        #expect(floatingResolved.isFloatingOrSplitKeyboard)
    }

    @Test func keyboardContextResolvesHardwareAndNonOverlappingKeyboardsToZero() throws {
        let window = try makeVisibleTestWindow(
            rootViewController: UIViewController(),
            size: CGSize(width: 390, height: 844)
        )
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        window.addSubview(scrollView)

        let nonOverlappingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 500, width: 390, height: 200),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )
        let hardwareContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 844, width: 390, height: 0),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        let nonOverlappingResolved = nonOverlappingContext.resolved(in: scrollView)
        let hardwareResolved = hardwareContext.resolved(in: scrollView)

        #expect(nonOverlappingResolved.height == 0)
        #expect(nonOverlappingResolved.intersection.isNull)
        #expect(hardwareResolved.height == 0)
        #expect(hardwareResolved.isHardwareKeyboardLikely)
    }

    @Test func keyboardAvoiderPreservesBaseScrollInsets() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.contentInset = UIEdgeInsets(top: 1, left: 2, bottom: 10, right: 4)
        scrollView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        scrollView.horizontalScrollIndicatorInsets = UIEdgeInsets(top: 9, left: 10, bottom: 11, right: 12)

        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter())
        )

        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 300, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        avoider.apply(visibleContext)

        #expect(scrollView.contentInset.bottom == 130)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 127)
        #expect(scrollView.horizontalScrollIndicatorInsets.bottom == 131)

        avoider.apply(.hidden)

        #expect(scrollView.contentInset.bottom == 10)
        #expect(scrollView.verticalScrollIndicatorInsets.bottom == 7)
        #expect(scrollView.horizontalScrollIndicatorInsets.bottom == 11)
    }

    @Test func keyboardAvoiderUsesInjectedNotificationCenterForDefaultObserver() {
        let notificationCenter = NotificationCenter()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            notificationCenter: notificationCenter
        )
        let keyboardFrame = CGRect(x: 0, y: 360, width: 320, height: 120)

        notificationCenter.post(
            name: UIResponder.keyboardWillShowNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: keyboardFrame,
                UIResponder.keyboardAnimationDurationUserInfoKey: 0,
            ]
        )

        #expect(scrollView.contentInset.bottom == 120)
        _ = avoider
    }

    @Test func keyboardAvoiderAppliesSafeAreaStrategiesAndExtraPadding() {
        let scrollView = TestSafeAreaScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        scrollView.testSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter()),
            notificationCenter: NotificationCenter()
        )
        avoider.extraBottomPadding = 8

        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 360, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )
        let nonOverlappingContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 640, width: 320, height: 120),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willChangeFrame
        )

        avoider.safeAreaStrategy = .ignore
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 138)

        avoider.safeAreaStrategy = .add
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 172)

        avoider.safeAreaStrategy = .subtractExisting
        avoider.apply(visibleContext)
        #expect(scrollView.contentInset.bottom == 104)

        avoider.apply(nonOverlappingContext)
        #expect(scrollView.contentInset.bottom == 10)
    }

    @Test func keyboardAvoiderTracksCustomActiveInputNotification() {
        let notificationCenter = NotificationCenter()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        scrollView.contentSize = CGSize(width: 320, height: 640)
        let activeInput = UIView(frame: CGRect(x: 0, y: 520, width: 320, height: 44))
        scrollView.addSubview(activeInput)

        let avoider = QuickLayoutKeyboardAvoider(
            scrollView: scrollView,
            observer: QuickLayoutKeyboardObserver(notificationCenter: NotificationCenter()),
            notificationCenter: notificationCenter
        )
        let visibleContext = QuickLayoutKeyboardContext(
            endFrame: CGRect(x: 0, y: 80, width: 320, height: 40),
            animationDuration: 0,
            animationOptions: [],
            isVisible: true,
            event: .willShow
        )

        notificationCenter.post(
            name: .quickLayoutKeyboardActiveInputDidBeginEditing,
            object: nil,
            userInfo: ["activeView": activeInput]
        )
        avoider.apply(visibleContext)

        #expect(scrollView.contentOffset.y > 0)

        scrollView.setContentOffset(.zero, animated: false)
        notificationCenter.post(name: .quickLayoutKeyboardActiveInputDidEndEditing, object: activeInput)
        avoider.apply(visibleContext)

        #expect(scrollView.contentOffset.y == 0)
    }

    @Test func listCellMeasuresQuickLayoutContent() {
        let titleLabel = UILabel()
        titleLabel.text = "Title"
        let messageLabel = UILabel()
        messageLabel.text = "A long message that should wrap inside the proposed collection cell width."
        messageLabel.numberOfLines = 0

        let cell = QuickLayoutCollectionViewCell {
            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                messageLabel
            }
            .padding(.all, 12)
        }

        cell.quickLayoutHorizontalFlexibility = .fixedSize
        cell.quickLayoutVerticalFlexibility = .fullyFlexible

        let size = cell.sizeThatFits(CGSize(width: 180, height: 44))

        #expect(size.width == 180)
        #expect(size.height > 44)
    }

    @Test func directionalEnvironmentHelpersRespectLayoutDirection() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        view.semanticContentAttribute = .forceRightToLeft

        let margins = view.quickLayoutDirectionalLayoutMargins

        #expect(margins.top == 1)
        #expect(margins.leading == 2)
        #expect(margins.bottom == 3)
        #expect(margins.trailing == 4)
    }

    @Test func quickLayoutEnvironmentReflectsCurrentUIViewState() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        view.semanticContentAttribute = .forceRightToLeft
        view.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 16, trailing: 20)

        let environment = view.quickLayoutEnvironment

        #expect(environment.layoutDirection == .rightToLeft)
        #expect(environment.preferredContentSizeCategory == view.traitCollection.preferredContentSizeCategory)
        #expect(environment.horizontalSizeClass == view.traitCollection.horizontalSizeClass)
        #expect(environment.verticalSizeClass == view.traitCollection.verticalSizeClass)
        #expect(environment.userInterfaceStyle == view.traitCollection.userInterfaceStyle)
        #expect(environment.displayScale == view.traitCollection.displayScale)
        #expect(environment.layoutMargins.leading == 12)
        #expect(environment.containerSize == CGSize(width: 320, height: 480))
        #expect(view.quickLayoutDirection == .rightToLeft)
    }

    @Test func quickLayoutEnvironmentReportsPublicChanges() {
        let previous = QuickLayoutEnvironment(
            layoutDirection: .leftToRight,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 0, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 375, height: 480)
        )
        let current = QuickLayoutEnvironment(
            layoutDirection: .rightToLeft,
            preferredContentSizeCategory: .large,
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            userInterfaceStyle: .light,
            displayScale: 2,
            safeAreaInsets: .init(top: 0, leading: 0, bottom: 34, trailing: 0),
            layoutMargins: .init(top: 8, leading: 8, bottom: 8, trailing: 8),
            containerSize: CGSize(width: 320, height: 480)
        )

        let changes = current.changes(from: previous)

        #expect(changes == [.layoutDirection, .safeArea, .containerSize])
        #expect(QuickLayoutEnvironmentChangeReason.all.isSuperset(of: changes))
    }

    @Test func quickLayoutViewNotifiesEnvironmentChangesFromMargins() {
        let hostingView = EnvironmentRecordingQuickLayoutView()
        hostingView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        hostingView.layoutMargins = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        hostingView.layoutIfNeeded()

        hostingView.layoutMargins = UIEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        hostingView.layoutMarginsDidChange()

        #expect(hostingView.environmentChanges.contains { $0.reason.contains(.layoutMargins) })
        #expect(hostingView.environmentChanges.last?.environment.layoutMargins.leading == 6)
    }

    @Test func diagnosticsRecordsLayoutPasses() {
        QuickLayoutDiagnostics.reset()
        QuickLayoutDiagnostics.isEnabled = true
        QuickLayoutDiagnostics.recordLayoutPass(for: "TestView", measuredSize: CGSize(width: 10, height: 20))

        let snapshot = QuickLayoutDiagnostics.snapshot()

        #expect(snapshot.totalLayoutPasses == 1)
        #expect(snapshot.entries.first?.viewName == "TestView")

        QuickLayoutDiagnostics.isEnabled = false
        QuickLayoutDiagnostics.reset()
    }

    @Test func lazyRepresentableDoesNotLoadUntilIncludedInBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var loadCount = 0
        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "A"))
        }

        var showsChild = false
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded == nil)
        #expect(loadCount == 0)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(lazyRepresentable.isLoaded)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(loadCount == 1)
    }

    @Test func representableAttachesAndDetachesWithQuickLayoutBody() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []

        let lazyRepresentable = LazyView {
            let representable = QuickLayoutViewControllerRepresentable(child)
            representable.eventHandler = { events.append($0.name) }
            return representable
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent === parent)
        #expect(parent.children.contains { $0 === child })
        #expect(events.contains("willAttach"))
        #expect(events.contains("didAttach"))

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(!parent.children.contains { $0 === child })
        #expect(lazyRepresentable.isLoaded)
        #expect(events.contains("willDetach"))
        #expect(events.contains("didDetach"))
    }

    @Test func lazyRepresentableReusesLoadedHostAndCanReplaceChild() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var loadCount = 0

        let lazyRepresentable = LazyView {
            loadCount += 1
            return QuickLayoutViewControllerRepresentable(firstChild)
        }

        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = false
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(loadCount == 1)
        #expect(firstChild.parent === parent)

        lazyRepresentable.ifLoaded?.setViewController(secondChild)

        #expect(firstChild.parent == nil)
        #expect(secondChild.parent === parent)
    }

    @Test func representableDetailedEventsIncludeContainmentContext() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()
        let firstChild = RepresentableTestChildViewController(name: "A")
        let secondChild = RepresentableTestChildViewController(name: "B")
        var detailedEvents: [QuickLayoutViewControllerRepresentable.DetailedEvent] = []

        let representable = QuickLayoutViewControllerRepresentable(firstChild)
        representable.detailedEventHandler = { detailedEvents.append($0) }
        parent.view.addSubview(representable)
        representable.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        representable.layoutIfNeeded()
        representable.setViewController(secondChild)

        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .willDetach && $0.parent === parent && $0.viewController === firstChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didAttach && $0.parent === parent && $0.viewController === secondChild
        })
        #expect(detailedEvents.contains {
            $0.kind == .didReplaceViewController && $0.oldViewController === firstChild && $0.newViewController === secondChild
        })
    }

    @Test func representableInvalidatesChildPreferredContentSize() {
        let child = RepresentableTestChildViewController(name: "A")
        let representable = QuickLayoutViewControllerRepresentable(child)

        let firstSize = representable.sizeThatFits(CGSize(width: 400, height: 400))
        child.preferredContentSize = CGSize(width: 240, height: 180)
        representable.invalidateChildLayout()
        let secondSize = representable.sizeThatFits(CGSize(width: 400, height: 400))

        #expect(firstSize.height == 96)
        #expect(secondSize.height == 180)
    }

    @Test func resettingLazyRepresentableCreatesANewHostOnNextLayout() {
        let parent = UIViewController()
        parent.loadViewIfNeeded()

        var hostCreationCount = 0
        func makeLazyRepresentable() -> LazyView<QuickLayoutViewControllerRepresentable> {
            LazyView {
                hostCreationCount += 1
                return QuickLayoutViewControllerRepresentable(RepresentableTestChildViewController(name: "\(hostCreationCount)"))
            }
        }

        var lazyRepresentable = makeLazyRepresentable()
        var showsChild = true
        let containerView = QuickLayoutView {
            VStack {
                if showsChild {
                    lazyRepresentable.frame(height: 120)
                }
            }
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)
        parent.view.addSubview(containerView)
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 1)
        #expect(lazyRepresentable.isLoaded)
        let firstHost = lazyRepresentable.ifLoaded!

        firstHost.dismantleViewController()
        showsChild = false
        lazyRepresentable = makeLazyRepresentable()
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(!lazyRepresentable.isLoaded)

        showsChild = true
        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(hostCreationCount == 2)
        #expect(lazyRepresentable.ifLoaded != nil)
        #expect(lazyRepresentable.ifLoaded! !== firstHost)
    }

    @Test func parentlessRepresentableDoesNotAttachWithoutControllerOwnedHierarchy() {
        let child = RepresentableTestChildViewController(name: "A")
        var events: [String] = []
        let representable = QuickLayoutViewControllerRepresentable(child)
        representable.eventHandler = { events.append($0.name) }

        let containerView = QuickLayoutView {
            representable.frame(height: 120)
        }
        containerView.frame = CGRect(x: 0, y: 0, width: 240, height: 200)

        containerView.setNeedsQuickLayout()
        containerView.quickLayoutIfNeeded()

        #expect(child.parent == nil)
        #expect(events.contains("missingParent"))
        #expect(!events.contains("didAttach"))
    }

    @Test func demoLocalizationResolvesCoreLanguages() {
        DemoLocalization.setLocale(identifier: "en-US")
        #expect(DemoLocalization.text("main.title") == "Examples")
        #expect(DemoLocalization.text("demo.localizationOverview.title") == "Language Center")

        DemoLocalization.setLocale(identifier: "zh-Hans")
        #expect(DemoLocalization.text("main.title") == "示例")
        #expect(DemoLocalization.text("language.follow.system") == "跟随系统")

        DemoLocalization.setLocale(identifier: "ar")
        #expect(DemoLocalization.text("main.title") == "الأمثلة")
        #expect(DemoLocalization.text("profile.section.about") == "نبذة")
        #expect(
            DemoLocalization.text("profile.skill.localization")
                == "التوطين"
        )
        #expect(
            DemoLocalization.text("profile.action.portfolio")
                == "معرض الأعمال"
        )
        #expect(
            DemoLocalization.text("uikit.showModal")
                == "عرض نافذة مشروطة"
        )
        #expect(
            DemoLocalization.text("boundary.recreateAlert")
                == "إعادة إنشاء التنبيه"
        )
        #expect(DemoLocalization.text("navigation.leading") == "عنصر البداية")
        #expect(DemoLocalization.text("navigation.trailing") == "عنصر النهاية")
        #expect(
            DemoLocalization.text(
                "navigation.edge.summary",
                DemoLocalization.text("navigation.edge.right"),
                "chevron.right"
            ).removingBidiIsolationMarks
                == "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
        )
        #expect(
            DemoLocalization.text("gesture.translation", Int64(0))
                == "الإزاحة الأفقية: 0"
        )
        #expect(
            DemoLocalization.text(
                "gesture.backSwipe",
                DemoLocalization.text("common.boolean.false")
            ).removingBidiIsolationMarks == "إيماءة الرجوع: لا"
        )
        #expect(DemoLocalization.currentLayoutDirection == .rightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func arabicDiagnosticScreensRenderLocalizedText() throws {
        DemoLocalization.setLocale(identifier: "ar")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let navigation = DirectionalNavigationDemoViewController()
        navigation.loadViewIfNeeded()
        let navigationTexts = navigation.view
            .allSubviews(of: UILabel.self)
            .compactMap(\.text)
            .map(\.removingBidiIsolationMarks)
        #expect(
            navigationTexts.contains(
                "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
            )
        )

        let gesture = SemanticGestureDemoViewController()
        gesture.loadViewIfNeeded()
        let gestureTexts = gesture.view
            .allSubviews(of: UILabel.self)
            .compactMap(\.text)
            .map(\.removingBidiIsolationMarks)
        #expect(
            gestureTexts.contains(
                "لم يتم السحب\nالإزاحة الأفقية: 0\nإيماءة الرجوع: لا"
            )
        )

        let keyboardView = AnimatedKeyboardResponsiveView()
        let keyboardDiagnostics = try #require(
            keyboardView.diagnosticsLabel.text
        )
        #expect(keyboardDiagnostics.contains("الحدث:"))
        #expect(keyboardDiagnostics.contains("الإطار الأصلي:"))
        #expect(keyboardDiagnostics.contains("منطقة التقاطع:"))
        #expect(keyboardDiagnostics.contains("الارتفاع:"))
        #expect(!keyboardDiagnostics.contains("event:"))
        #expect(!keyboardDiagnostics.contains("raw:"))
        #expect(!keyboardDiagnostics.contains("intersection:"))
        #expect(!keyboardDiagnostics.contains("height:"))
    }

    @Test func directionalNavigationKeepsSystemBackButtonWithDemoItems() {
        let root = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: root
        )
        let destination = DirectionalNavigationDemoViewController()

        navigationController.pushViewController(destination, animated: false)
        destination.loadViewIfNeeded()

        #expect(navigationController.viewControllers.count == 2)
        #expect(destination.navigationItem.leftBarButtonItem != nil)
        #expect(destination.navigationItem.leftItemsSupplementBackButton)
        #expect(!destination.navigationItem.hidesBackButton)
    }

    @Test func localizationChangeSeparatesLocaleAndDirectionReasons() {
        let leftToRightChange = LocalizationChange(
            previous: LocalizationSnapshot(
                locale: .englishUS,
                followsSystemLocale: false,
                revision: 0
            ),
            current: LocalizationSnapshot(
                locale: .simplifiedChinese,
                followsSystemLocale: false,
                revision: 1
            )
        )
        let rightToLeftChange = LocalizationChange(
            previous: LocalizationSnapshot(
                locale: .englishUS,
                followsSystemLocale: false,
                revision: 0
            ),
            current: LocalizationSnapshot(
                locale: .arabic,
                followsSystemLocale: false,
                revision: 1
            )
        )

        #expect(leftToRightChange.localeChanged)
        #expect(!leftToRightChange.layoutDirectionChanged)
        #expect(rightToLeftChange.localeChanged)
        #expect(rightToLeftChange.layoutDirectionChanged)
    }

    @Test func languageMenuUsesUIKitMirroringAcrossDirectionChanges() throws {
        let viewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            window.isHidden = true
            DemoLocalization.setLocale(identifier: "en-US")
        }

        DemoLocalization.setLocale(identifier: "zh-Hans")
        DemoLocalization.installLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceLeftToRight
        navigationController.view.layoutIfNeeded()

        let languageItem = viewController.navigationItem.rightBarButtonItem
        #expect(languageItem != nil)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        let leftToRightItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let leftToRightFrame = leftToRightItemView.convert(
            leftToRightItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            leftToRightFrame.midX
                > navigationController.navigationBar.bounds.midX
        )

        DemoLocalization.setLocale(identifier: "ar")
        DemoLocalization.reloadLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceRightToLeft
        navigationController.navigationBar.setNeedsLayout()
        navigationController.navigationBar.layoutIfNeeded()

        #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        #expect(!viewController.navigationItem.hidesBackButton)
        let rightToLeftItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let rightToLeftFrame = rightToLeftItemView.convert(
            rightToLeftItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            rightToLeftFrame.midX
                < navigationController.navigationBar.bounds.midX
        )

        DemoLocalization.setLocale(identifier: "zh-Hans")
        DemoLocalization.reloadLanguageMenu(on: viewController)
        navigationController.navigationBar.semanticContentAttribute =
            .forceLeftToRight
        navigationController.navigationBar.setNeedsLayout()
        navigationController.navigationBar.layoutIfNeeded()

        #expect(viewController.navigationItem.rightBarButtonItem === languageItem)
        #expect(viewController.navigationItem.leftBarButtonItem == nil)
        let returnedItemView = try #require(
            navigationController.navigationBar
                .allSubviews(of: UIView.self)
                .first {
                    $0.accessibilityIdentifier == "demo.language.menu"
                }
        )
        let returnedFrame = returnedItemView.convert(
            returnedItemView.bounds,
            to: navigationController.navigationBar
        )
        #expect(
            returnedFrame.midX
                > navigationController.navigationBar.bounds.midX
        )
    }

    @Test func liveRoomKeepsSystemBackButtonAfterSwitchingToArabic() {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer { DemoLocalization.setLocale(identifier: "en-US") }

        let rootViewController = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: rootViewController
        )
        let liveRoomViewController = LiveRoomViewController()
        navigationController.pushViewController(
            liveRoomViewController,
            animated: false
        )
        liveRoomViewController.loadViewIfNeeded()

        #expect(navigationController.viewControllers.count == 2)
        #expect(liveRoomViewController.navigationItem.leftBarButtonItem == nil)
        #expect(!liveRoomViewController.navigationItem.hidesBackButton)

        DemoLocalization.setLocale(identifier: "ar")
        DemoLocalization.reloadLanguageMenu(on: liveRoomViewController)

        let languageItem = liveRoomViewController.navigationItem
            .rightBarButtonItem
        #expect(
            languageItem?.accessibilityIdentifier == "demo.language.menu"
        )
        #expect(liveRoomViewController.navigationItem.leftBarButtonItem == nil)
        #expect(!liveRoomViewController.navigationItem.hidesBackButton)
    }

    @Test func plainNavigationPreviewReceivesLanguageMenuSelections() async throws {
        DemoLocalization.setLocale(identifier: "en-US")

        let profileViewController = ProfileViewController()
        let navigationController = UINavigationController(
            rootViewController: profileViewController
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )

        defer {
            DemoLocalization.unregister(window: window)
            window.isHidden = true
            DemoLocalization.setLocale(identifier: "en-US")
        }

        #expect(profileViewController.title == "Profile")

        DemoLocalization.setLocale(identifier: "ar")
        let appliedArabic = await waitForCondition {
            profileViewController.title
                == DemoLocalization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceRightToLeft
                && profileViewController.view.semanticContentAttribute
                    == .forceRightToLeft
        }
        #expect(appliedArabic)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        let appliedChinese = await waitForCondition {
            profileViewController.title
                == DemoLocalization.text("demo.profile.title")
                && window.semanticContentAttribute == .forceLeftToRight
                && profileViewController.view.semanticContentAttribute
                    == .forceLeftToRight
        }
        #expect(appliedChinese)
    }

    @Test func localizationStringCatalogContainsSupportedLocales() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        for key in [
            "main.title",
            "demo.safeAreaPadding.title",
            "safeAreaPadding.intro",
            "safeAreaPadding.previous",
            "safeAreaPadding.next",
            "demo.localizationOverview.title",
            "demo.uikitLocalization.title",
            "demo.swiftUIBridge.title",
            "demo.tableMessages.title",
            "demo.tableMessages.header",
            "demo.tableMessages.header.detail",
            "demo.tableMessages.footer",
            "dynamic.item.title",
            "dynamic.item.deleteHint",
            "dynamic.item.deleteButton",
            "dynamic.item.deleteAccessibilityHint",
            "common.boolean.false",
            "common.boolean.true",
            "gesture.translation",
            "keyboard.diagnostics.event",
            "keyboard.diagnostics.height",
            "keyboard.diagnostics.intersection",
            "keyboard.diagnostics.rawFrame",
            "navigation.edge.left",
            "navigation.edge.right",
            "navigation.edge.summary",
            "liveRoom.user.host",
            "liveRoom.user.individual.1",
            "liveRoom.user.individual.2",
            "liveRoom.user.individual.3",
            "liveRoom.user.individual.4",
            "liveRoom.user.party.1",
            "liveRoom.user.party.2",
            "liveRoom.user.party.3",
            "liveRoom.user.party.4",
            "liveRoom.user.party.5",
            "liveRoom.user.party.6",
        ] {
            let localizations = try #require(catalog.strings[key]?.localizations)
            #expect(localizations["en"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["zh-Hans"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
        }
    }

    @Test func arabicLocalizationsDoNotContainHanCharacters() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        let keysContainingHan: [String] = catalog.strings.compactMap {
            key, entry -> String? in
            guard let value = entry.localizations?["ar"]?.stringUnit.value else {
                return nil
            }
            let containsHan = value.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                    return true
                default:
                    return false
                }
            }
            return containsHan ? key : nil
        }

        #expect(keysContainingHan.isEmpty)
    }

    @Test func infoPlistStringCatalogContainsDisplayName() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("InfoPlist.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)
        let localizations = try #require(catalog.strings["CFBundleDisplayName"]?.localizations)

        #expect(localizations["en"]?.stringUnit.value == "QuickLayoutKit Demo")
        #expect(localizations["zh-Hans"]?.stringUnit.value == "QuickLayoutKit 演示")
        #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
    }

    @Test func mainMenuUsesListKitCellsWithQuickLayoutContentViews() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        #expect(main.view is QuickLayoutView)
        #expect(main.collectionView.superview === main.view)
        #expect(main.view.allSubviews(of: QuickLayoutScrollView.self).isEmpty)
        #expect(main.collectionView.numberOfSections == 3)
        #expect(main.collectionView.numberOfItems(inSection: 0) == 14)
        #expect(main.collectionView.numberOfItems(inSection: 1) == 1)
        #expect(main.collectionView.numberOfItems(inSection: 2) == 6)

        let cell = try mainMenuCell(
            at: IndexPath(item: 0, section: 0),
            in: main
        )
        let configuration = try #require(
            cell.contentConfiguration as? MainMenuContentConfiguration
        )
        let contentView = try #require(
            cell
                .allSubviews(of: MainMenuContentView.self)
                .first
        )

        #expect(configuration.title == "横向滚动")
        #expect(contentView.titleLabel.text == configuration.title)
        #expect(contentView.superview != nil)
        #expect(
            contentView.intrinsicContentSize
                == CGSize(
                    width: UIView.noIntrinsicMetric,
                    height: UIView.noIntrinsicMetric
                )
        )

        let narrowSize = contentView.sizeThatFits(
            CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        )
        let wideSize = contentView.sizeThatFits(
            CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude)
        )
        #expect(abs(narrowSize.width - 180) < 1)
        #expect(abs(wideSize.width - 320) < 1)
        #expect(narrowSize.height >= 52)
        #expect(wideSize.height >= 52)
        #expect(cell.accessories.isEmpty)
    }

    @Test func mainMenuReloadsRouteTitlesAfterLanguageChange() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        let main = MainViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 390, height: 844)
        )
        defer {
            testWindow.isHidden = true
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let chineseTitles = try [0, 1, 4].map { item in
            try mainMenuConfiguration(
                at: IndexPath(item: item, section: 2),
                in: main
            ).title
        }

        #expect(chineseTitles == ["语言中心", "UIKit 本地化", "SwiftUI 桥接"])

        DemoLocalization.setLocale(identifier: "ar")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(.rightToLeft)
        main.view.layoutIfNeeded()

        let arabicConfiguration = try mainMenuConfiguration(
            at: IndexPath(item: 0, section: 2),
            in: main
        )
        let arabicCell = try #require(
            main.collectionView.cellForItem(
                at: IndexPath(item: 0, section: 2)
            ) as? UICollectionViewListCell
        )

        #expect(
            arabicConfiguration.title
                == DemoLocalizer.live.text("demo.localizationOverview.title")
        )
        #expect(
            arabicCell.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
    }

    @Test func allLoadedUIKitDemoButtonsUseConfigurations() throws {
        DemoLocalization.setLocale(identifier: "en-US")
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let source = UIViewController()
        let navigationController = UINavigationController(
            rootViewController: source
        )
        let testWindow = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }

        let router = DemoRouter()
        var inspectedButtonCount = 0

        // SwiftUI owns the implementation behind SwiftUI.Button; this guard
        // covers the UIKit buttons authored by the Demo target.
        for route in DemoRoute.allCases where route != .swiftUIBridge {
            router.navigate(to: route, from: source)
            let destination = try #require(
                navigationController.topViewController
            )
            destination.view.frame = navigationController.view.bounds
            destination.view.setNeedsLayout()
            navigationController.view.layoutIfNeeded()
            destination.view.layoutIfNeeded()

            let buttons = destination.view.allSubviews(of: UIButton.self)
            inspectedButtonCount += buttons.count
            for button in buttons {
                #expect(
                    button.configuration != nil,
                    "\(route) contains a legacy UIButton"
                )
            }

            navigationController.popViewController(animated: false)
        }

        #expect(inspectedButtonCount > 0)
    }

    @Test func mainMenuSectionHeadersFollowQuickLayoutDirection() throws {
        DemoLocalization.setLocale(identifier: "ar")
        let main = MainViewController()
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.reloadLayoutDirection(.rightToLeft)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let headerView = try #require(
            main.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? MainMenuSectionHeaderView
        )
        let quickLayoutHeader = headerView.titleLabel

        #expect(quickLayoutHeader.textAlignment == .natural)
        #expect(
            main.collectionView.semanticContentAttribute == .forceRightToLeft
        )
        #expect(
            quickLayoutHeader.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        let rightToLeftFrame = quickLayoutHeader.convert(
            quickLayoutHeader.bounds,
            to: headerView
        )
        #expect(rightToLeftFrame.maxX > headerView.bounds.width - 32)

        DemoLocalization.setLocale(identifier: "zh-Hans")
        main.reloadLocalizedContent()
        main.reloadLayoutDirection(DemoLocalization.currentUIKitDirection)
        main.view.setNeedsLayout()
        main.view.layoutIfNeeded()

        let leftToRightHeaderView = try #require(
            main.collectionView.supplementaryView(
                forElementKind: UICollectionView.elementKindSectionHeader,
                at: IndexPath(item: 0, section: 0)
            ) as? MainMenuSectionHeaderView
        )
        let leftToRightHeader = leftToRightHeaderView.titleLabel

        #expect(leftToRightHeader.text == "QuickLayout 示例")
        #expect(leftToRightHeader.textAlignment == .natural)
        #expect(
            leftToRightHeader.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        let leftToRightFrame = leftToRightHeader.convert(
            leftToRightHeader.bounds,
            to: leftToRightHeaderView
        )
        #expect(leftToRightFrame.minX < 32)
        #expect(leftToRightFrame.minX < rightToLeftFrame.minX)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func mainMenuRebuildsAndMirrorsItsQuickLayoutContentRoundTrip() throws {
        let main = MainViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: main,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }
        main.reloadLayoutDirection(.leftToRight)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        let leftToRightCollectionView = main.collectionView
        let leftToRightAnchor = try #require(
            leftToRightCollectionView.captureLocalizationAnchor()
        )
        let ltrCell = try mainMenuCell(at: indexPath, in: main)
        let contentView = try #require(
            ltrCell
                .allSubviews(of: MainMenuContentView.self)
                .first
        )
        let ltrTitleFrame = contentView.titleLabel.convert(
            contentView.titleLabel.bounds,
            to: contentView
        )
        let ltrChevronFrame = contentView.disclosureImageView.convert(
            contentView.disclosureImageView.bounds,
            to: contentView
        )

        main.reloadLayoutDirection(.rightToLeft)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()
        let rightToLeftCollectionView = main.collectionView
        let rightToLeftAnchor = try #require(
            rightToLeftCollectionView.captureLocalizationAnchor()
        )
        let rtlCell = try mainMenuCell(at: indexPath, in: main)
        let rtlContentView = try #require(
            rtlCell
                .allSubviews(of: MainMenuContentView.self)
                .first
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlChevronFrame = rtlContentView.disclosureImageView.convert(
            rtlContentView.disclosureImageView.bounds,
            to: rtlContentView
        )

        #expect(rightToLeftCollectionView !== leftToRightCollectionView)
        #expect(leftToRightCollectionView.superview == nil)
        #expect(rightToLeftAnchor.indexPath == leftToRightAnchor.indexPath)
        #expect(
            abs(
                rightToLeftAnchor.offsetFromViewportTop
                    - leftToRightAnchor.offsetFromViewportTop
            ) < 1
        )
        #expect(
            rightToLeftCollectionView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(rtlCell.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlContentView.quickLayoutEnvironment.layoutDirection == .rightToLeft)
        #expect(rtlTitleFrame.minX > ltrTitleFrame.minX)
        #expect(rtlChevronFrame.minX < ltrChevronFrame.minX)

        main.reloadLayoutDirection(.leftToRight)
        main.view.layoutIfNeeded()
        main.collectionView.layoutIfNeeded()
        let returnedCollectionView = main.collectionView
        let returnedAnchor = try #require(
            returnedCollectionView.captureLocalizationAnchor()
        )
        let restoredCell = try mainMenuCell(at: indexPath, in: main)
        let restoredContentView = try #require(
            restoredCell
                .allSubviews(of: MainMenuContentView.self)
                .first
        )

        #expect(returnedCollectionView !== rightToLeftCollectionView)
        #expect(rightToLeftCollectionView.superview == nil)
        #expect(returnedAnchor.indexPath == leftToRightAnchor.indexPath)
        #expect(
            abs(
                returnedAnchor.offsetFromViewportTop
                    - leftToRightAnchor.offsetFromViewportTop
            ) < 1
        )
        #expect(
            returnedCollectionView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(restoredCell.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            restoredContentView.quickLayoutEnvironment.layoutDirection
                == .leftToRight
        )
        #expect(
            restoredContentView.titleLabel.convert(
                restoredContentView.titleLabel.bounds,
                to: restoredContentView
            ).approximatelyEquals(ltrTitleFrame)
        )
    }

    @Test func mainMenuSelectionRoutesThroughListKit() throws {
        let router = RecordingDemoRouter()
        let main = MainViewController(
            viewModel: MainViewModel(),
            router: router
        )
        main.loadViewIfNeeded()
        main.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        main.view.layoutIfNeeded()

        let indexPath = IndexPath(item: 0, section: 0)
        _ = try mainMenuCell(at: indexPath, in: main)
        main.collectionView.delegate?.collectionView?(
            main.collectionView,
            didSelectItemAt: indexPath
        )

        #expect(router.routes == [.horizontalScroll])
    }

    @Test func explicitViewTargetsFollowTheWindowDirectionRoundTrip() throws {
        let rootViewController = UIViewController()
        let window = try makeVisibleTestWindow(
            rootViewController: rootViewController,
            size: CGSize(width: 390, height: 844)
        )
        defer { window.isHidden = true }
        let inheritedContainer = UIView()
        let inheritedLabel = UILabel()
        inheritedContainer.addSubview(inheritedLabel)
        rootViewController.view.addSubview(inheritedContainer)
        window.semanticContentAttribute = .forceRightToLeft
        UIViewLayoutDirectionUpdater.apply(
            DemoLocalization.layoutDirectionUpdate(.rightToLeft),
            to: [rootViewController.view, inheritedContainer, inheritedLabel]
                .map {
                    UIViewLayoutDirectionTarget(
                        $0,
                        policy: .followApplication
                    )
                }
        )
        window.layoutIfNeeded()

        #expect(window.semanticContentAttribute == .forceRightToLeft)
        #expect(rootViewController.view.semanticContentAttribute == .forceRightToLeft)
        #expect(inheritedContainer.semanticContentAttribute == .forceRightToLeft)
        #expect(inheritedLabel.semanticContentAttribute == .forceRightToLeft)
        #expect(
            inheritedLabel.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )

        window.semanticContentAttribute = .forceLeftToRight
        UIViewLayoutDirectionUpdater.apply(
            DemoLocalization.layoutDirectionUpdate(.leftToRight),
            to: [rootViewController.view, inheritedContainer, inheritedLabel]
                .map {
                    UIViewLayoutDirectionTarget(
                        $0,
                        policy: .followApplication
                    )
                }
        )
        window.layoutIfNeeded()

        #expect(window.semanticContentAttribute == .forceLeftToRight)
        #expect(inheritedContainer.semanticContentAttribute == .forceLeftToRight)
        #expect(inheritedLabel.semanticContentAttribute == .forceLeftToRight)
        #expect(
            inheritedLabel.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
    }

    @Test func profileComposesMeasuredSectionViewsWithoutIntrinsicSizeAssumptions() throws {
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        scrollView.layoutIfNeeded()

        let sections: [ProfileSectionView] = [
            try #require(
                viewController.view.allSubviews(of: ProfileHeroView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileStatsView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileAboutView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActivityView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileSkillsView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActionsView.self).first
            )
        ]

        #expect(sections.count == 6)
        #expect(sections.allSatisfy { $0.bounds.width > 0 })
        #expect(sections.allSatisfy { $0.bounds.height > 0 })
        #expect(
            sections.allSatisfy {
                $0.quickLayoutSemanticDirectionBehavior
                    == .followEnclosingContainer
            }
        )

        let heroView = try #require(sections.first as? ProfileHeroView)
        #expect(heroView.intrinsicContentSize.width == UIView.noIntrinsicMetric)
        #expect(heroView.intrinsicContentSize.height == UIView.noIntrinsicMetric)
        #expect(heroView.quickLayoutHorizontalFlexibility == nil)
        #expect(heroView.quickLayoutVerticalFlexibility == nil)
        #expect(heroView.quick_flexibility(for: .horizontal) == .partial)
        #expect(heroView.quick_flexibility(for: .vertical) == .partial)
        let measuredHeroSize = heroView.sizeThatFits(
            CGSize(
                width: heroView.bounds.width,
                height: CGFloat.infinity
            )
        )
        #expect(abs(heroView.bounds.height - measuredHeroSize.height) < 1)
        #expect(heroView.layer.shadowPath != nil)
    }

    @Test func profileKeepsLandscapeSectionsInsideTheSafeViewport() throws {
        DemoLocalization.setLocale(identifier: "zh-Hans")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let viewController = ProfileViewController()
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        navigationController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: 47,
            bottom: 21,
            right: 59
        )
        let window = try makeVisibleTestWindow(
            rootViewController: navigationController,
            size: CGSize(width: 844, height: 390)
        )
        defer {
            window.isHidden = true
        }

        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()
        viewController.view.setNeedsLayout()
        window.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let sections = viewController.view.allSubviews(
            of: ProfileSectionView.self
        )
        let safeAreaInsets = viewController.view.safeAreaInsets
        let scrollFrame = scrollView.convert(
            scrollView.bounds,
            to: viewController.view
        )

        #expect(scrollFrame.approximatelyEquals(viewController.view.bounds))
        #expect(sections.count >= 6)
        #expect(safeAreaInsets.left >= 47)
        #expect(safeAreaInsets.right >= 59)
        #expect(scrollView.contentInset.left >= 16)
        #expect(scrollView.contentInset.right >= 16)
        #expect(
            scrollView.adjustedContentInset.left
                >= safeAreaInsets.left + 16
        )
        #expect(
            scrollView.adjustedContentInset.right
                >= safeAreaInsets.right + 16
        )
        #expect(
            sections.allSatisfy { section in
                let frame = section.convert(
                    section.bounds,
                    to: viewController.view
                )
                return frame.minX >= safeAreaInsets.left + 16 - 1
                    && frame.maxX <= viewController.view.bounds.maxX
                        - safeAreaInsets.right - 16 + 1
            }
        )
    }

    @Test func profileCardTitlesShareTheSameLogicalLeadingEdge() throws {
        DemoLocalization.setLocale(identifier: "ar")
        defer {
            DemoLocalization.setLocale(identifier: "en-US")
        }

        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 402,
            height: 1200
        )
        viewController.view.layoutIfNeeded()

        DemoLocalization.setLocale(identifier: "en-US")
        viewController.applyLocalization(
            .initial(
                snapshot: DemoLocalization.localizationController.currentSnapshot
            )
        )

        let cards: [ProfileCardView] = [
            try #require(
                viewController.view.allSubviews(of: ProfileAboutView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileActivityView.self).first
            ),
            try #require(
                viewController.view.allSubviews(of: ProfileSkillsView.self).first
            )
        ]
        let titleTexts = [
            DemoLocalization.text("profile.section.about"),
            DemoLocalization.text("profile.section.activity"),
            DemoLocalization.text("profile.section.skills")
        ]
        let titleLabels = try titleTexts.map { title in
            try #require(
                viewController.view.allSubviews(of: UILabel.self).first {
                    $0.text == title
                }
            )
        }
        let aboutView = try #require(cards.first as? ProfileAboutView)
        aboutView.configure(
            title: titleTexts[0],
            body: "Short localized body."
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        let ltrLeadingEdges = zip(cards, titleLabels).map { card, label in
            label.convert(label.bounds, to: card).minX
        }

        #expect(cards.allSatisfy { abs($0.bounds.width - 370) < 0.001 })
        #expect(ltrLeadingEdges.allSatisfy { abs($0 - 16) < 0.001 })

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        let rtlLeadingEdges = zip(cards, titleLabels).map { card, label in
            card.bounds.maxX - label.convert(label.bounds, to: card).maxX
        }

        #expect(rtlLeadingEdges.allSatisfy { abs($0 - 16) < 0.001 })
    }

    @Test func profileSectionOwnedButtonsRecoverTheirDirectionRoundTrip() throws {
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        let actionsView = try #require(
            viewController.view
                .allSubviews(of: ProfileActionsView.self)
                .first
        )
        actionsView.layoutIfNeeded()
        let buttons = actionsView.allSubviews(of: UIButton.self)

        #expect(actionsView.semanticContentAttribute == .forceRightToLeft)
        #expect(buttons.count == 2)
        #expect(
            buttons.allSatisfy {
                $0.semanticContentAttribute == .forceRightToLeft
                    && $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        actionsView.layoutIfNeeded()

        #expect(actionsView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            buttons.allSatisfy {
                $0.semanticContentAttribute == .forceLeftToRight
                    && $0.effectiveUserInterfaceLayoutDirection == .leftToRight
            }
        )
    }

    @Test func profileSkillFlowReusesAndMirrorsItsFirstChipRoundTrip() throws {
        let firstSkillTitle = DemoLocalization.text("profile.skill.uikit")
        let viewController = ProfileViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 1200
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        scrollView.layoutIfNeeded()
        let skillLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text == firstSkillTitle
            }
        )
        let chip = try #require(skillLabel.superview)
        let skillCloud = try #require(chip.superview)
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()
        let ltrChipFrame = chip.convert(chip.bounds, to: skillCloud)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()
        let rtlChipFrame = chip.convert(chip.bounds, to: skillCloud)

        #expect(skillLabel.superview === chip)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(chip.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(skillCloud.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlChipFrame.minX > ltrChipFrame.minX)
        #expect(
            isHorizontalMirror(
                rtlChipFrame,
                of: ltrChipFrame,
                in: skillCloud.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        skillCloud.layoutIfNeeded()
        chip.layoutIfNeeded()

        #expect(chip.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            chip.convert(chip.bounds, to: skillCloud)
                .approximatelyEquals(ltrChipFrame)
        )
    }

    @Test func overviewPageReflectsArabicDirection() {
        DemoLocalization.setLocale(identifier: "ar")
        let viewController = LocalizationOverviewViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.setNeedsLayout()
        viewController.view.layoutIfNeeded()

        let labels = viewController.view.allSubviews(of: UILabel.self).compactMap(\.text)

        #expect(labels.contains { $0.contains("RTL") })
        #expect(viewController.view.semanticContentAttribute == .forceRightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func uikitShowcaseAppliesCollectionDirection() throws {
        DemoLocalization.setLocale(identifier: "ar")
        let viewController = UIKitLocalizationShowcaseViewController()
        viewController.loadViewIfNeeded()
        viewController.reloadLayoutDirection(.rightToLeft)

        let collectionView = try #require(viewController.view.allSubviews(of: UICollectionView.self).first)

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)

        DemoLocalization.setLocale(identifier: "en-US")
    }

    @Test func localizationOverviewMirrorsItsReusedLeadingContent() throws {
        var usesRightToLeftLayout = false
        let localizer = DemoLocalizer { key, _ in key }
        let languageIdentifier = "test.system"
        let service = LocalizationOverviewService(
            snapshot: {
                LocalizationOverviewService.Snapshot(
                    currentLanguageSummary: "System",
                    usesRightToLeftLayout: usesRightToLeftLayout,
                    selectedIdentifier: languageIdentifier,
                    languages: [
                        LocalizationOverviewService.Language(
                            identifier: languageIdentifier,
                            nativeName: "",
                            localizedName: "System",
                            isFollowSystemOption: true
                        )
                    ]
                )
            },
            selectLanguage: { _ in }
        )
        let viewController = LocalizationOverviewViewController(
            viewModel: LocalizationOverviewViewModel(
                localizer: localizer,
                service: service
            )
        )
        let testWindow = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 390, height: 844)
        )
        defer { testWindow.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let bodyLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text == "localization.overview.body"
            }
        )
        let languageButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == languageIdentifier
            }
        )
        let ltrBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let ltrButtonTitleFrame = try #require(languageButton.titleLabel).convert(
            languageButton.titleLabel!.bounds,
            to: languageButton
        )
        let ltrButtonImageFrame = try #require(languageButton.imageView).convert(
            languageButton.imageView!.bounds,
            to: languageButton
        )
        let ltrConfiguration = try #require(languageButton.configuration)
        let expectedTitle = try #require(ltrConfiguration.title)

        #expect(ltrConfiguration.image != nil)
        #expect(languageButton.titleLabel?.text == expectedTitle)
        #expect(languageButton.imageView?.image != nil)
        #expect(ltrButtonTitleFrame.midX < ltrButtonImageFrame.midX)
        #expect(bodyLabel.effectiveUserInterfaceLayoutDirection == .leftToRight)

        usesRightToLeftLayout = true
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        languageButton.layoutIfNeeded()

        let updatedButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first {
                $0.accessibilityIdentifier == languageIdentifier
            }
        )
        let rtlBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let rtlButtonTitleFrame = try #require(updatedButton.titleLabel).convert(
            updatedButton.titleLabel!.bounds,
            to: updatedButton
        )
        let rtlButtonImageFrame = try #require(updatedButton.imageView).convert(
            updatedButton.imageView!.bounds,
            to: updatedButton
        )
        let rtlConfiguration = try #require(updatedButton.configuration)

        #expect(updatedButton === languageButton)
        #expect(rtlConfiguration.title == expectedTitle)
        #expect(rtlConfiguration.image != nil)
        #expect(updatedButton.titleLabel?.text == expectedTitle)
        #expect(updatedButton.imageView?.image != nil)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(bodyLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(updatedButton.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlButtonTitleFrame.midX > rtlButtonImageFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlBodyFrame,
                of: ltrBodyFrame,
                in: scrollView.contentSize.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlButtonTitleFrame,
                of: ltrButtonTitleFrame,
                in: updatedButton.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlButtonImageFrame,
                of: ltrButtonImageFrame,
                in: updatedButton.bounds.width
            )
        )
        #expect(
            viewController.view.allSubviews(of: UILabel.self).contains {
                $0.text == "language.direction: RTL"
            }
        )

        usesRightToLeftLayout = false
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        languageButton.layoutIfNeeded()

        let returnedBodyFrame = bodyLabel.convert(bodyLabel.bounds, to: scrollView)
        let returnedButtonTitleFrame = try #require(languageButton.titleLabel)
            .convert(languageButton.titleLabel!.bounds, to: languageButton)
        let returnedButtonImageFrame = try #require(languageButton.imageView)
            .convert(languageButton.imageView!.bounds, to: languageButton)

        #expect(languageButton.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(returnedBodyFrame.approximatelyEquals(ltrBodyFrame))
        #expect(returnedButtonTitleFrame.approximatelyEquals(ltrButtonTitleFrame))
        #expect(returnedButtonImageFrame.approximatelyEquals(ltrButtonImageFrame))
    }

    @Test func formFieldMirrorsTheSameIconAndTextFieldAcrossDirectionChanges() {
        let viewController = ScrollViewWithKeyboardViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let fieldView = viewController.nameFieldView
        let iconView = fieldView.iconView
        let textField = fieldView.textField
        fieldView.layoutIfNeeded()
        let ltrIconFrame = iconView.convert(iconView.bounds, to: fieldView)
        let ltrTextFieldFrame = textField.convert(textField.bounds, to: fieldView)

        #expect(ltrIconFrame.midX < ltrTextFieldFrame.midX)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        fieldView.layoutIfNeeded()

        let rtlIconFrame = iconView.convert(iconView.bounds, to: fieldView)
        let rtlTextFieldFrame = textField.convert(textField.bounds, to: fieldView)

        #expect(fieldView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(fieldView.semanticContentAttribute == .forceRightToLeft)
        #expect(iconView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(textField.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(rtlIconFrame.midX > rtlTextFieldFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlIconFrame,
                of: ltrIconFrame,
                in: fieldView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTextFieldFrame,
                of: ltrTextFieldFrame,
                in: fieldView.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        fieldView.layoutIfNeeded()

        #expect(fieldView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            iconView.convert(iconView.bounds, to: fieldView)
                .approximatelyEquals(ltrIconFrame)
        )
        #expect(
            textField.convert(textField.bounds, to: fieldView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
    }

    @Test func semanticSectionsMirrorOnlyTheUnspecifiedQuickLayoutRows() throws {
        let viewController = SemanticContentDemoViewController()
        let testWindow = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 390, height: 1600)
        )
        defer { testWindow.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()

        let unspecifiedRow = viewController.unspecifiedSection.example2
        let forcedLTRRow = viewController.ltrSection.example2
        let forcedRTLRow = viewController.rtlSection.example2
        [unspecifiedRow, forcedLTRRow, forcedRTLRow].forEach {
            $0.layoutIfNeeded()
        }

        let unspecifiedLeading = unspecifiedRow.leadingBackgroundView
        let forcedLTRLeading = forcedLTRRow.leadingBackgroundView
        let forcedRTLLeading = forcedRTLRow.leadingBackgroundView
        let ltrUnspecifiedFrame = unspecifiedLeading.convert(
            unspecifiedLeading.bounds,
            to: unspecifiedRow
        )
        let ltrForcedLTRFrame = forcedLTRLeading.convert(
            forcedLTRLeading.bounds,
            to: forcedLTRRow
        )
        let ltrForcedRTLFrame = forcedRTLLeading.convert(
            forcedRTLLeading.bounds,
            to: forcedRTLRow
        )

        #expect(
            ltrUnspecifiedFrame.midX
                < unspecifiedRow.trailingBackgroundView.frame.midX
        )
        #expect(
            ltrForcedLTRFrame.midX
                < forcedLTRRow.trailingBackgroundView.frame.midX
        )
        #expect(
            ltrForcedRTLFrame.midX
                > forcedRTLRow.trailingBackgroundView.frame.midX
        )

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        [unspecifiedRow, forcedLTRRow, forcedRTLRow].forEach {
            $0.layoutIfNeeded()
        }

        let rtlUnspecifiedFrame = unspecifiedLeading.convert(
            unspecifiedLeading.bounds,
            to: unspecifiedRow
        )
        let rtlForcedLTRFrame = forcedLTRLeading.convert(
            forcedLTRLeading.bounds,
            to: forcedLTRRow
        )
        let rtlForcedRTLFrame = forcedRTLLeading.convert(
            forcedRTLLeading.bounds,
            to: forcedRTLRow
        )

        #expect(unspecifiedRow.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(unspecifiedRow.semanticContentAttribute == .forceRightToLeft)
        #expect(forcedLTRRow.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(forcedRTLRow.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(
            rtlUnspecifiedFrame.midX
                > unspecifiedRow.trailingBackgroundView.frame.midX
        )
        #expect(
            rtlForcedLTRFrame.midX
                < forcedLTRRow.trailingBackgroundView.frame.midX
        )
        #expect(
            rtlForcedRTLFrame.midX
                > forcedRTLRow.trailingBackgroundView.frame.midX
        )
        #expect(
            isHorizontalMirror(
                rtlUnspecifiedFrame,
                of: ltrUnspecifiedFrame,
                in: unspecifiedRow.bounds.width
            )
        )
        #expect(rtlForcedLTRFrame.approximatelyEquals(ltrForcedLTRFrame))
        #expect(rtlForcedRTLFrame.approximatelyEquals(ltrForcedRTLFrame))

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        viewController.scrollView.layoutIfNeeded()
        unspecifiedRow.layoutIfNeeded()

        #expect(unspecifiedRow.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(
            unspecifiedLeading.convert(unspecifiedLeading.bounds, to: unspecifiedRow)
                .approximatelyEquals(ltrUnspecifiedFrame)
        )
    }

    @Test func representableParentRelaysDirectionToItsExistingChild() throws {
        let viewController = ViewControllerRepresentableDemoViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let scrollView = try #require(
            viewController.view
                .allSubviews(of: QuickLayoutScrollView.self)
                .first
        )
        let stateLabel = try #require(
            viewController.view.allSubviews(of: UILabel.self).first {
                $0.text?.contains("LazyView isLoaded") == true
            }
        )
        let showButton = try #require(
            viewController.view.allSubviews(of: UIButton.self).first
        )
        let ltrStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        let rtlStateFrame = stateLabel.convert(stateLabel.bounds, to: scrollView)

        #expect(stateLabel.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(scrollView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            isHorizontalMirror(
                rtlStateFrame,
                of: ltrStateFrame,
                in: scrollView.contentSize.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        #expect(
            stateLabel.convert(stateLabel.bounds, to: scrollView)
                .approximatelyEquals(ltrStateFrame)
        )

        showButton.sendActions(for: .touchUpInside)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()

        let child = try #require(viewController.children.first)
        let childView = child.view!
        let childIdentity = ObjectIdentifier(child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(ObjectIdentifier(viewController.children[0]) == childIdentity)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        let childLabels = childView.subviews.compactMap { $0 as? UILabel }
        let childButtons = childView.subviews.compactMap { $0 as? UIButton }
        #expect(childLabels.count == 2)
        #expect(childButtons.count == 1)
        #expect(childButtons.allSatisfy { $0.configuration != nil })
        #expect(
            childLabels.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )
        #expect(
            childButtons.allSatisfy {
                $0.effectiveUserInterfaceLayoutDirection == .rightToLeft
            }
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        scrollView.layoutIfNeeded()
        childView.layoutIfNeeded()

        #expect(viewController.children.first === child)
        #expect(childView.effectiveUserInterfaceLayoutDirection == .leftToRight)
    }

    @Test func keyboardControllerUpdatesItsNestedViewWithoutMovingVerticalContent() throws {
        let viewController = KeyboardHandlingViewController()
        viewController.loadViewIfNeeded()
        viewController.view.frame = CGRect(
            x: 0,
            y: 0,
            width: 390,
            height: 844
        )
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let keyboardView = try #require(
            viewController.view
                .allSubviews(of: AnimatedKeyboardResponsiveView.self)
                .first
        )
        keyboardView.layoutIfNeeded()
        let textField = keyboardView.textField
        let submitButton = keyboardView.submitButton
        let ltrTextFieldFrame = textField.convert(textField.bounds, to: keyboardView)
        let ltrSubmitFrame = submitButton.convert(
            submitButton.bounds,
            to: keyboardView
        )

        #expect(ltrTextFieldFrame.maxY < ltrSubmitFrame.minY)
        #expect(textField.textAlignment == .left)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        keyboardView.layoutIfNeeded()

        #expect(keyboardView.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(keyboardView.semanticContentAttribute == .forceRightToLeft)
        #expect(textField.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(submitButton.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        #expect(textField.textAlignment == .right)
        #expect(
            textField.convert(textField.bounds, to: keyboardView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
        #expect(
            submitButton.convert(submitButton.bounds, to: keyboardView)
                .approximatelyEquals(ltrSubmitFrame)
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        keyboardView.layoutIfNeeded()

        #expect(keyboardView.effectiveUserInterfaceLayoutDirection == .leftToRight)
        #expect(textField.textAlignment == .left)
        #expect(
            textField.convert(textField.bounds, to: keyboardView)
                .approximatelyEquals(ltrTextFieldFrame)
        )
        #expect(
            submitButton.convert(submitButton.bounds, to: keyboardView)
                .approximatelyEquals(ltrSubmitFrame)
        )
    }

    @Test func collectionMessagesInheritDirectionForVisibleAndNewContent() async throws {
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, _ in prefix + key }
        let viewController = MesssageViewController(
            viewModel: MessageListViewModel(
                configuration: .collection,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 220)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let collectionView = try #require(
            viewController.view.allSubviews(of: UICollectionView.self).first
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        #expect(
            !collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )

        let cell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let contentView = cell.messageContentView
        contentView.layoutIfNeeded()
        let avatarView = contentView.avatarView
        let titleLabel = contentView.titleLabel
        let ltrAvatarFrame = avatarView.convert(avatarView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)
        // Local QuickLayout frames can look correct while UICollectionView's
        // reusable-view coordinate mapping is still mirrored. Keep a physical
        // window-space baseline to catch that stale UIKit state.
        let ltrAvatarWindowFrame = avatarView.convert(
            avatarView.bounds,
            to: window
        )
        let ltrTitleWindowFrame = titleLabel.convert(
            titleLabel.bounds,
            to: window
        )

        #expect(titleLabel.text == "ltr.messages.title.1")
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(cell.semanticContentAttribute == .forceLeftToRight)
        #expect(cell.contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(avatarView.semanticContentAttribute == .unspecified)
        #expect(titleLabel.semanticContentAttribute == .unspecified)
        #expect(contentView.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrAvatarFrame.midX < ltrTitleFrame.midX)

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let rtlCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let rtlContentView = rtlCell.messageContentView
        rtlContentView.layoutIfNeeded()
        let rtlAvatarFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: rtlContentView
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlAvatarWindowFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: window
        )
        let rtlTitleWindowFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: window
        )

        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(rtlCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(rtlContentView.avatarView.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.titleLabel.semanticContentAttribute == .unspecified)
        #expect(rtlContentView.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlAvatarFrame.midX > rtlTitleFrame.midX)
        #expect(rtlAvatarWindowFrame.midX > rtlTitleWindowFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlAvatarFrame,
                of: ltrAvatarFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTitleFrame,
                of: ltrTitleFrame,
                in: rtlContentView.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let returnedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let returnedContent = returnedCell.messageContentView
        returnedContent.layoutIfNeeded()

        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .leftToRight
        )
        #expect(returnedCell.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.contentView.semanticContentAttribute
                == .forceLeftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(returnedContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(returnedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(returnedContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedCell.transform == .identity)
        #expect(returnedCell.contentView.transform == .identity)
        #expect(returnedContent.transform == .identity)
        #expect(returnedContent.titleLabel.transform == .identity)
        #expect(CATransform3DIsIdentity(returnedCell.layer.transform))
        #expect(CATransform3DIsIdentity(returnedCell.layer.sublayerTransform))
        #expect(CATransform3DIsIdentity(returnedContent.layer.transform))
        #expect(
            CATransform3DIsIdentity(returnedContent.layer.sublayerTransform)
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrAvatarFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrTitleFrame)
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: window
            )
                .approximatelyEquals(ltrAvatarWindowFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: window
            )
                .approximatelyEquals(ltrTitleWindowFrame)
        )

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? MessageCell
            else {
                return false
            }
            return cell.messageContentView.titleLabel.text
                == "rtl.messages.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        let localizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let localizedContent = localizedCell.messageContentView
        localizedContent.layoutIfNeeded()
        #expect(localizedContent.titleLabel.text == "rtl.messages.title.1")
        #expect(collectionView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            collectionView.effectiveUserInterfaceLayoutDirection
                == .rightToLeft
        )
        #expect(localizedCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(localizedContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(localizedContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(localizedContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )

        collectionView.scrollToItem(
            at: IndexPath(item: 3, section: 0),
            at: .bottom,
            animated: false
        )
        collectionView.layoutIfNeeded()

        let newlyVisibleCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 3, section: 0)
            ) as? MessageCell
        )
        let newlyVisibleContent = newlyVisibleCell.messageContentView
        newlyVisibleCell.layoutIfNeeded()
        newlyVisibleContent.layoutIfNeeded()
        let newAvatarFrame = newlyVisibleContent.avatarView.convert(
            newlyVisibleContent.avatarView.bounds,
            to: newlyVisibleContent
        )
        let newTitleFrame = newlyVisibleContent.titleLabel.convert(
            newlyVisibleContent.titleLabel.bounds,
            to: newlyVisibleContent
        )

        #expect(
            collectionView.indexPathsForVisibleItems.contains(
                IndexPath(item: 3, section: 0)
            )
        )
        #expect(newlyVisibleContent.titleLabel.text == "rtl.messages.title.4")
        #expect(newlyVisibleCell.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.contentView.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            newlyVisibleContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(newlyVisibleContent.avatarView.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.titleLabel.semanticContentAttribute == .unspecified)
        #expect(newlyVisibleContent.messageLabel.semanticContentAttribute == .unspecified)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == collectionView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newAvatarFrame.midX > newTitleFrame.midX)

        prefix = "returned."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.leftToRight)
        collectionView.scrollToItem(
            at: IndexPath(item: 0, section: 0),
            at: .top,
            animated: false
        )
        let returnedLocalizedContentDidApply = await waitForCondition {
            guard
                let cell = collectionView.cellForItem(
                    at: IndexPath(item: 0, section: 0)
                ) as? MessageCell
            else {
                return false
            }
            return cell.messageContentView.titleLabel.text
                == "returned.messages.title.1"
        }
        #expect(returnedLocalizedContentDidApply)
        viewController.view.layoutIfNeeded()
        collectionView.layoutIfNeeded()

        let returnedLocalizedCell = try #require(
            collectionView.cellForItem(
                at: IndexPath(item: 0, section: 0)
            ) as? MessageCell
        )
        let returnedLocalizedContent = returnedLocalizedCell.messageContentView
        returnedLocalizedContent.layoutIfNeeded()
        let returnedLocalizedAvatarWindowFrame =
            returnedLocalizedContent.avatarView.convert(
                returnedLocalizedContent.avatarView.bounds,
                to: window
            )
        let returnedLocalizedTitleWindowFrame =
            returnedLocalizedContent.titleLabel.convert(
                returnedLocalizedContent.titleLabel.bounds,
                to: window
            )

        #expect(
            returnedLocalizedContent.titleLabel.text
                == "returned.messages.title.1"
        )
        #expect(collectionView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedLocalizedContent.semanticContentAttribute
                == .forceLeftToRight
        )
        // 文本宽度可以因语言变化而不同；物理 leading 坐标必须回到初始 LTR，
        // 这能捕获局部 frame 正确但 window 坐标仍残留 RTL 镜像的回归。
        #expect(
            abs(
                returnedLocalizedAvatarWindowFrame.minX
                    - ltrAvatarWindowFrame.minX
            ) < 0.5
        )
        #expect(
            abs(
                returnedLocalizedTitleWindowFrame.minX
                    - ltrTitleWindowFrame.minX
            ) < 0.5
        )
        #expect(
            returnedLocalizedAvatarWindowFrame.midX
                < returnedLocalizedTitleWindowFrame.midX
        )
    }

    @Test func tableMessagesInheritDirectionForVisibleAndNewContent() async throws {
        let sectionHorizontalPadding: CGFloat = 16
        let sectionEdgeTolerance: CGFloat = 1
        let sectionSizingTolerance: CGFloat = 1.01
        var prefix = "ltr."
        let localizer = DemoLocalizer { key, _ in prefix + key }
        let viewController = MessageTableViewController(
            viewModel: MessageListViewModel(
                configuration: .table,
                localizer: localizer
            )
        )
        viewController.loadViewIfNeeded()
        let window = try makeVisibleTestWindow(
            rootViewController: viewController,
            size: CGSize(width: 320, height: 260)
        )
        defer { window.isHidden = true }
        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()

        let tableView = try #require(viewController.tableView)
        tableView.reloadData()
        tableView.layoutIfNeeded()
        #expect(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            ) == nil
        )

        let cell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let contentView = cell.messageContentView
        contentView.layoutIfNeeded()
        let avatarView = contentView.avatarView
        let titleLabel = contentView.titleLabel
        let ltrAvatarFrame = avatarView.convert(avatarView.bounds, to: contentView)
        let ltrTitleFrame = titleLabel.convert(titleLabel.bounds, to: contentView)

        let header = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let headerContent = header.sectionContentView
        headerContent.layoutIfNeeded()
        let headerTitleLabel = headerContent.titleLabel
        let headerDetailLabel = headerContent.detailLabel
        #expect(headerTitleLabel.text == "ltr.demo.tableMessages.header")
        #expect(
            headerDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let ltrHeaderTitleFrame = headerTitleLabel.convert(
            headerTitleLabel.bounds,
            to: headerContent
        )
        let ltrHeaderDetailFrame = headerDetailLabel.convert(
            headerDetailLabel.bounds,
            to: headerContent
        )

        #expect(titleLabel.text == "ltr.messages.title.1")
        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(contentView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            cell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            cell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(ltrAvatarFrame.midX < ltrTitleFrame.midX)
        #expect(headerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            header.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(headerContent.frame)
        )
        #expect(
            header.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            header.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            headerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrHeaderTitleFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                ltrHeaderDetailFrame.minX
                    - (headerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        let footer = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let footerContent = footer.sectionContentView
        footerContent.layoutIfNeeded()
        let footerTitleLabel = footerContent.titleLabel
        let footerDetailLabel = footerContent.detailLabel
        #expect(footerTitleLabel.text == "ltr.demo.tableMessages.footer")
        #expect(footerDetailLabel.text == nil)
        let ltrFooterTitleFrame = footerTitleLabel.convert(
            footerTitleLabel.bounds,
            to: footerContent
        )

        #expect(footerContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            footer.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(footerContent.frame)
        )
        #expect(
            footer.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footer.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            footerDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                ltrFooterTitleFrame.minX
                    - (footerContent.bounds.minX + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 0, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()

        viewController.reloadLayoutDirection(.rightToLeft)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()

        let rtlCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let rtlContentView = rtlCell.messageContentView
        rtlContentView.layoutIfNeeded()
        let rtlAvatarFrame = rtlContentView.avatarView.convert(
            rtlContentView.avatarView.bounds,
            to: rtlContentView
        )
        let rtlTitleFrame = rtlContentView.titleLabel.convert(
            rtlContentView.titleLabel.bounds,
            to: rtlContentView
        )
        let rtlHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let rtlHeaderContent = rtlHeader.sectionContentView
        rtlHeaderContent.layoutIfNeeded()
        let rtlHeaderTitleLabel = rtlHeaderContent.titleLabel
        let rtlHeaderDetailLabel = rtlHeaderContent.detailLabel
        #expect(rtlHeaderTitleLabel.text == "ltr.demo.tableMessages.header")
        #expect(
            rtlHeaderDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let rtlHeaderTitleFrame = rtlHeaderTitleLabel.convert(
            rtlHeaderTitleLabel.bounds,
            to: rtlHeaderContent
        )
        let rtlHeaderDetailFrame = rtlHeaderDetailLabel.convert(
            rtlHeaderDetailLabel.bounds,
            to: rtlHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(rtlContentView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlContentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(rtlAvatarFrame.midX > rtlTitleFrame.midX)
        #expect(
            isHorizontalMirror(
                rtlAvatarFrame,
                of: ltrAvatarFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlTitleFrame,
                of: ltrTitleFrame,
                in: rtlContentView.bounds.width
            )
        )
        #expect(rtlHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlHeader.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlHeaderContent.frame)
        )
        #expect(
            rtlHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeader.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlHeaderTitleFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                rtlHeaderDetailFrame.maxX
                    - (rtlHeaderContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderTitleFrame,
                of: ltrHeaderTitleFrame,
                in: rtlHeaderContent.bounds.width
            )
        )
        #expect(
            isHorizontalMirror(
                rtlHeaderDetailFrame,
                of: ltrHeaderDetailFrame,
                in: rtlHeaderContent.bounds.width
            )
        )

        viewController.reloadLayoutDirection(.leftToRight)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let returnedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let returnedContent = returnedCell.messageContentView
        returnedContent.layoutIfNeeded()
        let returnedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let returnedHeaderContent = returnedHeader.sectionContentView
        returnedHeaderContent.layoutIfNeeded()
        let returnedHeaderTitleLabel = returnedHeaderContent.titleLabel
        let returnedHeaderDetailLabel = returnedHeaderContent.detailLabel
        #expect(
            returnedHeaderTitleLabel.text
                == "ltr.demo.tableMessages.header"
        )
        #expect(
            returnedHeaderDetailLabel.text
                == "ltr.demo.tableMessages.header.detail"
        )
        let returnedHeaderTitleFrame = returnedHeaderTitleLabel.convert(
            returnedHeaderTitleLabel.bounds,
            to: returnedHeaderContent
        )
        let returnedHeaderDetailFrame = returnedHeaderDetailLabel.convert(
            returnedHeaderDetailLabel.bounds,
            to: returnedHeaderContent
        )

        #expect(tableView.semanticContentAttribute == .forceLeftToRight)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .leftToRight
        )
        #expect(returnedContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(returnedHeaderContent.semanticContentAttribute == .forceLeftToRight)
        #expect(
            returnedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedHeaderTitleFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedHeaderDetailFrame.minX
                    - (returnedHeaderContent.bounds.minX
                        + sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            returnedContent.avatarView.convert(
                returnedContent.avatarView.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrAvatarFrame)
        )
        #expect(
            returnedContent.titleLabel.convert(
                returnedContent.titleLabel.bounds,
                to: returnedContent
            )
                .approximatelyEquals(ltrTitleFrame)
        )

        prefix = "rtl."
        viewController.reloadLocalizedContent()
        viewController.reloadLayoutDirection(.rightToLeft)
        let localizedContentDidApply = await waitForCondition {
            guard
                let header = tableView.headerView(forSection: 0)
                    as? MessageTableHeaderFooterView,
                let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
                    as? MessageTableCell
            else {
                return false
            }
            return header.sectionContentView.titleLabel.text
                    == "rtl.demo.tableMessages.header"
                && cell.messageContentView.titleLabel.text
                    == "rtl.messages.title.1"
        }
        #expect(localizedContentDidApply)
        viewController.view.layoutIfNeeded()
        tableView.layoutIfNeeded()
        let localizedCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 0, section: 0)
            ) as? MessageTableCell
        )
        let localizedContent = localizedCell.messageContentView
        localizedContent.layoutIfNeeded()
        let localizedHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let localizedHeaderContent = localizedHeader.sectionContentView
        localizedHeaderContent.layoutIfNeeded()
        let localizedHeaderTitleLabel = localizedHeaderContent.titleLabel
        let localizedHeaderDetailLabel = localizedHeaderContent.detailLabel
        #expect(
            localizedHeaderTitleLabel.text
                == "rtl.demo.tableMessages.header"
        )
        #expect(
            localizedHeaderDetailLabel.text
                == "rtl.demo.tableMessages.header.detail"
        )
        let localizedHeaderTitleFrame = localizedHeaderTitleLabel.convert(
            localizedHeaderTitleLabel.bounds,
            to: localizedHeaderContent
        )
        let localizedHeaderDetailFrame = localizedHeaderDetailLabel.convert(
            localizedHeaderDetailLabel.bounds,
            to: localizedHeaderContent
        )

        #expect(localizedContent.titleLabel.text == "rtl.messages.title.1")
        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        )
        #expect(localizedContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(localizedHeaderContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            localizedHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            localizedHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                localizedHeaderTitleFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                localizedHeaderDetailFrame.maxX
                    - (localizedHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )

        tableView.scrollToRow(
            at: IndexPath(row: 11, section: 0),
            at: .top,
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.headerView(forSection: 0) == nil)

        let newlyVisibleCell = try #require(
            tableView.cellForRow(
                at: IndexPath(row: 11, section: 0)
            ) as? MessageTableCell
        )
        let newlyVisibleContent = newlyVisibleCell.messageContentView
        newlyVisibleCell.layoutIfNeeded()
        newlyVisibleContent.layoutIfNeeded()
        let newAvatarFrame = newlyVisibleContent.avatarView.convert(
            newlyVisibleContent.avatarView.bounds,
            to: newlyVisibleContent
        )
        let newTitleFrame = newlyVisibleContent.titleLabel.convert(
            newlyVisibleContent.titleLabel.bounds,
            to: newlyVisibleContent
        )
        let rtlFooter = try #require(
            tableView.footerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let rtlFooterContent = rtlFooter.sectionContentView
        rtlFooterContent.layoutIfNeeded()
        let rtlFooterTitleLabel = rtlFooterContent.titleLabel
        let rtlFooterDetailLabel = rtlFooterContent.detailLabel
        #expect(rtlFooterTitleLabel.text == "rtl.demo.tableMessages.footer")
        #expect(rtlFooterDetailLabel.text == nil)
        let rtlFooterTitleFrame = rtlFooterTitleLabel.convert(
            rtlFooterTitleLabel.bounds,
            to: rtlFooterContent
        )

        #expect(newlyVisibleContent.titleLabel.text == "rtl.messages.title.4")
        #expect(newlyVisibleContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            newlyVisibleCell.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleCell.contentView.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            newlyVisibleContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(newAvatarFrame.midX > newTitleFrame.midX)
        #expect(rtlFooterContent.semanticContentAttribute == .forceRightToLeft)
        #expect(
            rtlFooter.contentView.bounds.insetBy(dx: -1, dy: -1)
                .contains(rtlFooterContent.frame)
        )
        #expect(
            rtlFooter.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            rtlFooterDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                rtlFooterTitleFrame.maxX
                    - (rtlFooterContent.bounds.maxX - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        let rtlFooterFittingSize = rtlFooter.systemLayoutSizeFitting(
            CGSize(width: rtlFooter.bounds.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        #expect(
            abs(rtlFooter.bounds.height - rtlFooterFittingSize.height)
                <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForFooter(inSection: 0).height
                    - rtlFooter.bounds.height
            ) <= sectionSizingTolerance
        )

        tableView.setContentOffset(
            CGPoint(
                x: tableView.contentOffset.x,
                y: -tableView.adjustedContentInset.top
            ),
            animated: false
        )
        tableView.layoutIfNeeded()
        #expect(tableView.footerView(forSection: 0) == nil)

        let returnedRTLHeader = try #require(
            tableView.headerView(forSection: 0)
                as? MessageTableHeaderFooterView
        )
        let returnedRTLHeaderContent = returnedRTLHeader.sectionContentView
        returnedRTLHeaderContent.layoutIfNeeded()
        let returnedRTLHeaderTitleLabel = returnedRTLHeaderContent.titleLabel
        let returnedRTLHeaderDetailLabel = returnedRTLHeaderContent.detailLabel
        #expect(
            returnedRTLHeaderTitleLabel.text
                == "rtl.demo.tableMessages.header"
        )
        #expect(
            returnedRTLHeaderDetailLabel.text
                == "rtl.demo.tableMessages.header.detail"
        )
        let returnedRTLHeaderTitleFrame = returnedRTLHeaderTitleLabel.convert(
            returnedRTLHeaderTitleLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderDetailFrame = returnedRTLHeaderDetailLabel.convert(
            returnedRTLHeaderDetailLabel.bounds,
            to: returnedRTLHeaderContent
        )
        let returnedRTLHeaderFittingSize = returnedRTLHeader
            .systemLayoutSizeFitting(
                CGSize(width: returnedRTLHeader.bounds.width, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )

        #expect(tableView.semanticContentAttribute == .forceRightToLeft)
        #expect(
            returnedRTLHeaderContent.semanticContentAttribute
                == .forceRightToLeft
        )
        #expect(
            returnedRTLHeader.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderContent.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderTitleLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            returnedRTLHeaderDetailLabel.effectiveUserInterfaceLayoutDirection
                == tableView.effectiveUserInterfaceLayoutDirection
        )
        #expect(
            abs(
                returnedRTLHeaderTitleFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeaderDetailFrame.maxX
                    - (returnedRTLHeaderContent.bounds.maxX
                        - sectionHorizontalPadding)
            ) <= sectionEdgeTolerance
        )
        #expect(
            abs(
                returnedRTLHeader.bounds.height
                    - returnedRTLHeaderFittingSize.height
            ) <= sectionSizingTolerance
        )
        #expect(
            abs(
                tableView.rectForHeader(inSection: 0).height
                    - returnedRTLHeader.bounds.height
            ) <= sectionSizingTolerance
        )
    }

    @Test func semanticGestureUsesDirectionalLayout() {
        DemoLocalization.setLocale(identifier: "ar")

        let physicalRight = DirectionalLayout.semanticHorizontalDirection(
            translationX: 20,
            layoutDirection: DemoLocalization.currentLayoutDirection
        )
        let isBackSwipe = DirectionalLayout.isBackSwipe(
            translationX: -20,
            layoutDirection: DemoLocalization.currentLayoutDirection
        )

        #expect(physicalRight == .leading)
        #expect(isBackSwipe)

        DemoLocalization.setLocale(identifier: "en-US")
    }
}

@MainActor
@discardableResult
private func applyLiveRoomSnapshot(
    to viewController: LiveRoomViewController,
    businessMode: LiveRoomBusinessMode,
    audienceSeatState: LiveRoomAudienceSeatState
) -> Bool {
    let current = viewController.viewModel.state.snapshot
    let assignments = LiveRoomViewModel.fixtureAssignments(
        for: businessMode
    )
    return viewController.viewModel.consumeStageSnapshot(
        LiveRoomStageSnapshot(
            revision: current.revision + 1,
            businessMode: businessMode,
            audienceSeatState: audienceSeatState,
            assignments: assignments,
            capabilities: LiveRoomBusinessCapability.defaults(
                for: businessMode
            )
        )
    )
}

@MainActor
private func liveRoomAssignments(
    vacating position: Int
) -> [LiveRoomSeatAssignment] {
    LiveRoomViewModel.partyAssignments.map { assignment in
        guard assignment.position.rawValue == position else {
            return assignment
        }
        return LiveRoomSeatAssignment(
            seatID: assignment.seatID,
            slotID: assignment.slotID,
            position: assignment.position,
            occupant: nil,
            audioState: .unavailable,
            score: 0
        )
    }
}

private struct TestStringCatalog: Decodable {
    let strings: [String: TestStringCatalogEntry]
}

private struct TestStringCatalogEntry: Decodable {
    let localizations: [String: TestStringLocalization]?
}

private struct TestStringLocalization: Decodable {
    let stringUnit: TestStringUnit
}

private struct TestStringUnit: Decodable {
    let value: String
}

/// 测试专用的后台麦位流，不向生产默认数据写入任何状态。
private final class TestLiveRoomStageSnapshotProvider:
    LiveRoomStageSnapshotProviding,
    @unchecked Sendable {

    private let stream: AsyncStream<LiveRoomStageSnapshot>
    private let continuation: AsyncStream<LiveRoomStageSnapshot>.Continuation

    init() {
        let pair = AsyncStream<LiveRoomStageSnapshot>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    func stageSnapshots() async -> AsyncStream<LiveRoomStageSnapshot> {
        stream
    }

    func yield(_ snapshot: LiveRoomStageSnapshot) {
        continuation.yield(snapshot)
    }

    func finish() {
        continuation.finish()
    }
}

@MainActor
private func mainMenuCell(
    at indexPath: IndexPath,
    in viewController: MainViewController
) throws -> UICollectionViewListCell {
    viewController.collectionView.scrollToItem(
        at: indexPath,
        at: .centeredVertically,
        animated: false
    )
    viewController.collectionView.setNeedsLayout()
    viewController.collectionView.layoutIfNeeded()
    return try #require(
        viewController.collectionView.cellForItem(at: indexPath)
            as? UICollectionViewListCell
    )
}

@MainActor
private func mainMenuConfiguration(
    at indexPath: IndexPath,
    in viewController: MainViewController
) throws -> MainMenuContentConfiguration {
    let cell = try mainMenuCell(at: indexPath, in: viewController)
    return try #require(
        cell.contentConfiguration as? MainMenuContentConfiguration
    )
}

@MainActor
private func makeVisibleTestWindow(
    rootViewController: UIViewController,
    size: CGSize,
    semanticContentAttribute: UISemanticContentAttribute = .unspecified
) throws -> UIWindow {
    let windowScene = try #require(
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
    )
    let window = UIWindow(windowScene: windowScene)
    window.frame = CGRect(origin: .zero, size: size)
    window.semanticContentAttribute = semanticContentAttribute
    window.rootViewController = rootViewController
    window.isHidden = false
    rootViewController.view.frame = window.bounds
    rootViewController.view.setNeedsLayout()
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
private func activate(_ control: UIControl) {
    if let button = control as? QuickLayoutButton {
        button.performAction()
    } else {
        control.sendActions(for: .touchUpInside)
    }
}

@MainActor
private func waitForCondition(
    attempts: Int = 200,
    _ condition: () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func isHorizontalMirror(
    _ frame: CGRect,
    of originalFrame: CGRect,
    in containerWidth: CGFloat,
    tolerance: CGFloat = 1
) -> Bool {
    abs(frame.midX - (containerWidth - originalFrame.midX)) < tolerance
        && abs(frame.midY - originalFrame.midY) < tolerance
        && abs(frame.width - originalFrame.width) < tolerance
        && abs(frame.height - originalFrame.height) < tolerance
}

private func center(of view: UIView, in coordinateSpace: UIView) -> CGPoint {
    view.convert(
        CGPoint(x: view.bounds.midX, y: view.bounds.midY),
        to: coordinateSpace
    )
}

private extension CGPoint {
    func approximatelyEquals(
        _ other: CGPoint,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(x - other.x) < tolerance
            && abs(y - other.y) < tolerance
    }
}

private extension CGRect {
    func approximatelyEquals(
        _ other: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(minX - other.minX) < tolerance
            && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}

private extension String {
    /// Foundation may add Unicode bidi-isolation marks around formatted
    /// substitutions on newer SDKs. They are correct for rendering but should
    /// not make localized copy assertions SDK-dependent.
    var removingBidiIsolationMarks: String {
        replacingOccurrences(of: "\u{2066}", with: "")
            .replacingOccurrences(of: "\u{2067}", with: "")
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }
}

private extension UIView {
    func allSubviews<T: UIView>(of type: T.Type) -> [T] {
        subviews.flatMap { subview -> [T] in
            var matches: [T] = []
            if let typed = subview as? T {
                matches.append(typed)
            }
            matches.append(contentsOf: subview.allSubviews(of: type))
            return matches
        }
    }
}

private final class EnvironmentRecordingQuickLayoutView: QuickLayoutView {

    var environmentChanges: [(environment: QuickLayoutEnvironment, reason: QuickLayoutEnvironmentChangeReason)] = []

    override func quickLayoutEnvironmentDidChange(
        _ environment: QuickLayoutEnvironment,
        reason: QuickLayoutEnvironmentChangeReason
    ) {
        super.quickLayoutEnvironmentDidChange(environment, reason: reason)
        environmentChanges.append((environment, reason))
    }
}

private final class TestSafeAreaScrollView: UIScrollView {

    var testSafeAreaInsets: UIEdgeInsets = .zero

    override var safeAreaInsets: UIEdgeInsets {
        testSafeAreaInsets
    }
}

private final class RepresentableTestChildViewController: UIViewController {

    let name: String

    init(name: String) {
        self.name = name
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 180, height: 96)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        self.view = view
    }
}

@MainActor
private final class RecordingDemoRouter: DemoRouting {

    private(set) var routes: [DemoRoute] = []

    func navigate(
        to route: DemoRoute,
        from sourceViewController: UIViewController
    ) {
        routes.append(route)
    }
}
