//
//  AppDelegate.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DemoLocalization.start()
        return true
    }

    // MARK: - 场景会话生命周期

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // 创建新场景会话时，返回用于创建场景的配置。
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // 用户丢弃场景会话时，释放这些场景专用且无法继续使用的资源。
    }


}
