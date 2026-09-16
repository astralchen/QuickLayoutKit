//
//  SeatUserCardViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class SeatUserCardViewController:
    LocalizedQuickLayoutHostingController {

    let seatID: Int

    private let showsRoom: Bool
    private let seat: SeatAssignment
    private let dismissButton = QuickLayoutButton(frame: .zero)
    private let cardView = SeatUserCardView()

    init(seat: SeatAssignment, showsRoom: Bool = false) {
        self.showsRoom = showsRoom
        self.seat = seat
        seatID = seat.id
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "liveRoom.userCard.overlay"

        dismissButton.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        dismissButton.accessibilityLabel = Localization.text("common.close")
        dismissButton.action = { [weak self] in self?.dismissUserCard() }
        cardView.closeButton.action = { [weak self] in self?.dismissUserCard() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: cardView)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        dismissButton.accessibilityLabel = Localization.text("common.close")
        cardView.configure(seat: seat, showsRoom: showsRoom)
    }

    override var body: Layout {
        ZStack {
            dismissButton
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            cardView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .frame(maxWidth: 340)
                .padding(.horizontal, 24)
        }
    }

    private func dismissUserCard() {
        dismiss(animated: true)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("用户卡片") {
    SeatUserCardViewController(seat: VoiceRoomPreviewData.seats[2])
}
#endif
