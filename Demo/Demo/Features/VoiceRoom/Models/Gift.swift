//
//  Gift.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

/// 原生礼物动画的视觉样式。
enum GiftEffectStyle: Int, Equatable, Sendable {
    /// 沿飞行轨迹显示拖尾。
    case trail
    /// 礼物抵达后显示粒子爆发效果。
    case burst
    /// 使用更大规模的庆典效果。
    case celebration
}

/// 礼物面板用于筛选目录的栏目。
enum GiftCategory: CaseIterable {
    /// 显示目录中的全部礼物。
    case all
    /// 使用远程 VAP 主特效的礼物栏目。
    case vap
    /// 使用远程 SVGA 主特效的礼物栏目。
    case svga
    /// 同一次赠送包含多个按顺序播放的主特效。
    case multiple
    /// 显示单价不超过 520 金币的热门礼物。
    case popular
    /// 显示浪漫主题礼物。
    case romantic
    /// 显示派对主题礼物。
    case party
    /// 显示采用爆发样式的互动礼物。
    case interactive
    /// 显示采用庆典样式的豪华礼物。
    case luxury
    /// 显示单价不低于 1,888 金币的收藏栏目礼物。
    case collection

    /// 标题使用的本地化资源键。
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

    /// 不随界面语言变化的栏目标识。
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

    /// 返回指定礼物是否属于此栏目。
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

/// 可赠送礼物的身份、单价、显示资源和特效配置。
struct Gift: Equatable, Sendable {
    /// 不随排序、语言或素材地址变化的礼物标识。
    let id: String
    /// 标题使用的本地化资源键。
    let titleKey: String
    /// 显示图标使用的 SF Symbols 名称。
    let symbolName: String
    /// 每份礼物赠送给一名用户时消耗的金币数。
    let price: Int
    /// 从主题调色板选取颜色的索引。
    let themeIndex: Int
    /// 礼物图标和原生动画使用的视觉样式。
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

/// 可选择的单个收礼人赠送数量及其显示名称。
struct GiftQuantityOption: Equatable, Sendable {
    /// 每名收礼人接收的礼物份数。
    let value: Int
    /// 标题使用的本地化资源键。
    let titleKey: String

    /// 按面板显示顺序排列的预设赠送数量。
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

/// 等待房间业务层校验并扣款的一次赠送请求。
struct GiftSendRequest {
    /// 本次赠送或展示的礼物。
    let gift: Gift
    /// 请求声明的收礼麦位列表；提交时必须校验用户唯一且仍为本房可见用户。
    let recipients: [SeatAssignment]
    /// 向每名收礼人赠送的礼物份数。
    let quantity: Int
    /// 请求声明的总金币数；提交时仍需重新计算并校验。
    let totalCost: Int
}

extension Gift {

    /// 计算向指定人数赠送指定份数礼物的总金币数。
    ///
    /// - Parameters:
    ///   - quantity: 每名收礼人的礼物份数。
    ///   - recipientCount: 收礼人数。
    /// - Returns: 总金币数及溢出标记；输入不合法或任一次乘法溢出时，不应使用计算结果扣款。
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
