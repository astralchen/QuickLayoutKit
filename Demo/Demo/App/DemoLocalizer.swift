//
//  DemoLocalizer.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import Foundation
import AppLocalization

/// The narrow localization dependency consumed by view models.
///
/// Keeping the resolver behind a value makes view-model state deterministic in
/// tests while `DemoLocalization` continues to own the app-wide locale flow.
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
