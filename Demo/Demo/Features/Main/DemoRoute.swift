//
//  DemoRoute.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

/// 演示应用中不依赖 UIKit 的导航目标。
enum DemoRoute: CaseIterable, Hashable, Sendable {
    case horizontalScroll
    case safeAreaPadding
    case contentMargins
    case positionAndZIndex
    case viewThatFits
    case profile
    case counter
    case dynamicScroll
    case dashboard
    case liveRoom
    case imessageChat
    case messages
    case tableMessages
    case keyboard
    case form
    case semanticContent
    case representable
    case localizationOverview
    case uikitLocalization
    case directionalNavigation
    case semanticGesture
    case swiftUIBridge
    case localizationBoundary

    var titleKey: String {
        switch self {
        case .horizontalScroll:
            "demo.horizontalScroll.title"
        case .safeAreaPadding:
            "demo.safeAreaPadding.title"
        case .contentMargins:
            "demo.contentMargins.title"
        case .positionAndZIndex:
            "demo.positionAndZIndex.title"
        case .viewThatFits:
            "demo.viewThatFits.title"
        case .profile:
            "demo.profile.title"
        case .counter:
            "demo.counter.title"
        case .dynamicScroll:
            "demo.dynamicScroll.title"
        case .dashboard:
            "demo.dashboard.title"
        case .liveRoom:
            "demo.liveRoom.title"
        case .imessageChat:
            "demo.imessage.title"
        case .messages:
            "demo.messages.title"
        case .tableMessages:
            "demo.tableMessages.title"
        case .keyboard:
            "demo.keyboard.title"
        case .form:
            "demo.form.title"
        case .semanticContent:
            "demo.semantic.title"
        case .representable:
            "demo.representable.title"
        case .localizationOverview:
            "demo.localizationOverview.title"
        case .uikitLocalization:
            "demo.uikitLocalization.title"
        case .directionalNavigation:
            "demo.directionalNavigation.title"
        case .semanticGesture:
            "demo.semanticGesture.title"
        case .swiftUIBridge:
            "demo.swiftUIBridge.title"
        case .localizationBoundary:
            "demo.localizationBoundary.title"
        }
    }

    /// 主菜单为每个演示入口使用稳定的 SF Symbol；这里只保存符号名称，避免导航模型
    /// 依赖 UIKit，同时让列表配置可以直接随路由更新对应图标。
    var iconSystemName: String {
        switch self {
        case .horizontalScroll:
            "arrow.left.and.right"
        case .safeAreaPadding:
            "inset.filled.rectangle"
        case .contentMargins:
            "arrow.left.and.right.text.vertical"
        case .positionAndZIndex:
            "square.3.layers.3d"
        case .viewThatFits:
            "chevron.up.chevron.down"
        case .profile:
            "person.crop.circle"
        case .counter:
            "plus.forwardslash.minus"
        case .dynamicScroll:
            "scroll"
        case .dashboard:
            "rectangle.3.group"
        case .liveRoom:
            "music.mic"
        case .imessageChat:
            "message.fill"
        case .messages:
            "bubble.left.and.bubble.right"
        case .tableMessages:
            "list.bullet.rectangle"
        case .keyboard:
            "keyboard"
        case .form:
            "list.clipboard"
        case .semanticContent:
            "arrow.left.and.right"
        case .representable:
            "arrow.triangle.2.circlepath"
        case .localizationOverview:
            "globe"
        case .uikitLocalization:
            "uiwindow.split.2x1"
        case .directionalNavigation:
            "arrow.triangle.turn.up.right.diamond"
        case .semanticGesture:
            "hand.draw"
        case .swiftUIBridge:
            "swift"
        case .localizationBoundary:
            "square.dashed.inset.filled"
        }
    }
}
