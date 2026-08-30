//
//  LiveRoomRechargePackageSectionView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import QuickLayout
import QuickLayoutKit
import UIKit

/// 充值档位区域，负责标题、档位网格及档位点击转发。
final class LiveRoomRechargePackageSectionView: QuickLayoutView {

    private enum Metrics {
        static let minimumPackageWidth: CGFloat = 96
        static let horizontalSpacing: CGFloat = 10
        static let verticalSpacing: CGFloat = 10
        static let packageHeight: CGFloat = 88
        static let accessibilityPackageHeight: CGFloat = 104
    }

    let titleLabel = UILabel()
    private(set) var packageButtons: [LiveRoomRechargePackageButton] = []
    private var resolvedColumnsPerRow = 1

    var packageDidSelect: ((LiveRoomRechargePackage) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureViews()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        resolveColumns(for: size.width)
        return super.sizeThatFits(size)
    }

    override func layoutSubviews() {
        resolveColumns(for: bounds.width)
        super.layoutSubviews()
    }

    override var body: Layout {
        VStack(spacing: 18) {
            titleLabel
                .resizable(axis: .horizontal)
            if !packageButtons.isEmpty {
                packageGrid
            }
        }
    }

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
                            Spacer()
                                .frame(height: Metrics.packageHeight)
                        }
                    }
                }
            }
        }
    }

    func configure(
        title: String,
        packages: [LiveRoomRechargePackage],
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

    private var packageButtonRows: [[LiveRoomRechargePackageButton]] {
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

    private var columnsPerRow: Int {
        resolvedColumnsPerRow
    }

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

    private func updatePackageButtonCount(_ count: Int) {
        if packageButtons.count < count {
            packageButtons.append(contentsOf: (packageButtons.count..<count).map {
                _ in LiveRoomRechargePackageButton(frame: .zero)
            })
        } else if packageButtons.count > count {
            packageButtons[count...].forEach { $0.action = {} }
            packageButtons.removeLast(packageButtons.count - count)
        }
    }

    private func configureViews() {
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        titleLabel.adjustsFontForContentSizeCategory = true
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomRechargePackageSectionPreview() -> UIViewController {
    let packages = LiveRoomRechargePackage.catalog
    let view = LiveRoomRechargePackageSectionView(frame: .zero)
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
            LiveRoomBackdropView().resizable()
            view
                .resizable(axis: .horizontal)
                .fixedSize(axis: .vertical)
                .frame(maxWidth: 620)
                .padding(20)
        }
    }
}

#Preview("充值档位区域") {
    makeLiveRoomRechargePackageSectionPreview()
}
#endif
