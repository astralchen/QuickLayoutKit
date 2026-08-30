//
//  LiveRoomViewController.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import Combine
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomViewController: DemoQuickLayoutHostingController {

    override var localizedTitleKey: String? { "demo.liveRoom.title" }

    let viewModel: LiveRoomViewModel
    let backdropView = LiveRoomBackdropView()
    let roomHeaderView = LiveRoomHeaderView()
    let seatStageView = LiveRoomSeatStageView()
    let messagesView = LiveRoomMessagesView()
    let actionBarView = LiveRoomActionBarView()
    // 特效容器始终位于送礼面板之上，但不参与命中测试，连续赠送时不会挡住操作。
    let giftEffectOverlayView = UIView()
    let keyboardObserver = QuickLayoutKeyboardObserver()
    var cancellables: Set<AnyCancellable> = []
    // 默认值对应 35pt 控件、上下各 10pt 内边距以及与公屏的 10pt 间距。
    // 首次测量后会按 Action Bar 的真实高度更新，避免紧凑屏幕出现额外空隙。
    var actionBarReservedHeight: CGFloat = 65
    var giftFlightAnimators: [UUID: LiveRoomGiftFlightAnimator] = [:]
    var pendingRechargeRequiredBalance: Int?
    // representable 负责送礼子控制器的 UIKit containment，避免 modal 层级压住特效。
    var giftSheetHost: QuickLayoutViewControllerRepresentable?

    var renderedState: LiveRoomViewModel.State?
    var lastGiftRecipientSeatIDs: [Int] = []
    var lastGiftID: String?
    var lastGiftQuantity = 1
    var giftDeliveryCount = 0
    var lastGiftAnimationOrigin: CGPoint?
    var lastGiftAnimationTargetPoints: [CGPoint] = []
    var giftSheetViewController:
        LiveRoomGiftSheetViewController?
    var rechargeViewController:
        LiveRoomRechargeViewController?
    var audienceSheetViewController:
        LiveRoomAudienceSheetViewController?

    lazy var seatTransitionCoordinator =
        LiveRoomSeatStageTransitionCoordinator(
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
        (presentedViewController as? LiveRoomUserCardViewController)?.seatID
    }

    var presentedAudienceMemberCount: Int? {
        audienceSheetViewController?.memberCount
    }

    var pushedRoomInformationViewController:
        LiveRoomInformationViewController? {
        navigationController?.topViewController
            as? LiveRoomInformationViewController
    }

    var pushedAudienceProfileViewController:
        LiveRoomAudienceProfileViewController? {
        navigationController?.topViewController
            as? LiveRoomAudienceProfileViewController
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
        self.init(viewModel: LiveRoomViewModel(), initialGiftBalance: 12_800)
    }

    init(
        viewModel: LiveRoomViewModel,
        initialGiftBalance: Int = 12_800
    ) {
        self.viewModel = viewModel
        viewModel.configureGiftBalance(initialGiftBalance)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        viewModel = LiveRoomViewModel(initialGiftBalance: 12_800)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureViews()
        bindViewModel()
        viewModel.startObservingStageSnapshots()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let didChangeCompactPresentation = seatStageView.setCompactPresentation(
            usesCompactPageLayout
                || (
                    keyboardObserver.context.resolved(in: view).height > 0
                        && actionBarView.isShowingMessageComposer
                )
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
        if keyboardObserver.isKeyboardVisible {
            applyKeyboardContext(keyboardObserver.context)
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
        guard isMovingFromParent || navigationController?.isBeingDismissed == true
        else { return }
        giftFlightAnimators.values.forEach { $0.cancel() }
        giftFlightAnimators.removeAll()
        seatTransitionCoordinator.finishImmediately()
        giftSheetHost?.dismantleViewController()
        giftSheetHost = nil
        giftSheetViewController = nil
        audienceSheetViewController = nil
        viewModel.stopObservingStageSnapshots()
    }

    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        reloadRoomHeader(using: viewModel.state)
        reloadPublicChat(scrollToLatest: false)
        actionBarView.configure(
            message: DemoLocalization.text("liveRoom.action.message"),
            microphone: DemoLocalization.text("liveRoom.action.microphone"),
            gift: DemoLocalization.text("liveRoom.action.gift"),
            more: DemoLocalization.text("liveRoom.action.more"),
            inputPlaceholder: DemoLocalization.text(
                "liveRoom.action.input.placeholder"
            ),
            send: DemoLocalization.text("liveRoom.action.send"),
            cancel: DemoLocalization.text("liveRoom.action.cancel")
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
                .ignoresSafeArea(.container, edges: .all)

            ZStack(alignment: .bottom) {
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

                actionBarView
                    .resizable(axis: .horizontal)
                    .fixedSize(axis: .vertical)
            }
            .frame(maxWidth: maximumContentWidth)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, actionBarBottomSpacing)
            .frame(maxWidth: .infinity)
            .safeAreaPadding(.all, 0)

            if let giftSheetHost {
                // 面板覆盖直播间内容，但仍与直播间处于同一个 QuickLayout 层级。
                giftSheetHost
                    .resizable()
                    .ignoresSafeArea(.container, edges: .all)
            }

            // 放在 ZStack 最后一层，保证飞行动画和豪华横幅显示在面板上方。
            giftEffectOverlayView
                .resizable()
                .ignoresSafeArea(.container, edges: .all)
        }
    }

    static func actionBarBottomSpacing(for safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom > 0 ? 0 : 8
    }

    var usesCompactPageLayout: Bool {
        view.bounds.height < 780
            || traitCollection.preferredContentSizeCategory
                .isAccessibilityCategory
    }

    var actionBarBottomSpacing: CGFloat {
        Self.actionBarBottomSpacing(for: view.safeAreaInsets.bottom)
    }

    var maximumContentWidth: CGFloat {
        view.bounds.width >= 700 ? 720 : 620
    }

    func configureViews() {
        view.backgroundColor = UIColor(red: 0.08, green: 0.05, blue: 0.24, alpha: 1)
        actionBarView.messageDidSend = { [weak self] message in
            self?.sendPublicMessage(message)
        }
        actionBarView.giftDidTap = { [weak self] in
            self?.presentGiftSheet()
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
        keyboardObserver.$context
            .sink { [weak self] context in
                self?.applyKeyboardContext(context)
            }
            .store(in: &cancellables)
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

    func render(_ state: LiveRoomViewModel.State) {
        let previousPresentation = renderedState?.stagePresentation
        renderedState = state
        reloadRoomHeader(using: state)
        let transition = LiveRoomSeatTransitionDescriptor(
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

    private func reloadRoomHeader(using state: LiveRoomViewModel.State) {
        roomHeaderView.configure(
            roomTitle: DemoLocalization.text("liveRoom.room.title"),
            roomSubtitle: DemoLocalization.text("liveRoom.room.subtitle"),
            audience: DemoLocalization.text(
                "liveRoom.room.audience",
                state.audienceCount
            ),
            audienceAccessibilityHint: DemoLocalization.text(
                "liveRoom.audience.openHint"
            ),
            avatarAccessibilityLabel: DemoLocalization.text(
                "liveRoom.info.avatar.accessibility"
            ),
            avatarAccessibilityHint: DemoLocalization.text(
                "liveRoom.info.avatar.hint"
            )
        )
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomControllerPreview(
    businessMode: LiveRoomBusinessMode,
    audienceSeatState: LiveRoomAudienceSeatState
) -> UIViewController {
    let viewModel = LiveRoomPreviewData.makeRoomViewModel(
        businessMode: businessMode,
        audienceSeatState: audienceSeatState
    )
    return UINavigationController(
        rootViewController: LiveRoomViewController(
            viewModel: viewModel,
            initialGiftBalance: viewModel.giftBalance
        )
    )
}

#Preview("直播间 · 九麦") {
    makeLiveRoomControllerPreview(
        businessMode: .party,
        audienceSeatState: .enabled
    )
}

#Preview("直播间 · 五麦") {
    makeLiveRoomControllerPreview(
        businessMode: .individual,
        audienceSeatState: .enabled
    )
}
#endif
