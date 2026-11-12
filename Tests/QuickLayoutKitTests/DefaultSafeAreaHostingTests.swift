import QuickLayout
import Testing
import UIKit
@testable import QuickLayoutKitUIKit
@testable import QuickLayoutKitCore

@MainActor
@Suite(.serialized)
struct DefaultSafeAreaHostingTests {
    /// 固定高度预览位于外层滚动内容中，不应因为高于视口而再次恢复顶部安全区。
    @Test func nestedFixedViewportDoesNotExpandIntoSiblingContent() {
        let outer = QuickLayoutScrollView()
        let inner = QuickLayoutScrollView()
        let header = UIView()
        let host = InsetTestHost {
            ScrollView(outer) {
                QuickLayoutKitCore.VStack(spacing: 12) {
                    header.frame(height: 160)
                    ScrollView(inner) { UIView().frame(height: 900) }.frame(height: 360)
                }
            }
        }
        host.localInsets = UIEdgeInsets(top: 78, left: 62, bottom: 64, right: 62)
        for size in [CGSize(width: 874, height: 402), CGSize(width: 402, height: 874), CGSize(width: 874, height: 402)] {
            host.frame.size = size
            for _ in 0..<3 { host.setNeedsLayout(); host.layoutIfNeeded(); outer.layoutIfNeeded(); inner.layoutIfNeeded() }
            #expect(abs(inner.frame.height - 360) < 1)
            #expect(inner.frame.minY >= header.frame.maxY + 11)
        }
    }

    /// 父级避让重叠区域后，内层忽略键盘只恢复键盘超出容器安全区的部分。
    @Test func nestedProjectionRetainsContainerConstraintUnderKeyboard() {
        let values = QuickLayoutSafeAreaValues(
            containerSize: CGSize(width: 300, height: 800),
            physicalContainerInsets: UIEdgeInsets(top: 20, left: 0, bottom: 34, right: 0),
            physicalKeyboardInsets: UIEdgeInsets(top: 0, left: 0, bottom: 300, right: 0)
        ).consuming(.all)
        let nested = values.projected(from: CGRect(x: 0, y: 0, width: 300, height: 800),
                                      into: CGRect(x: 0, y: 20, width: 300, height: 480), keyboard: .zero)
        #expect(nested.effectiveInsets.bottom == 0)
        #expect(nested.expansion(ignoring: .keyboard, edges: .bottom).bottom == 266)
        #expect(nested.expansion(ignoring: .container, edges: .bottom).bottom == 0)
    }

    /// 原生滚动容器已经预留的边距不能随项目移入遮挡区而累加到自适应高度。
    @Test func nativeScrollInsetsKeepItemNaturalHeightStable() {
        let scroll = UIScrollView()
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentInset = UIEdgeInsets(top: 30, left: 12, bottom: 80, right: 16)
        let wrapper = UIView()
        let item = LocalSafeAreaItem()
        scroll.addSubview(wrapper)
        wrapper.addSubview(item)
        for bottom in [0.0, 6.333, 34.0, 58.0, 0.0] {
            item.localInsets = UIEdgeInsets(top: 24, left: 10, bottom: bottom, right: 12)
            for _ in 0..<4 {
                #expect(item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity)) == CGSize(width: 100, height: 40))
            }
        }
    }

    /// 旋转后滚动产生的局部遮挡可大于列表 inset，不能将这部分反馈为项目自然尺寸。
    @Test func nativeListOcclusionDoesNotInflateItemMeasurements() {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collection.contentInsetAdjustmentBehavior = .never
        collection.contentInset = UIEdgeInsets(top: 80, left: 20, bottom: 34, right: 20)
        let host = QuickLayoutView { List(collection) }
        host.frame = CGRect(x: 0, y: 0, width: 844, height: 390)
        host.layoutIfNeeded()
        let wrapper = UIView()
        let item = LocalSafeAreaItem()
        collection.addSubview(wrapper)
        wrapper.addSubview(item)
        for insets in [UIEdgeInsets.zero,
                       UIEdgeInsets(top: 250, left: 62, bottom: 180, right: 62),
                       UIEdgeInsets(top: 700, left: 0, bottom: 500, right: 0), .zero] {
            item.localInsets = insets
            let measured = item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
            #expect(measured == CGSize(width: 100, height: 40), "局部遮挡：\(insets)，测量：\(measured)")
        }
    }

    /// 未声明 List 的原生复用内容也不能将滚动主轴的视口遮挡计入自然尺寸。
    @Test func unmanagedNativeReusableContentDoesNotMeasureViewportOcclusion() {
        let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let table = UITableView()
        for list: UIScrollView in [collection, table] {
            list.contentInsetAdjustmentBehavior = .never
            list.contentInset = UIEdgeInsets(top: 80, left: 20, bottom: 34, right: 20)
            let reusable: UIView = list is UITableView ? UITableViewCell() : UICollectionReusableView()
            list.addSubview(reusable)
            let item = LocalSafeAreaItem()
            reusable.addSubview(item)
            for insets in [UIEdgeInsets.zero, UIEdgeInsets(top: 250, left: 0, bottom: 180, right: 0), .zero] {
                item.localInsets = insets
                #expect(item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity)) == CGSize(width: 100, height: 40))
            }
        }
    }

    /// 复用边界只消除主轴遮挡，交叉轴安全区不能消失，也不能重复扣减已有 inset。
    @Test func reusableContentPreservesCrossAxisSafeArea() {
        for direction in [UICollectionView.ScrollDirection.vertical, .horizontal] {
            let flow = UICollectionViewFlowLayout()
            flow.scrollDirection = direction
            let collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
            collection.contentInsetAdjustmentBehavior = .never
            collection.contentInset = UIEdgeInsets(top: 8, left: 20, bottom: 4, right: 20)
            let cell = UICollectionViewCell()
            collection.addSubview(cell)
            let item = LocalSafeAreaItem()
            cell.contentView.addSubview(item)
            for _ in 0..<3 {
                item.localInsets = direction == .vertical
                    ? UIEdgeInsets(top: 250, left: 62, bottom: 180, right: 62)
                    : UIEdgeInsets(top: 20, left: 250, bottom: 10, right: 180)
                let expected = direction == .vertical ? CGSize(width: 184, height: 40) : CGSize(width: 100, height: 58)
                #expect(item.sizeThatFits(CGSize(width: 300, height: 300)) == expected)
            }
        }
    }

    /// 表头里的局部显式安全区仍然有效；列表外部作用域不应污染复用内容。
    @Test func nativeReusableBoundaryPreservesInnerScope() {
        let table = UITableView()
        let header = UITableViewHeaderFooterView()
        table.addSubview(header)
        let item = LocalSafeAreaItem()
        header.contentView.addSubview(item)
        header.contentView.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
        item.frame = header.contentView.bounds
        item.localInsets.top = 250
        let values = QuickLayoutSafeAreaValues(containerSize: item.bounds.size,
            physicalContainerInsets: UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0))
        let measured = QuickLayoutSafeAreaHostContext.$source.withValue(header.contentView) {
            QuickLayoutSafeAreaContext.withValues(values) {
                item.sizeThatFits(CGSize(width: 300, height: 300))
            }
        }
        #expect(measured == CGSize(width: 100, height: 52))
    }

    /// UIKit 可以在另一宿主的布局回调中测量已有视图；无亲缘关系时不继承任务局部区域。
    @Test func unrelatedHostCannotReplaceMountedItemSafeArea() {
        let parent = UIView()
        let item = LocalSafeAreaItem()
        item.localInsets.bottom = 8
        parent.addSubview(item)
        let unrelated = UIView()
        let measured = unrelated.withQuickLayoutContainerSize(
            CGSize(width: 300, height: 500),
            insets: UIEdgeInsets(top: 0, left: 0, bottom: 90, right: 0)
        ) {
            item.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        }
        #expect(measured == CGSize(width: 100, height: 48))
    }

    /// 后代的布局回调不能反向覆盖祖先的安全区来源。
    @Test func descendantCannotReplaceRootSafeArea() {
        let root = LocalSafeAreaItem()
        root.localInsets.top = 20
        let descendant = UIView()
        root.addSubview(descendant)
        let measured = descendant.withQuickLayoutContainerSize(
            CGSize(width: 300, height: 500),
            insets: UIEdgeInsets(top: 0, left: 0, bottom: 90, right: 0)
        ) {
            root.sizeThatFits(CGSize(width: 300, height: CGFloat.infinity))
        }
        #expect(measured == CGSize(width: 100, height: 60))
    }
}

private final class LocalSafeAreaItem: QuickLayoutView {
    var localInsets = UIEdgeInsets.zero
    private let content = UIView()
    override var safeAreaInsets: UIEdgeInsets { localInsets }
    override var body: Layout { content.frame(width: 100, height: 40) }
}

private final class InsetTestHost: QuickLayoutView {
    var localInsets = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { localInsets }
}
