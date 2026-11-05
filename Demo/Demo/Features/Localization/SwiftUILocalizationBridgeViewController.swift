//
//  SwiftUILocalizationBridgeViewController.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import SwiftUI
import AppLocalization

final class SwiftUILocalizationBridgeViewController: LocalizedViewController {
    override var localizedTitleKey: String? { "demo.swiftUIBridge.title" }

    private var hostingController: UIHostingController<AnyView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installHostedViewIfNeeded()
    }

    override func reloadLayoutDirection(_ direction: UIUserInterfaceLayoutDirection) {
        super.reloadLayoutDirection(direction)
        guard let hostingController else { return }
        // SwiftUI 文案和布局由观察到的本地化环境更新，UIKit 只同步宿主视图边界。
        UIViewLayoutDirectionUpdater.apply(
            Localization.currentUIKitUpdate,
            to: [UIViewLayoutDirectionTarget(
                hostingController.view,
                policy: .fixed(direction.appLayoutDirection.semanticContentAttribute)
            )]
        )
    }

    private func installHostedViewIfNeeded() {
        guard hostingController == nil else { return }
        let update = Localization.currentUIKitUpdate
        let root = AnyView(
            SwiftUILocalizationBridgeView(
                localizationController: Localization.localizationController,
                resolver: Localization.resolver
            )
            .appLocalizationEnvironment(Localization.localizationController)
        )

        let hostingController = UIHostingController(rootView: root)
        UIViewLayoutDirectionUpdater.apply(
            update,
            to: [
                UIViewLayoutDirectionTarget(
                    hostingController.view,
                    policy: .followApplication
                )
            ]
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            // 让 SwiftUI 统一消费继承的安全区；UIKit 仅传递完整容器边界。
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }
}

private struct SwiftUILocalizationBridgeView: View {
    @ObservedObject var localizationController: LocalizationController
    let resolver: LocalizedStringResolver
    @State private var isSheetPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(resolver.string("swiftui.bridge.body", bundle: .main))
                    .font(.body)
                // 文案已由 resolver 本地化，直接展示，避免 SwiftUI 再次提取插值模板。
                Text(verbatim: "\(resolver.string("language.direction", bundle: .main)): \(localizationController.layoutDirection == .rightToLeft ? "RTL" : "LTR")")
                    .foregroundStyle(.secondary)
                Button(resolver.string("swiftui.showSheet", bundle: .main)) {
                    isSheetPresented = true
                }
                .accessibilityIdentifier("localization.swiftUI.showSheet")
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .sheet(isPresented: $isSheetPresented) {
            NavigationView {
                ScrollView {
                    Text(resolver.string("swiftui.sheet.message", bundle: .main))
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding()
                        .frame(maxWidth: .infinity)
                }
                    .navigationTitle(resolver.string("demo.swiftUIBridge.title", bundle: .main))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(resolver.string("common.close", bundle: .main)) {
                                isSheetPresented = false
                            }
                            .accessibilityIdentifier("localization.swiftUI.closeSheet")
                        }
                    }
            }
            .navigationViewStyle(.stack)
            .appLocalizationEnvironment(localizationController)
        }
    }
}


@available(iOS 17.0, *)
#Preview {
    UINavigationController(rootViewController: SwiftUILocalizationBridgeViewController())
}
