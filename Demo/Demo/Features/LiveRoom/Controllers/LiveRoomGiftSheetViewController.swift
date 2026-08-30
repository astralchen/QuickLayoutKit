//
//  LiveRoomGiftSheetViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomGiftSheetViewController:
    DemoQuickLayoutHostingController {

    var recipientSeatIDs: [Int] {
        recipients.map { $0.position.rawValue }
    }
    private(set) var selectedRecipientSeatIDs: [Int]
    private(set) var selectedRecipientUserIDs: [LiveRoomUserID]
    private(set) var selectedGiftID: String?

    var giftCount: Int { gifts.count }
    var giftScrollView: UIScrollView {
        sheetView.giftScrollView
    }
    var recipientScrollView: UIScrollView {
        sheetView.recipientScrollView
    }
    var giftCategoryScrollView: UIScrollView {
        sheetView.categoryScrollView
    }
    var giftColumnCount: Int { sheetView.giftColumnCount }
    var visibleGiftCount: Int { sheetView.visibleGiftCount }
    var selectedGiftCategoryID: String { sheetView.selectedGiftCategoryID }
    var selectedGiftQuantity: Int { sheetView.selectedGiftQuantity }
    var giftQuantityValues: [Int] { sheetView.giftQuantityValues }
    var recipientStatusText: String? { sheetView.recipientStatusText }
    var giftBalance: Int { sheetView.giftBalance }
    var balanceStatusText: String? { sheetView.balanceStatusText }

    var giftSendRequest: ((LiveRoomGiftSendRequest) -> Int?)?
    var insufficientBalanceDidOccur: ((Int, Int) -> Void)?
    var closeDidRequest: (() -> Void)?

    private var recipients: [LiveRoomSeat]
    private let gifts: [LiveRoomGift]
    private let backdropButton = QuickLayoutButton(frame: .zero)
    private let backdropBlurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    private let ambientGlowView = LiveRoomGiftAmbientView()
    private let sheetView: LiveRoomGiftSheetView
    private var isClosing = false

    init(
        recipients: [LiveRoomSeat],
        gifts: [LiveRoomGift] = LiveRoomGift.catalog,
        initiallySelectedRecipientSeatIDs: [Int] = [],
        initialBalance: Int = 12_800
    ) {
        self.recipients = recipients
        self.gifts = gifts
        let availableRecipientSeatIDs = Set(
            recipients.map { $0.position.rawValue }
        )
        let initialSelection = Set(initiallySelectedRecipientSeatIDs)
            .intersection(availableRecipientSeatIDs)
        selectedRecipientSeatIDs = recipients
            .filter { initialSelection.contains($0.position.rawValue) }
            .map { $0.position.rawValue }
        selectedRecipientUserIDs = recipients.compactMap { recipient in
            initialSelection.contains(recipient.position.rawValue)
                ? recipient.userID
                : nil
        }
        selectedGiftID = gifts.first?.id
        sheetView = LiveRoomGiftSheetView(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientSeatIDs: initialSelection,
            initialBalance: initialBalance
        )
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(
        recipients: [LiveRoomSeat],
        gifts: [LiveRoomGift] = LiveRoomGift.catalog,
        initiallySelectedRecipientUserIDs: [LiveRoomUserID],
        initialBalance: Int = 12_800
    ) {
        let selectedUserIDs = Set(initiallySelectedRecipientUserIDs)
        self.init(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientSeatIDs: recipients.compactMap {
                guard
                    let userID = $0.userID,
                    selectedUserIDs.contains(userID)
                else { return nil }
                return $0.position.rawValue
            },
            initialBalance: initialBalance
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        view.accessibilityIdentifier = "liveRoom.gift.overlay"

        backdropButton.backgroundColor = UIColor.black.withAlphaComponent(0.30)
        backdropButton.accessibilityIdentifier = "liveRoom.gift.backdrop"
        backdropButton.action = { [weak self] in self?.closeGiftSheet() }
        backdropBlurView.isUserInteractionEnabled = false
        backdropBlurView.alpha = UIAccessibility.isReduceTransparencyEnabled
            ? 0
            : 0.52
        ambientGlowView.accessibilityIdentifier =
            "liveRoom.gift.ambientGlow"
        sheetView.recipientDidSelect = { [weak self] seat in
            self?.selectedRecipientSeatIDs = seat.map {
                $0.position.rawValue
            }
            self?.selectedRecipientUserIDs = seat.compactMap(\.userID)
        }
        sheetView.giftDidSelect = { [weak self] gift in
            self?.selectedGiftID = gift.id
        }
        sheetView.sendDidTap = { [weak self] request in
            self?.send(request)
        }
        sheetView.insufficientBalanceDidOccur = { [weak self] required, balance in
            self?.insufficientBalanceDidOccur?(required, balance)
        }

        if UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled {
            backdropButton.alpha = 0
            backdropBlurView.alpha = 0
            ambientGlowView.alpha = 0
            ambientGlowView.transform = CGAffineTransform(
                scaleX: 0.96,
                y: 0.96
            )
            // 首帧先放到容器底部之外，避免子控制器装载后短暂闪现。
            sheetView.alpha = 1
            sheetView.transform = CGAffineTransform(
                translationX: 0,
                y: max(view.bounds.height, 1)
            )
        } else {
            backdropButton.alpha = 1
            ambientGlowView.alpha = 1
            ambientGlowView.transform = .identity
            sheetView.alpha = 1
            sheetView.transform = .identity
        }
    }

    func animateIn() {
        view.layoutIfNeeded()
        guard UIView.areAnimationsEnabled else {
            applyPresentedState()
            UIAccessibility.post(
                notification: .screenChanged,
                argument: sheetView
            )
            return
        }

        if UIAccessibility.isReduceMotionEnabled {
            applyPresentedState()
            UIAccessibility.post(
                notification: .screenChanged,
                argument: sheetView
            )
            return
        }

        sheetView.layer.removeAllAnimations()
        let offscreenTranslation = giftSheetOffscreenTranslation
        UIView.performWithoutAnimation {
            // 使用面板实测高度，保证无论 iPhone SE、刘海屏或 iPad 都从屏幕外完整滑入。
            sheetView.alpha = 1
            sheetView.transform = CGAffineTransform(
                translationX: 0,
                y: offscreenTranslation
            )
        }
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.90,
            initialSpringVelocity: 0.22,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.applyPresentedState()
        } completion: { _ in
            UIAccessibility.post(
                notification: .screenChanged,
                argument: self.sheetView
            )
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        guard !isClosing else { return }
        isClosing = true
        view.endEditing(true)
        view.layoutIfNeeded()
        let reducesMotion = UIAccessibility.isReduceMotionEnabled
        let offscreenTranslation = giftSheetOffscreenTranslation
        UIView.animate(
            withDuration: reducesMotion ? 0.15 : 0.28,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn]
        ) {
            self.backdropButton.alpha = 0
            self.backdropBlurView.alpha = 0
            self.ambientGlowView.alpha = 0
            self.ambientGlowView.transform = CGAffineTransform(
                scaleX: 0.98,
                y: 0.98
            )
            if reducesMotion {
                self.sheetView.alpha = 0
            } else {
                // 退场复用同一段完整位移，与入场方向严格相反。
                self.sheetView.alpha = 1
                self.sheetView.transform = CGAffineTransform(
                    translationX: 0,
                    y: offscreenTranslation
                )
            }
        } completion: { _ in
            completion()
        }
    }

    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        sheetView.giftAnimationOrigin(in: view)
    }

    func setSelectedRecipientSeatIDs(_ seatIDs: [Int]) {
        let validSeatIDs = Set(seatIDs).intersection(recipientSeatIDs)
        selectedRecipientSeatIDs = recipients
            .filter { validSeatIDs.contains($0.position.rawValue) }
            .map { $0.position.rawValue }
        selectedRecipientUserIDs = recipients.compactMap { recipient in
            validSeatIDs.contains(recipient.position.rawValue)
                ? recipient.userID
                : nil
        }
        sheetView.setSelectedRecipientSeatIDs(Set(seatIDs))
    }

    func setSelectedRecipientUserIDs(_ userIDs: [LiveRoomUserID]) {
        let validUserIDs = Set(userIDs).intersection(
            recipients.compactMap(\.userID)
        )
        selectedRecipientUserIDs = recipients.compactMap { recipient in
            guard
                let userID = recipient.userID,
                validUserIDs.contains(userID)
            else { return nil }
            return userID
        }
        selectedRecipientSeatIDs = recipients.compactMap { recipient in
            guard
                let userID = recipient.userID,
                validUserIDs.contains(userID)
            else { return nil }
            return recipient.position.rawValue
        }
        sheetView.setSelectedRecipientUserIDs(validUserIDs)
    }

    /// 在面板保持打开时更新后台当前可见收礼人。
    func updateRecipients(_ recipients: [LiveRoomSeat]) {
        self.recipients = recipients
        sheetView.updateRecipients(recipients)
        selectedRecipientUserIDs = recipients.compactMap { recipient in
            guard
                let userID = recipient.userID,
                sheetView.selectedRecipientUserIDs.contains(userID)
            else { return nil }
            return userID
        }
        selectedRecipientSeatIDs = recipients.compactMap { recipient in
            guard
                let userID = recipient.userID,
                sheetView.selectedRecipientUserIDs.contains(userID)
            else { return nil }
            return recipient.position.rawValue
        }
    }

    @discardableResult
    func setSelectedGiftQuantity(_ quantity: Int) -> Bool {
        sheetView.setSelectedGiftQuantity(quantity)
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        backdropButton.accessibilityLabel = DemoLocalization.text(
            "liveRoom.gift.close"
        )
        sheetView.reloadLocalizedContent()
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        sheetView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        sheetView.setNeedsQuickLayout()
    }

    override var body: Layout {
        ZStack(alignment: .bottom) {
            backdropButton
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            backdropBlurView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            ambientGlowView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)

            sheetView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
        }
    }

    @objc private func closeGiftSheet() {
        closeDidRequest?()
    }

    override func accessibilityPerformEscape() -> Bool {
        closeDidRequest?()
        return true
    }

    private func send(_ request: LiveRoomGiftSendRequest) -> Int? {
        guard !isClosing else { return nil }
        // 发送只触发业务回调，不关闭面板，用户可以保持当前选择连续赠送。
        return giftSendRequest?(request)
    }

    private var giftSheetOffscreenTranslation: CGFloat {
        LiveRoomGiftSheetMotionMetrics.offscreenTranslation(
            sheetHeight: sheetView.bounds.height,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    private func applyPresentedState() {
        backdropButton.alpha = 1
        backdropBlurView.alpha = UIAccessibility.isReduceTransparencyEnabled
            ? 0
            : 0.52
        ambientGlowView.alpha = 1
        ambientGlowView.transform = .identity
        sheetView.alpha = 1
        sheetView.transform = .identity
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomGiftSheetControllerPreview() -> UIViewController {
    var balance = 88_888
    let viewController = LiveRoomGiftSheetViewController(
        recipients: LiveRoomPreviewData.occupiedSeats,
        gifts: LiveRoomPreviewData.gifts,
        initiallySelectedRecipientSeatIDs: [0, 2],
        initialBalance: balance
    )
    viewController.giftSendRequest = { request in
        guard request.totalCost <= balance else { return nil }
        balance -= request.totalCost
        return balance
    }
    viewController.loadViewIfNeeded()
    UIView.performWithoutAnimation {
        viewController.animateIn()
    }
    return viewController
}

#Preview("送礼面板") {
    makeLiveRoomGiftSheetControllerPreview()
}
#endif
