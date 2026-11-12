import ObjectiveC
import QuickLayout
import QuickLayoutKitCore
import UIKit

/// 保存测量阶段的父级作用域；弱引用避免跨宿主重挂载时保留旧视图树。
@MainActor
private final class InheritedSafeArea {
    weak var source: UIView?
    let values: QuickLayoutSafeAreaValues
    let sourceExpansion: UIEdgeInsets
    let sourceInsets: UIEdgeInsets
    let sourceKeyboardInsets: UIEdgeInsets
    init(source: UIView, values: QuickLayoutSafeAreaValues, sourceExpansion: UIEdgeInsets) {
        self.source = source
        self.values = values
        self.sourceExpansion = sourceExpansion
        sourceInsets = source.safeAreaInsets
        sourceKeyboardInsets = (source as? QuickLayoutView)?.quickLayoutKeyboardSafeAreaInsets ?? .zero
    }
}

@MainActor
enum QuickLayoutSafeAreaHostContext {
    @TaskLocal static var source: UIView?
    @TaskLocal static var sourceExpansion = UIEdgeInsets.zero
    nonisolated(unsafe) private static var inheritedKey: UInt8 = 0

    static func capture(_ views: [UIView], from source: UIView, values: QuickLayoutSafeAreaValues) {
        for view in views where view !== source {
            let previous = objc_getAssociatedObject(view, &inheritedKey) as? InheritedSafeArea
            if !(source is UIScrollView),
               previous?.source !== source
                || previous?.sourceInsets != source.safeAreaInsets
                || previous?.sourceKeyboardInsets != ((source as? QuickLayoutView)?.quickLayoutKeyboardSafeAreaInsets ?? .zero)
                || previous?.sourceExpansion != sourceExpansion {
                // 左右区域互换可能不改变宿主尺寸；普通 UIKit 包装的后代也必须重新放置。
                func invalidate(_ descendant: UIView) {
                    descendant.setNeedsLayout()
                    for child in descendant.subviews { invalidate(child) }
                }
                invalidate(view)
            }
            objc_setAssociatedObject(view, &inheritedKey, InheritedSafeArea(source: source, values: values, sourceExpansion: sourceExpansion),
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            if let observer = view as? any QuickLayoutSafeAreaGeometryObserver {
                let expansion = sourceExpansion
                observer.quickLayoutSafeAreaGeometry = { [weak source, weak view] in
                    guard let source, let view, view.isDescendant(of: source) else { return nil }
                    return values.projected(from: expandedBounds(of: source, by: expansion),
                                            into: view.convert(view.bounds, to: source), keyboard: .zero)
                        .physicalSafeBoundaryInsets
                }
            }
        }
    }

    /// 使用真实子视图边界判断局部布局是否接触安全边界，不扩展居中的局部 frame。
    static func touchingEdges(_ views: [UIView], source: UIView, values: QuickLayoutSafeAreaValues) -> EdgeSet {
        let reference = expandedBounds(of: source, by: sourceExpansion)
        let safe = reference.inset(by: values.physicalSafeBoundaryInsets)
        let rectangles = views.filter { $0.isDescendant(of: source) && !$0.bounds.isEmpty }
            .map { $0.convert($0.bounds, to: source) }
        guard let first = rectangles.first else { return [] }
        let rect = rectangles.dropFirst().reduce(first) { $0.union($1) }
        var result: EdgeSet = []
        if rect.minY <= safe.minY + 0.5 { result.insert(.top) }
        if rect.maxY >= safe.maxY - 0.5 { result.insert(.bottom) }
        let rtl = LayoutContext.layoutDirection == .rightToLeft
        if rect.minX <= safe.minX + 0.5 { result.insert(rtl ? .trailing : .leading) }
        if rect.maxX >= safe.maxX - 0.5 { result.insert(rtl ? .leading : .trailing) }
        return result
    }

    private static func expandedBounds(of view: UIView, by insets: UIEdgeInsets) -> CGRect {
        // 滚动内容的边界属于完整内容矩形，不随 contentOffset 移动，也不能截成视口高度。
        let bounds = (view as? UIScrollView).map { CGRect(origin: .zero, size: $0.contentSize) } ?? view.bounds
        return bounds.inset(by: UIEdgeInsets(top: -insets.top, left: -insets.left,
                                            bottom: -insets.bottom, right: -insets.right))
    }

    static func values(for view: UIView, size: CGSize, container: UIEdgeInsets,
                       keyboard: UIEdgeInsets) -> QuickLayoutSafeAreaValues {
        // 原生列表的复用内容是独立坐标边界。外层视口遮挡不能反馈为滚动主轴的
        // 自然尺寸；列表内部的局部 Kit 作用域仍可正常继承。
        var nativeAncestor: UIScrollView?
        var reusableContent = false
        var nativeScrollDirection: UICollectionView.ScrollDirection?
        var parentView: UIView? = view
        while let candidate = parentView {
            reusableContent = reusableContent || candidate is UICollectionReusableView
                || candidate is UITableViewCell || candidate is UITableViewHeaderFooterView
            if candidate !== view, let scroll = candidate as? UIScrollView {
                if scroll.quickLayoutUsesNativeListSafeArea {
                    nativeAncestor = scroll
                } else if reusableContent, let direction = nativeDirection(of: scroll) {
                    nativeAncestor = scroll
                    nativeScrollDirection = direction
                }
                // 内层滚动容器已隔开坐标空间，不能继续借用外层列表的消费记录。
                break
            }
            parentView = candidate.superview
        }
        func sourceBelongsToContent(_ source: UIView) -> Bool {
            nativeAncestor.map { source !== $0 && source.isDescendant(of: $0) } ?? true
        }
        if let source, sourceBelongsToContent(source), source !== view, !source.isDescendant(of: view),
           view.superview == nil || view.isDescendant(of: source),
           let current = QuickLayoutSafeAreaContext.current {
            // 试探测量只读取当前提议，持久继承值由布局包装器在 capture 中记录。
            // body 中也可能主动测量已挂载的深层宿主；它收到的是自己的几何位置，
            // 不能把当前外层尚未消费的顶部区域直接当作自身的自然高度。
            var values = view.isDescendant(of: source) && !(source is UIScrollView)
                ? current.projected(from: expandedBounds(of: source, by: sourceExpansion),
                                    into: view.convert(view.bounds, to: source), keyboard: keyboard)
                : current
            values.containerSize = size
            return values
        }
        // 普通 UIKit 包装也可承载 Kit 后代；沿祖先恢复作用域，避免包装层打断消费记录。
        var ancestor: UIView? = view
        while let candidate = ancestor {
            if let nativeAncestor, candidate === nativeAncestor {
                // List 已统一承担两轴安全区；未经过 List 的原生复用内容只排除滚动主轴
                // 的视口遮挡。交叉轴仍保留局部安全区，再扣除原生列表已经提供的 inset。
                // 单元格内部的显式 Kit 作用域已在到达此边界前处理。
                var contentInsets = UIEdgeInsets.zero
                if let direction = nativeScrollDirection {
                    contentInsets = container
                    if direction == .vertical { contentInsets.top = 0; contentInsets.bottom = 0 }
                    else { contentInsets.left = 0; contentInsets.right = 0 }
                }
                let values = QuickLayoutSafeAreaValues(containerSize: size, physicalContainerInsets: contentInsets,
                                                      physicalKeyboardInsets: keyboard)
                let ignored = nativeAncestor.quickLayoutNativeIgnoredContainerEdges
                var edges: EdgeSet = []
                if ignored.top > 0 { edges.insert(.top) }
                if ignored.bottom > 0 { edges.insert(.bottom) }
                let rtl = LayoutContext.layoutDirection == .rightToLeft
                if ignored.left > 0 { edges.insert(rtl ? .trailing : .leading) }
                if ignored.right > 0 { edges.insert(rtl ? .leading : .trailing) }
                return values.ignoring(.container, edges: edges)
                    .consumingAppliedInsets(nativeAncestor.adjustedContentInset)
            }
            if let inherited = objc_getAssociatedObject(candidate, &inheritedKey) as? InheritedSafeArea,
               let source = inherited.source, sourceBelongsToContent(source), source !== view, view.isDescendant(of: source) {
                return inherited.values.projected(from: expandedBounds(of: source, by: inherited.sourceExpansion),
                                                  into: view.convert(view.bounds, to: source), keyboard: keyboard)
            }
            ancestor = candidate.superview
        }
        objc_setAssociatedObject(view, &inheritedKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let values = QuickLayoutSafeAreaValues(containerSize: size, physicalContainerInsets: container,
                                              physicalKeyboardInsets: keyboard)
        // 原生列表也通过 adjustedContentInset 承担安全区。自适应单元格不能把滚动过程中
        // UIKit 临时报告的局部遮挡继续加进自然高度，否则尾部项目会持续增高。
        var parent = view.superview
        while let candidate = parent {
            if let scroll = candidate as? UIScrollView {
                return values.consumingAppliedInsets(scroll.adjustedContentInset)
            }
            parent = candidate.superview
        }
        return values
    }

    /// 仅对可确定滚动主轴的原生列表建立复用边界，不推测未知自定义布局的方向。
    private static func nativeDirection(of scroll: UIScrollView) -> UICollectionView.ScrollDirection? {
        if scroll is UITableView { return .vertical }
        guard let collection = scroll as? UICollectionView else { return nil }
        switch collection.collectionViewLayout {
        case let layout as UICollectionViewFlowLayout: return layout.scrollDirection
        case let layout as UICollectionViewCompositionalLayout: return layout.configuration.scrollDirection
        case let layout as UICollectionViewWaterfallLayout: return layout.configuration.scrollDirection
        default: return nil
        }
    }
}
