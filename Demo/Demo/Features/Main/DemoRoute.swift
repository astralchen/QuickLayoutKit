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
    case profile
    case counter
    case dynamicScroll
    case dashboard
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
        case .profile:
            "demo.profile.title"
        case .counter:
            "demo.counter.title"
        case .dynamicScroll:
            "demo.dynamicScroll.title"
        case .dashboard:
            "demo.dashboard.title"
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
}
