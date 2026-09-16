//
//  VoiceRoomViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import Combine
import QuickLayout
import QuickLayoutKit
import UIKit

final class VoiceRoomViewController: LocalizedQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.liveRoom.title" }

    let viewModel: VoiceRoomViewModel
    let backdropView = StarfieldBackgroundView()
    let roomHeaderView = RoomHeaderView()
    let seatStageView = SeatStageView()
    let messagesView = RoomPublicChatView()
    let actionBarView = RoomActionBarView()
    // 特效容器始终位于送礼面板之上，但不参与命中测试，连续赠送时不会挡住操作。
    let giftEffectOverlayView = UIView()
    var cancellables: Set<AnyCancellable> = []
    var followRequestTask: Task<Void, Never>?
    // 默认值对应 35pt 控件、上下各 10pt 内边距以及与公屏的 10pt 间距。
    // 首次测量后会按 Action Bar 的真实高度更新，避免紧凑屏幕出现额外空隙。
    var actionBarReservedHeight: CGFloat = 65
    var giftFlightAnimators: [UUID: GiftFlightAnimator] = [:]
    /// VAP、SVGA 共用的主特效队列，页面不可见时取消全部展示。
    lazy var giftMainEffectCoordinator = GiftMainEffectCoordinator { [weak self] in
        GiftMainEffectPlayer(containerView: self?.giftEffectOverlayView ?? UIView())
    }
    /// Scene 恢复前台时仅激活实际可见的房间页面。
    private var isGiftEffectPageVisible = false
    /// Scene 事件来源；测试使用独立通知中心，避免模拟事件触发系统观察者。
    private let notificationCenter: NotificationCenter
    var pendingRechargeRequiredBalance: Int?
    // representable 负责送礼子控制器的 UIKit containment，避免 modal 层级压住特效。
    var giftSheetHost: QuickLayoutViewControllerRepresentable?

    var renderedState: VoiceRoomViewModel.State?
    var lastGiftRecipientSeatIDs: [Int] = []
    var lastGiftID: String?
    var lastGiftQuantity = 1
    var giftDeliveryCount = 0
    var lastGiftAnimationOrigin: CGPoint?
    var lastGiftAnimationTargetPoints: [CGPoint] = []
    var giftSheetViewController:
        GiftSheetViewController?
    var rechargeViewController:
        RechargeViewController?
    var audienceSheetViewController:
        AudienceSheetViewController?

    lazy var seatTransitionCoordinator =
        SeatStageTransitionCoordinator(
            stageView: seatStageView,
            messagesView: messagesView
        )

    var displayedSeatCount: Int {
        renderedState?.displayedSeats.count ?? 0
    }

    var giftBalance: Int { viewModel.giftBalance }

    var publicChatScrollView: UIScrollView {
        messagesView.scrollView
    }

    var isShowingMessageComposer: Bool {
        actionBarView.isShowingMessageComposer
    }

    var latestPublicChatMessage: String? {
        messagesView.latestMessage
    }

    var presentedUserCardSeatID: Int? {
        (presentedViewController as? SeatUserCardViewController)?.seatID
    }

    var presentedAudienceMemberCount: Int? {
        audienceSheetViewController?.memberCount
    }

    var pushedRoomInformationViewController:
        RoomInformationViewController? {
        navigationController?.topViewController
            as? RoomInformationViewController
    }

    var pushedAudienceProfileViewController:
        AudienceProfileViewController? {
        navigationController?.topViewController
            as? AudienceProfileViewController
    }

    var presentedGiftRecipientSeatIDs: [Int] {
        giftSheetViewController?.recipientSeatIDs ?? []
    }

    var isGiftSheetVisible: Bool {
        giftSheetViewController != nil
    }

    var activeGiftFlightCount: Int {
        giftFlightAnimators.count
    }

    var giftEffectContainerView: UIView {
        giftEffectOverlayView
    }

    convenience init() {
        self.init(viewModel: VoiceRoomViewModel(), initialGiftBalance: 12_800)
    }

    init(
        viewModel: VoiceRoomViewModel,
        initialGiftBalance: Int = 12_800,
        notificationCenter: NotificationCenter = .default
    ) {
        self.viewModel = viewModel
        self.notificationCenter = notificationCenter
        viewModel.configureGiftBalance(initialGiftBalance)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = VoiceRoomViewModel(initialGiftBalance: 12_800)
        notificationCenter = .default
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        quickLayoutKeyboardSafeAreaBehavior = .docked(
            usesBottomSafeArea: true
        )
        configureViews()
        bindViewModel()
        viewModel.startObservingStageSnapshots()
        observeGiftEffectSceneLifecycle()
    }

    /// 页面显示后接受新主特效；先前清空的队列不会恢复。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isGiftEffectPageVisible = true
        if view.window?.windowScene?.activationState == .foregroundActive {
            giftMainEffectCoordinator.activate()
        }
    }

    /// 只响应当前页面所属 Scene，避免多窗口后台事件误停其他房间。
    private func observeGiftEffectSceneLifecycle() {
        notificationCenter.publisher(for: UIScene.didEnterBackgroundNotification)
            .sink { [weak self] notification in
                guard let self, let scene = notification.object as? UIScene,
                      scene === self.view.window?.windowScene else { return }
                self.giftMainEffectCoordinator.deactivate()
            }
            .store(in: &cancellables)
        notificationCenter.publisher(for: UIScene.didActivateNotification)
            .sink { [weak self] notification in
                guard let self, self.isGiftEffectPageVisible,
                      let scene = notification.object as? UIScene,
                      scene === self.view.window?.windowScene else { return }
                self.giftMainEffectCoordinator.activate()
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let didChangeCompactPresentation = seatStageView.setCompactPresentation(
            usesCompactPageLayout
        )
        if didChangeCompactPresentation {
            seatTransitionCoordinator.finishImmediately()
        }
        let requiredActionBarHeight = actionBarView.bounds.height > 0
            ? actionBarView.bounds.height + 10
            : 65
        let didChangeActionBarReservedHeight = abs(
            actionBarReservedHeight - requiredActionBarHeight
        ) > 0.5
        if didChangeActionBarReservedHeight {
            actionBarReservedHeight = requiredActionBarHeight
            setNeedsQuickLayout()
        }
        if #available(iOS 17.0, *) {
            let dismissPadding = actionBarView.bounds.height
            if abs(
                quickLayoutKeyboardDismissPadding - dismissPadding
            ) > 0.5 {
                // 只扩展滚动收起手势的响应区域；不把 Action Bar 高度计入键盘 safe-area。
                quickLayoutKeyboardDismissPadding = dismissPadding
            }
        }
        if !didChangeCompactPresentation,
            !didChangeActionBarReservedHeight {
            messagesView.commitPendingScrollToLatest()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        seatTransitionCoordinator.finishImmediately()
        setNeedsQuickLayout()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        seatTransitionCoordinator.finishImmediately()
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isGiftEffectPageVisible = false
        giftMainEffectCoordinator.deactivate()
        guard isMovingFromParent || navigationController?.isBeingDismissed == true
        else { return }
        giftFlightAnimators.values.forEach { $0.cancel() }
        giftFlightAnimators.removeAll()
        followRequestTask?.cancel()
        followRequestTask = nil
        seatTransitionCoordinator.finishImmediately()
        giftSheetHost?.dismantleViewController()
        giftSheetHost = nil
        giftSheetViewController = nil
        audienceSheetViewController = nil
        viewModel.stopObservingStageSnapshots()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        reloadPublicChat(scrollToLatest: false)
        actionBarView.configure(
            message: Localization.text("liveRoom.action.message"),
            microphone: Localization.text("liveRoom.action.microphone"),
            gift: Localization.text("liveRoom.action.gift"),
            more: Localization.text("liveRoom.action.more"),
            inputPlaceholder: Localization.text(
                "liveRoom.action.input.placeholder"
            ),
            send: Localization.text("liveRoom.action.send"),
            cancel: Localization.text("liveRoom.action.cancel")
        )
        render(viewModel.state)
    }

    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        seatTransitionCoordinator.finishImmediately()
        super.reloadLayoutDirection(direction)
        let semanticAttribute = direction
            .appLayoutDirection
            .semanticContentAttribute
        [
            roomHeaderView,
            seatStageView,
            messagesView,
            actionBarView,
        ].forEach {
            $0.semanticContentAttribute = semanticAttribute
            $0.setNeedsLayout()
        }
        setNeedsQuickLayout()
    }

    override var body: Layout {
        ZStack {
            backdropView
                .resizable()
                .ignoresSafeArea(.all, edges: .all)

            VStack(spacing: 10) {
                roomHeaderView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)
                seatStageView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)
                messagesView
                    .resizable()
                    .frame(
                        minHeight: usesCompactPageLayout ? 0 : 80,
                        maxHeight: .infinity
                    )
            }
            .padding(.bottom, actionBarReservedHeight)
            .frame(maxWidth: maximumContentWidth)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .safeAreaPadding(.all, 0)
            // 主体只响应容器安全区域；键盘不会重新测量麦位或压缩公屏。
            .ignoresSafeArea(.keyboard, edges: .bottom)

            actionBarView
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .frame(maxWidth: maximumContentWidth)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .safeAreaPadding(.all, 0)
                // Action Bar 的底边只采用键盘区域。隐藏时该区域是否使用
                // container bottom safe area 由宿主行为统一决定。
                .ignoresSafeArea(.container, edges: .bottom)

            if let giftSheetHost {
                // 面板覆盖直播间内容，但仍与直播间处于同一个 QuickLayout 层级。
                giftSheetHost
                    .resizable()
                    .ignoresSafeArea(.all, edges: .all)
            }

            // 放在 ZStack 最后一层，保证飞行动画和豪华横幅显示在面板上方。
            giftEffectOverlayView
                .resizable()
                .ignoresSafeArea(.all, edges: .all)
        }
    }

    var usesCompactPageLayout: Bool {
        view.bounds.height < 780
            || traitCollection.preferredContentSizeCategory
                .isAccessibilityCategory
    }

    var maximumContentWidth: CGFloat {
        view.bounds.width >= 700 ? 720 : 620
    }

    func configureViews() {
        view.backgroundColor = UIColor(red: 0.08, green: 0.05, blue: 0.24, alpha: 1)
        publicChatScrollView.keyboardDismissMode = .interactive
        actionBarView.messageDidSend = { [weak self] message in
            self?.sendPublicMessage(message)
        }
        actionBarView.giftDidTap = { [weak self] in
            self?.presentGiftSheet()
        }
        messagesView.followDidTap = { [weak self] in
            self?.toggleFollowing()
        }
        roomHeaderView.audienceDidTap = { [weak self] in
            self?.presentAudienceSheet()
        }
        roomHeaderView.roomAvatarDidTap = { [weak self] in
            self?.pushRoomInformation()
        }
        giftEffectOverlayView.backgroundColor = .clear
        giftEffectOverlayView.isUserInteractionEnabled = false
        giftEffectOverlayView.isAccessibilityElement = false
        giftEffectOverlayView.accessibilityElementsHidden = true
        giftEffectOverlayView.accessibilityIdentifier =
            "liveRoom.gift.effect.container"
        seatStageView.layoutMetricsDidChange = { [weak self] in
            self?.setNeedsQuickLayout()
        }
        seatStageView.seatDidSelect = { [weak self] seat in
            self?.presentUserCard(for: seat)
        }
        NotificationCenter.default.publisher(
            for: UIApplication.willResignActiveNotification
        )
        .sink { [weak self] _ in
            self?.seatTransitionCoordinator.finishImmediately()
        }
        .store(in: &cancellables)
    }

    func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    func render(_ state: VoiceRoomViewModel.State) {
        let previousState = renderedState
        let previousPresentation = previousState?.stagePresentation
        renderedState = state
        reloadRoomHeader(using: state)
        if previousState?.isFollowing != state.isFollowing
            || previousState?.pendingFollowingState
                != state.pendingFollowingState {
            reloadPublicChat(scrollToLatest: false)
        }
        let transition = SeatTransitionDescriptor(
            from: previousPresentation,
            to: state.stagePresentation
        )
        seatTransitionCoordinator.transition(
            to: state.stagePresentation,
            animated: transition.requiresTransition,
            in: view
        ) { [weak self] in
            guard let self else { return }
            self.setNeedsQuickLayout()
            self.view.layoutIfNeeded()
        }
        giftSheetViewController?.updateRecipients(state.visibleRecipients)
        actionBarView.setMoreMenu(makeSeatLayoutMenu(for: state))
    }

    private func reloadRoomHeader(using state: VoiceRoomViewModel.State) {
        roomHeaderView.configure(
            roomTitle: Localization.text("liveRoom.room.title"),
            roomSubtitle: Localization.text("liveRoom.room.subtitle"),
            audience: Localization.text(
                "liveRoom.room.audience",
                state.audienceCount
            ),
            audienceAccessibilityHint: Localization.text(
                "liveRoom.audience.openHint"
            ),
            avatarAccessibilityLabel: Localization.text(
                "liveRoom.info.avatar.accessibility"
            ),
            avatarAccessibilityHint: Localization.text(
                "liveRoom.info.avatar.hint"
            )
        )
    }
}

#if DEBUG
@MainActor
private func makeVoiceRoomControllerPreview(
    roomMode: RoomMode,
    audienceSeatState: AudienceSeatState
) -> UIViewController {
    let viewModel = VoiceRoomPreviewData.makeRoomViewModel(
        roomMode: roomMode,
        audienceSeatState: audienceSeatState
    )
    return UINavigationController(
        rootViewController: VoiceRoomViewController(
            viewModel: viewModel,
            initialGiftBalance: viewModel.giftBalance
        )
    )
}

@available(iOS 17.0, *)
#Preview("直播间 · 九麦") {
    makeVoiceRoomControllerPreview(
        roomMode: .party,
        audienceSeatState: .enabled
    )
}

@available(iOS 17.0, *)
#Preview("直播间 · 五麦") {
    makeVoiceRoomControllerPreview(
        roomMode: .individual,
        audienceSeatState: .enabled
    )
}
#endif
