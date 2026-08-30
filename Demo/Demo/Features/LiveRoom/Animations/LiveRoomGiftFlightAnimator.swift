//
//  LiveRoomGiftFlightAnimator.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import UIKit

@MainActor
final class LiveRoomGiftFlightAnimator {

    let id = UUID()

    private weak var containerView: UIView?
    private let overlayView = UIView()
    private let giftView = UIView()
    private let giftImageView = UIImageView()
    private let quantityLabel = UILabel()
    private var completion: (() -> Void)?
    private var completionWorkItem: DispatchWorkItem?

    init(containerView: UIView) {
        self.containerView = containerView
        configureViews()
    }

    func start(
        gift: LiveRoomGift,
        quantity: Int,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        delay: TimeInterval = 0,
        showsCelebration: Bool = false,
        arrival: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        guard let containerView else {
            completion()
            return
        }
        self.completion = completion
        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(overlayView)

        let color = LiveRoomTheme.giftColor(at: gift.themeIndex)
        let giftDiameter: CGFloat
        switch gift.effectStyle {
        case .trail:
            giftDiameter = 54
        case .burst:
            giftDiameter = 60
        case .celebration:
            giftDiameter = 68
        }
        giftView.bounds.size = CGSize(width: giftDiameter, height: giftDiameter)
        giftView.layer.cornerRadius = giftDiameter / 2
        giftView.backgroundColor = color
        giftView.layer.shadowColor = color.cgColor
        giftImageView.image = UIImage(systemName: gift.symbolName)
        configureQuantityLabel(quantity, giftDiameter: giftDiameter)
        giftView.center = startPoint

        if showsCelebration
            && gift.effectStyle == .celebration
            && !UIAccessibility.isReduceMotionEnabled {
            playCelebrationBanner(gift: gift, color: color, delay: delay)
        }

        if UIAccessibility.isReduceMotionEnabled {
            playReducedMotion(
                to: endPoint,
                delay: delay,
                arrival: arrival
            )
            return
        }

        playFlight(
            from: startPoint,
            to: endPoint,
            gift: gift,
            color: color,
            delay: delay,
            arrival: arrival
        )
    }

    func cancel() {
        completionWorkItem?.cancel()
        completionWorkItem = nil
        overlayView.layer.removeAllAnimations()
        overlayView.removeFromSuperview()
        finish()
    }

    private func configureViews() {
        overlayView.isUserInteractionEnabled = false
        overlayView.isAccessibilityElement = false
        overlayView.accessibilityElementsHidden = true
        overlayView.accessibilityIdentifier = "liveRoom.gift.effect.overlay"

        giftView.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        giftView.layer.cornerRadius = 27
        giftView.layer.borderWidth = 2
        giftView.layer.borderColor = UIColor.white.withAlphaComponent(0.72).cgColor
        giftView.layer.shadowOpacity = 0.72
        giftView.layer.shadowRadius = 14
        giftView.layer.shadowOffset = .zero

        giftImageView.frame = giftView.bounds.insetBy(dx: 13, dy: 13)
        giftImageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        giftImageView.contentMode = .scaleAspectFit
        giftImageView.tintColor = .white
        giftView.addSubview(giftImageView)

        quantityLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        quantityLabel.textColor = .white
        quantityLabel.font = .monospacedDigitSystemFont(
            ofSize: 10,
            weight: .bold
        )
        quantityLabel.textAlignment = .center
        quantityLabel.layer.cornerRadius = 9
        quantityLabel.clipsToBounds = true
        quantityLabel.isHidden = true
        giftView.addSubview(quantityLabel)
        overlayView.addSubview(giftView)
    }

    private func configureQuantityLabel(
        _ quantity: Int,
        giftDiameter: CGFloat
    ) {
        quantityLabel.isHidden = quantity <= 1
        guard quantity > 1 else { return }
        quantityLabel.text = "×\(quantity)"
        let fittedSize = quantityLabel.sizeThatFits(
            CGSize(width: 72, height: 18)
        )
        let width = min(72, max(30, fittedSize.width + 10))
        quantityLabel.frame = CGRect(
            x: giftDiameter - width * 0.72,
            y: giftDiameter - 15,
            width: width,
            height: 18
        )
    }

    private func playReducedMotion(
        to endPoint: CGPoint,
        delay: TimeInterval,
        arrival: @escaping () -> Void
    ) {
        giftView.alpha = 0
        giftView.center = endPoint
        giftView.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
        UIView.animate(
            withDuration: 0.18,
            delay: delay,
            options: .curveEaseOut,
            animations: {
                self.giftView.alpha = 1
                self.giftView.transform = .identity
            },
            completion: { _ in
                arrival()
                UIView.animate(
                    withDuration: 0.16,
                    animations: {
                        self.giftView.alpha = 0
                        self.giftView.transform = CGAffineTransform(
                            scaleX: 1.25,
                            y: 1.25
                        )
                    },
                    completion: { _ in
                        self.overlayView.removeFromSuperview()
                        self.finish()
                    }
                )
            }
        )
    }

    private func playFlight(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        gift: LiveRoomGift,
        color: UIColor,
        delay: TimeInterval,
        arrival: @escaping () -> Void
    ) {
        let path = flightPath(from: startPoint, to: endPoint)
        let beginTime = CACurrentMediaTime() + 0.04 + delay
        let duration: CFTimeInterval
        let sparkleCount: Int
        switch gift.effectStyle {
        case .trail:
            duration = 0.78
            sparkleCount = 3
        case .burst:
            duration = 0.92
            sparkleCount = 6
        case .celebration:
            duration = 1.05
            sparkleCount = 10
        }

        for index in 0..<sparkleCount {
            let sparkle = makeSparkle(color: color, index: index)
            sparkle.center = startPoint
            overlayView.insertSubview(sparkle, belowSubview: giftView)
            addFlightAnimations(
                to: sparkle,
                path: path,
                beginTime: beginTime + Double(index + 1) * 0.055,
                duration: duration,
                isGift: false
            )
        }

        giftView.center = endPoint
        addFlightAnimations(
            to: giftView,
            path: path,
            beginTime: beginTime,
            duration: duration,
            isGift: true
        )

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            arrival()
            if gift.effectStyle != .trail {
                self.playBurst(
                    at: endPoint,
                    color: color,
                    style: gift.effectStyle
                )
            }
            UIImpactFeedbackGenerator(
                style: gift.effectStyle == .celebration ? .heavy : .light
            ).impactOccurred()
            let exitDuration: TimeInterval = gift.effectStyle == .celebration
                ? 0.46
                : (gift.effectStyle == .burst ? 0.32 : 0.20)
            UIView.animate(
                withDuration: exitDuration,
                delay: 0,
                options: .curveEaseOut,
                animations: {
                    self.giftView.alpha = 0
                    self.giftView.transform = CGAffineTransform(
                        scaleX: 1.48,
                        y: 1.48
                    )
                },
                completion: { _ in
                    self.overlayView.removeFromSuperview()
                    self.finish()
                }
            )
        }
        completionWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.04 + delay + duration,
            execute: workItem
        )
    }

    private func flightPath(from startPoint: CGPoint, to endPoint: CGPoint) -> CGPath {
        let deltaX = endPoint.x - startPoint.x
        let deltaY = endPoint.y - startPoint.y
        let lift = max(90, abs(deltaY) * 0.32)
        let path = UIBezierPath()
        path.move(to: startPoint)
        path.addCurve(
            to: endPoint,
            controlPoint1: CGPoint(
                x: startPoint.x + deltaX * 0.18,
                y: startPoint.y - lift
            ),
            controlPoint2: CGPoint(
                x: endPoint.x - deltaX * 0.12,
                y: endPoint.y + lift * 0.26
            )
        )
        return path.cgPath
    }

    private func addFlightAnimations(
        to view: UIView,
        path: CGPath,
        beginTime: CFTimeInterval,
        duration: CFTimeInterval,
        isGift: Bool
    ) {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path
        position.calculationMode = .paced

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = isGift
            ? [0.45, 1.08, 0.90, 1.0]
            : [0.25, 0.85, 0.55, 0.12]
        scale.keyTimes = [0, 0.24, 0.72, 1]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = isGift
            ? [0, 1, 1, 1]
            : [0, 0.92, 0.68, 0]
        opacity.keyTimes = [0, 0.12, 0.70, 1]

        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = isGift ? [-0.14, 0.10, -0.05, 0] : [0, 0, 0, 0]
        rotation.keyTimes = [0, 0.38, 0.76, 1]

        let group = CAAnimationGroup()
        group.animations = [position, scale, opacity, rotation]
        group.beginTime = beginTime
        group.duration = duration
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(group, forKey: "liveRoom.gift.flight")
    }

    private func makeSparkle(color: UIColor, index: Int) -> UIView {
        let diameter = CGFloat(6 + (index % 4) * 3)
        let sparkle = UIView(
            frame: CGRect(x: 0, y: 0, width: diameter, height: diameter)
        )
        sparkle.backgroundColor = index.isMultiple(of: 3) ? .white : color
        sparkle.layer.cornerRadius = diameter / 2
        sparkle.layer.shadowColor = color.cgColor
        sparkle.layer.shadowOpacity = 0.8
        sparkle.layer.shadowRadius = 5
        return sparkle
    }

    private func playBurst(
        at point: CGPoint,
        color: UIColor,
        style: LiveRoomGiftEffectStyle
    ) {
        let particleCount = style == .celebration ? 16 : 10
        let distance: CGFloat = style == .celebration ? 82 : 54
        for index in 0..<particleCount {
            let particle = makeSparkle(color: color, index: index)
            particle.center = point
            overlayView.addSubview(particle)
            let angle = CGFloat(index) / CGFloat(particleCount) * .pi * 2
            let destination = CGPoint(
                x: point.x + cos(angle) * distance,
                y: point.y + sin(angle) * distance
            )
            particle.transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
            UIView.animate(
                withDuration: style == .celebration ? 0.48 : 0.32,
                delay: Double(index % 3) * 0.018,
                options: .curveEaseOut,
                animations: {
                    particle.center = destination
                    particle.alpha = 0
                    particle.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                },
                completion: { _ in particle.removeFromSuperview() }
            )
        }
    }

    private func playCelebrationBanner(
        gift: LiveRoomGift,
        color: UIColor,
        delay: TimeInterval
    ) {
        let bannerWidth = min(320, max(220, overlayView.bounds.width - 32))
        let bannerView = UIView(
            frame: CGRect(x: 0, y: 0, width: bannerWidth, height: 72)
        )
        bannerView.center = CGPoint(
            x: overlayView.bounds.midX,
            y: max(84, overlayView.bounds.height * 0.18)
        )
        bannerView.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        bannerView.layer.cornerRadius = 24
        bannerView.layer.cornerCurve = .continuous
        bannerView.layer.borderWidth = 1.5
        bannerView.layer.borderColor = color.withAlphaComponent(0.82).cgColor
        bannerView.layer.shadowColor = color.cgColor
        bannerView.layer.shadowOpacity = 0.72
        bannerView.layer.shadowRadius = 22
        bannerView.accessibilityIdentifier = "liveRoom.gift.effect.celebration"

        let imageView = UIImageView()
        imageView.image = UIImage(systemName: gift.symbolName)
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 38),
            imageView.heightAnchor.constraint(equalToConstant: 38),
        ])

        let titleLabel = UILabel()
        titleLabel.text = DemoLocalization.text(
            "liveRoom.gift.celebration",
            DemoLocalization.text(gift.titleKey)
        )
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.numberOfLines = 2
        titleLabel.textAlignment = .natural

        let contentStack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        contentStack.axis = .horizontal
        contentStack.alignment = .center
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: bannerView.leadingAnchor,
                constant: 18
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: bannerView.trailingAnchor,
                constant: -18
            ),
            contentStack.topAnchor.constraint(
                greaterThanOrEqualTo: bannerView.topAnchor,
                constant: 10
            ),
            contentStack.bottomAnchor.constraint(
                lessThanOrEqualTo: bannerView.bottomAnchor,
                constant: -10
            ),
            contentStack.centerYAnchor.constraint(
                equalTo: bannerView.centerYAnchor
            ),
        ])

        bannerView.alpha = 0
        bannerView.transform = CGAffineTransform(
            translationX: 0,
            y: -18
        ).scaledBy(x: 0.92, y: 0.92)
        overlayView.addSubview(bannerView)
        UIView.animateKeyframes(
            withDuration: 1.25,
            delay: delay,
            options: [.calculationModeCubic, .beginFromCurrentState]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.20) {
                bannerView.alpha = 1
                bannerView.transform = .identity
            }
            UIView.addKeyframe(withRelativeStartTime: 0.78, relativeDuration: 0.22) {
                bannerView.alpha = 0
                bannerView.transform = CGAffineTransform(
                    translationX: 0,
                    y: -12
                ).scaledBy(x: 0.96, y: 0.96)
            }
        }
    }

    private func finish() {
        completionWorkItem = nil
        let completion = completion
        self.completion = nil
        completion?()
    }
}

