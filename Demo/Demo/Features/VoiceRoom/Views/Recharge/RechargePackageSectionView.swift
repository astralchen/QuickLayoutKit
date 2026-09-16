//
//  RechargePackageSectionView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值档位区域，负责标题、档位网格及档位点击转发。
final class RechargePackageSectionView: QuickLayoutView {

    /// 充值档位网格共用的尺寸与间距常量。
    private enum Metrics {
        /// 单个充值档位允许的最小宽度，单位为点。
        static let minimumPackageWidth: CGFloat = 96
        /// 相邻列之间的水平间距，单位为点。
        static let horizontalSpacing: CGFloat = 10
        /// 相邻行之间的垂直间距，单位为点。
        static let verticalSpacing: CGFloat = 10
        /// 常规内容尺寸下的充值档位高度，单位为点。
        static let packageHeight: CGFloat = 88
        /// 辅助功能大字体下的充值档位高度，单位为点。
        static let accessibilityPackageHeight: CGFloat = 104
    }

    /// 显示组件主标题的标签。
    let titleLabel = UILabel()
    /// 按档位顺序排列的充值选择按钮。
    private(set) var packageButtons: [RechargePackageButton] = []
    /// 最近一次按容器宽度解析出的网格列数。
    private var resolvedColumnsPerRow = 1

    /// 用户选择充值档位时调用的回调；参数为所选档位。
    var packageDidSelect: ((RechargePackage) -> Void)?

    /// 使用指定初始矩形创建视图并配置初始外观。
    ///
    /// - Parameter frame: 视图在父视图坐标系中的初始矩形，单位为点。
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    /// 从给定解码器初始化视图。
    ///
    /// - Parameter coder: 包含视图归档数据的解码器。
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    /// 先按建议宽度解析网格列数，再返回档位区域的合适尺寸。
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        resolveColumns(for: size.width)
        return super.sizeThatFits(size)
    }

    /// 在实际宽度变化后重新解析充值网格列数。
    override func layoutSubviews() {
        resolveColumns(for: bounds.width)
        super.layoutSubviews()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
    override var body: Layout {
        VStack(spacing: 18) {
            titleLabel
                .resizable(axis: .horizontal)
            if !packageButtons.isEmpty {
                packageGrid
            }
        }
    }

    /// 按当前列数和内容尺寸类别生成的充值档位网格布局。
    @LayoutBuilder
    private var packageGrid: Layout {
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            VStack(spacing: Metrics.verticalSpacing) {
                ForEach(packageButtons) { button in
                    button
                        .resizable()
                        .frame(height: Metrics.accessibilityPackageHeight)
                }
            }
        } else {
            Grid(
                alignment: .topLeading,
                horizontalSpacing: Metrics.horizontalSpacing,
                verticalSpacing: Metrics.verticalSpacing
            ) {
                for row in packageButtonRows {
                    GridRow(alignment: .top) {
                        ForEach(row) { button in
                            button
                                .resizable()
                                .frame(height: Metrics.packageHeight)
                        }
                        for _ in row.count..<columnsPerRow {
                            // Grid 中的空位与按钮使用相同的横向弹性和优先级，保留完整列宽。
                            Spacer()
                                .frame(maxWidth: .infinity)
                                .layoutPriority(0)
                                .frame(height: Metrics.packageHeight)
                        }
                    }
                }
            }
        }
    }

    /// 更新区域标题、档位按钮内容和当前选择。
    func configure(
        title: String,
        packages: [RechargePackage],
        selectedAmount: Int
    ) {
        titleLabel.text = title
        updatePackageButtonCount(packages.count)
        for (button, package) in zip(packageButtons, packages) {
            button.accessibilityIdentifier =
                "liveRoom.recharge.package.\(package.amount)"
            button.configure(
                package: package,
                isSelected: package.amount == selectedAmount
            )
            button.action = { [weak self] in
                self?.packageDidSelect?(package)
            }
        }
        setNeedsQuickLayout()
    }

    /// 按当前列数分组的充值档位按钮行。
    private var packageButtonRows: [[RechargePackageButton]] {
        stride(
            from: packageButtons.startIndex,
            to: packageButtons.endIndex,
            by: columnsPerRow
        ).map { startIndex in
            let endIndex = min(
                startIndex + columnsPerRow,
                packageButtons.endIndex
            )
            return Array(packageButtons[startIndex..<endIndex])
        }
    }

    /// 当前网格实际采用的列数。
    private var columnsPerRow: Int {
        resolvedColumnsPerRow
    }

    /// 根据容器宽度、最小档位宽度和字体环境更新网格列数。
    private func resolveColumns(for containerWidth: CGFloat) {
        guard containerWidth.isFinite, containerWidth > 0 else {
            resolvedColumnsPerRow = 1
            return
        }
        let widthIncludingTrailingSpacing =
            containerWidth + Metrics.horizontalSpacing
        let packageWidthIncludingSpacing =
            Metrics.minimumPackageWidth + Metrics.horizontalSpacing
        resolvedColumnsPerRow = max(
            1,
            Int(
                floor(
                    widthIncludingTrailingSpacing
                        / packageWidthIncludingSpacing
                )
            )
        )
    }

    /// 使可复用的档位按钮数量与当前目录条目数一致。
    private func updatePackageButtonCount(_ count: Int) {
        if packageButtons.count < count {
            packageButtons.append(contentsOf: (packageButtons.count..<count).map {
                _ in RechargePackageButton(frame: .zero)
            })
        } else if packageButtons.count > count {
            packageButtons[count...].forEach { $0.action = {} }
            packageButtons.removeLast(packageButtons.count - count)
        }
    }

    /// 配置子视图的样式、交互和辅助功能属性。
    private func configureViews() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true
    }
}

#if DEBUG
/// 创建展示充值档位网格的预览控制器。
@MainActor
private func makeRechargePackageSectionPreview() -> UIViewController {
    let packages = RechargePackage.catalog
    let view = RechargePackageSectionView(frame: .zero)
    view.configure(
        title: "选择充值档位",
        packages: packages,
        selectedAmount: 12_800
    )
    view.packageDidSelect = { [weak view] package in
        view?.configure(
            title: "选择充值档位",
            packages: packages,
            selectedAmount: package.amount
        )
    }
    return QuickLayoutHostingController {
        ZStack {
            StarfieldBackgroundView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .frame(maxWidth: 620)
                .padding(20)
        }
    }
}

@available(iOS 17.0, *)
#Preview("充值档位区域") {
    makeRechargePackageSectionPreview()
}
#endif
