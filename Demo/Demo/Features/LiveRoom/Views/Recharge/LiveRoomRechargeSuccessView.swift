//
//  LiveRoomRechargeSuccessView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayoutKit
import UIKit

#if DEBUG
import QuickLayout
#endif

final class LiveRoomRechargeSuccessView: UIView {

    private let blurView = UIVisualEffectView(
        effect: UIBlurEffect(style: .systemUltraThinMaterialDark)
    )
    private let haloView = QuickLayoutShapeView(
        fillColor: .clear,
        strokeColor: UIColor.systemYellow.withAlphaComponent(0.72),
        strokeStyle: QuickLayoutStrokeStyle(lineWidth: 2),
        path: { rect in UIBezierPath(ovalIn: rect).cgPath }
    )
    private let secondaryHaloView = QuickLayoutShapeView(
        fillColor: .clear,
        strokeColor: UIColor.systemYellow.withAlphaComponent(0.42),
        strokeStyle: QuickLayoutStrokeStyle(lineWidth: 1),
        path: { rect in UIBezierPath(ovalIn: rect).cgPath }
    )
    private let checkmarkBackgroundView = UIView()
    private let checkmarkImageView = UIImageView()
    private let messageLabel = UILabel()
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

    required init?(coder: NSCoder) {
        return nil
    }

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

    func configure(message: String) {
        messageLabel.text = message
    }

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
@MainActor
private func makeLiveRoomRechargeSuccessViewPreview() -> UIViewController {
    let view = LiveRoomRechargeSuccessView()
    view.configure(message: "充值成功 · +6,300 星币")
    return QuickLayoutHostingController {
        ZStack {
            LiveRoomBackdropView().resizable()
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

#Preview("充值成功") {
    makeLiveRoomRechargeSuccessViewPreview()
}
#endif
