//
//  GiftSheetView.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import AppLocalization
import QuickLayout
import QuickLayoutKit
import UIKit

/// 呈现收礼人、礼物目录和发送选项的面板内容视图。
final class GiftSheetView:
    QuickLayoutView,
    UICollectionViewDataSource {

    /// 收礼选择变化后的回调；参数为当前已选麦位绑定列表。
    var recipientDidSelect: (([SeatAssignment]) -> Void)?
    /// 礼物选择变化后的回调；参数为新选中的礼物。
    var giftDidSelect: ((Gift) -> Void)?
    /// 提交已选礼物的同步业务回调；返回确认余额，失败时返回 `nil`。
    var sendDidTap: ((GiftSendRequest) -> Int?)?
    /// 余额不足时的回调；参数依次为所需余额和当前余额。
    var insufficientBalanceDidOccur: ((Int, Int) -> Void)?

    /// 提供当前页面业务状态并处理用户操作的视图模型。
    let viewModel: GiftSheetViewModel
    /// 面板内容后方的渐变背景。
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
    /// 显示收礼选择摘要或提示的标签。
    let recipientTitleLabel = UILabel()
    /// 显示当前礼物目录摘要的标签。
    let giftSummaryLabel = UILabel()
    /// 与当前收礼列表对应的选择按钮。
    var recipientButtons: [GiftRecipientButton]
    /// 横向排列收礼人按钮的滚动容器。
    let recipientCarouselScrollView = QuickLayoutScrollView(
        .horizontal,
        showsIndicators: false
    )
    /// 覆盖收礼列表边缘以提示横向滚动的渐隐视图。
    let recipientFadeView = GiftRecipientFadeView(frame: .zero)
    /// 切换当前全部收礼人选择状态的按钮。
    let selectAllButton = GiftSelectAllButton(frame: .zero)
    /// 按栏目枚举顺序创建的礼物栏目按钮。
    let categoryButtons = GiftCategory.allCases.map { _ in
        CapsuleTextButton(frame: .zero)
    }
    /// 横向排列礼物栏目按钮的滚动容器。
    let categoryCarouselScrollView = QuickLayoutScrollView(
        .horizontal,
        showsIndicators: false
    )
    /// 显示当前栏目礼物网格的集合视图。
    let giftCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: layout
        )
        return collectionView
    }()
    /// 显示当前金币余额或余额不足提示的标签。
    let balanceLabel = UILabel()
    /// 展示当前数量并弹出预设数量菜单的按钮。
    let quantityButton = UIButton(type: .system)
    /// 提交当前选择或输入内容的按钮。
    let sendButton = CapsuleTextButton(frame: .zero)
    /// 等待布局完成后滚动居中的栏目；没有请求时为 `nil`。
    var categoryPendingCentering: GiftCategory? = .all
    /// 一个布尔值，指示组件是否使用紧凑尺寸参数。
    var usesCompactMetrics = false

    /// 当前可用的收礼麦位数据。
    var recipients: [SeatAssignment] { viewModel.recipients }
    /// 按目录顺序排列的可选礼物。
    var gifts: [Gift] { viewModel.gifts }
    /// 视图模型提供的可选赠送数量。
    var giftQuantityOptions: [GiftQuantityOption] {
        viewModel.quantityOptions
    }
    /// 已选择收礼人的稳定用户标识集合。
    var selectedRecipientUserIDs: Set<RoomUserID> {
        viewModel.selectedRecipientUserIDs
    }
    /// 兼容调试接口的零基麦位位置集合，不表示用户标识。
    var selectedRecipientIDs: Set<Int> {
        viewModel.selectedRecipientPositions
    }
    /// 当前选中礼物的稳定标识；未选择时为 `nil`。
    var selectedGiftID: String? { viewModel.selectedGiftID }
    /// 每名收礼人的赠送份数；初始值为 `1`。
    var selectedGiftQuantity: Int { viewModel.selectedGiftQuantity }
    /// 业务层确认后供礼物面板使用的金币余额。
    var giftBalance: Int { viewModel.giftBalance }
    /// 当前选中的礼物栏目；初始值为全部礼物。
    var selectedCategory: GiftCategory { viewModel.selectedCategory }
    /// 一个布尔值，指示是否显示选择收礼人的提示；初始值为 `false`。
    var showsRecipientRequiredPrompt: Bool {
        viewModel.showsRecipientRequiredPrompt
    }
    /// 一个布尔值，指示是否显示余额不足提示；初始值为 `false`。
    var showsInsufficientBalancePrompt: Bool {
        viewModel.showsInsufficientBalancePrompt
    }

    /// 礼物网格使用的滚动视图。
    var giftScrollView: UIScrollView { giftCollectionView }
    /// 收礼人列表使用的水平滚动视图。
    var recipientScrollView: UIScrollView { recipientCarouselScrollView }
    /// 供宿主访问的礼物栏目滚动视图。
    var categoryScrollView: UIScrollView { categoryCarouselScrollView }
    /// 当前礼物网格每行的列数。
    var giftColumnCount = 4
    /// 当前栏目筛选后的礼物数量。
    var visibleGiftCount: Int { visibleGifts.count }
    /// 当前选中栏目的稳定标识。
    var selectedGiftCategoryID: String { selectedCategory.id }
    /// 可选赠送数量的整数列表。
    var giftQuantityValues: [Int] { giftQuantityOptions.map(\.value) }
    /// 当前显示的收礼人状态或选择提示文案。
    var recipientStatusText: String? { recipientTitleLabel.text }
    /// 当前显示的余额状态或余额不足提示文案。
    var balanceStatusText: String? { balanceLabel.text }

    /// 当前栏目筛选后可见的礼物列表。
    var visibleGifts: [Gift] {
        viewModel.visibleGifts
    }

    /// 使用收礼列表、礼物目录、初始选择与余额创建礼物面板内容。
    init(
        recipients: [SeatAssignment],
        gifts: [Gift],
        initiallySelectedRecipientUserIDs: Set<RoomUserID>,
        initialBalance: Int
    ) {
        viewModel = GiftSheetViewModel(
            recipients: recipients,
            gifts: gifts,
            initiallySelectedRecipientUserIDs:
                initiallySelectedRecipientUserIDs,
            initialBalance: initialBalance
        )
        recipientButtons = recipients.map { _ in
            GiftRecipientButton(frame: .zero)
        }
        super.init(frame: .zero)
        configureViews()
    }

    /// 使用收礼列表、礼物目录、初始选择与余额创建礼物面板内容。
    convenience init(
        recipients: [SeatAssignment],
        gifts: [Gift],
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

    /// 不支持从归档创建此组件，始终返回 `nil`。
    required init?(coder: NSCoder) {
        return nil
    }

    /// 在布局完成后更新网格尺寸并处理待居中的礼物栏目。
    override func layoutSubviews() {
        let shouldUseCompactMetrics = bounds.width > 0 && bounds.width < 350
        if usesCompactMetrics != shouldUseCompactMetrics {
            usesCompactMetrics = shouldUseCompactMetrics
            updateButtons()
            setNeedsQuickLayout()
        }
        super.layoutSubviews()
        updateGiftGridMetrics()
        // 分类内容的方向和尺寸先完成布局，再用新的内容坐标计算居中位置。
        categoryCarouselScrollView.layoutIfNeeded()
        centerPendingGiftCategoryIfNeeded()
    }

    /// 描述此组件当前内容和布局关系的 QuickLayout 布局。
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
                recipientFadeView
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

    /// 根据当前语言刷新显示文案和辅助功能描述。
    func reloadLocalizedContent() {
        recipientTitleLabel.text = Localization.text(
            "liveRoom.gift.recipient.title"
        )
        updateButtons(reloadsGifts: true)
        categoryPendingCentering = selectedCategory
        setNeedsQuickLayout()
    }

    /// 配置子视图的样式、交互和辅助功能属性。
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
            GiftCategory.allCases
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
            GiftCollectionCell.self,
            forCellWithReuseIdentifier: GiftCollectionCell.reuseIdentifier
        )
        giftCollectionView.accessibilityIdentifier = "liveRoom.gift.grid"

        sendButton.accessibilityIdentifier = "liveRoom.gift.send"
        sendButton.action = { [weak self] in self?.sendSelectedGift() }
        reloadLocalizedContent()
    }

    /// 同步最新收礼人列表，重建对应按钮并保留仍有效的用户选择。
    func updateRecipients(_ recipients: [SeatAssignment]) {
        viewModel.updateRecipients(recipients)
        recipientButtons = recipients.map { _ in
            GiftRecipientButton(frame: .zero)
        }
        configureRecipientButtons()
        updateButtons()
        setNeedsQuickLayout()
    }

    /// 为收礼人按钮绑定点击行为，并设置列表所需的视图属性。
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
/// 创建展示礼物面板内容的预览控制器。
@MainActor
private func makeGiftSheetViewPreview() -> UIViewController {
    var balance = 88_888
    let view = GiftSheetView(
        recipients: VoiceRoomPreviewData.occupiedSeats,
        gifts: Gift.catalog,
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

@available(iOS 17.0, *)
#Preview("送礼面板内容") {
    makeGiftSheetViewPreview()
}
#endif
