//
//  LiveRoomGift.swift
//  Demo
//
//  LiveRoom MVVM feature.
//

import Foundation

enum LiveRoomGiftEffectStyle: Int, Equatable, Sendable {
    case trail
    case burst
    case celebration
}

enum LiveRoomGiftCategory: CaseIterable {
    case all
    case popular
    case romantic
    case party
    case interactive
    case luxury
    case collection

    var titleKey: String {
        switch self {
        case .all:
            "liveRoom.gift.category.all"
        case .popular:
            "liveRoom.gift.category.popular"
        case .romantic:
            "liveRoom.gift.category.romantic"
        case .party:
            "liveRoom.gift.category.party"
        case .interactive:
            "liveRoom.gift.category.interactive"
        case .luxury:
            "liveRoom.gift.category.luxury"
        case .collection:
            "liveRoom.gift.category.collection"
        }
    }

    var id: String {
        switch self {
        case .all:
            "all"
        case .popular:
            "popular"
        case .romantic:
            "romantic"
        case .party:
            "party"
        case .interactive:
            "interactive"
        case .luxury:
            "luxury"
        case .collection:
            "collection"
        }
    }

    func includes(_ gift: LiveRoomGift) -> Bool {
        switch self {
        case .all:
            true
        case .popular:
            gift.price <= 520
        case .romantic:
            ["heart", "rose", "star", "crystal", "constellation", "aurora"]
                .contains(gift.id)
        case .party:
            ["music", "microphone", "fireworks", "castle", "sportsCar", "yacht"]
                .contains(gift.id)
        case .interactive:
            gift.effectStyle == .burst
        case .luxury:
            gift.effectStyle == .celebration
        case .collection:
            gift.price >= 1_888
        }
    }
}

struct LiveRoomGift: Equatable, Sendable {
    let id: String
    let titleKey: String
    let symbolName: String
    let price: Int
    let themeIndex: Int
    let effectStyle: LiveRoomGiftEffectStyle
}

struct LiveRoomGiftQuantityOption: Equatable, Sendable {
    let value: Int
    let titleKey: String

    static let presets = [
        LiveRoomGiftQuantityOption(
            value: 1,
            titleKey: "liveRoom.gift.quantity.one"
        ),
        LiveRoomGiftQuantityOption(
            value: 10,
            titleKey: "liveRoom.gift.quantity.ten"
        ),
        LiveRoomGiftQuantityOption(
            value: 30,
            titleKey: "liveRoom.gift.quantity.thirty"
        ),
        LiveRoomGiftQuantityOption(
            value: 66,
            titleKey: "liveRoom.gift.quantity.sixtySix"
        ),
        LiveRoomGiftQuantityOption(
            value: 188,
            titleKey: "liveRoom.gift.quantity.oneEightyEight"
        ),
        LiveRoomGiftQuantityOption(
            value: 520,
            titleKey: "liveRoom.gift.quantity.fiveTwenty"
        ),
        LiveRoomGiftQuantityOption(
            value: 1_314,
            titleKey: "liveRoom.gift.quantity.thirteenFourteen"
        ),
    ]
}

struct LiveRoomGiftSendRequest {
    let gift: LiveRoomGift
    let recipients: [LiveRoomSeat]
    let quantity: Int
    let totalCost: Int
}

extension LiveRoomGift {

    /// 使用溢出安全乘法计算一次赠送的总成本。
    func totalCost(
        quantity: Int,
        recipientCount: Int
    ) -> (cost: Int, overflow: Bool) {
        guard quantity > 0, recipientCount > 0, price >= 0 else {
            return (0, true)
        }
        let (quantityCost, quantityOverflow) = price
            .multipliedReportingOverflow(by: quantity)
        guard !quantityOverflow else { return (0, true) }
        let (totalCost, recipientOverflow) = quantityCost
            .multipliedReportingOverflow(by: recipientCount)
        return (totalCost, recipientOverflow)
    }
}
