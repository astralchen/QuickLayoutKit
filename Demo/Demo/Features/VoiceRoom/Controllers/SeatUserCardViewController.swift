//
//  SeatUserCardViewController.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 承载弹窗内的占麦用户资料。
final class SeatUserCardViewController:
    LocalizedQuickLayoutHostingController {

    /// 资料卡对应的零基麦位位置，供页面状态检查使用。
    let seatID: Int

    /// 一个布尔值，指示资料卡是否额外显示用户所属的 PK 房间侧。
    private let showsRoom: Bool
    /// 资料卡显示的麦位绑定和占麦用户数据。
    private let seat: SeatAssignment
    /// 显示占麦用户资料的卡片内容视图。
    private let cardView = SeatUserCardView()

    /// 创建居中显示的麦位用户资料弹窗。
    static func makeAlert(seat: SeatAssignment, showsRoom: Bool = false) -> AlertController {
        let alert = AlertController(preferredStyle: .alert)
        alert.panelWidth = .custom { context in
            // Alert 已留出每侧 12 pt，资料卡每侧还需要 12 pt。
            min(340, context.availableWidth - 2 * 12)
        }
        alert.contentInsets = .zero
        alert.dismissesOnBackdropTap = true
        alert.contentViewController = SeatUserCardViewController(seat: seat, showsRoom: showsRoom)
        alert.view.accessibilityIdentifier = "liveRoom.userCard.overlay"
        return alert
    }

    /// 创建指定麦位用户的资料卡。
    ///
    /// - Parameters:
    ///   - seat: 当前占麦用户及其麦位数据。
    ///   - showsRoom: 是否显示 PK 所属房间侧。
    private init(seat: SeatAssignment, showsRoom: Bool) {
        self.showsRoom = showsRoom
        self.seat = seat
        seatID = seat.id
        super.init(nibName: nil, bundle: nil)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 在视图加载后配置界面并连接内容与交互。
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
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
        cardView.configure(seat: seat, showsRoom: showsRoom)
        (parent as? AlertController)?.invalidateContentSize()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        cardView
            .resizable(axis: .horizontal)
            .fixedSize(axis: .vertical)
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissUserCard))]
    }

    override func accessibilityPerformEscape() -> Bool {
        dismissUserCard()
        return true
    }

    /// 关闭当前麦位用户资料卡。
    @objc private func dismissUserCard() {
        (parent as? AlertController)?.dismiss(animated: true)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("用户卡片") {
    SeatUserCardViewController.makeAlert(seat: VoiceRoomPreviewData.seats[2])
}
#endif
