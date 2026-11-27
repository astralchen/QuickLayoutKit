import QuickLayoutKit
import UIKit

/// 两种引擎使用同一组选项和值，便于逐项比较。偏移量在呈现完成后设置。
enum PopoverComparisonOption: String, CaseIterable {
    case hide = "shouldHideArrow"
    case offset = "arrowOffset = 39"
    case inset = "dimmingViewTopEdgeInset = 90"
    case radius = "cornerRadius = 7"
    case corners = "cornerConfiguration (12 / 28)"
    case style = "popoverBackgroundStyle = 1"
    case tint = "arrowBackgroundColor = systemRed"
    case disableBlur = "backgroundBlurDisabled"
    case blur = "backgroundBlurEffectStyle = dark"

    @available(iOS 26, *)
    private var configuration: UICornerConfiguration {
        .uniformEdges(topRadius: .fixed(12), bottomRadius: .fixed(28))
    }

    @MainActor func apply(to pc: PopoverPresentationController) {
        switch self {
        case .hide: pc.shouldHideArrow = true
        case .offset: pc.arrowOffset = 39
        case .inset: pc.dimmingViewTopEdgeInset = 90
        case .radius: pc.cornerRadius = 7
        case .corners: if #available(iOS 26, *) { pc.cornerConfiguration = configuration }
        case .style: pc.popoverBackgroundStyle = .init(rawValue: 1)
        case .tint: pc.arrowBackgroundColor = .systemRed
        case .disableBlur: pc.backgroundBlurDisabled = true
        case .blur: pc.backgroundBlurEffectStyle = .dark
        }
    }

    @MainActor func apply(to pc: UIPopoverPresentationController) {
        if self == .radius { pc.setCustomBackgroundCornerRadius(7) }
        if #available(iOS 26, *), self == .corners { pc.setCustomBackgroundCornerConfiguration(configuration) }
        #if DEBUG
        // 仅在对照系统默认背景时需要 UIKit 的私有圆角访问器。

        func method(_ name: String) -> (Selector, IMP)? {
            let selector = NSSelectorFromString(name)
            guard pc.responds(to: selector), let imp = pc.method(for: selector) else { return nil }
            return (selector, imp)
        }
        func number(_ name: String, _ value: Double) {
            guard let (sel, imp) = method(name) else { return }
            typealias Setter = @convention(c) (NSObject, Selector, Double) -> Void
            unsafeBitCast(imp, to: Setter.self)(pc, sel, value)
        }
        func integer(_ name: String, _ value: Int) {
            guard let (sel, imp) = method(name) else { return }
            typealias Setter = @convention(c) (NSObject, Selector, Int) -> Void
            unsafeBitCast(imp, to: Setter.self)(pc, sel, value)
        }
        func enable(_ name: String) {
            guard let (sel, imp) = method(name) else { return }
            typealias Setter = @convention(c) (NSObject, Selector, Bool) -> Void
            unsafeBitCast(imp, to: Setter.self)(pc, sel, true)
        }
        switch self {
        case .hide: enable("_setShouldHideArrow:")
        case .disableBlur: enable("_setBackgroundBlurDisabled:")
        case .offset: number("_setArrowOffset:", 39)
        case .inset: number("_setDimmingViewTopEdgeInset:", 90)
        case .radius:
            number("_setCornerRadius:", 7)
        case .corners:
            if #available(iOS 26, *) {
                guard let (sel, _) = method("_setCornerConfiguration:") else { return }
                // UIKit 的 Swift 圆角配置是值类型。通过 UIView 取得对应的 Objective-C 对象。
                let reference = UIView()
                reference.cornerConfiguration = configuration
                pc.perform(sel, with: reference.value(forKey: "cornerConfiguration"))
            }
        case .style: integer("_setPopoverBackgroundStyle:", 1)
        case .tint:
            if let (sel, _) = method("setArrowBackgroundColor:") { pc.perform(sel, with: UIColor.systemRed) }
        case .blur: integer("_setBackgroundBlurEffectStyle:", UIBlurEffect.Style.dark.rawValue)
        }
        #endif
    }
}
