//
//  GiftBackdropViews.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayoutKit
import UIKit

#if DEBUG
import QuickLayout
#endif

/// 在礼物面板两侧绘制柔和渐变光晕的装饰视图。
final class GiftAmbientGlowView: UIView {

    // 这里需要径向环境光；QuickLayoutLinearGradientView 对齐 SwiftUI
    // LinearGradient，仅承诺线性渐变，因此保留专用 CAGradientLayer，避免错误抽象。
    /// 绘制面板前导侧光晕的渐变图层。
    private let leadingGlowLayer = CAGradientLayer()
    /// 绘制面板尾随侧光晕的渐变图层。
    private let trailingGlowLayer = CAGradientLayer()

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        configure(
            leadingGlowLayer,
            color: UIColor.systemPurple.withAlphaComponent(0.34),
            startPoint: CGPoint(x: 0.10, y: 0.95),
            endPoint: CGPoint(x: 0.75, y: 0.20)
        )
        configure(
            trailingGlowLayer,
            color: UIColor.systemBlue.withAlphaComponent(0.26),
            startPoint: CGPoint(x: 0.95, y: 0.78),
            endPoint: CGPoint(x: 0.28, y: 0.16)
        )
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 将两侧渐变图层调整为当前视图边界。
    override func layoutSubviews() {
        super.layoutSubviews()
        leadingGlowLayer.frame = bounds
        trailingGlowLayer.frame = bounds
    }

    /// 设置单个环境光图层的径向渐变颜色和起止位置。
    private func configure(
        _ gradientLayer: CAGradientLayer,
        color: UIColor,
        startPoint: CGPoint,
        endPoint: CGPoint
    ) {
        gradientLayer.type = .radial
        gradientLayer.colors = [color.cgColor, UIColor.clear.cgColor]
        gradientLayer.locations = [0, 1]
        gradientLayer.startPoint = startPoint
        gradientLayer.endPoint = endPoint
        layer.addSublayer(gradientLayer)
    }
}

/// 礼物面板入场和退场共用的位移计算规则。
enum GiftSheetMotionMetrics {

    /// 返回将面板完全移到屏幕底部之外所需的位移，单位为点。
    static func offscreenTranslation(
        sheetHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        max(0, sheetHeight) + max(0, safeAreaBottom) + 12
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("送礼氛围背景") {
    QuickLayoutHostingController {
        GiftAmbientGlowView()
            .resizable()
            .frame(width: 390, height: 220)
    }
}
#endif
