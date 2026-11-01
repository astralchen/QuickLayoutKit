//
//  SceneDelegate.swift
//  Demo
//
//  Created by Sondra on 2025/12/26.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = AppTabBarController()
        self.window = window
        Localization.register(window: window)
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 系统释放场景后，清理下次连接时可以重新创建的场景资源。
        // 场景可能在进入后台后断开并再次连接；断开并不表示会话已经被丢弃。
        if let window {
            Localization.unregister(window: window)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景进入活跃状态后，恢复非活跃期间暂停或尚未启动的任务。
        if let window {
            Localization.synchronize(window: window)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 场景即将进入非活跃状态；来电等临时中断可能触发该回调。
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Localization.refreshSystemLocaleIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景进入后台时保存数据、释放共享资源，并记录恢复当前界面所需的场景状态。
    }


}
