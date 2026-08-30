//
//  LiveRoomViewController+LayoutMenu.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import UIKit

extension LiveRoomViewController {

    /// 根据服务端 capability 构建生产业务菜单。
    ///
    /// 菜单只提交业务命令，不直接修改麦位布局。对应操作会在服务端新 revision
    /// 快照返回后生效。
    func makeSeatLayoutMenu(
        for state: LiveRoomViewModel.State
    ) -> UIMenu {
        let capabilities = state.snapshot.capabilities
        let isExecuting = state.pendingBusinessCommand != nil
        var children: [UIMenuElement] = []

        if capabilities.contains(.switchRoomType) {
            let partyAction = UIAction(
                title: DemoLocalization.text("liveRoom.layout.nine"),
                image: UIImage(systemName: "person.3.sequence.fill"),
                attributes: isExecuting ? .disabled : [],
                state: state.snapshot.businessMode == .party ? .on : .off
            ) { [weak self] _ in
                self?.submitBusinessCommand(.switchRoomType(.party))
            }
            let individualAction = UIAction(
                title: DemoLocalization.text("liveRoom.layout.five"),
                image: UIImage(systemName: "person.crop.circle"),
                attributes: isExecuting ? .disabled : [],
                state: state.snapshot.businessMode == .individual ? .on : .off
            ) { [weak self] _ in
                self?.submitBusinessCommand(.switchRoomType(.individual))
            }
            children.append(
                UIMenu(
                    options: .displayInline,
                    children: [partyAction, individualAction]
                )
            )
        }

        if capabilities.contains(.toggleAudienceSeats),
            state.snapshot.businessMode == .individual {
            let isEnabled = state.snapshot.audienceSeatState == .enabled
            let audienceAction = UIAction(
                title: DemoLocalization.text(
                    isEnabled
                        ? "liveRoom.condition.cancel"
                        : "liveRoom.condition.satisfy"
                ),
                image: UIImage(
                    systemName: isEnabled
                        ? "person.2.slash.fill"
                        : "person.2.fill"
                ),
                attributes: isExecuting ? .disabled : []
            ) { [weak self] _ in
                self?.submitBusinessCommand(
                    .setAudienceSeatsEnabled(!isEnabled)
                )
            }
            children.append(
                UIMenu(options: .displayInline, children: [audienceAction])
            )
        }

        if capabilities.contains(.startPK) {
            children.append(
                UIAction(
                    title: DemoLocalization.text("liveRoom.business.pk.start"),
                    image: UIImage(systemName: "bolt.horizontal.circle.fill"),
                    attributes: isExecuting ? .disabled : []
                ) { [weak self] _ in
                    self?.submitBusinessCommand(.startPK(styleID: "default"))
                }
            )
        }

        if capabilities.contains(.endPK) {
            children.append(
                UIAction(
                    title: DemoLocalization.text("liveRoom.business.pk.end"),
                    image: UIImage(systemName: "xmark.circle.fill"),
                    attributes: isExecuting ? .disabled : []
                ) { [weak self] _ in
                    self?.submitBusinessCommand(.endPK)
                }
            )
        }

        return UIMenu(
            title: DemoLocalization.text("liveRoom.layout.title"),
            image: UIImage(systemName: "ellipsis.circle"),
            children: children
        )
    }

    func submitBusinessCommand(_ command: LiveRoomBusinessCommand) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didSucceed = await viewModel.performBusinessCommand(command)
            guard !didSucceed, presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: DemoLocalization.text(
                    "liveRoom.business.command.failure.title"
                ),
                message: DemoLocalization.text(
                    "liveRoom.business.command.failure.message"
                ),
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(
                    title: DemoLocalization.text("common.ok"),
                    style: .default
                )
            )
            present(alert, animated: true)
        }
    }
}
