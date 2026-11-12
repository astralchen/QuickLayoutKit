#if DEBUG
import AppLocalization
import Combine
import SwiftUI

/// 在与示例目录相同的分栏内测量系统分组列表的滚动范围和指示器。
struct CatalogScrollReference: View {
    let sections: [MainViewModel.State.Section]

    var body: some View {
        List {
            ForEach(sections, id: \.id) { section in
                Section(header: Text(verbatim: section.title)) {
                    ForEach(section.routes, id: \.id) { row in
                        Text(verbatim: row.title).accessibilityIdentifier(row.id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // 方向往返时系统列表的复用行可能保留镜像。仅重建列表，保留分栏和导航宿主。
        .appLocalizationEnvironment(Localization.localizationController, resetContentOnLayoutDirectionChange: true)
    }

    @MainActor static func makeController() -> UIViewController {
        CatalogReferenceController(rootView: current)
    }

    @MainActor fileprivate static var current: Self {
        Self(sections: MainViewModel().state.sections)
    }
}

/// 语言菜单走 Demo 的本地化流程，保留同一个 SwiftUI 宿主。
private final class CatalogReferenceController: UIHostingController<CatalogScrollReference>, UIKitLocalizationApplying {
    private var pendingAnchor: (row: CatalogRowPosition<IndexPath>, leading: CGFloat)?
    private var limitedRow: (requested: CatalogRowPosition<IndexPath>, visible: CatalogRowPosition<IndexPath>)?
    private weak var previousList: UICollectionView?
    private var isRestoring = false
    private var directionObservation: AnyCancellable?

    private func captureReadingPosition() {
        guard let list = contentScrollView(for: .top) as? UICollectionView,
              list.contentOffset.y + list.adjustedContentInset.top > 1,
              let anchor = list.captureLocalizationAnchor(),
              let height = list.layoutAttributesForItem(at: anchor.indexPath)?.size.height else {
            pendingAnchor = nil
            limitedRow = nil
            return
        }
        // 对照目录不进行搜索或排序；语言变化仅替换文案，分组及条目的索引保持稳定。
        let current = CatalogRowPosition(id: anchor.indexPath, offset: anchor.offsetFromViewportTop, height: height)
        let row = limitedRow.flatMap { current.isSameReadingPosition(as: $0.visible) ? $0.requested : nil } ?? current
        pendingAnchor = (row, anchor.offsetFromViewportLeading)
        previousList = list
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !isRestoring, let anchor = pendingAnchor,
              let list = contentScrollView(for: .top) as? UICollectionView, list !== previousList,
              list.window != nil, list.bounds.height > 0 else { return }
        isRestoring = true
        defer { isRestoring = false }
        let row = anchor.row
        guard !list.isDragging && !list.isDecelerating else {
            pendingAnchor = nil
            return
        }
        func restore(_ offset: CGFloat) -> Bool {
            list.restoreLocalizationAnchor(.init(indexPath: row.id, offsetFromViewportTop: offset,
                                                 offsetFromViewportLeading: anchor.leading))
        }
        // 首次滚动让目标行进入自适应测量范围，再按译文的实际行高恢复。
        guard restore(row.offset), let height = list.layoutAttributesForItem(at: row.id)?.size.height else { return }
        let offset = row.offset(for: height)
        guard offset == row.offset || restore(offset) else { return }
        // 初始布局属性可能仍是估算值。读回实际首行，直到自适应布局稳定后再消费锚点。
        let actual = list.captureLocalizationAnchor()
        let atBoundary = list.contentOffset.y <= -list.adjustedContentInset.top + 0.5 ||
            list.contentOffset.y >= list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom - 0.5
        if (actual?.indexPath == row.id && abs((actual?.offsetFromViewportTop ?? .infinity) - offset) <= 1) || atBoundary {
            limitedRow = nil
            if let actual, let height = list.layoutAttributesForItem(at: actual.indexPath)?.size.height {
                let visible = CatalogRowPosition(id: actual.indexPath, offset: actual.offsetFromViewportTop, height: height)
                if !row.isSameReadingPosition(as: visible) { limitedRow = (row, visible) }
            }
            pendingAnchor = nil
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // @Published 在写入新语言前同步发送。等场景分发 UIKit 更新时，SwiftUI 可能已经重建 List。
        directionObservation = Localization.localizationController.$currentLocale
            .map(\.layoutDirection).removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.captureReadingPosition() }
        installLanguageMenu()
        applyLocalization(Localization.currentUIKitUpdate)
    }

    func applyLocalization(_ update: UIKitLocalizationUpdate) {
        title = Localization.text("app.tab.examples")
        reloadLanguageMenu()
        rootView = .current
    }
}
#endif
