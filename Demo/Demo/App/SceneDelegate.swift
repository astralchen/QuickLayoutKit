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
        // 在此配置窗口，并将其关联到传入的 `UIWindowScene`。
        // 使用 storyboard 时，系统会自动初始化 `window` 并关联场景。
        // 连接到此代理并不表示场景或会话刚刚创建；新会话配置由 AppDelegate 提供。
        guard scene is UIWindowScene else { return }
        if let window {
            DemoLocalization.register(window: window)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // 系统释放场景后，清理下次连接时可以重新创建的场景资源。
        // 场景可能在进入后台后断开并再次连接；断开并不表示会话已经被丢弃。
        if let window {
            DemoLocalization.unregister(window: window)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景进入活跃状态后，恢复非活跃期间暂停或尚未启动的任务。
        if let window {
            DemoLocalization.synchronize(window: window)
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // 场景即将进入非活跃状态；来电等临时中断可能触发该回调。
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        DemoLocalization.refreshSystemLocaleIfNeeded()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景进入后台时保存数据、释放共享资源，并记录恢复当前界面所需的场景状态。
    }


}
