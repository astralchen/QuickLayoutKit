//
//  LiveRoomWaveformView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import UIKit

#if DEBUG
import QuickLayout
import QuickLayoutKit
#endif

final class LiveRoomWaveformView: UIView {

    private static let animationKey = "liveRoom.waveform.pulse"
    private let barLayers = (0..<3).map { _ in CALayer() }
    private var wantsAnimation = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

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

    func setAnimating(_ isAnimating: Bool) {
        guard wantsAnimation != isAnimating else { return }
        wantsAnimation = isAnimating
        updateAnimationState()
    }

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

    @objc private func reduceMotionStatusDidChange() {
        updateAnimationState()
    }

    private func updateAnimationState() {
        guard wantsAnimation,
              window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            stopAnimating()
            return
        }
        startAnimating()
    }

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
@MainActor
private func makeLiveRoomWaveformPreview() -> UIViewController {
    let view = LiveRoomWaveformView()
    view.backgroundColor = .systemGreen
    view.layer.cornerRadius = 16
    view.setAnimating(true)
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView()
            view
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 20,
                        leading: 32,
                        bottom: 20,
                        trailing: 32
                    )
                )
        }
        .frame(width: 96, height: 72)
    }
}

#Preview("声音波纹") {
    makeLiveRoomWaveformPreview()
}
#endif
