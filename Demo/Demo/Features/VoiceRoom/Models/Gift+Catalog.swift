//
//  Gift+Catalog.swift
//  Demo
//
//  VoiceRoom MVVM feature.
//

import Foundation

extension Gift {

    /// 按展示顺序排列的内置、远程和组合礼物目录。
    static let catalog = [
        Gift(
            id: "heart",
            titleKey: "liveRoom.gift.item.heart",
            symbolName: "heart.fill",
            price: 10,
            themeIndex: 0,
            effectStyle: .trail
        ),
        Gift(
            id: "rose",
            titleKey: "liveRoom.gift.item.rose",
            symbolName: "leaf.fill",
            price: 20,
            themeIndex: 1,
            effectStyle: .trail
        ),
        Gift(
            id: "star",
            titleKey: "liveRoom.gift.item.star",
            symbolName: "star.fill",
            price: 52,
            themeIndex: 2,
            effectStyle: .trail
        ),
        Gift(
            id: "music",
            titleKey: "liveRoom.gift.item.music",
            symbolName: "music.note",
            price: 88,
            themeIndex: 3,
            effectStyle: .trail
        ),
        Gift(
            id: "microphone",
            titleKey: "liveRoom.gift.item.microphone",
            symbolName: "mic.fill",
            price: 128,
            themeIndex: 4,
            effectStyle: .trail
        ),
        Gift(
            id: "rocket",
            titleKey: "liveRoom.gift.item.rocket",
            symbolName: "paperplane.fill",
            price: 188,
            themeIndex: 5,
            effectStyle: .trail
        ),
        Gift(
            id: "crystal",
            titleKey: "liveRoom.gift.item.crystal",
            symbolName: "diamond.fill",
            price: 266,
            themeIndex: 2,
            effectStyle: .trail
        ),
        Gift(
            id: "crown",
            titleKey: "liveRoom.gift.item.crown",
            symbolName: "crown.fill",
            price: 388,
            themeIndex: 1,
            effectStyle: .trail
        ),
        Gift(
            id: "treasure",
            titleKey: "liveRoom.gift.item.treasure",
            symbolName: "gift.fill",
            price: 520,
            themeIndex: 0,
            effectStyle: .burst
        ),
        Gift(
            id: "fireworks",
            titleKey: "liveRoom.gift.item.fireworks",
            symbolName: "sparkles",
            price: 666,
            themeIndex: 1,
            effectStyle: .burst
        ),
        Gift(
            id: "castle",
            titleKey: "liveRoom.gift.item.castle",
            symbolName: "building.columns.fill",
            price: 888,
            themeIndex: 3,
            effectStyle: .burst
        ),
        Gift(
            id: "sportsCar",
            titleKey: "liveRoom.gift.item.sportsCar",
            symbolName: "car.fill",
            price: 1_314,
            themeIndex: 0,
            effectStyle: .burst
        ),
        Gift(
            id: "yacht",
            titleKey: "liveRoom.gift.item.yacht",
            symbolName: "ferry.fill",
            price: 1_888,
            themeIndex: 4,
            effectStyle: .burst
        ),
        Gift(
            id: "constellation",
            titleKey: "liveRoom.gift.item.constellation",
            symbolName: "moon.stars.fill",
            price: 2_888,
            themeIndex: 2,
            effectStyle: .burst
        ),
        Gift(
            id: "galaxy",
            titleKey: "liveRoom.gift.item.galaxy",
            symbolName: "globe.asia.australia.fill",
            price: 5_200,
            themeIndex: 4,
            effectStyle: .celebration
        ),
        Gift(
            id: "aurora",
            titleKey: "liveRoom.gift.item.aurora",
            symbolName: "sun.max.fill",
            price: 8_888,
            themeIndex: 5,
            effectStyle: .celebration
        ),
        Gift(
            id: "phoenix",
            titleKey: "liveRoom.gift.item.phoenix",
            symbolName: "flame.fill",
            price: 13_140,
            themeIndex: 0,
            effectStyle: .celebration
        ),
        Gift(
            id: "universe",
            titleKey: "liveRoom.gift.item.universe",
            symbolName: "globe",
            price: 18_888,
            themeIndex: 3,
            effectStyle: .celebration
        ),
    ] + remoteEffectGifts + multipleEffectGifts

    /// 组合已有素材演示一份礼物多个主特效；仅跳过自身素材缺失的组合。
    private static var multipleEffectGifts: [Gift] {
        let configurations: [(id: String, symbol: String, price: Int, theme: Int,
                              style: GiftEffectStyle, remoteIDs: [String])] = [
            ("flowerDuet", "sparkles", 520, 2, .burst,
             ["flowerJourney", "flowerBouquet"]),
            ("flowerSeaSuite", "leaf.fill", 666, 1, .trail,
             ["vap.花海倾心", "svga.漫花风吟"]),
            ("rosePromise", "heart.fill", 888, 0, .burst,
             ["svga.玫瑰之芯", "vap.玫瑰恋人"]),
            ("moonlitVoyage", "moon.stars.fill", 1_314, 3, .trail,
             ["vap.花舟赴月", "svga.蓝鸢映月"]),
            ("galaxyDream", "globe", 1_888, 4, .celebration,
             ["svga.深陷银河", "vap.星梦情缘"]),
            ("fireworkGala", "sparkles", 2_888, 1, .celebration,
             ["vap.花火信约", "svga.烟花映夏"]),
            ("rhythmParty", "music.note", 666, 5, .burst,
             ["svga.欢乐节拍", "svga.梦焰狂欢"]),
            ("auroraDream", "sun.max.fill", 5_200, 4, .celebration,
             ["vap.极光圣殿", "vap.琉光月影"]),
        ]
        return configurations.compactMap { configuration in
            let remoteGifts = configuration.remoteIDs.compactMap { id in
                remoteEffectGifts.first { $0.id == id }
            }
            guard remoteGifts.count == configuration.remoteIDs.count else { return nil }
            return Gift(
                id: configuration.id,
                titleKey: "liveRoom.gift.item.\(configuration.id)",
                symbolName: configuration.symbol,
                price: configuration.price,
                themeIndex: configuration.theme,
                effectStyle: configuration.id == "flowerDuet" ? .trail : configuration.style,
                effects: [.native(configuration.style)] + remoteGifts.flatMap(\.effects)
            )
        }
    }

    /// 按两个配置文件的原始顺序生成所有远程礼物，不预加载动画。
    private static let remoteEffectGifts: [Gift] = {
        remoteEffectGifts(list: "gift_effects_mp4", format: "vap", pathExtension: "mp4", makeEffect: GiftEffect.vap)
            + remoteEffectGifts(list: "gift_effects_svga", format: "svga", pathExtension: "svga", makeEffect: GiftEffect.svga)
    }()

    /// 将有效配置映射为可赠送数据；身份由格式和名称确定，不随排序或 URL 更新变化。
    /// 保留原有两项演示礼物的 ID 与翻译，其余名称直接回退到配置原文。
    private static func remoteEffectGifts(
        list: String,
        format: String,
        pathExtension: String,
        makeEffect: (URL) -> GiftEffect
    ) -> [Gift] {
        GiftEffectResources.validEntries(named: list, pathExtension: pathExtension).compactMap { entry in
            guard let url = entry.remoteURL(pathExtension: pathExtension) else { return nil }
            let id: String
            switch (format, entry.name) {
            case ("vap", "花下与君游"): id = "flowerJourney"
            case ("svga", "萌萌花束"): id = "flowerBouquet"
            default: id = "\(format).\(entry.name)"
            }
            return Gift(
                id: id, titleKey: "liveRoom.gift.item.\(id)",
                symbolName: format == "vap" ? "leaf.fill" : "camera.macro",
                price: 520, themeIndex: format == "vap" ? 1 : 0,
                effectStyle: .trail, effects: [makeEffect(url)], sourceName: entry.name
            )
        }
    }
}
