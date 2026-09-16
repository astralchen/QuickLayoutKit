import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 独立于麦位身份的舞台装饰，不参与点击或收礼定位。
final class RoomPKDecorationView: QuickLayoutView {
    var sizeClass = SeatSizeClass.regular {
        didSet {
            guard sizeClass != oldValue else { return }
            setNeedsQuickLayout()
        }
    }
    private let currentLabel = UILabel()
    private let opponentLabel = UILabel()
    private let pkLabel = UILabel()

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

    required init?(coder: NSCoder) { nil }

    func reloadLocalizedContent() {
        currentLabel.text = Localization.text("liveRoom.pk.current")
        opponentLabel.text = Localization.text("liveRoom.pk.opponent")
        setNeedsQuickLayout()
    }

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
