//
//  MainMenuContentView.swift
//  Demo
//
//  Created by Codex on 2026/8/21.
//

import UIKit
import QuickLayout
import QuickLayoutKit

struct MainMenuContentConfiguration: UIContentConfiguration, Equatable {
    let title: String
    let accessibilityIdentifier: String
    var isHighlighted = false
    var isSelected = false

    func makeContentView() -> UIView & UIContentView {
        MainMenuContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        guard let state = state as? UICellConfigurationState else {
            return self
        }

        var updated = self
        updated.isHighlighted = state.isHighlighted
        updated.isSelected = state.isSelected
        return updated
    }
}

/// 与 Today 自定义输入 Cell 相同，由 `UIContentConfiguration` 创建和更新；
/// 内容测量与 reusable 生命周期方向恢复则交给 QuickLayoutKit。
final class MainMenuContentView: QuickLayoutContentView {

    let titleLabel = UILabel()
    let disclosureImageView = UIImageView(
        image: UIImage(systemName: "chevron.forward")
    )

    override var body: Layout {
        HStack(alignment: .center, spacing: 12) {
            titleLabel
            Spacer()
            disclosureImageView
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 8, height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
    }

    init(configuration: MainMenuContentConfiguration) {
        super.init(configuration: configuration)

        layer.cornerRadius = 10
        clipsToBounds = true
        isAccessibilityElement = false

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .natural

        disclosureImageView.contentMode = .scaleAspectFit
        disclosureImageView.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(textStyle: .body)

        applyCurrentContentConfiguration()
    }

    override func applyContentConfiguration(
        _ configuration: UIContentConfiguration
    ) {
        guard let configuration =
            configuration as? MainMenuContentConfiguration else {
            assertionFailure(
                "Unexpected content configuration: \(type(of: configuration))"
            )
            return
        }
        apply(configuration)
        super.applyContentConfiguration(configuration)
    }

    private func apply(_ configuration: MainMenuContentConfiguration) {
        titleLabel.text = configuration.title
        titleLabel.accessibilityIdentifier =
            configuration.accessibilityIdentifier

        let accentColor = UIColor.systemBlue
        titleLabel.textColor = accentColor
        disclosureImageView.tintColor = accentColor

        if configuration.isSelected {
            backgroundColor = accentColor.withAlphaComponent(0.22)
        } else if configuration.isHighlighted {
            backgroundColor = accentColor.withAlphaComponent(0.16)
        } else {
            backgroundColor = accentColor.withAlphaComponent(0.10)
        }
    }
}

final class MainMenuSectionHeaderView: QuickLayoutCollectionReusableView {

    let titleLabel = UILabel()

    override var quickLayoutDirectionViews: [UIView] {
        [self, titleLabel]
    }

    override var body: Layout {
        titleLabel
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .natural
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, identifier: String) {
        titleLabel.text = title
        titleLabel.accessibilityIdentifier = identifier
        setNeedsQuickLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        titleLabel.accessibilityIdentifier = nil
        setNeedsQuickLayout()
    }
}
