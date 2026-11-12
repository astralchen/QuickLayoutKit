import UIKit

/// 声明原生集合列表，复用现有数据源、布局和复用注册，不创建第二层滚动视图。
/// 默认填满父布局提供的有限空间；视口可延伸到安全区外，内容与指示器通过 inset 避让。
@MainActor public func List(_ collectionView: UICollectionView) -> QuickLayoutScrollElement {
    nativeListElement(collectionView)
}

/// 声明原生表格列表，保留其数据源、分组、选择和复用行为。
/// 支持 safeAreaPadding、safeAreaInset、contentMargins 与按区域忽略安全区。
@MainActor public func List(_ tableView: UITableView) -> QuickLayoutScrollElement {
    nativeListElement(tableView)
}

@MainActor private func nativeListElement(_ scrollView: UIScrollView) -> QuickLayoutScrollElement {
    scrollView.quickLayoutScrollMarginState.reset(on: scrollView)
    return QuickLayoutScrollElement(scrollView).resizable()
}
