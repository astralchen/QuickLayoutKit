//
//  ContentConfigurationListSupport.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

nonisolated enum ContentConfigurationListSection: Hashable, Sendable {
    case content
}

nonisolated struct ContentConfigurationListItemID: Hashable, Sendable {
    let group: Int
    let symbolName: String
}

struct ContentConfigurationListItem {
    let id: ContentConfigurationListItemID
    let model: ContentConfigurationModel
}

enum ContentConfigurationListFactory {

    static func localizedItems(
        repeating repetitionCount: Int = 1
    ) -> [ContentConfigurationListItem] {
        localizedItems(
            repeating: repetitionCount,
            localizer: .live
        )
    }

    static func localizedItems(
        repeating repetitionCount: Int = 1,
        localizer: Localizer
    ) -> [ContentConfigurationListItem] {
        let samples = ContentConfigurationModel.localizedMockData(localizer: localizer)
        return (0..<max(0, repetitionCount)).flatMap { group in
            samples.map { model in
                ContentConfigurationListItem(
                    id: ContentConfigurationListItemID(
                        group: group,
                        symbolName: model.imageName
                    ),
                    model: model
                )
            }
        }
    }
}
