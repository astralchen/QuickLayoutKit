//
//  GiftSheetViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 管理礼物、收礼人和数量选择，并生成待业务层确认的赠送请求。
@MainActor
final class GiftSheetViewModel {

    /// 当前礼物选择对应的发送校验结果。
    enum SendDecision {
        /// 已形成请求，可交由房间业务层再次校验并扣款。
        case ready(GiftSendRequest)
        /// 缺少有效礼物或尚未选择收礼人。
        case recipientRequired
        /// 余额不足或成本计算溢出，并携带所需与当前余额。
        case insufficientBalance(required: Int, current: Int)
    }

    /// 当前可用的收礼麦位数据。
    private(set) var recipients: [SeatAssignment]
    /// 按目录顺序排列的可选礼物。
    let gifts: [Gift]
    /// 允许选择的礼物赠送数量列表。
    let quantityOptions: [GiftQuantityOption]

    /// 已选择收礼人的稳定用户标识集合。
    private(set) var selectedRecipientUserIDs: Set<RoomUserID>
    /// 当前选中礼物的稳定标识；未选择时为 `nil`。
    private(set) var selectedGiftID: String?
    /// 每名收礼人的赠送份数；初始值为 `1`。
    private(set) var selectedGiftQuantity = 1
    /// 业务层确认后供礼物面板使用的金币余额。
    private(set) var giftBalance: Int
    /// 当前选中的礼物栏目；初始值为全部礼物。
    private(set) var selectedCategory: GiftCategory = .all
    /// 一个布尔值，指示是否显示选择收礼人的提示；初始值为 `false`。
    private(set) var showsRecipientRequiredPrompt = false
    /// 一个布尔值，指示是否显示余额不足提示；初始值为 `false`。
    private(set) var showsInsufficientBalancePrompt = false

    /// 创建礼物选择状态，并将初始收礼选择限制在当前可用用户内。
    ///
    /// 初始选中目录中的第一份礼物；负余额按零处理。未提供数量选项时使用 `GiftQuantityOption.presets`。
    init(
        recipients: [SeatAssignment],
        gifts: [Gift],
        initiallySelectedRecipientUserIDs: Set<RoomUserID>,
        initialBalance: Int,
        quantityOptions: [GiftQuantityOption]? = nil
    ) {
        self.recipients = recipients
        self.gifts = gifts
        self.quantityOptions = quantityOptions
            ?? GiftQuantityOption.presets
        let availableUserIDs = Set(recipients.compactMap(\.userID))
        selectedRecipientUserIDs = initiallySelectedRecipientUserIDs
            .intersection(availableUserIDs)
        selectedGiftID = gifts.first?.id
        giftBalance = max(0, initialBalance)
    }

    /// 创建礼物选择状态，并将初始收礼选择限制在当前可用用户内。
    ///
    /// 初始选中目录中的第一份礼物；负余额按零处理。未提供数量选项时使用 `GiftQuantityOption.presets`。
    convenience init(
        recipients: [SeatAssignment],
        gifts: [Gift],
        initiallySelectedRecipientSeatIDs: Set<Int>,
        initialBalance: Int,
        quantityOptions: [GiftQuantityOption]? = nil
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
            initialBalance: initialBalance,
            quantityOptions: quantityOptions
        )
    }

    /// 按收礼人列表顺序解析出的已选麦位绑定。
    var selectedRecipients: [SeatAssignment] {
        recipients.filter { recipient in
            recipient.userID.map(selectedRecipientUserIDs.contains) == true
        }
    }

    /// 现有 Demo 调试接口使用的零基麦位位置集合。
    var selectedRecipientPositions: Set<Int> {
        Set(selectedRecipients.map { $0.position.rawValue })
    }

    /// 兼容调试接口的零基麦位位置集合，不表示用户标识。
    var selectedRecipientIDs: Set<Int> {
        selectedRecipientPositions
    }

    /// 当前栏目筛选后可见的礼物列表。
    var visibleGifts: [Gift] {
        gifts.filter { selectedCategory.includes($0) }
    }

    /// 切换有效收礼人的选择状态，并清除发送提示。
    ///
    /// 用户标识重载直接匹配用户；位置重载先从当前列表解析用户。
    ///
    /// - Returns: 收礼人存在且已完成切换时为 `true`；否则为 `false`。
    @discardableResult
    func toggleRecipient(userID: RoomUserID) -> Bool {
        guard recipients.contains(where: { $0.userID == userID }) else {
            return false
        }
        if selectedRecipientUserIDs.contains(userID) {
            selectedRecipientUserIDs.remove(userID)
        } else {
            selectedRecipientUserIDs.insert(userID)
        }
        clearPrompts()
        return true
    }

    /// 切换有效收礼人的选择状态，并清除发送提示。
    ///
    /// 用户标识重载直接匹配用户；位置重载先从当前列表解析用户。
    ///
    /// - Returns: 收礼人存在且已完成切换时为 `true`；否则为 `false`。
    @discardableResult
    func toggleRecipient(id position: Int) -> Bool {
        guard let userID = recipients.first(where: {
            $0.position.rawValue == position
        })?.userID else { return false }
        return toggleRecipient(userID: userID)
    }

    /// 在全选当前可用用户和清空选择之间切换。
    func toggleAllRecipients() {
        let availableUserIDs = Set(recipients.compactMap(\.userID))
        if selectedRecipientUserIDs == availableUserIDs {
            selectedRecipientUserIDs.removeAll()
        } else {
            selectedRecipientUserIDs = availableUserIDs
        }
        clearPrompts()
    }

    /// 设置收礼人选择，并移除当前列表中不存在的用户标识。
    func setSelectedRecipientUserIDs(_ userIDs: Set<RoomUserID>) {
        let availableUserIDs = Set(recipients.compactMap(\.userID))
        selectedRecipientUserIDs = userIDs.intersection(availableUserIDs)
        clearPrompts()
    }

    /// 使用最新舞台 assignment 更新可赠送用户。
    ///
    /// 选择状态按稳定 `userID` 取交集；礼物、栏目、数量、余额和滚动位置不重置。
    func updateRecipients(_ recipients: [SeatAssignment]) {
        self.recipients = recipients
        let availableUserIDs = Set(recipients.compactMap(\.userID))
        // 选择绑定用户身份；换麦仍保留选择，离开可赠送列表的用户立即移除。
        selectedRecipientUserIDs.formIntersection(availableUserIDs)
        clearPrompts()
    }

    /// 选择目录中不同于当前选项的礼物，并清除余额提示。
    ///
    /// - Returns: 选择发生变化时为 `true`；礼物不存在或已经选中时为 `false`。
    @discardableResult
    func selectGift(id: String) -> Bool {
        guard
            gifts.contains(where: { $0.id == id }),
            selectedGiftID != id
        else { return false }
        selectedGiftID = id
        showsInsufficientBalancePrompt = false
        return true
    }

    /// 选择预设列表中包含的赠送数量，并清除余额提示。
    ///
    /// - Returns: 数量属于预设列表时为 `true`；否则为 `false`。
    @discardableResult
    func selectGiftQuantity(_ quantity: Int) -> Bool {
        guard quantityOptions.contains(where: { $0.value == quantity }) else {
            return false
        }
        selectedGiftQuantity = quantity
        showsInsufficientBalancePrompt = false
        return true
    }

    /// 切换礼物栏目，并在当前礼物不属于新栏目时选择该栏目的第一项。
    ///
    /// - Parameter category: 需要显示的目标栏目。
    /// - Returns: 切换后自动选中的替代礼物；栏目未变化、无需替换或新栏目为空时为 `nil`。
    func selectCategory(_ category: GiftCategory) -> Gift? {
        guard selectedCategory != category else { return nil }
        selectedCategory = category
        showsInsufficientBalancePrompt = false
        guard let selectedGiftID,
            !visibleGifts.contains(where: { $0.id == selectedGiftID })
        else { return nil }
        let replacement = visibleGifts.first
        self.selectedGiftID = replacement?.id
        return replacement
    }

    /// 校验当前选择并生成发送结果，同时更新需要显示的错误提示。
    ///
    /// 此方法不扣款。最终收礼人有效性和余额由房间业务层在提交时再次校验。
    ///
    /// - Returns: 待确认请求、缺少收礼人或余额不足的结果。
    func makeSendDecision() -> SendDecision {
        guard
            let gift = gifts.first(where: { $0.id == selectedGiftID })
        else { return .recipientRequired }
        guard !selectedRecipients.isEmpty else {
            showsRecipientRequiredPrompt = true
            return .recipientRequired
        }
        let (totalCost, overflow) = gift.totalCost(
            quantity: selectedGiftQuantity,
            recipientCount: selectedRecipients.count
        )
        // 溢出视为不可支付，不能将截断后的较小整数误认为有效总价。
        guard !overflow, totalCost <= giftBalance else {
            showsInsufficientBalancePrompt = true
            return .insufficientBalance(
                required: overflow ? Int.max : totalCost,
                current: giftBalance
            )
        }
        return .ready(
            GiftSendRequest(
                gift: gift,
                recipients: selectedRecipients,
                quantity: selectedGiftQuantity,
                totalCost: totalCost
            )
        )
    }

    /// 应用业务层确认的非负余额，并清除余额不足提示。
    func applyConfirmedBalance(_ balance: Int) {
        giftBalance = max(0, balance)
        showsInsufficientBalancePrompt = false
    }

    /// 清除选择收礼人的提示状态。
    func clearRecipientRequiredPrompt() {
        showsRecipientRequiredPrompt = false
    }

    /// 清除余额不足的提示状态。
    func clearInsufficientBalancePrompt() {
        showsInsufficientBalancePrompt = false
    }

    /// 清除收礼人和余额两类发送提示。
    private func clearPrompts() {
        showsRecipientRequiredPrompt = false
        showsInsufficientBalancePrompt = false
    }
}
