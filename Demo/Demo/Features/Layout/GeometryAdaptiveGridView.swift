import QuickLayoutKit
import UIKit

/// Demo 的列数策略：以 Reader 的实际可用宽度计算，不依赖屏幕或设备类型。
struct GeometryAdaptiveGridMetrics: Equatable, Sendable {
    static let itemCount = 6
    static let spacing: CGFloat = 12
    static let minimumCellWidth: CGFloat = 104
    let columns: Int
    let rows: Int
    let cellSize: CGSize

    init(size: CGSize) {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let capacity = floor((width + Self.spacing) / (Self.minimumCellWidth + Self.spacing))
        columns = Int(min(4, max(1, capacity)))
        rows = (Self.itemCount + columns - 1) / columns
        cellSize = CGSize(
            width: max(0, (width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns)),
            height: max(0, (height - CGFloat(rows - 1) * Self.spacing) / CGFloat(rows))
        )
    }
}

/// 使用稳定卡片身份，宽度变化只重排 Grid；Reader 内容直接挂在此宿主上。
final class GeometryAdaptiveGridView: QuickLayoutView {
    private let cards: [UILabel] = (0..<GeometryAdaptiveGridMetrics.itemCount).map { index in
        let label = UILabel()
        label.text = String(format: "%02d", index + 1)
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.textAlignment = .center
        let colors: [UIColor] = [.systemIndigo, .systemTeal, .systemOrange, .systemPink, .systemBlue, .systemPurple]
        label.backgroundColor = colors[index].withAlphaComponent(0.16)
        label.textColor = .label
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
        label.accessibilityIdentifier = "geometry.grid.card.\(index)"
        return label
    }
    var contentInset: CGFloat = 16
    private(set) var metrics: GeometryAdaptiveGridMetrics?
    var didChange: ((GeometryAdaptiveGridMetrics) -> Void)?

    override var body: Layout {
        GeometryReader { [cards] proxy in
            let metrics = GeometryAdaptiveGridMetrics(size: proxy.size)
            Grid(horizontalSpacing: GeometryAdaptiveGridMetrics.spacing,
                 verticalSpacing: GeometryAdaptiveGridMetrics.spacing) {
                for row in 0..<metrics.rows {
                    GridRow {
                        for column in 0..<metrics.columns {
                            let index = row * metrics.columns + column
                            if index < cards.count {
                                cards[index].resizable()
                                    .frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                            } else {
                                // 补齐末行的空列，避免末行卡片扩展到整行宽度。
                                Spacer().frame(width: metrics.cellSize.width, height: metrics.cellSize.height)
                            }
                        }
                    }
                }
            }
        }
        .onGeometryChange(for: GeometryAdaptiveGridMetrics.self, of: { .init(size: $0.size) }) { [weak self] metrics in
            self?.metrics = metrics
            self?.didChange?(metrics)
        }
        .padding(contentInset)
    }
}
