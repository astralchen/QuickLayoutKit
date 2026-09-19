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

/// 协调语音房舞台、公屏、业务导航和礼物效果的页面控制器。
final class VoiceRoomViewController: LocalizedQuickLayoutHostingController {

    /// 导航标题使用的本地化资源键。
    override var localizedTitleKey: String? { "demo.liveRoom.title" }

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: VoiceRoomViewModel
    /// 页面使用的星点渐变背景视图。
    let backdropView = StarfieldBackgroundView()
    /// 显示房间标题、资料入口和在线人数的页头视图。
    let roomHeaderView = RoomHeaderView()
    /// 根据已确认舞台状态展示麦位的容器。
    let seatStageView = SeatStageView()
    /// 房间公屏视图。
    let messagesView = RoomPublicChatView()
    /// 房间底部的消息输入与操作按钮区域。
    let actionBarView = RoomActionBarView()
    // 特效容器始终位于送礼面板之上，但不参与命中测试，连续赠送时不会挡住操作。
    /// 承载礼物主特效的透明视图。
    let giftEffectOverlayView = UIView()
    /// 当前页面持有的 Combine 订阅集合。
    var cancellables: Set<AnyCancellable> = []
    /// 正在等待关注接口确认的任务；结束后清空。
    var followRequestTask: Task<Void, Never>?
    // 默认值对应 35pt 控件、上下各 10pt 内边距以及与公屏的 10pt 间距。
    // 首次测量后会按 Action Bar 的真实高度更新，避免紧凑屏幕出现额外空隙。
    /// 页面为底部操作栏预留的高度，单位为点。
    var actionBarReservedHeight: CGFloat = 65
    /// 按实例标识持有的活动礼物飞行动画。
    var giftFlightAnimators: [UUID: GiftFlightAnimator] = [:]
    /// VAP、SVGA 共用的主特效队列，页面不可见时取消全部展示。
    lazy var giftMainEffectCoordinator = GiftMainEffectCoordinator { [weak self] in
        GiftMainEffectPlayer(containerView: self?.giftEffectOverlayView ?? UIView())
    }
    /// Scene 恢复前台时仅激活实际可见的房间页面。
    private var isGiftEffectPageVisible = false
    /// Scene 事件来源；测试使用独立通知中心，避免模拟事件触发系统观察者。
    private let notificationCenter: NotificationCenter
    /// 等待礼物面板关闭后继续处理的目标充值余额。
    var pendingRechargeRequiredBalance: Int?
    // representable 负责送礼子控制器的 UIKit containment，避免 modal 层级压住特效。
    /// 将礼物子控制器接入 QuickLayout 布局的宿主节点。
    var giftSheetHost: QuickLayoutViewControllerRepresentable?

    /// 最近一次已应用到界面的完整房间状态。
    var renderedState: VoiceRoomViewModel.State?
    /// 最近一次赠送记录的收礼人零基麦位位置。
    var lastGiftRecipientSeatIDs: [Int] = []
    /// 最近一次赠送的礼物标识。
    var lastGiftID: String?
    /// 最近一次赠送给每名收礼人的份数。
    var lastGiftQuantity = 1
    /// 当前会话已启动展示的赠送次数。
    var giftDeliveryCount = 0
    /// 最近一次礼物飞行在效果容器中的起点。
    var lastGiftAnimationOrigin: CGPoint?
    /// 最近一次礼物飞行在效果容器中的目标点列表。
    var lastGiftAnimationTargetPoints: [CGPoint] = []
    /// 当前展示的礼物面板控制器；未展示时为 `nil`。
    var giftSheetViewController:
        GiftSheetViewController?
    /// 当前充值页面的控制器引用。
    var rechargeViewController:
        RechargeViewController?
    /// 当前展示的在线观众面板控制器。
    var audienceSheetViewController:
        AudienceSheetViewController?

    /// 当前舞台的可见麦位数量。
    var displayedSeatCount: Int {
        renderedState?.stagePresentation.visibleSlots.count ?? 0
    }

    /// 业务层确认后供礼物面板使用的金币余额。
    var giftBalance: Int { viewModel.giftBalance }

    /// 公屏消息的滚动容器。
    var publicChatScrollView: UIScrollView {
        messagesView.scrollView
    }

    /// 一个布尔值，指示底部操作栏是否显示消息编辑区域。
    var isShowingMessageComposer: Bool {
        actionBarView.isShowingMessageComposer
    }

    /// 当前公屏中的最后一条消息；没有消息时为 `nil`。
    var latestPublicChatMessage: String? {
        messagesView.latestMessage
    }

    /// 当前用户资料卡对应的零基麦位位置；未展示时为 `nil`。
    var presentedUserCardSeatID: Int? {
        (presentedViewController as? SeatUserCardViewController)?.seatID
    }

    /// 当前观众面板加载的用户数量；未展示时为 `nil`。
    var presentedAudienceMemberCount: Int? {
        audienceSheetViewController?.memberCount
    }

    /// 导航栈中已打开的房间资料控制器。
    var pushedRoomInformationViewController:
        RoomInformationViewController? {
        navigationController?.topViewController
            as? RoomInformationViewController
    }

    /// 导航栈中已打开的观众资料控制器。
    var pushedAudienceProfileViewController:
        AudienceProfileViewController? {
        navigationController?.topViewController
            as? AudienceProfileViewController
    }

    /// 当前礼物面板中的收礼人零基麦位位置列表。
    var presentedGiftRecipientSeatIDs: [Int] {
        giftSheetViewController?.recipientSeatIDs ?? []
    }

    /// 一个布尔值，指示礼物面板当前是否存在。
    var isGiftSheetVisible: Bool {
        giftSheetViewController != nil
    }

    /// 当前仍被页面持有的礼物飞行动画数量。
    var activeGiftFlightCount: Int {
        giftFlightAnimators.count
    }

    /// 用于放置主特效和飞行动画的容器视图。
    var giftEffectContainerView: UIView {
        giftEffectOverlayView
    }

    /// 使用默认演示视图模型创建语音房页面。
    convenience init() {
        self.init(viewModel: VoiceRoomViewModel(), initialGiftBalance: 12_800)
    }

    /// 创建语音房页面，并配置初始金币余额与场景通知来源。
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

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        viewModel = VoiceRoomViewModel(initialGiftBalance: 12_800)
        notificationCenter = .default
        super.init(coder: coder)
    }

    /// 在视图加载后配置界面并连接内容与交互。
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

    /// 在布局完成后同步舞台尺寸等级、操作栏预留高度和待处理的公屏滚动。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let didChangeCompactPresentation = seatStageView.setCompactPresentation(
            usesCompactPageLayout
        )
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

    /// 安全区变化时结束旧几何转场，并请求重新布局页面。
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        seatStageView.finishUpdatesImmediately()
        setNeedsQuickLayout()
    }

    /// 容器尺寸变化前结束舞台转场，避免使用旧尺寸继续动画。
    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        seatStageView.finishUpdatesImmediately()
        super.viewWillTransition(to: size, with: coordinator)
    }

    /// 页面不可见时停止接收和播放排队主特效。
    ///
    /// 仅当页面退出导航层级或整个导航容器被关闭时，才进一步取消飞行动画、关注请求和快照订阅，并清理子控制器及转场。
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
        seatStageView.finishUpdatesImmediately()
        giftSheetHost?.dismantleViewController()
        giftSheetHost = nil
        giftSheetViewController = nil
        audienceSheetViewController = nil
        viewModel.stopObservingStageSnapshots()
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
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

    /// 应用新的界面布局方向，并使相关内容重新布局。
    override func reloadLayoutDirection(
        _ direction: UIUserInterfaceLayoutDirection
    ) {
        seatStageView.finishUpdatesImmediately()
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
        messagesView.updateLayoutDirection()
        setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 一个布尔值，指示页面高度是否需要采用紧凑布局。
    var usesCompactPageLayout: Bool {
        view.bounds.height < 780
            || (viewModel.state.stagePresentation.layoutID == .roomPKNine
                && isShowingMessageComposer)
            || traitCollection.preferredContentSizeCategory
                .isAccessibilityCategory
    }

    /// 页面主体允许使用的最大内容宽度，单位为点。
    var maximumContentWidth: CGFloat {
        view.bounds.width >= 700 ? 720 : 620
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    func configureViews() {
        view.backgroundColor = UIColor(red: 0.08, green: 0.05, blue: 0.24, alpha: 1)
        publicChatScrollView.keyboardDismissMode = .interactive
        actionBarView.messageDidSend = { [weak self] message in
            self?.sendPublicMessage(message)
        }
        actionBarView.giftDidTap = { [weak self] in
            self?.presentGiftSheet()
        }
        roomHeaderView.followDidTap = { [weak self] in
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
            self?.seatStageView.finishUpdatesImmediately()
        }
        .store(in: &cancellables)
    }

    /// 绑定视图模型状态回调，并将后续状态变化交给页面渲染。
    func bindViewModel() {
        viewModel.bind { [weak self] state in
            self?.render(state)
        }
    }

    /// 提交最新房间状态，并按变化更新舞台、观众面板和页头。
    func render(_ state: VoiceRoomViewModel.State) {
        let previousState = renderedState
        let previousPresentation = previousState?.stagePresentation
        renderedState = state
        reloadRoomHeader(using: state)
        if previousState?.publicMessages != state.publicMessages
            || previousState?.isFollowing != state.isFollowing
            || previousState?.pendingFollowingState
                != state.pendingFollowingState {
            reloadPublicChat(scrollToLatest: false)
        }
        let transition = SeatTransitionDescriptor(
            from: previousPresentation,
            to: state.stagePresentation
        )
        seatStageView.apply(
            presentation: state.stagePresentation,
            animated: transition.requiresTransition
        )
        setNeedsQuickLayout()
        view.layoutIfNeeded()
        giftSheetViewController?.updateRecipients(state.visibleRecipients)
        if previousState?.audienceMembers != state.audienceMembers
            || previousState?.audienceCount != state.audienceCount {
            audienceSheetViewController?.update(
                totalCount: state.audienceCount,
                members: state.audienceMembers
            )
            if let profile = pushedAudienceProfileViewController,
                let member = state.audienceMembers.first(where: { $0.id == profile.memberID }) {
                profile.update(member: member)
            }
        }
        actionBarView.setMoreMenu(makeSeatLayoutMenu(for: state))
    }

    /// 根据在线人数和房间资料刷新页头文案。
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
/// 创建展示指定房型的语音房控制器的预览控制器。
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
@available(iOS 17.0, *)
#Preview("直播间 · 厅 PK") {
    makeVoiceRoomControllerPreview(roomMode: .pk(styleID: "room.nine"), audienceSeatState: .enabled)
}
#endif
