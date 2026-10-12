import UIKit
import ObjectiveC

/// 一个窗口只使用一个显示链接；弱引用观察者，后台或卸载后停止采样。
@MainActor
final class GeometryWindowMonitor: NSObject {
    /// 所属窗口的弱引用，监测器不延长窗口生命周期。
    private weak var window: UIWindow?
    /// 当前窗口的观察者弱引用集合，以对象身份去重。
    private var observers: [ObjectIdentifier: WeakObserver] = [:]
    /// 窗口可见且有活动观察者时运行的显示链接。
    private var displayLink: CADisplayLink?
    /// 使用类型擦除保存新系统版本的区域标识映射。
    private var identifiers: Any?
    /// 将单个监测器关联到窗口的唯一键。
    private static var associationKey: UInt8 = 0

    /// 延迟创建的窗口级系统区域身份映射，仅在支持保留区域的系统中访问。
    @available(iOS 27.1, *)
    var regionIdentifiers: GeometryRegionIdentifiers {
        if let ids = identifiers as? GeometryRegionIdentifiers { return ids }
        let ids = GeometryRegionIdentifiers()
        identifiers = ids
        return ids
    }

    /// 取得窗口已有监测器，或创建并关联一个新监测器。
    static func forWindow(_ window: UIWindow) -> GeometryWindowMonitor {
        if let monitor = objc_getAssociatedObject(window, &associationKey) as? GeometryWindowMonitor { return monitor }
        let monitor = GeometryWindowMonitor(window: window)
        objc_setAssociatedObject(window, &associationKey, monitor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return monitor
    }

    /// 保存窗口并观察应用、场景和窗口可见性变化。
    private init(window: UIWindow) {
        self.window = window
        super.init()
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.didBecomeActiveNotification,
                     UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIWindow.didBecomeHiddenNotification, UIWindow.didBecomeVisibleNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(activityChanged), name: name, object: nil)
        }
    }

    /// 登记观察者，并根据当前活动状态启停采样。
    func add(_ observer: GeometryObserverView) {
        observers[ObjectIdentifier(observer)] = WeakObserver(observer)
        updateLink()
    }

    /// 移除观察者；没有有效观察者时停止显示链接。
    func remove(_ observer: GeometryObserverView) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
        updateLink()
    }

    /// 在应用、场景或窗口状态变化后重新评估采样条件。
    @objc private func activityChanged() { updateLink() }

    /// 清除跨窗口及已释放的观察者，只在前台可见窗口中保持采样。
    private func updateLink() {
        observers = observers.filter { $0.value.value?.window === window && $0.value.value != nil }
        let active = window != nil && window?.isHidden == false && !observers.isEmpty &&
            UIApplication.shared.applicationState != .background &&
            (window?.windowScene == nil || window?.windowScene?.activationState == .foregroundActive)
        if active, displayLink == nil {
            let link = CADisplayLink(target: GeometryDisplayLinkTarget(self), selector: #selector(GeometryDisplayLinkTarget.tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !active {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// 先冻结全部观察者的几何，再统一发送回调，避免回调互相影响采样。
    func refresh() {
        updateLink()
        // 先冻结整个窗口，再调用业务闭包，避免一个 action 改变另一个观察者的采样结果。
        let snapshots = observers.values.compactMap { reference -> (GeometryObserverView, GeometryProxy)? in
            guard let observer = reference.value, observer.hasAppliedGeometry else { return nil }
            return (observer, observer.snapshot())
        }
        for (observer, snapshot) in snapshots { observer.deliver(snapshot) }
    }

    /// 不延长观察者生命周期的引用包装。
    private final class WeakObserver {
        /// 可能已释放的观察者视图。
        weak var value: GeometryObserverView?
        /// 记录观察者的弱引用。
        init(_ value: GeometryObserverView) { self.value = value }
    }
}

/// 通过弱引用转发显示链接回调，避免显示链接与监测器循环持有。
@MainActor
private final class GeometryDisplayLinkTarget: NSObject {
    /// 负责当前窗口采样的弱引用监测器。
    weak var monitor: GeometryWindowMonitor?
    /// 保存监测器的弱引用。
    init(_ monitor: GeometryWindowMonitor) { self.monitor = monitor }
    /// 逐帧刷新窗口快照；监测器已释放时使显示链接失效。
    @objc func tick(_ link: CADisplayLink) {
        guard let monitor else { link.invalidate(); return }
        monitor.refresh()
    }
}
