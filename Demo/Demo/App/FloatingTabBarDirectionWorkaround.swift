import Darwin
import ObjectiveC
import UIKit

/// 系统浮动 Tab 栏 RTL→LTR 镜像的临时兼容处理，仅供本 Demo 使用。
///
/// PRIVATE API：下方调用 UIKit 未公开的 `layoutRTL` / `setLayoutRTL:`。
/// iPad / iOS 27.2 实测：collection 已恢复 LTR，但原生 compositional layout 保留
/// layoutRTL=true，后续 _fullResolve 又打开水平轴翻转。仅 invalidateLayout 无法恢复。
/// 必须在窗口/容器改变方向之前同步缓存，让 UIKit 自己更新轴翻转；镜像出现后只清缓存无效。
///
/// 保留原 UITabBarController、页面和系统浮动栏；不调整 transform、不固定 LTR、不 swizzle。
/// 私有类型/签名可能随系统变化，检查不匹配时跳过；这不是受支持的 UIKit API，也不保证其他
/// 系统版本兼容。不要下沉为 AppLocalization 的默认行为。UIKit 修复后，应移除此文件及
/// AppTabBarController.prepareForLocalization 中的调用，并用中→阿→中、badge/尺寸变化、
/// 聊天草稿/焦点回归确认无需该处理。调查及正负对照见 Docs/TabDirectionInvestigation-2026-11-02.md。
@MainActor
enum FloatingTabBarDirectionWorkaround {
    static func prepare(in rootView: UIView?, direction: UIUserInterfaceLayoutDirection) {
        guard #available(iOS 18.0, *), let rootView else { return }
        let targetRTL = direction == .rightToLeft

        func visit(_ view: UIView) {
            if let collection = view as? UICollectionView,
               NSStringFromClass(type(of: collection)) == "_UIFloatingTabBarCollectionView" {
                synchronize(collection.collectionViewLayout, targetRTL: targetRTL)
                return
            }
            for child in view.subviews { visit(child) }
        }
        visit(rootView)
    }

    private static func synchronize(_ layout: UICollectionViewLayout, targetRTL: Bool) {
        guard NSStringFromClass(type(of: layout)) == "_UIFloatingTabBarCollectionViewLayout" else { return }
        let getterSelector = NSSelectorFromString("layoutRTL")
        let setterSelector = NSSelectorFromString("setLayoutRTL:")
        guard let getterMethod = class_getInstanceMethod(type(of: layout), getterSelector),
              let setterMethod = class_getInstanceMethod(type(of: layout), setterSelector),
              method_getNumberOfArguments(getterMethod) == 2,
              method_getNumberOfArguments(setterMethod) == 3 else { return }

        let getterReturn = method_copyReturnType(getterMethod)
        let setterReturn = method_copyReturnType(setterMethod)
        let setterArgument = method_copyArgumentType(setterMethod, 2)
        defer { free(getterReturn); free(setterReturn); free(setterArgument) }
        guard String(cString: getterReturn) == "B",
              String(cString: setterReturn) == "v",
              let setterArgument, String(cString: setterArgument) == "B" else { return }

        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        let getter = unsafeBitCast(method_getImplementation(getterMethod), to: Getter.self)
        guard getter(layout, getterSelector) != targetRTL else { return }
        let setter = unsafeBitCast(method_getImplementation(setterMethod), to: Setter.self)
        setter(layout, setterSelector, targetRTL)
    }
}
