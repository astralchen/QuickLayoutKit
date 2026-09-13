import AVFAudio
import CoreGraphics
import Testing
import UIKit
import AppLocalization
import QuickLayoutKit
@_spi(Testing) import QuickLayoutKitUIKit
@testable import Demo

extension DemoTests {

    @Test func demoLocalizationResolvesCoreLanguages() {
        Localization.setLocale(identifier: "en-US")
        #expect(Localization.text("main.title") == "Examples")
        #expect(Localization.text("demo.localizationOverview.title") == "Language Center")

        Localization.setLocale(identifier: "zh-Hans")
        #expect(Localization.text("main.title") == "示例")
        #expect(Localization.text("language.follow.system") == "跟随系统")

        Localization.setLocale(identifier: "ar")
        #expect(Localization.text("main.title") == "الأمثلة")
        #expect(Localization.text("profile.section.about") == "نبذة")
        #expect(
            Localization.text("profile.skill.localization")
                == "التوطين"
        )
        #expect(
            Localization.text("profile.action.portfolio")
                == "معرض الأعمال"
        )
        #expect(
            Localization.text("uikit.showModal")
                == "عرض نافذة مشروطة"
        )
        #expect(
            Localization.text("boundary.recreateAlert")
                == "إعادة إنشاء التنبيه"
        )
        #expect(Localization.text("navigation.leading") == "عنصر البداية")
        #expect(Localization.text("navigation.trailing") == "عنصر النهاية")
        #expect(
            Localization.text(
                "navigation.edge.summary",
                Localization.text("navigation.edge.right"),
                "chevron.right"
            ).removingBidiIsolationMarks
                == "حافة الرجوع: اليمين، علامة الاتجاه: chevron.right"
        )
        #expect(
            Localization.text("gesture.translation", Int64(0))
                == "الإزاحة الأفقية: 0"
        )
        #expect(
            Localization.text(
                "gesture.backSwipe",
                Localization.text("common.boolean.false")
            ).removingBidiIsolationMarks == "إيماءة الرجوع: لا"
        )
        #expect(Localization.currentLayoutDirection == .rightToLeft)

        Localization.setLocale(identifier: "en-US")
    }

    @Test func localizationStringCatalogContainsSupportedLocales() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        for key in [
            "main.title",
            "demo.safeAreaPadding.title",
            "safeAreaPadding.intro",
            "safeAreaPadding.previous",
            "safeAreaPadding.next",
            "demo.localizationOverview.title",
            "demo.uikitLocalization.title",
            "demo.swiftUIBridge.title",
            "demo.contentConfiguration.table.title",
            "demo.contentConfiguration.table.header",
            "demo.contentConfiguration.table.header.detail",
            "demo.contentConfiguration.table.footer",
            "dynamic.item.title",
            "dynamic.item.deleteHint",
            "dynamic.item.deleteButton",
            "dynamic.item.deleteAccessibilityHint",
            "common.boolean.false",
            "common.boolean.true",
            "gesture.translation",
            "keyboard.diagnostics.event",
            "keyboard.diagnostics.height",
            "keyboard.diagnostics.intersection",
            "keyboard.diagnostics.rawFrame",
            "navigation.edge.left",
            "navigation.edge.right",
            "navigation.edge.summary",
            "liveRoom.user.host",
            "liveRoom.user.individual.1",
            "liveRoom.user.individual.2",
            "liveRoom.user.individual.3",
            "liveRoom.user.individual.4",
            "liveRoom.user.party.1",
            "liveRoom.user.party.2",
            "liveRoom.user.party.3",
            "liveRoom.user.party.4",
            "liveRoom.user.party.5",
            "liveRoom.user.party.6",
        ] {
            let localizations = try #require(catalog.strings[key]?.localizations)
            #expect(localizations["en"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["zh-Hans"]?.stringUnit.value.isEmpty == false)
            #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
        }
    }

    @Test func arabicLocalizationsDoNotContainHanCharacters() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)

        let keysContainingHan: [String] = catalog.strings.compactMap {
            key, entry -> String? in
            guard let value = entry.localizations?["ar"]?.stringUnit.value else {
                return nil
            }
            let containsHan = value.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                    return true
                default:
                    return false
                }
            }
            return containsHan ? key : nil
        }

        #expect(keysContainingHan.isEmpty)
    }

    @Test func infoPlistStringCatalogContainsDisplayName() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let catalogURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Demo")
            .appendingPathComponent("InfoPlist.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(TestStringCatalog.self, from: data)
        let localizations = try #require(catalog.strings["CFBundleDisplayName"]?.localizations)

        #expect(localizations["en"]?.stringUnit.value == "QuickLayoutKit Demo")
        #expect(localizations["zh-Hans"]?.stringUnit.value == "QuickLayoutKit 演示")
        #expect(localizations["ar"]?.stringUnit.value.isEmpty == false)
    }
}

private struct TestStringCatalog: Decodable {
    let strings: [String: TestStringCatalogEntry]
}

private struct TestStringCatalogEntry: Decodable {
    let localizations: [String: TestStringLocalization]?
}

private struct TestStringLocalization: Decodable {
    let stringUnit: TestStringUnit
}

private struct TestStringUnit: Decodable {
    let value: String
}
