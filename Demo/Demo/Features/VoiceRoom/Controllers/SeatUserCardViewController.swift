//
//  SeatUserCardViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 展示指定占麦用户资料的模态控制器。
final class SeatUserCardViewController:
    LocalizedQuickLayoutHostingController {

    /// 资料卡对应的零基麦位位置，供页面状态检查使用。
    let seatID: Int

    /// 一个布尔值，指示资料卡是否额外显示用户所属的 PK 房间侧。
    private let showsRoom: Bool
    /// 资料卡显示的麦位绑定和占麦用户数据。
    private let seat: SeatAssignment
    /// 接收卡片外点击以关闭资料卡的透明按钮。
    private let dismissButton = QuickLayoutButton(frame: .zero)
    /// 显示占麦用户资料的卡片内容视图。
    private let cardView = SeatUserCardView()

    /// 创建指定麦位用户的资料卡。
    ///
    /// - Parameters:
    ///   - seat: 当前占麦用户及其麦位数据。
    ///   - showsRoom: 是否显示 PK 所属房间侧；默认值为 `false`。
    init(seat: SeatAssignment, showsRoom: Bool = false) {
        self.showsRoom = showsRoom
        self.seat = seat
        seatID = seat.id
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
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
        view.accessibilityIdentifier = "liveRoom.userCard.overlay"

        dismissButton.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        dismissButton.accessibilityLabel = Localization.text("common.close")
        dismissButton.action = { [weak self] in self?.dismissUserCard() }
        cardView.closeButton.action = { [weak self] in self?.dismissUserCard() }
    }

    /// 在页面显示后完成依赖可见状态的界面更新。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIAccessibility.post(notification: .screenChanged, argument: cardView)
    }

    /// 根据当前语言刷新显示文案和辅助功能描述。
    override func reloadLocalizedContent() {
        super.reloadLocalizedContent()
        dismissButton.accessibilityLabel = Localization.text("common.close")
        cardView.configure(seat: seat, showsRoom: showsRoom)
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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

    /// 关闭当前麦位用户资料卡。
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
