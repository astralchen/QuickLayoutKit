//
//  RechargeSuccessView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayoutKit
import UIKit

#if DEBUG
import QuickLayout
#endif

/// 呈现充值成功文案、勾选标记和装饰动画的浮层。
final class RechargeSuccessView: UIView {

    /// 成功提示浮层的模糊背景视图。
    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    /// 当前主体周围的光晕装饰视图。
    private let haloView = QuickLayoutShapeView(
        fillColor: .clear,
        strokeColor: UIColor.systemYellow.withAlphaComponent(0.72),
        strokeStyle: QuickLayoutStrokeStyle(lineWidth: 2),
        path: { rect in UIBezierPath(ovalIn: rect).cgPath }
    )
    /// 充值成功提示的第二层扩散光晕。
    private let secondaryHaloView = QuickLayoutShapeView(
        fillColor: .clear,
        strokeColor: UIColor.systemYellow.withAlphaComponent(0.42),
        strokeStyle: QuickLayoutStrokeStyle(lineWidth: 1),
        path: { rect in UIBezierPath(ovalIn: rect).cgPath }
    )
    /// 充值成功勾选标记的圆形背景。
    private let checkmarkBackgroundView = UIView()
    /// 显示已关注或已选中状态的勾选图标。
    private let checkmarkImageView = UIImageView()
    /// 显示当前提示正文的标签。
    private let messageLabel = UILabel()
    /// 围绕成功标记播放扩散动画的星光图像视图。
    private let sparkleImageViews = (0..<8).map { index in
        let imageView = UIImageView(
            image: UIImage(systemName: index.isMultiple(of: 2)
                ? "sparkle"
                : "star.fill")
        )
        imageView.tintColor = index.isMultiple(of: 3)
            ? .systemPink
            : .systemYellow
        imageView.contentMode = .scaleAspectFit
        return imageView
    }

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.34
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 10)

        blurView.layer.cornerRadius = 26
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        blurView.layer.borderWidth = 1
        blurView.layer.borderColor = UIColor.systemYellow
            .withAlphaComponent(0.42).cgColor

        haloView.layer.opacity = 0
        secondaryHaloView.layer.opacity = 0

        checkmarkBackgroundView.backgroundColor = .systemYellow
        checkmarkBackgroundView.layer.cornerRadius = 27
        checkmarkBackgroundView.layer.shadowColor = UIColor.systemYellow.cgColor
        checkmarkBackgroundView.layer.shadowOpacity = 0.48
        checkmarkBackgroundView.layer.shadowRadius = 12
        checkmarkBackgroundView.layer.shadowOffset = .zero

        checkmarkImageView.image = UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 24,
                weight: .bold
            )
        )
        checkmarkImageView.tintColor = UIColor(
            red: 0.12,
            green: 0.10,
            blue: 0.04,
            alpha: 1
        )
        checkmarkImageView.contentMode = .scaleAspectFit

        messageLabel.font = .preferredFont(forTextStyle: .headline)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.adjustsFontSizeToFitWidth = true
        messageLabel.minimumScaleFactor = 0.72
        messageLabel.numberOfLines = 2

        addSubview(blurView)
        addSubview(haloView)
        addSubview(secondaryHaloView)
        sparkleImageViews.forEach(addSubview)
        addSubview(checkmarkBackgroundView)
        addSubview(checkmarkImageView)
        addSubview(messageLabel)
    }

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 根据当前浮层边界更新模糊背景、光晕及星光的位置。
    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds

        let badgeFrame = CGRect(
            x: (bounds.width - 54) / 2,
            y: 25,
            width: 54,
            height: 54
        )
        checkmarkBackgroundView.frame = badgeFrame
        checkmarkImageView.frame = badgeFrame.insetBy(dx: 14, dy: 14)

        let haloFrame = badgeFrame.insetBy(dx: -11, dy: -11)
        [haloView, secondaryHaloView].forEach {
            $0.frame = haloFrame
        }

        messageLabel.frame = CGRect(
            x: 16,
            y: 95,
            width: max(0, bounds.width - 32),
            height: 48
        )

        let sparkleCenters = [
            CGPoint(x: 44, y: 44),
            CGPoint(x: 73, y: 20),
            CGPoint(x: bounds.width - 70, y: 22),
            CGPoint(x: bounds.width - 40, y: 49),
            CGPoint(x: 51, y: 91),
            CGPoint(x: bounds.width - 49, y: 92),
            CGPoint(x: 91, y: 77),
            CGPoint(x: bounds.width - 91, y: 76),
        ]
        for (index, imageView) in sparkleImageViews.enumerated() {
            let side: CGFloat = index.isMultiple(of: 2) ? 14 : 10
            imageView.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            imageView.center = sparkleCenters[index]
        }
    }

    /// 更新充值成功提示文案。
    func configure(message: String) {
        messageLabel.text = message
    }

    /// 移除先前装饰动画并恢复新一轮成功动画的初始状态。
    func prepareForAnimation() {
        layoutIfNeeded()
        haloView.layer.removeAllAnimations()
        secondaryHaloView.layer.removeAllAnimations()
        haloView.layer.opacity = 0
        secondaryHaloView.layer.opacity = 0
        checkmarkBackgroundView.transform = CGAffineTransform(
            scaleX: 0.42,
            y: 0.42
        )
        checkmarkImageView.transform = CGAffineTransform(
            scaleX: 0.42,
            y: 0.42
        )
        let badgeCenter = checkmarkBackgroundView.center
        for imageView in sparkleImageViews {
            imageView.layer.removeAllAnimations()
            imageView.alpha = 0
            imageView.transform = CGAffineTransform(
                translationX: badgeCenter.x - imageView.center.x,
                y: badgeCenter.y - imageView.center.y
            ).scaledBy(x: 0.30, y: 0.30)
        }
    }

    /// 播放成功标记、光晕和星光装饰；调用方应先确认允许动态效果。
    func playDecorativeAnimation() {
        playHaloAnimation(on: haloView.layer, delay: 0.05)
        playHaloAnimation(on: secondaryHaloView.layer, delay: 0.18)

        UIView.animate(
            withDuration: 0.55,
            delay: 0.08,
            usingSpringWithDamping: 0.58,
            initialSpringVelocity: 0.48,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.checkmarkBackgroundView.transform = .identity
            self.checkmarkImageView.transform = .identity
        }

        for (index, imageView) in sparkleImageViews.enumerated() {
            UIView.animateKeyframes(
                withDuration: 0.92,
                delay: 0.08 + Double(index) * 0.025,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                UIView.addKeyframe(
                    withRelativeStartTime: 0,
                    relativeDuration: 0.32
                ) {
                    imageView.alpha = 1
                    imageView.transform = CGAffineTransform(
                        scaleX: 1.18,
                        y: 1.18
                    )
                }
                UIView.addKeyframe(
                    withRelativeStartTime: 0.32,
                    relativeDuration: 0.32
                ) {
                    imageView.alpha = 0.92
                    imageView.transform = .identity
                }
                UIView.addKeyframe(
                    withRelativeStartTime: 0.72,
                    relativeDuration: 0.28
                ) {
                    imageView.alpha = 0
                    imageView.transform = CGAffineTransform(
                        scaleX: 0.72,
                        y: 0.72
                    )
                }
            }
        }
    }

    /// 为指定光晕图层添加延迟扩散和淡出动画。
    private func playHaloAnimation(
        on haloLayer: CALayer,
        delay: CFTimeInterval
    ) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.54
        scaleAnimation.toValue = 1.38

        let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnimation.values = [0, 0.86, 0]
        opacityAnimation.keyTimes = [0, 0.20, 1]

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [scaleAnimation, opacityAnimation]
        animationGroup.duration = 0.90
        animationGroup.beginTime = CACurrentMediaTime() + delay
        animationGroup.timingFunction = CAMediaTimingFunction(
            name: .easeOut
        )
        haloLayer.add(animationGroup, forKey: "rechargeSuccessHalo")
    }
}

#if DEBUG
/// 创建展示充值成功浮层的预览控制器。
@MainActor
private func makeRechargeSuccessViewPreview() -> UIViewController {
    let view = RechargeSuccessView()
    view.configure(message: "充值成功 · +6,300 星币")
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable()
                .padding(
                    EdgeInsets(
                        top: 34,
                        leading: 36,
                        bottom: 34,
                        trailing: 36
                    )
                )
                .frame(width: 310, height: 230)
        }
    }
}

@available(iOS 17.0, *)
#Preview("充值成功") {
    makeRechargeSuccessViewPreview()
}
#endif
