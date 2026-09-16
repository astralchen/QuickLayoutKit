import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 独立于麦位身份的舞台装饰，不参与点击或收礼定位。
final class RoomPKDecorationView: QuickLayoutView {
    /// 当前环境采用的麦位尺寸等级。
    var sizeClass = SeatSizeClass.regular {
        didSet {
            guard sizeClass != oldValue else { return }
            setNeedsQuickLayout()
        }
    }
    /// 标示 PK 本房区域的标签。
    private let currentLabel = UILabel()
    /// 标示 PK 对方区域的标签。
    private let opponentLabel = UILabel()
    /// 位于双方区域之间的 PK 标记。
    private let pkLabel = UILabel()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        for (label, key, color) in [
            (currentLabel, "liveRoom.pk.current", UIColor.systemPink),
            (opponentLabel, "liveRoom.pk.opponent", UIColor.systemCyan)
        ] {
            label.text = Localization.text(key)
            label.textColor = .white
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textAlignment = .center
            label.backgroundColor = color.withAlphaComponent(0.30)
            label.layer.cornerRadius = 9
            label.clipsToBounds = true
        }
        pkLabel.text = "PK"
        pkLabel.font = .systemFont(ofSize: 23, weight: .heavy)
        pkLabel.textAlignment = .center
        pkLabel.textColor = .white
        pkLabel.layer.shadowColor = UIColor.systemPink.cgColor
        pkLabel.layer.shadowRadius = 7
        pkLabel.layer.shadowOpacity = 0.8
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) { nil }

    /// 根据当前语言刷新显示文案和辅助功能描述。
    func reloadLocalizedContent() {
        currentLabel.text = Localization.text("liveRoom.pk.current")
        opponentLabel.text = Localization.text("liveRoom.pk.opponent")
        setNeedsQuickLayout()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        let geometry = RoomPKGeometry(width: bounds.width, sizeClass: sizeClass)
        let badgeWidth = min(60, geometry.wingWidth)
        return ZStack(alignment: .top) {
            HStack(spacing: geometry.centerGap) {
                currentLabel.resizable()
                    .frame(width: badgeWidth, height: 18)
                    .frame(width: geometry.wingWidth)
                opponentLabel.resizable()
                    .frame(width: badgeWidth, height: 18)
                    .frame(width: geometry.wingWidth)
            }
            // 固定房间物理左右；标签文字仍采用自身的语言方向。
            .layoutDirection(.leftToRight)
            pkLabel.resizable()
                .frame(width: 40, height: 32)
                .padding(.top, RoomPKGeometry.headerHeight + geometry.hostSize.height * 0.28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

#if DEBUG

@available(iOS 17.0, *)
#Preview("厅 PK 舞台标识") {
    QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            RoomPKDecorationView().resizable().frame(height: 160).padding(16)
        }
    }
}
#endif
