//
//  LiveRoomGiftSheetView.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

final class LiveRoomGiftSheetView:
    QuickLayoutView,
    UICollectionViewDataSource {

    var recipientDidSelect: (([LiveRoomSeat]) -> Void)?
    var giftDidSelect: ((LiveRoomGift) -> Void)?
    var sendDidTap: ((LiveRoomGiftSendRequest) -> Int?)?
    var insufficientBalanceDidOccur: ((Int, Int) -> Void)?

    let viewModel: LiveRoomGiftSheetViewModel
    let backgroundGradientView = QuickLayoutLinearGradientView(
        stops: [
            QuickLayoutGradient.Stop(
                color: UIColor.systemPurple.withAlphaComponent(0.30),
                location: 0
            ),
            QuickLayoutGradient.Stop(
                color: UIColor.systemIndigo.withAlphaComponent(0.12),
                location: 0.42
            ),
            QuickLayoutGradient.Stop(color: .clear, location: 1),
        ],
        startPoint: UnitPoint(x: 0.08, y: 0),
        endPoint: UnitPoint(x: 0.90, y: 0.72)
    )
    let recipientTitleLabel = UILabel()
    let giftSummaryLabel = UILabel()
    var recipientButtons: [LiveRoomGiftRecipientButton]
    let recipientCarouselScrollView = QuickLayoutScrollView(
        .horizontal,
        showsIndicators: false
    )
    let recipientFogView = LiveRoomGiftRecipientFogView(frame: .zero)
    let selectAllButton = LiveRoomGiftSelectAllButton(frame: .zero)
    let categoryButtons = LiveRoomGiftCategory.allCases.map { _ in
        LiveRoomCapsuleTextButton(frame: .zero)
    }
    let categoryCarouselScrollView = QuickLayoutScrollView(
        .horizontal,
        showsIndicators: false
    )
    let giftCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        return collectionView
    }()
    let balanceLabel = UILabel()
    let quantityButton = UIButton(type: .system)
    let sendButton = LiveRoomCapsuleTextButton(frame: .zero)
    var categoryPendingCentering: LiveRoomGiftCategory? = .all
    var usesCompactMetrics = false

    var recipients: [LiveRoomSeat] { viewModel.recipients }
    var gifts: [LiveRoomGift] { viewModel.gifts }
    var giftQuantityOptions: [LiveRoomGiftQuantityOption] {
        viewModel.quantityOptions
    }
    var selectedRecipientUserIDs: Set<LiveRoomUserID> {
        viewModel.selectedRecipientUserIDs
    }
    var selectedRecipientIDs: Set<Int> {
        viewModel.selectedRecipientPositions
    }
    var selectedGiftID: String? { viewModel.selectedGiftID }
    var selectedGiftQuantity: Int { viewModel.selectedGiftQuantity }
    var giftBalance: Int { viewModel.giftBalance }
    var selectedCategory: LiveRoomGiftCategory { viewModel.selectedCategory }
    var showsRecipientRequiredPrompt: Bool {
        viewModel.showsRecipientRequiredPrompt
    }
    var showsInsufficientBalancePrompt: Bool {
        viewModel.showsInsufficientBalancePrompt
    }

    var giftScrollView: UIScrollView { giftCollectionView }
    var recipientScrollView: UIScrollView { recipientCarouselScrollView }
    var categoryScrollView: UIScrollView { categoryCarouselScrollView }
    var giftColumnCount = 4
    var visibleGiftCount: Int { visibleGifts.count }
    var selectedGiftCategoryID: String { selectedCategory.id }
    var giftQuantityValues: [Int] { giftQuantityOptions.map(\.value) }
    var recipientStatusText: String? { recipientTitleLabel.text }
    var balanceStatusText: String? { balanceLabel.text }

    var visibleGifts: [LiveRoomGift] {
        viewModel.visibleGifts
    }

    init(
        recipients: [LiveRoomSeat],
        gifts: [LiveRoomGift],
        initiallySelectedRecipientUserIDs: Set<LiveRoomUserID>,
        initialBalance: Int
    ) {
        viewModel = LiveRoomGiftSheetViewModel(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientUserIDs:
                initiallySelectedRecipientUserIDs,
            initialBalance: initialBalance
        )
        recipientButtons = recipients.map { _ in
            LiveRoomGiftRecipientButton(frame: .zero)
        }
        super.init(frame: .zero)
        configureViews()
    }

    convenience init(
        recipients: [LiveRoomSeat],
        gifts: [LiveRoomGift],
        initiallySelectedRecipientSeatIDs: Set<Int>,
        initialBalance: Int
    ) {
        let userIDs = Set(recipients.compactMap { recipient in
            initiallySelectedRecipientSeatIDs.contains(
                recipient.position.rawValue
            ) ? recipient.userID : nil
        })
        self.init(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientUserIDs: userIDs,
            initialBalance: initialBalance
        )
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layoutSubviews() {
        let shouldUseCompactMetrics = bounds.width > 0 && bounds.width < 350
        if usesCompactMetrics != shouldUseCompactMetrics {
            usesCompactMetrics = shouldUseCompactMetrics
            updateButtons()
            setNeedsQuickLayout()
        }
        super.layoutSubviews()
        updateGiftGridMetrics()
        centerPendingGiftCategoryIfNeeded()
    }

    override var body: Layout {
        VStack(alignment: .leading, spacing: usesCompactMetrics ? 8 : 11) {
            recipientTitleLabel
                .resizable(axis: .horizontal)
            ZStack(alignment: .trailing) {
                ScrollView(
                    recipientCarouselScrollView,
                    .horizontal,
                    showsIndicators: false
                ) {
                    HStack(spacing: usesCompactMetrics ? 4 : 8) {
                        ForEach(recipientButtons) { button in
                            button
                                .resizable()
                                .frame(
                                    width: usesCompactMetrics ? 40 : 48,
                                    height: usesCompactMetrics ? 48 : 56
                                )
                        }
                    }
                }
                .resizable(axis: .horizontal)
                // 尾部预留固定操作区，滚到末尾时最后一位用户仍可完整显示和点击。
                .contentMargins(
                    .trailing,
                    usesCompactMetrics ? 58 : 70,
                    for: .scrollContent
                )

                // 雾化覆盖在滚动内容上，而不是占用独立间距，避免形成矩形黑带。
                recipientFogView
                    .resizable()
                    .frame(
                        width: usesCompactMetrics ? 64 : 80,
                        height: usesCompactMetrics ? 48 : 56
                    )
                selectAllButton
                    .resizable()
                    .frame(
                        width: usesCompactMetrics ? 46 : 54,
                        height: usesCompactMetrics ? 30 : 34
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: usesCompactMetrics ? 48 : 56)

            ScrollView(
                categoryCarouselScrollView,
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: usesCompactMetrics ? 6 : 10) {
                    ForEach(categoryButtons) { button in
                        button
                            .resizable(axis: .vertical)
                            .fixedSize(axis: .horizontal)
                            .frame(
                                minWidth: usesCompactMetrics ? 56 : 64,
                                minHeight: 32
                            )
                    }
                }
            }
            .resizable()
            .frame(height: 32)
            giftSummaryLabel
                .resizable(axis: .horizontal)
            giftCollectionView
                .resizable()
                .frame(height: usesCompactMetrics ? 154 : 176)

            HStack(spacing: usesCompactMetrics ? 6 : 8) {
                balanceLabel
                    .resizable(axis: .horizontal)
                    .frame(minWidth: usesCompactMetrics ? 52 : 64)
                quantityButton
                    .resizable(axis: .vertical)
                    .frame(height: 46)
                sendButton
                    .resizable(axis: .vertical)
                    .frame(height: 46)
            }
        }
        .padding(.horizontal, usesCompactMetrics ? 12 : 18)
        .padding(.top, usesCompactMetrics ? 18 : 24)
        .padding(.bottom, usesCompactMetrics ? 10 : 14)
        .safeAreaPadding(.bottom, 0)
        .background { backgroundGradientView }
    }

    func reloadLocalizedContent() {
        recipientTitleLabel.text = DemoLocalization.text(
            "liveRoom.gift.recipient.title"
        )
        updateButtons(reloadsGifts: true)
        categoryPendingCentering = selectedCategory
        setNeedsQuickLayout()
    }

    func configureViews() {
        quickLayoutSemanticDirectionBehavior = .followEnclosingContainer
        accessibilityIdentifier = "liveRoom.gift.sheet"
        backgroundColor = .clear

        backgroundGradientView.backgroundColor = UIColor(
            red: 0.055,
            green: 0.055,
            blue: 0.10,
            alpha: 0.94
        )
        backgroundGradientView.isUserInteractionEnabled = false
        backgroundGradientView.accessibilityIdentifier =
            "liveRoom.gift.sheet.backgroundGradient"
        backgroundGradientView.layer.cornerRadius = 28
        backgroundGradientView.layer.cornerCurve = .continuous
        backgroundGradientView.layer.maskedCorners = [
            .layerMinXMinYCorner,
            .layerMaxXMinYCorner,
        ]
        backgroundGradientView.layer.borderWidth = 1
        backgroundGradientView.layer.borderColor = UIColor.white
            .withAlphaComponent(0.14)
            .cgColor
        backgroundGradientView.layer.shadowColor = UIColor.black.cgColor
        backgroundGradientView.layer.shadowOpacity = 0.42
        backgroundGradientView.layer.shadowRadius = 24
        backgroundGradientView.layer.shadowOffset = CGSize(width: 0, height: -8)

        recipientTitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        recipientTitleLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        recipientTitleLabel.adjustsFontForContentSizeCategory = true
        recipientTitleLabel.accessibilityIdentifier =
            "liveRoom.gift.recipientStatus"

        recipientCarouselScrollView.backgroundColor = .clear
        recipientCarouselScrollView.alwaysBounceHorizontal = true
        recipientCarouselScrollView.alwaysBounceVertical = false
        recipientCarouselScrollView.showsHorizontalScrollIndicator = false
        recipientCarouselScrollView.showsVerticalScrollIndicator = false
        recipientCarouselScrollView.decelerationRate = .fast
        recipientCarouselScrollView.clipsToBounds = true
        recipientCarouselScrollView.accessibilityIdentifier =
            "liveRoom.gift.recipientScroll"
        recipientCarouselScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        categoryCarouselScrollView.backgroundColor = .clear
        // 内容不足一屏时不制造可滚动手感，保持栏目自然排列。
        categoryCarouselScrollView.alwaysBounceHorizontal = false
        categoryCarouselScrollView.alwaysBounceVertical = false
        categoryCarouselScrollView.showsHorizontalScrollIndicator = false
        categoryCarouselScrollView.showsVerticalScrollIndicator = false
        categoryCarouselScrollView.decelerationRate = .fast
        categoryCarouselScrollView.clipsToBounds = true
        categoryCarouselScrollView.accessibilityIdentifier =
            "liveRoom.gift.categoryScroll"
        categoryCarouselScrollView.quickLayoutSemanticDirectionBehavior =
            .followEnclosingContainer

        giftSummaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        giftSummaryLabel.textColor = .systemYellow
        giftSummaryLabel.adjustsFontSizeToFitWidth = true
        giftSummaryLabel.minimumScaleFactor = 0.75

        balanceLabel.font = .monospacedDigitSystemFont(
            ofSize: 12,
            weight: .medium
        )
        balanceLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        balanceLabel.adjustsFontSizeToFitWidth = true
        balanceLabel.minimumScaleFactor = 0.78

        quantityButton.showsMenuAsPrimaryAction = true
        quantityButton.changesSelectionAsPrimaryAction = false
        quantityButton.accessibilityIdentifier = "liveRoom.gift.quantity"

        selectAllButton.accessibilityIdentifier = "liveRoom.gift.selectAll"
        selectAllButton.action = { [weak self] in
            self?.toggleAllRecipients()
        }

        configureRecipientButtons()

        for (button, category) in zip(
            categoryButtons,
            LiveRoomGiftCategory.allCases
        ) {
            button.accessibilityIdentifier =
                "liveRoom.gift.category.\(category.id)"
            button.action = { [weak self] in
                self?.selectCategory(category)
            }
        }

        giftCollectionView.backgroundColor = .clear
        giftCollectionView.alwaysBounceVertical = true
        giftCollectionView.alwaysBounceHorizontal = false
        giftCollectionView.showsVerticalScrollIndicator = true
        giftCollectionView.showsHorizontalScrollIndicator = false
        giftCollectionView.indicatorStyle = .white
        giftCollectionView.contentInset = UIEdgeInsets(
            top: 1,
            left: 0,
            bottom: 8,
            right: 0
        )
        giftCollectionView.dataSource = self
        giftCollectionView.register(
            LiveRoomGiftCollectionCell.self,
            forCellWithReuseIdentifier: LiveRoomGiftCollectionCell.reuseIdentifier
        )
        giftCollectionView.accessibilityIdentifier = "liveRoom.gift.grid"

        sendButton.accessibilityIdentifier = "liveRoom.gift.send"
        sendButton.action = { [weak self] in self?.sendSelectedGift() }
        reloadLocalizedContent()
    }

    func updateRecipients(_ recipients: [LiveRoomSeat]) {
        viewModel.updateRecipients(recipients)
        recipientButtons = recipients.map { _ in
            LiveRoomGiftRecipientButton(frame: .zero)
        }
        configureRecipientButtons()
        updateButtons()
        setNeedsQuickLayout()
    }

    private func configureRecipientButtons() {
        for (button, recipient) in zip(recipientButtons, recipients) {
            button.accessibilityIdentifier =
                "liveRoom.gift.recipient.\(recipient.position.rawValue)"
            button.action = { [weak self] in
                self?.selectRecipient(recipient)
            }
        }
    }
}

#if DEBUG
@MainActor
private func makeLiveRoomGiftSheetViewPreview() -> UIViewController {
    var balance = 88_888
    let view = LiveRoomGiftSheetView(
        recipients: LiveRoomPreviewData.occupiedSeats,
        gifts: LiveRoomGift.catalog,
        initiallySelectedRecipientSeatIDs: [],
        initialBalance: balance
    )
    view.sendDidTap = { request in
        guard request.totalCost <= balance else { return nil }
        balance -= request.totalCost
        return balance
    }
    let viewController = QuickLayoutHostingController {
        // 组件预览只展示 Sheet 本身；横向跟随容器，纵向保持固有高度并贴底。
        view
            .resizable(axis: .horizontal)
            .fixedSize(axis: .vertical)
            .containerRelativeFrame(.horizontal)
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
    viewController.view.backgroundColor = .clear
    return viewController
}

#Preview("送礼面板内容") {
    makeLiveRoomGiftSheetViewPreview()
}
#endif
