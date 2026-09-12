//
//  ContentConfigurationModel.swift
//  Demo
//
//  Created by Sondra on 2025/12/17.
//

import UIKit

struct ContentConfigurationModel {
    let title: String
    let detail: String
    let imageName: String
    let themeColor: UIColor
}


extension ContentConfigurationModel {

    static var mockData: [ContentConfigurationModel] {
        localizedMockData()
    }

    static func localizedMockData() -> [ContentConfigurationModel] {
        localizedMockData(localizer: .live)
    }

    static func localizedMockData(
        localizer: Localizer
    ) -> [ContentConfigurationModel] {
        [
            ContentConfigurationModel(
                title: localizer.text("contentConfiguration.sample.title.1"),
                detail: localizer.text("contentConfiguration.sample.detail.1"),
                imageName: "moon.stars.fill",
                themeColor: .systemIndigo
            ),
            ContentConfigurationModel(
                title: localizer.text("contentConfiguration.sample.title.2"),
                detail: localizer.text("contentConfiguration.sample.detail.2"),
                imageName: "cloud.rain.fill",
                themeColor: .systemTeal
            ),
            ContentConfigurationModel(
                title: localizer.text("contentConfiguration.sample.title.3"),
                detail: localizer.text("contentConfiguration.sample.detail.3"),
                imageName: "sun.max.fill",
                themeColor: .systemOrange
            ),
            ContentConfigurationModel(
                title: localizer.text("contentConfiguration.sample.title.4"),
                detail: localizer.text("contentConfiguration.sample.detail.4"),
                imageName: "mountain.2.fill",
                themeColor: .systemGreen
            )
        ]
    }
}
