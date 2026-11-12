import ObjectiveC
import QuickLayoutKitCore
import UIKit

/// 在宿主重建布局时撤销已经移除的声明；独立滚动布局保留最近的测量结果。
@MainActor
private final class SafeAreaInsetScrollPass {
    private final class Entry {
        weak var scroll: UIScrollView?
        init(_ scroll: UIScrollView) { self.scroll = scroll }
    }
    private var previous: [ObjectIdentifier: Entry] = [:]
    private var current: [ObjectIdentifier: Entry] = [:]
    private var depth = 0
    @TaskLocal static var active: SafeAreaInsetScrollPass?

    func withPass<Result>(_ operation: () throws -> Result) rethrows -> Result {
        let starts = depth == 0
        if starts { current.removeAll(keepingCapacity: true) }
        depth += 1
        defer {
            depth -= 1
            if starts {
                for (id, entry) in previous where current[id] == nil {
                    guard let scroll = entry.scroll, scroll.safeAreaInsetOwner === self else { continue }
                    scroll.quickLayoutScrollMarginState.setSafeAreaReservation(.init(), on: scroll)
                    if !(scroll is QuickLayoutScrollView) { scroll.quickLayoutScrollMarginState.reset(on: scroll) }
                    scroll.safeAreaInsetOwner = nil
                }
                // 原生列表的 UIKit 自动 inset 在放置后才更新；同一事务按最终视口补偿一次。
                for entry in current.values {
                    if let scroll = entry.scroll { scroll.quickLayoutScrollMarginState.updateLayoutDirectionIfNeeded(on: scroll) }
                }
                previous = current
            }
        }
        return try Self.$active.withValue(self, operation: operation)
    }

    func register(_ scroll: UIScrollView) {
        current[ObjectIdentifier(scroll)] = Entry(scroll)
        scroll.safeAreaInsetOwner = self
    }

    isolated deinit {
        for entry in previous.values {
            guard let scroll = entry.scroll,
                  scroll.safeAreaInsetOwner == nil || scroll.safeAreaInsetOwner === self else { continue }
            scroll.quickLayoutScrollMarginState.setSafeAreaReservation(.init(), on: scroll)
            if !(scroll is QuickLayoutScrollView) { scroll.quickLayoutScrollMarginState.reset(on: scroll) }
        }
    }
}

private final class WeakInsetOwner {
    weak var value: SafeAreaInsetScrollPass?
    init(_ value: SafeAreaInsetScrollPass?) { self.value = value }
}

private enum InsetKeys {
    nonisolated(unsafe) static var pass: UInt8 = 0
    nonisolated(unsafe) static var owner: UInt8 = 0
}

extension UIView {
    func withQuickLayoutSafeAreaInsetPass<Result>(_ operation: () throws -> Result) rethrows -> Result {
        let pass: SafeAreaInsetScrollPass
        if let existing = objc_getAssociatedObject(self, &InsetKeys.pass) as? SafeAreaInsetScrollPass {
            pass = existing
        } else {
            pass = SafeAreaInsetScrollPass()
            objc_setAssociatedObject(self, &InsetKeys.pass, pass, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return try pass.withPass(operation)
    }
}

extension UIScrollView {
    fileprivate var safeAreaInsetOwner: SafeAreaInsetScrollPass? {
        get { (objc_getAssociatedObject(self, &InsetKeys.owner) as? WeakInsetOwner)?.value }
        set { objc_setAssociatedObject(self, &InsetKeys.owner, WeakInsetOwner(newValue), .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func quickLayoutSetSafeAreaInsetReservation(_ value: QuickLayoutSafeAreaInsetReservation) {
        if let pass = SafeAreaInsetScrollPass.active { pass.register(self) }
        else { safeAreaInsetOwner = nil }
        quickLayoutScrollMarginState.setSafeAreaReservation(value, on: self)
    }
}
