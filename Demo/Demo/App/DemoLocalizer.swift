//
//  DemoLocalizer.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation
import AppLocalization

/// 供视图模型使用的最小本地化依赖。
///
/// 将解析闭包封装在值类型中，使视图模型状态在测试中保持确定；
/// 应用级语言环境流程仍由 `DemoLocalization` 统一管理。
@MainActor
struct DemoLocalizer {
    typealias Resolver = (_ key: String, _ arguments: [CVarArg]) -> String

    private let resolve: Resolver

    init(resolve: @escaping Resolver) {
        self.resolve = resolve
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        resolve(key, arguments)
    }

    static let live = DemoLocalizer { key, arguments in
        DemoLocalization.resolver.string(
            key,
            bundle: .main,
            arguments: arguments
        )
    }
}
