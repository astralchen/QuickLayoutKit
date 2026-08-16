//
//  LocalizationOverviewViewModel.swift
//  Demo
//
//  Created by Codex on 2026/8/15.
//

import AppLocalization
import Foundation

@MainActor
struct LocalizationOverviewService {
    struct Language: Equatable {
        let identifier: String
        let nativeName: String
        let localizedName: String
        let isFollowSystemOption: Bool
    }

    struct Snapshot: Equatable {
        let currentLanguageSummary: String
        let usesRightToLeftLayout: Bool
        let selectedIdentifier: String
        let languages: [Language]
    }

    let snapshot: () -> Snapshot
    let selectLanguage: (_ identifier: String) -> Void

    static let live = LocalizationOverviewService(
        snapshot: {
            let controller = DemoLocalization.localizationController
            let followSystem = Language(
                identifier: LocalizationController.followSystemLocaleIdentifier,
                nativeName: "",
                localizedName: DemoLocalization.localeDisplayName(
                    controller.currentLocale
                ),
                isFollowSystemOption: true
            )
            let supportedLanguages = controller.supportedLocales.map { locale in
                Language(
                    identifier: locale.identifier,
                    nativeName: locale.nativeDisplayName,
                    localizedName: DemoLocalization.localeDisplayName(locale),
                    isFollowSystemOption: false
                )
            }

            return Snapshot(
                currentLanguageSummary: DemoLocalization.currentLanguageSummary(),
                usesRightToLeftLayout:
                    DemoLocalization.currentLayoutDirection == .rightToLeft,
                selectedIdentifier: controller.followsSystemLocale
                    ? LocalizationController.followSystemLocaleIdentifier
                    : controller.currentLocale.identifier,
                languages: [followSystem] + supportedLanguages
            )
        },
        selectLanguage: { identifier in
            DemoLocalization.setLocale(identifier: identifier)
        }
    )
}

@MainActor
final class LocalizationOverviewViewModel {
    struct LanguageOption: Equatable {
        let identifier: String
        let title: String
        let subtitle: String
        let isSelected: Bool
    }

    struct State: Equatable {
        let bodyText: String
        let currentLanguageText: String
        let directionText: String
        let languages: [LanguageOption]
    }

    private let localizer: DemoLocalizer
    private let service: LocalizationOverviewService
    private var render: ((State) -> Void)?

    private(set) var state: State

    convenience init() {
        self.init(localizer: .live, service: .live)
    }

    init(
        localizer: DemoLocalizer,
        service: LocalizationOverviewService
    ) {
        self.localizer = localizer
        self.service = service
        state = Self.makeState(localizer: localizer, snapshot: service.snapshot())
    }

    func bind(_ render: @escaping (State) -> Void) {
        self.render = render
        render(state)
    }

    func refreshLocalizedContent() {
        state = Self.makeState(
            localizer: localizer,
            snapshot: service.snapshot()
        )
        render?(state)
    }

    func selectLanguage(identifier: String) {
        guard state.languages.contains(where: { $0.identifier == identifier }) else {
            return
        }

        service.selectLanguage(identifier)
        refreshLocalizedContent()
    }

    private static func makeState(
        localizer: DemoLocalizer,
        snapshot: LocalizationOverviewService.Snapshot
    ) -> State {
        State(
            bodyText: localizer.text("localization.overview.body"),
            currentLanguageText:
                "\(localizer.text("language.current")): "
                + snapshot.currentLanguageSummary,
            directionText:
                "\(localizer.text("language.direction")): "
                + (snapshot.usesRightToLeftLayout ? "RTL" : "LTR"),
            languages: snapshot.languages.map { language in
                LanguageOption(
                    identifier: language.identifier,
                    title: language.isFollowSystemOption
                        ? localizer.text("language.follow.system")
                        : language.nativeName,
                    subtitle: language.localizedName,
                    isSelected:
                        language.identifier == snapshot.selectedIdentifier
                )
            }
        )
    }
}
