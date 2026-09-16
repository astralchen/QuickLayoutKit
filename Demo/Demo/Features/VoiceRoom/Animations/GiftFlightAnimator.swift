//
//  GiftFlightAnimator.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import UIKit

/// 呈现从赠礼起点飞向单个收礼人的原生礼物动画。
@MainActor
final class GiftFlightAnimator {

    /// 此飞行动画实例的唯一标识，用于登记和移除活动动画。
    let id = UUID()

    /// 承载动画的外部容器；弱引用不延长页面生命周期。
    private weak var containerView: UIView?
    /// 承载临时动画内容的透明覆盖视图。
    private let overlayView = UIView()
    /// 容纳礼物图标和数量的动画视图。
    private let giftView = UIView()
    /// 显示礼物符号的图像视图。
    private let giftImageView = UIImageView()
    /// 显示赠送数量的文本标签。
    private let quantityLabel = UILabel()
    /// 当前动画完成后的回调；清理后释放。
    private var completion: (() -> Void)?
    /// 延迟结束动画的工作项，取消时同步撤销。
    private var completionWorkItem: DispatchWorkItem?

    /// 创建在指定容器中展示单个收礼人飞行动画的对象。
    ///
    /// - Parameter containerView: 动画坐标所属的容器；动画器仅弱引用此视图。
    init(containerView: UIView) {
        self.containerView = containerView
        configureViews()
    }

    /// 配置礼物并开始从起点到收礼人的飞行动画。
    ///
    /// 起点与终点使用容器视图坐标。减少动态效果开启时采用淡入淡出展示。
    ///
    /// - Parameters:
    ///   - gift: 本次显示的礼物。
    ///   - style: 原生效果样式；为 `nil` 时使用礼物的默认样式。
    ///   - quantity: 向此收礼人赠送的份数。
    ///   - startPoint: 容器坐标中的飞行起点。
    ///   - endPoint: 容器坐标中的目标位置。
    ///   - delay: 开始展示前的延迟，单位为秒。
    ///   - showsCelebration: 是否同时展示庆典横幅。
    ///   - arrival: 礼物抵达时执行的回调。
    ///   - completion: 动画结束并清理后执行的回调。
    func start(
        gift: Gift,
        style: GiftEffectStyle? = nil,
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
        let style = style ?? gift.effectStyle
        self.completion = completion
        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(overlayView)

        let color = VoiceRoomTheme.giftColor(at: gift.themeIndex)
        let giftDiameter: CGFloat
        switch style {
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
            && style == .celebration
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
            style: style,
            color: color,
            delay: delay,
            arrival: arrival
        )
    }

    /// 撤销待执行的完成工作项、移除覆盖视图，并执行完成清理回调。
    func cancel() {
        completionWorkItem?.cancel()
        completionWorkItem = nil
        overlayView.layer.removeAllAnimations()
        overlayView.removeFromSuperview()
        finish()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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

    /// 设置赠送数量文案，并根据礼物直径调整数量标签位置。
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

    /// 以淡入淡出方式在目标位置展示礼物，并在抵达时通知调用方。
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

    /// 创建礼物飞行、拖尾和抵达粒子动画。
    private func playFlight(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        gift: Gift,
        style: GiftEffectStyle,
        color: UIColor,
        delay: TimeInterval,
        arrival: @escaping () -> Void
    ) {
        let path = flightPath(from: startPoint, to: endPoint)
        let beginTime = CACurrentMediaTime() + 0.04 + delay
        let duration: CFTimeInterval
        let sparkleCount: Int
        switch style {
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
            if style != .trail {
                self.playBurst(
                    at: endPoint,
                    color: color,
                    style: style
                )
            }
            UIImpactFeedbackGenerator(
                style: style == .celebration ? .heavy : .light
            ).impactOccurred()
            let exitDuration: TimeInterval = style == .celebration
                ? 0.46
                : (style == .burst ? 0.32 : 0.20)
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

    /// 返回连接起点与终点的弧形贝塞尔路径；坐标属于动画容器。
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

    /// 为礼物或拖尾视图添加位置、缩放、旋转及透明度动画。
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

    /// 创建指定颜色的拖尾粒子视图。
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

    /// 在礼物抵达位置生成与效果样式对应的扩散粒子。
    private func playBurst(
        at point: CGPoint,
        color: UIColor,
        style: GiftEffectStyle
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

    /// 在容器顶部显示礼物名称和庆典图标的横幅动画。
    private func playCelebrationBanner(
        gift: Gift,
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
        titleLabel.text = Localization.text(
            "liveRoom.gift.celebration",
            gift.localizedTitle
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

    /// 取出并清空完成回调后调用一次，避免重复终态重复通知。
    private func finish() {
        completionWorkItem = nil
        let completion = completion
        self.completion = nil
        completion?()
    }
}

