//
//  GiftSheetViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 管理礼物面板展示、选择回调和发送请求的控制器。
final class GiftSheetViewController:
    LocalizedQuickLayoutHostingController {

    /// 当前收礼列表中的零基麦位位置。
    var recipientSeatIDs: [Int] {
        recipients.map { $0.position.rawValue }
    }
    /// 已选收礼人的零基麦位位置；用户身份由 `selectedRecipientUserIDs` 维护。
    private(set) var selectedRecipientSeatIDs: [Int]
    /// 已选择收礼人的稳定用户标识集合。
    private(set) var selectedRecipientUserIDs: [RoomUserID]
    /// 当前选中礼物的稳定标识；未选择时为 `nil`。
    private(set) var selectedGiftID: String?

    /// 礼物目录中的条目总数。
    var giftCount: Int { gifts.count }
    /// 礼物网格使用的滚动视图。
    var giftScrollView: UIScrollView {
        sheetView.giftScrollView
    }
    /// 收礼人列表使用的水平滚动视图。
    var recipientScrollView: UIScrollView {
        sheetView.recipientScrollView
    }
    /// 礼物栏目使用的水平滚动视图。
    var giftCategoryScrollView: UIScrollView {
        sheetView.categoryScrollView
    }
    /// 当前礼物网格每行的列数。
    var giftColumnCount: Int { sheetView.giftColumnCount }
    /// 当前栏目筛选后的礼物数量。
    var visibleGiftCount: Int { sheetView.visibleGiftCount }
    /// 当前选中栏目的稳定标识。
    var selectedGiftCategoryID: String { sheetView.selectedGiftCategoryID }
    /// 每名收礼人的赠送份数；初始值为 `1`。
    var selectedGiftQuantity: Int { sheetView.selectedGiftQuantity }
    /// 可选赠送数量的整数列表。
    var giftQuantityValues: [Int] { sheetView.giftQuantityValues }
    /// 当前显示的收礼人状态或选择提示文案。
    var recipientStatusText: String? { sheetView.recipientStatusText }
    /// 业务层确认后供礼物面板使用的金币余额。
    var giftBalance: Int { sheetView.giftBalance }
    /// 当前显示的余额状态或余额不足提示文案。
    var balanceStatusText: String? { sheetView.balanceStatusText }

    /// 提交赠送请求的业务回调；成功时返回确认余额，拒绝时返回 `nil`。
    var giftSendRequest: ((GiftSendRequest) -> Int?)?
    /// 余额不足时的回调；参数依次为所需余额和当前余额。
    var insufficientBalanceDidOccur: ((Int, Int) -> Void)?
    /// 用户请求关闭面板时调用的回调。
    var closeDidRequest: (() -> Void)?

    /// 当前可用的收礼麦位数据。
    private var recipients: [SeatAssignment]
    /// 按目录顺序排列的可选礼物。
    private let gifts: [Gift]
    /// 覆盖背景并接收面板外点击的按钮。
    private let backdropButton = QuickLayoutButton(frame: .zero)
    /// 礼物面板背后的模糊背景视图。
    private let backdropBlurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    /// 礼物面板周围的环境光装饰视图。
    private let ambientGlowView = GiftAmbientGlowView()
    /// 控制器管理的面板内容视图。
    private let sheetView: GiftSheetView
    /// 一个布尔值，指示面板正在执行关闭流程，防止重复退出。
    private var isClosing = false

    /// 创建礼物面板，并用当前收礼列表解析初始选择。
    ///
    /// 默认礼物目录为 `Gift.catalog`，默认金币余额为 `12_800`。初始选择中不可用的用户会被忽略。
    init(
        recipients: [SeatAssignment],
        gifts: [Gift] = Gift.catalog,
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
        sheetView = GiftSheetView(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientSeatIDs: initialSelection,
            initialBalance: initialBalance
        )
        super.init(nibName: nil, bundle: nil)
    }

    /// 创建礼物面板，并用当前收礼列表解析初始选择。
    ///
    /// 默认礼物目录为 `Gift.catalog`，默认金币余额为 `12_800`。初始选择中不可用的用户会被忽略。
    convenience init(
        recipients: [SeatAssignment],
        gifts: [Gift] = Gift.catalog,
        initiallySelectedRecipientUserIDs: [RoomUserID],
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

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 在视图加载后配置界面并连接内容与交互。
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

    /// 播放面板和背景的入场动画，并在减少动态效果时简化过渡。
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

    /// 播放面板退场动画，并在结束后调用完成回调。
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

    /// 返回礼物飞行起点在指定视图坐标系中的位置；视图不可用时为 `nil`。
    func giftAnimationOrigin(in view: UIView) -> CGPoint? {
        sheetView.giftAnimationOrigin(in: view)
    }

    /// 将零基麦位位置转换为当前用户标识后更新收礼人选择。
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

    /// 按稳定用户标识更新收礼人选择并同步面板显示。
    func setSelectedRecipientUserIDs(_ userIDs: [RoomUserID]) {
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
    func updateRecipients(_ recipients: [SeatAssignment]) {
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

    /// 尝试选择指定赠送数量，并返回是否被当前预设接受。
    @discardableResult
    func setSelectedGiftQuantity(_ quantity: Int) -> Bool {
        sheetView.setSelectedGiftQuantity(quantity)
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        backdropButton.accessibilityLabel = Localization.text(
            "liveRoom.gift.close"
        )
        sheetView.reloadLocalizedContent()
    }

    /// 应用新的界面布局方向，并使相关内容重新布局。
    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        super.reloadLayoutDirection(direction)
        sheetView.semanticContentAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        sheetView.setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 向宿主转发礼物面板关闭请求。
    @objc private func closeGiftSheet() {
        closeDidRequest?()
    }

    /// 响应辅助功能退出手势并请求关闭当前面板。
    override func accessibilityPerformEscape() -> Bool {
        closeDidRequest?()
        return true
    }

    /// 转交赠送请求给业务回调，并返回确认后的余额。
    private func send(_ request: GiftSendRequest) -> Int? {
        guard !isClosing else { return nil }
        // 发送只触发业务回调，不关闭面板，用户可以保持当前选择连续赠送。
        return giftSendRequest?(request)
    }

    /// 将礼物面板移出当前屏幕底部所需的纵向位移，单位为点。
    private var giftSheetOffscreenTranslation: CGFloat {
        GiftSheetMotionMetrics.offscreenTranslation(
            sheetHeight: sheetView.bounds.height,
            safeAreaBottom: view.safeAreaInsets.bottom
        )
    }

    /// 恢复面板完成入场后的透明度和变换状态。
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
/// 在首次完成布局后展示礼物面板的预览导航容器。
@MainActor
private final class GiftSheetPreviewNavigationController:
    UINavigationController {

    /// 预览中承载礼物面板的房间控制器。
    private let roomViewController: VoiceRoomViewController
    /// 一个布尔值，指示预览是否已经自动展示过礼物面板。
    private var didPresentGiftSheet = false

    /// 创建用于承载指定房间控制器的礼物面板预览导航栈。
    init(roomViewController: VoiceRoomViewController) {
        self.roomViewController = roomViewController
        super.init(rootViewController: roomViewController)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 在房间完成首次有效布局后自动展示预览礼物面板。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard
            !didPresentGiftSheet,
            roomViewController.viewIfLoaded?.bounds.isEmpty == false
        else { return }
        didPresentGiftSheet = true
        // 预览复用正式入口；关闭动画后可稳定展示最终状态，且不产生中间帧差异。
        UIView.performWithoutAnimation {
            roomViewController.presentGiftSheet()
        }
    }
}

/// 创建展示礼物面板控制器的预览控制器。
@MainActor
private func makeGiftSheetControllerPreview() -> UIViewController {
    let viewModel = VoiceRoomPreviewData.makeRoomViewModel(
        roomMode: .party,
        audienceSeatState: .enabled
    )
    let roomViewController = VoiceRoomViewController(
        viewModel: viewModel,
        initialGiftBalance: viewModel.giftBalance
    )
    return GiftSheetPreviewNavigationController(
        roomViewController: roomViewController
    )
}

@available(iOS 17.0, *)
#Preview("送礼面板") {
    makeGiftSheetControllerPreview()
}
#endif
