//
//  GiftSheetViewModel.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

@MainActor
final class GiftSheetViewModel {

    enum SendDecision {
        case ready(GiftSendRequest)
        case recipientRequired
        case insufficientBalance(required: Int, current: Int)
    }

    private(set) var recipients: [SeatAssignment]
    let gifts: [Gift]
    let quantityOptions: [GiftQuantityOption]

    private(set) var selectedRecipientUserIDs: Set<RoomUserID>
    private(set) var selectedGiftID: String?
    private(set) var selectedGiftQuantity = 1
    private(set) var giftBalance: Int
    private(set) var selectedCategory: GiftCategory = .all
    private(set) var showsRecipientRequiredPrompt = false
    private(set) var showsInsufficientBalancePrompt = false

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

    var selectedRecipients: [SeatAssignment] {
        recipients.filter { recipient in
            recipient.userID.map(selectedRecipientUserIDs.contains) == true
        }
    }

    /// 现有 Demo 调试接口使用的零基麦位位置集合。
    var selectedRecipientPositions: Set<Int> {
        Set(selectedRecipients.map { $0.position.rawValue })
    }

    var selectedRecipientIDs: Set<Int> {
        selectedRecipientPositions
    }

    var visibleGifts: [Gift] {
        gifts.filter { selectedCategory.includes($0) }
    }

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

    @discardableResult
    func toggleRecipient(id position: Int) -> Bool {
        guard let userID = recipients.first(where: {
            $0.position.rawValue == position
        })?.userID else { return false }
        return toggleRecipient(userID: userID)
    }

    func toggleAllRecipients() {
        let availableUserIDs = Set(recipients.compactMap(\.userID))
        if selectedRecipientUserIDs == availableUserIDs {
            selectedRecipientUserIDs.removeAll()
        } else {
            selectedRecipientUserIDs = availableUserIDs
        }
        clearPrompts()
    }

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
        selectedRecipientUserIDs.formIntersection(availableUserIDs)
        clearPrompts()
    }

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

    @discardableResult
    func selectGiftQuantity(_ quantity: Int) -> Bool {
        guard quantityOptions.contains(where: { $0.value == quantity }) else {
            return false
        }
        selectedGiftQuantity = quantity
        showsInsufficientBalancePrompt = false
        return true
    }

    /// 返回栏目切换后被自动选中的礼物；视图据此更新外部选择回调。
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

    func applyConfirmedBalance(_ balance: Int) {
        giftBalance = max(0, balance)
        showsInsufficientBalancePrompt = false
    }

    func clearRecipientRequiredPrompt() {
        showsRecipientRequiredPrompt = false
    }

    func clearInsufficientBalancePrompt() {
        showsInsufficientBalancePrompt = false
    }

    private func clearPrompts() {
        showsRecipientRequiredPrompt = false
        showsInsufficientBalancePrompt = false
    }
}
