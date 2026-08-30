//
//  LiveRoomGiftSheetView+Rendering.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

extension LiveRoomGiftSheetView {

    func updateBalanceLabel() {
        balanceLabel.text = DemoLocalization.text(
            showsInsufficientBalancePrompt
                ? "liveRoom.gift.balance.insufficient"
                : "liveRoom.gift.balance",
            giftBalance
        )
        balanceLabel.textColor = showsInsufficientBalancePrompt
            ? .systemPink
            : UIColor.white.withAlphaComponent(0.72)
        setNeedsQuickLayout()
    }

    func updateRecipientStatusLabel() {
        if showsRecipientRequiredPrompt {
            recipientTitleLabel.text = DemoLocalization.text(
                "liveRoom.gift.recipient.required"
            )
            recipientTitleLabel.textColor = .systemPink
        } else {
            recipientTitleLabel.text = DemoLocalization.text(
                "liveRoom.gift.recipient.count",
                selectedRecipientUserIDs.count
            )
            recipientTitleLabel.textColor = UIColor.white.withAlphaComponent(
                0.72
            )
        }
        if selectedRecipientUserIDs.isEmpty {
            sendButton.accessibilityHint = DemoLocalization.text(
                "liveRoom.gift.recipient.required"
            )
        } else if let selectedGift = gifts.first(where: {
            $0.id == selectedGiftID
        }) {
            let (totalCost, overflow) = selectedGift.totalCost(
                quantity: selectedGiftQuantity,
                recipientCount: selectedRecipientUserIDs.count
            )
            sendButton.accessibilityHint = overflow || totalCost > giftBalance
                ? DemoLocalization.text(
                    "liveRoom.gift.balance.insufficient",
                    giftBalance
                )
                : nil
        } else {
            sendButton.accessibilityHint = nil
        }
    }

    func updateButtons(reloadsGifts: Bool = false) {
        for (button, recipient) in zip(recipientButtons, recipients) {
            let isSelected = recipient.userID.map(
                selectedRecipientUserIDs.contains
            ) == true
            button.configure(
                recipient: recipient,
                isSelected: isSelected,
                usesCompactMetrics: usesCompactMetrics
            )
            button.accessibilityLabel = DemoLocalization.text(recipient.nameKey)
            button.accessibilityValue = isSelected
                ? DemoLocalization.text("liveRoom.gift.selected")
                : nil
        }

        for (button, category) in zip(
            categoryButtons,
            LiveRoomGiftCategory.allCases
        ) {
            let isSelected = category == selectedCategory
            button.configure(
                title: DemoLocalization.text(category.titleKey),
                font: .systemFont(
                    ofSize: usesCompactMetrics ? 11 : 13,
                    weight: isSelected ? .bold : .semibold
                ),
                foregroundColor: isSelected
                    ? .white
                    : UIColor.white.withAlphaComponent(0.50),
                backgroundColor: isSelected
                    ? UIColor.white.withAlphaComponent(0.14)
                    : .clear,
                borderColor: isSelected
                    ? UIColor.systemYellow.withAlphaComponent(0.85)
                    : .clear,
                borderWidth: isSelected ? 1 : 0,
                contentInsets: EdgeInsets(
                    top: 5,
                    leading: usesCompactMetrics ? 5 : 9,
                    bottom: 5,
                    trailing: usesCompactMetrics ? 5 : 9
                )
            )
            button.accessibilityValue = isSelected
                ? DemoLocalization.text("liveRoom.gift.selected")
                : nil
        }

        if reloadsGifts {
            giftCollectionView.reloadData()
        }

        updateQuantityButton()

        if let selectedGift = gifts.first(where: {
            $0.id == selectedGiftID
        }) {
            sendButton.configure(
                title: DemoLocalization.text("liveRoom.gift.send.action"),
                font: .systemFont(ofSize: 16, weight: .semibold),
                foregroundColor: UIColor(
                    red: 0.12,
                    green: 0.10,
                    blue: 0.04,
                    alpha: 1
                ),
                backgroundColor: .systemYellow,
                contentInsets: EdgeInsets(
                    top: 8,
                    leading: 24,
                    bottom: 8,
                    trailing: 24
                )
            )
            let (giftValue, giftValueOverflow) = selectedGift.price
                .multipliedReportingOverflow(by: selectedGiftQuantity)
            giftSummaryLabel.text = DemoLocalization.text(
                "liveRoom.gift.summary",
                DemoLocalization.text(selectedGift.titleKey),
                giftValueOverflow ? Int.max : giftValue
            )
        }
        updateBalanceLabel()
        updateRecipientStatusLabel()
        let selectsAllRecipients = !recipients.isEmpty
            && selectedRecipientUserIDs.count == recipients.count
        selectAllButton.configure(
            isSelected: selectsAllRecipients,
            usesCompactMetrics: usesCompactMetrics
        )
        selectAllButton.accessibilityLabel = DemoLocalization.text(
            selectsAllRecipients
                ? "liveRoom.gift.selectAll.cancel"
                : "liveRoom.gift.selectAll"
        )
    }

    func updateQuantityButton() {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "×\(selectedGiftQuantity)"
        configuration.image = UIImage(
            systemName: "chevron.up.chevron.down"
        )
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 5
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(
            0.10
        )
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: usesCompactMetrics ? 9 : 12,
            bottom: 8,
            trailing: usesCompactMetrics ? 9 : 12
        )
        configuration.background.strokeColor = UIColor.white
            .withAlphaComponent(0.18)
        configuration.background.strokeWidth = 1
        quantityButton.configuration = configuration

        let selectedOption = giftQuantityOptions.first {
            $0.value == selectedGiftQuantity
        }
        quantityButton.accessibilityLabel = DemoLocalization.text(
            "liveRoom.gift.quantity.accessibility",
            selectedGiftQuantity,
            selectedOption.map {
                DemoLocalization.text($0.titleKey)
            } ?? ""
        )
        quantityButton.menu = UIMenu(
            title: DemoLocalization.text("liveRoom.gift.quantity.title"),
            children: giftQuantityOptions.map { option in
                let action = UIAction(
                    title: "\(option.value)  \(DemoLocalization.text(option.titleKey))"
                ) { [weak self] _ in
                    self?.selectGiftQuantity(option.value)
                }
                action.state = option.value == selectedGiftQuantity ? .on : .off
                return action
            }
        )
    }

    func updateGiftGridMetrics() {
        guard
            let layout = giftCollectionView.collectionViewLayout
                as? UICollectionViewFlowLayout,
            giftCollectionView.bounds.width > 0
        else { return }

        let spacing: CGFloat = usesCompactMetrics ? 6 : 10
        let minimumItemWidth: CGFloat = usesCompactMetrics ? 62 : 72
        let availableWidth = giftCollectionView.bounds.width
        // 根据礼物容器的真实宽度求列数，不依赖具体设备型号或屏幕方向。
        let resolvedColumnCount = min(
            6,
            max(
                3,
                Int((availableWidth + spacing) / (minimumItemWidth + spacing))
            )
        )
        let itemWidth = floor(
            (availableWidth - CGFloat(resolvedColumnCount - 1) * spacing)
                / CGFloat(resolvedColumnCount)
        )
        let itemHeight: CGFloat = usesCompactMetrics ? 72 : 82
        let resolvedItemSize = CGSize(width: itemWidth, height: itemHeight)
        guard
            giftColumnCount != resolvedColumnCount
                || layout.itemSize != resolvedItemSize
                || layout.minimumInteritemSpacing != spacing
        else { return }

        giftColumnCount = resolvedColumnCount
        layout.itemSize = resolvedItemSize
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = .zero
        layout.invalidateLayout()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleGifts.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LiveRoomGiftCollectionCell.reuseIdentifier,
            for: indexPath
        )
        guard let giftCell = cell as? LiveRoomGiftCollectionCell else {
            return cell
        }
        let gift = visibleGifts[indexPath.item]
        giftCell.configure(
            gift: gift,
            isSelected: gift.id == selectedGiftID
        ) { [weak self] in
            self?.selectGift(gift)
        }
        return giftCell
    }
}
