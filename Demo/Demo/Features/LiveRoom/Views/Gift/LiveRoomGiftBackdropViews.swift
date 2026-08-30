//
//  LiveRoomGiftBackdropViews.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayoutKit
import UIKit

#if DEBUG
import QuickLayout
#endif

final class LiveRoomGiftAmbientView: UIView {

    // 这里需要径向环境光；QuickLayoutLinearGradientView 对齐 SwiftUI
    // LinearGradient，仅承诺线性渐变，因此保留专用 CAGradientLayer，避免错误抽象。
    private let leadingGlowLayer = CAGradientLayer()
    private let trailingGlowLayer = CAGradientLayer()

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

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        leadingGlowLayer.frame = bounds
        trailingGlowLayer.frame = bounds
    }

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

enum LiveRoomGiftSheetMotionMetrics {

    static func offscreenTranslation(
        sheetHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        max(0, sheetHeight) + max(0, safeAreaBottom) + 12
    }
}

#if DEBUG
#Preview("送礼氛围背景") {
    QuickLayoutHostingController {
        LiveRoomGiftAmbientView()
            .resizable()
            .frame(width: 390, height: 220)
    }
}
#endif
