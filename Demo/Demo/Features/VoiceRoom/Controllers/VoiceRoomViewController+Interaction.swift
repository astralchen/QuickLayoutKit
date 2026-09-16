//
//  VoiceRoomViewController+Interaction.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension VoiceRoomViewController {

    /// 在没有在途关注任务时请求切换关注状态。
    func toggleFollowing() {
        guard followRequestTask == nil else { return }
        followRequestTask = Task { [weak self] in
            guard let self else { return }
            _ = await viewModel.toggleFollowing()
            followRequestTask = nil
        }
    }

    /// 创建房间资料页并推入当前导航栈。
    func pushRoomInformation() {
        // 仅允许当前直播间在无弹层时执行一次 push，避免连续点击造成重复页面。
        guard
            let navigationController,
            navigationController.topViewController === self,
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }

        let state = viewModel.state
        let informationViewModel = RoomInformationViewModel(
            information: viewModel.roomInformation,
            audienceCount: state.audienceCount
        )
        navigationController.pushViewController(
            RoomInformationViewController(
                viewModel: informationViewModel
            ),
            animated: true
        )
    }

    /// 使用当前观众状态展示在线观众面板。
    func presentAudienceSheet() {
        guard
            presentedViewController == nil,
            giftSheetViewController == nil,
            audienceSheetViewController == nil
        else { return }

        let state = viewModel.state
        let audienceViewModel = AudienceSheetViewModel(
            totalCount: state.audienceCount,
            members: state.audienceMembers
        )
        let viewController = AudienceSheetViewController(
            viewModel: audienceViewModel
        )
        viewController.memberDidSelect = { [weak self, weak viewController]
            member in
            guard let self, let viewController else { return }
            showAudienceProfile(member, dismissing: viewController)
        }
        audienceSheetViewController = viewController
        viewController.presentationController?.delegate = self
        present(viewController, animated: true)
    }

    /// 关闭观众面板后打开所选用户资料页。
    func showAudienceProfile(
        _ member: AudienceMember,
        dismissing sheetViewController: AudienceSheetViewController
    ) {
        guard audienceSheetViewController === sheetViewController else {
            return
        }

        // 先解除选择回调并关闭系统 Sheet，完成后再使用原导航栈 push，
        // 避免半屏弹层转场和导航转场同时执行造成层级或动画异常。
        sheetViewController.memberDidSelect = nil
        audienceSheetViewController = nil
        sheetViewController.dismiss(animated: true) { [weak self] in
            guard
                let self,
                let navigationController,
                navigationController.topViewController === self,
                presentedViewController == nil
            else { return }

            let currentMember = self.viewModel.state.audienceMembers.first { $0.id == member.id }
                ?? member
            let viewModel = AudienceProfileViewModel(member: currentMember)
            navigationController.pushViewController(
                AudienceProfileViewController(viewModel: viewModel),
                animated: true
            )
        }
    }

    /// 提交公屏消息，成功后刷新消息列表并滚动到最新内容。
    func sendPublicMessage(_ message: String) {
        guard viewModel.sendPublicMessage(message) else { return }
        reloadPublicChat(scrollToLatest: true)
        // 发送回调发生在输入条退出的同一事件周期内。主动提交根布局后再滚动，
        // 保证使用默认操作条和最终公屏高度，而不是键盘态的旧 bounds。
        setNeedsQuickLayout()
        quickLayoutIfNeeded()
        view.layoutIfNeeded()
        messagesView.commitPendingScrollToLatest()
    }

    /// 为有效占麦用户展示资料卡，必要时显示 PK 房间侧。
    func presentUserCard(for seat: SeatAssignment) {
        guard
            seat.isOccupied,
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }
        present(
            SeatUserCardViewController(seat: seat, showsRoom: viewModel.state.stagePresentation.layoutID == .roomPKNine),
            animated: true
        )
    }

    /// 用本地化文案、关注状态和会话消息刷新公屏。
    func reloadPublicChat(scrollToLatest: Bool) {
        let seedMessages = [
            Localization.text("liveRoom.messages.first"),
            Localization.text("liveRoom.messages.second"),
            Localization.text("liveRoom.messages.third"),
        ]
        let initialMessages = (0..<8).map { index in
            seedMessages[index % seedMessages.count]
        }
        let messages = initialMessages + viewModel.sentPublicMessages.map {
            Localization.text("liveRoom.messages.me", $0)
        }
        let followTitleKey: String
        switch viewModel.state.pendingFollowingState {
        case true?:
            followTitleKey = "liveRoom.messages.followRequesting"
        case false?:
            followTitleKey = "liveRoom.messages.unfollowRequesting"
        case nil:
            followTitleKey = viewModel.state.isFollowing
                ? "liveRoom.messages.followed"
                : "liveRoom.messages.follow"
        }
        messagesView.configure(
            title: Localization.text("liveRoom.messages.title"),
            follow: Localization.text(followTitleKey),
            isFollowing: viewModel.state.isFollowing,
            isFollowRequesting:
                viewModel.state.pendingFollowingState != nil,
            messages: messages,
            scrollToLatest: scrollToLatest
        )
    }

}

extension VoiceRoomViewController: UIAdaptivePresentationControllerDelegate {

    /// 在系统交互式关闭面板后清理对应控制器引用。
    func presentationControllerDidDismiss(
        _ presentationController: UIPresentationController
    ) {
        guard
            presentationController.presentedViewController
                === audienceSheetViewController
        else { return }
        audienceSheetViewController = nil
        UIAccessibility.post(
            notification: .layoutChanged,
            argument: roomHeaderView
        )
    }
}
