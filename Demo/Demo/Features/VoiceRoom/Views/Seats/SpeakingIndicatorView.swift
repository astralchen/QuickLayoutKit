//
//  SpeakingIndicatorView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import UIKit

#if DEBUG
import QuickLayout
import QuickLayoutKit
#endif

/// 使用循环柱状动画提示麦位处于说话状态，不展示实际音频采样波形。
final class SpeakingIndicatorView: UIView {

    /// 波形条动画在图层中使用的唯一键。
    private static let animationKey = "liveRoom.waveform.pulse"
    /// 构成说话指示器的三个波形条图层。
    private let barLayers = (0..<3).map { _ in CALayer() }
    /// 一个布尔值，指示业务状态是否要求显示说话动画。
    private var wantsAnimation = false

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    /// 移除减少动态效果状态变化的通知监听。
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 根据是否位于窗口中重新评估说话动画的运行状态。
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

    /// 根据当前边界布局三个波形条并设置圆角。
    override func layoutSubviews() {
        super.layoutSubviews()
        let barWidth = max(1, bounds.width * 0.18)
        let availableSpacing = max(0, bounds.width - barWidth * 3)
        let spacing = availableSpacing / 2
        let heightFactors: [CGFloat] = [0.56, 1, 0.72]

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, barLayer) in barLayers.enumerated() {
            let height = max(2, bounds.height * heightFactors[index])
            barLayer.frame = CGRect(
                x: CGFloat(index) * (barWidth + spacing),
                y: (bounds.height - height) / 2,
                width: barWidth,
                height: height
            )
            barLayer.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
    }

    /// 更新业务期望的说话状态，并结合窗口和辅助功能环境决定是否播放。
    func setAnimating(_ isAnimating: Bool) {
        guard wantsAnimation != isAnimating else { return }
        wantsAnimation = isAnimating
        updateAnimationState()
    }

    /// 配置组件的基础样式和交互行为。
    private func configureView() {
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        barLayers.forEach { barLayer in
            barLayer.backgroundColor = UIColor.white.cgColor
            layer.addSublayer(barLayer)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
    }

    /// 在减少动态效果设置变化时刷新波形动画状态。
    @objc private func reduceMotionStatusDidChange() {
        updateAnimationState()
    }

    /// 仅在需要动画、位于窗口且未启用减少动态效果时启动波形。
    private func updateAnimationState() {
        guard wantsAnimation,
              window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            stopAnimating()
            return
        }
        startAnimating()
    }

    /// 为尚未运行的波形条添加错峰循环缩放动画。
    private func startAnimating() {
        let durations: [CFTimeInterval] = [0.48, 0.62, 0.54]
        let delays: [CFTimeInterval] = [0, 0.12, 0.24]
        let currentTime = CACurrentMediaTime()

        for (index, barLayer) in barLayers.enumerated() {
            guard barLayer.animation(forKey: Self.animationKey) == nil else {
                continue
            }
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = 0.36
            animation.toValue = 1
            animation.duration = durations[index]
            animation.beginTime = currentTime + delays[index]
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            animation.isRemovedOnCompletion = false
            barLayer.add(animation, forKey: Self.animationKey)
        }
    }

    /// 移除波形动画并恢复静态波形条外观。
    private func stopAnimating() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayers.forEach { barLayer in
            barLayer.removeAnimation(forKey: Self.animationKey)
            barLayer.transform = CATransform3DIdentity
        }
        CATransaction.commit()
    }
}

#if DEBUG
/// 创建展示指定尺寸的说话指示器的预览控制器。
@MainActor
private func makeSpeakingIndicatorPreview(
    microphoneDiameter: CGFloat,
    waveformDiameter: CGFloat
) -> UIViewController {
    let backgroundView = UIView()
    backgroundView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.92)
    backgroundView.layer.cornerRadius = microphoneDiameter / 2

    let speakingIndicatorView = SpeakingIndicatorView()
    speakingIndicatorView.setAnimating(true)

    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            // 复刻麦位中的真实层级：圆形状态背景包裹透明波形视图。
            ZStack {
                backgroundView
                    .resizable()
                    .frame(
                        width: microphoneDiameter,
                        height: microphoneDiameter
                    )
                speakingIndicatorView
                    .resizable()
                    .frame(
                        width: waveformDiameter,
                        height: waveformDiameter
                    )
            }
        }
        .frame(width: 72, height: 72)
    }
}

@available(iOS 17.0, *)
#Preview("声音波纹 · 常规麦位") {
    makeSpeakingIndicatorPreview(
        microphoneDiameter: 22,
        waveformDiameter: 11
    )
}

@available(iOS 17.0, *)
#Preview("声音波纹 · 放大麦位") {
    makeSpeakingIndicatorPreview(
        microphoneDiameter: 28,
        waveformDiameter: 14
    )
}
#endif
