//
//  Gift.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

enum GiftEffectStyle: Int, Equatable, Sendable {
    case trail
    case burst
    case celebration
}

enum GiftCategory: CaseIterable {
    case all
    /// 使用远程 VAP 主特效的礼物栏目。
    case vap
    /// 使用远程 SVGA 主特效的礼物栏目。
    case svga
    /// 同一次赠送包含多个按顺序播放的主特效。
    case multiple
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
        case .vap:
            "liveRoom.gift.category.vap"
        case .svga:
            "liveRoom.gift.category.svga"
        case .multiple:
            "liveRoom.gift.category.multiple"
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
        case .vap:
            "vap"
        case .svga:
            "svga"
        case .multiple:
            "multiple"
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

    func includes(_ gift: Gift) -> Bool {
        switch self {
        case .all:
            true
        case .vap:
            gift.effects.contains { if case .vap = $0 { true } else { false } }
        case .svga:
            gift.effects.contains { if case .svga = $0 { true } else { false } }
        case .multiple:
            gift.effects.count > 1
        case .popular:
            gift.price <= 520
        case .romantic:
            ["heart", "rose", "star", "crystal", "constellation", "aurora",
             "flowerJourney", "flowerBouquet"]
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

struct Gift: Equatable, Sendable {
    let id: String
    let titleKey: String
    let symbolName: String
    let price: Int
    let themeIndex: Int
    var effectStyle: GiftEffectStyle

    /// 按配置顺序各播放一次的统一特效列表，可混合原生、VAP 和 SVGA。
    var effects: [GiftEffect]

    /// 配置提供的原始名称；没有对应翻译时用于展示，不影响礼物身份。
    var sourceName: String? = nil

    /// 创建统一礼物数据；未指定列表时使用与单元格样式一致的原生特效。
    init(id: String, titleKey: String, symbolName: String, price: Int,
         themeIndex: Int, effectStyle: GiftEffectStyle,
         effects: [GiftEffect]? = nil, sourceName: String? = nil) {
        self.id = id
        self.titleKey = titleKey
        self.symbolName = symbolName
        self.price = price
        self.themeIndex = themeIndex
        self.effectStyle = effectStyle
        self.effects = effects ?? [.native(effectStyle)]
        self.sourceName = sourceName
    }

}

struct GiftQuantityOption: Equatable, Sendable {
    let value: Int
    let titleKey: String

    static let presets = [
        GiftQuantityOption(
            value: 1,
            titleKey: "liveRoom.gift.quantity.one"
        ),
        GiftQuantityOption(
            value: 10,
            titleKey: "liveRoom.gift.quantity.ten"
        ),
        GiftQuantityOption(
            value: 30,
            titleKey: "liveRoom.gift.quantity.thirty"
        ),
        GiftQuantityOption(
            value: 66,
            titleKey: "liveRoom.gift.quantity.sixtySix"
        ),
        GiftQuantityOption(
            value: 188,
            titleKey: "liveRoom.gift.quantity.oneEightyEight"
        ),
        GiftQuantityOption(
            value: 520,
            titleKey: "liveRoom.gift.quantity.fiveTwenty"
        ),
        GiftQuantityOption(
            value: 1_314,
            titleKey: "liveRoom.gift.quantity.thirteenFourteen"
        ),
    ]
}

struct GiftSendRequest {
    let gift: Gift
    let recipients: [SeatAssignment]
    let quantity: Int
    let totalCost: Int
}

extension Gift {

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
