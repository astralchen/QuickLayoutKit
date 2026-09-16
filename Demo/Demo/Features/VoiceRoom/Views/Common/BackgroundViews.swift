//
//  BackgroundViews.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayoutKit
import UIKit

#if DEBUG
import QuickLayout
#endif

/// 在渐变背景上绘制装饰性星点的房间背景视图。
final class StarfieldBackgroundView: QuickLayoutLinearGradientView {

    /// 绘制背景星点路径的形状视图。
    private let starsView = QuickLayoutShapeView(frame: .zero)

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGradient()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGradient()
    }

    /// 使星点装饰覆盖最新的背景边界。
    override func layoutSubviews() {
        super.layoutSubviews()
        starsView.frame = bounds
    }

    /// 配置房间背景的渐变颜色和星点装饰。
    private func configureGradient() {
        gradient = QuickLayoutGradient(stops: [
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.13, green: 0.08, blue: 0.36, alpha: 1),
                location: 0
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.30, green: 0.16, blue: 0.61, alpha: 1),
                location: 0.52
            ),
            QuickLayoutGradient.Stop(
                color: UIColor(red: 0.11, green: 0.34, blue: 0.68, alpha: 1),
                location: 1
            ),
        ])
        startPoint = UnitPoint(x: 0.05, y: 0)
        endPoint = UnitPoint(x: 0.95, y: 1)

        starsView.fillColor = UIColor.white.withAlphaComponent(0.55)
        starsView.shape = QuickLayoutAnyShape { bounds in
            let points: [CGPoint] = [
                CGPoint(x: 0.08, y: 0.12), CGPoint(x: 0.24, y: 0.08),
                CGPoint(x: 0.40, y: 0.16), CGPoint(x: 0.68, y: 0.10),
                CGPoint(x: 0.88, y: 0.18), CGPoint(x: 0.15, y: 0.34),
                CGPoint(x: 0.52, y: 0.30), CGPoint(x: 0.78, y: 0.42),
                CGPoint(x: 0.31, y: 0.51), CGPoint(x: 0.92, y: 0.57),
                CGPoint(x: 0.10, y: 0.69), CGPoint(x: 0.62, y: 0.72),
                CGPoint(x: 0.38, y: 0.84), CGPoint(x: 0.82, y: 0.91),
            ]
            let path = CGMutablePath()
            for point in points {
                let center = CGPoint(
                    x: bounds.width * point.x,
                    y: bounds.height * point.y
                )
                path.addEllipse(
                    in: CGRect(
                        x: center.x - 1.5,
                        y: center.y - 1.5,
                        width: 3,
                        height: 3
                    )
                )
            }
            return path
        }
        starsView.layer.shadowColor = UIColor.white.cgColor
        starsView.layer.shadowOpacity = 0.7
        starsView.layer.shadowRadius = 3
        addSubview(starsView)
        isAccessibilityElement = false
    }
}

/// 为子视图提供半透明背景和连续圆角的卡片容器。
class TranslucentCardView: QuickLayoutView {

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        backgroundColor = UIColor.black.withAlphaComponent(0.18)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("直播间背景") {
    QuickLayoutHostingController {
        StarfieldBackgroundView()
            .resizable()
    }
}

@available(iOS 17.0, *)
#Preview("直播间通用卡片") {
    QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            TranslucentCardView().resizable().padding(16)
                .frame(height: 180)
        }
    }
}
#endif
