//
//  MessageModel.swift
//  MessageCell
//
//  Created by Sondra on 2025/12/17.
//

import UIKit

struct MessageModel {
    let title: String
    let message: String
    let imageName: String
    let themeColor: UIColor
}


extension MessageModel {

    static var mockData: [MessageModel] {
        localizedMockData()
    }

    static func localizedMockData() -> [MessageModel] {
        localizedMockData(localizer: .live)
    }

    static func localizedMockData(
        localizer: DemoLocalizer
    ) -> [MessageModel] {
        [
            MessageModel(
                title: localizer.text("messages.title.1"),
                message: localizer.text("messages.body.1"),
                imageName: "moon.stars.fill",
                themeColor: .systemIndigo
            ),
            MessageModel(
                title: localizer.text("messages.title.2"),
                message: localizer.text("messages.body.2"),
                imageName: "cloud.rain.fill",
                themeColor: .systemTeal
            ),
            MessageModel(
                title: localizer.text("messages.title.3"),
                message: localizer.text("messages.body.3"),
                imageName: "sun.max.fill",
                themeColor: .systemOrange
            ),
            MessageModel(
                title: localizer.text("messages.title.4"),
                message: localizer.text("messages.body.4"),
                imageName: "mountain.2.fill",
                themeColor: .systemGreen
            )
        ]
    }
}
