//
//  LiveRoomViewController+Interaction.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayoutKit
import UIKit

extension LiveRoomViewController {

    func pushRoomInformation() {
        // 仅允许当前直播间在无弹层时执行一次 push，避免连续点击造成重复页面。
        guard
            let navigationController,
            navigationController.topViewController === self,
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }

        let state = viewModel.state
        let informationViewModel = LiveRoomInformationViewModel(
            information: viewModel.roomInformation,
            audienceCount: state.audienceCount
        )
        navigationController.pushViewController(
            LiveRoomInformationViewController(
                viewModel: informationViewModel
            ),
            animated: true
        )
    }

    func presentAudienceSheet() {
        guard
            presentedViewController == nil,
            giftSheetViewController == nil,
            audienceSheetViewController == nil
        else { return }

        let state = viewModel.state
        let audienceViewModel = LiveRoomAudienceViewModel(
            totalCount: state.audienceCount,
            members: state.audienceMembers
        )
        let viewController = LiveRoomAudienceSheetViewController(
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

    func showAudienceProfile(
        _ member: LiveRoomAudienceMember,
        dismissing sheetViewController: LiveRoomAudienceSheetViewController
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

            let viewModel = LiveRoomAudienceProfileViewModel(member: member)
            navigationController.pushViewController(
                LiveRoomAudienceProfileViewController(viewModel: viewModel),
                animated: true
            )
        }
    }

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

    func presentUserCard(for seat: LiveRoomSeat) {
        guard
            seat.isOccupied,
            presentedViewController == nil,
            giftSheetViewController == nil
        else { return }
        present(
            LiveRoomUserCardViewController(seat: seat),
            animated: true
        )
    }

    func reloadPublicChat(scrollToLatest: Bool) {
        let seedMessages = [
            DemoLocalization.text("liveRoom.messages.first"),
            DemoLocalization.text("liveRoom.messages.second"),
            DemoLocalization.text("liveRoom.messages.third"),
        ]
        let initialMessages = (0..<8).map { index in
            seedMessages[index % seedMessages.count]
        }
        let messages = initialMessages + viewModel.sentPublicMessages.map {
            DemoLocalization.text("liveRoom.messages.me", $0)
        }
        messagesView.configure(
            title: DemoLocalization.text("liveRoom.messages.title"),
            follow: DemoLocalization.text("liveRoom.messages.follow"),
            messages: messages,
            scrollToLatest: scrollToLatest
        )
    }

    func applyKeyboardContext(_ context: QuickLayoutKeyboardContext) {
        guard isViewLoaded else { return }
        let resolved = context.resolved(in: view)
        // 键盘出现时先压缩麦位舞台，为输入条留出聊天区域，避免只平移输入条后覆盖麦位。
        let didChangeCompactPresentation = seatStageView.setCompactPresentation(
            usesCompactPageLayout
                || (resolved.height > 0 && actionBarView.isShowingMessageComposer)
        )
        if didChangeCompactPresentation {
            // 键盘可能改变舞台 Metrics。旧动画坐标一旦失效，应立即提交最新布局，
            // 避免继续使用键盘出现前的舞台和公屏 Frame。
            seatTransitionCoordinator.finishImmediately()
        }
        let untransformedBottom = actionBarView.center.y
            + actionBarView.bounds.height / 2
        let overlap = resolved.height > 0
            ? max(
                0,
                untransformedBottom - resolved.intersection.minY + 8
            )
            : 0
        let targetTransform = CGAffineTransform(
            translationX: 0,
            y: -overlap
        )
        guard actionBarView.transform != targetTransform else { return }
        UIView.animate(
            withDuration: context.animationDuration,
            delay: 0,
            options: context.animationOptions,
            animations: {
                self.actionBarView.transform = targetTransform
            }
        )
    }
}

extension LiveRoomViewController: UIAdaptivePresentationControllerDelegate {

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
