//
//  SwiftUILocalizationBridgeDemoViewController.swift
//  Demo
//
//  Created by Codex on 2026/6/2.
//

import UIKit
import SwiftUI
import AppLocalization

final class SwiftUILocalizationBridgeDemoViewController: LocalizedViewController {
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
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
        VStack(alignment: .leading, spacing: 20) {
            Text(resolver.string("swiftui.bridge.body", bundle: .main))
                .font(.body)
            Text("\(resolver.string("language.direction", bundle: .main)): \(localizationController.layoutDirection == .rightToLeft ? "RTL" : "LTR")")
                .foregroundStyle(.secondary)
            Button(resolver.string("swiftui.showSheet", bundle: .main)) {
                isSheetPresented = true
            }
            Spacer()
        }
        .padding(20)
        .sheet(isPresented: $isSheetPresented) {
            NavigationView {
                Text(resolver.string("swiftui.sheet.message", bundle: .main))
                    .padding()
                    .navigationTitle(resolver.string("demo.swiftUIBridge.title", bundle: .main))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(resolver.string("common.close", bundle: .main)) {
                                isSheetPresented = false
                            }
                        }
                    }
            }
            .appLocalizationEnvironment(localizationController)
        }
    }
}


#Preview {
    UINavigationController(rootViewController: SwiftUILocalizationBridgeDemoViewController())
}
