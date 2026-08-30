//
//  LiveRoomUserCardViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomUserCardViewController:
    DemoQuickLayoutHostingController {

    let seatID: Int

    private let seat: LiveRoomSeat
    private let dismissButton = QuickLayoutButton(frame: .zero)
    private let cardView = LiveRoomUserCardView()

    init(seat: LiveRoomSeat) {
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
        dismissButton.accessibilityLabel = DemoLocalization.text("common.close")
        dismissButton.action = { [weak self] in self?.dismissUserCard() }
        cardView.closeButton.action = { [weak self] in self?.dismissUserCard() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: cardView)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        dismissButton.accessibilityLabel = DemoLocalization.text("common.close")
        cardView.configure(seat: seat)
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
#Preview("用户卡片") {
    LiveRoomUserCardViewController(seat: LiveRoomPreviewData.seats[2])
}
#endif
