import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func voiceRoomSeatLayoutsExpandOnIPadWidth() throws {
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

        applyVoiceRoomSnapshot(
            to: viewController,
            roomMode: .individual,
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

    @Test func voiceRoomPublicChatMessagesFillAvailableWidthOnIPad() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

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

    @Test func voiceRoomNineSeatSecondRowKeepsTextAtIdealSize() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewModel = VoiceRoomViewModel(
            stageSnapshot: VoiceRoomViewModel.makeDefaultStageSnapshot(
                assignments: voiceRoomAssignments(vacating: 6)
            )
        )
        let viewController = VoiceRoomViewController(viewModel: viewModel)
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
            let speakingIndicatorView = try #require(
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
                #expect(speakingIndicatorView.isHidden)
                #expect(
                    speakingIndicatorView.layer.sublayers?.allSatisfy {
                        $0.animationKeys()?.isEmpty != false
                    } == true
                )
            } else {
                #expect(!speakingIndicatorView.isHidden)
                #expect(speakingIndicatorView.layer.sublayers?.count == 3)
                if !UIAccessibility.isReduceMotionEnabled {
                    #expect(
                        speakingIndicatorView.layer.sublayers?.allSatisfy {
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

    @Test func voiceRoomSeatNamesSeparateOccupantsFromVacantSlots() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = VoiceRoomViewController(
            viewModel: VoiceRoomViewModel()
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
                == Localization.text("liveRoom.user.party.5")
        )
        #expect(
            try seatName(at: 7)
                == Localization.text("liveRoom.user.party.6")
        )
        #expect(
            try seatName(at: 5)
                == Localization.text("liveRoom.userCard.guestSeat", 5)
        )
        #expect(
            try seatName(at: 8)
                == Localization.text("liveRoom.seat.eight")
        )
    }

    @Test func voiceRoomFiveSeatLayoutUsesLargeHostAndFitsNarrowScreen() throws {
        Localization.setLocale(identifier: "zh-Hans")
        defer { Localization.setLocale(identifier: "en-US") }

        let viewController = VoiceRoomViewController()
        applyVoiceRoomSnapshot(
            to: viewController,
            roomMode: .individual,
            audienceSeatState: .enabled
        )
        let navigationController = UINavigationController(
            rootViewController: viewController
        )
        // iPhone SE (3rd generation) portrait viewport after its 20-point
        // status bar. UINavigationController remains responsible for its bar.
        let viewportController = FixedViewportTestViewController(
            childViewController: navigationController,
            viewportSize: CGSize(width: 320, height: 548)
        )
        let window = try makeVisibleTestWindow(
            rootViewController: viewportController
        )
        defer { window.isHidden = true }

        layout(viewController, in: navigationController)

        #expect(viewController.view.bounds.size == CGSize(width: 320, height: 548))
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
        #expect(
            abs(bottomSpacing) < 1,
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

        applyVoiceRoomSnapshot(
            to: viewController,
            roomMode: .party,
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
}

@MainActor
private func voiceRoomAssignments(
    vacating position: Int
) -> [SeatAssignment] {
    VoiceRoomViewModel.partyAssignments.map { assignment in
        guard assignment.position.rawValue == position else {
            return assignment
        }
        return SeatAssignment(
            seatID: assignment.seatID,
            slotID: assignment.slotID,
            position: assignment.position,
            occupant: nil,
            audioState: .unavailable,
            score: 0
        )
    }
}

/// Hosts a deterministic device viewport inside the active scene's real safe
/// area so tests do not inherit unrelated sensor-housing insets.
private final class FixedViewportTestViewController: UIViewController {

    private let childViewController: UIViewController
    private let viewportSize: CGSize

    init(childViewController: UIViewController, viewportSize: CGSize) {
        self.childViewController = childViewController
        self.viewportSize = viewportSize
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(childViewController)
        view.addSubview(childViewController.view)
        childViewController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        childViewController.view.frame = CGRect(
            origin: view.safeAreaLayoutGuide.layoutFrame.origin,
            size: viewportSize
        )
        childViewController.view.setNeedsLayout()
        childViewController.view.layoutIfNeeded()
    }
}
