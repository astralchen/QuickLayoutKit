import AppLocalization

extension Gift {
    /// 礼物当前语言的显示名称。
    ///
    /// 优先使用 `titleKey` 对应的翻译，缺少翻译时将 `sourceName` 作为本地化解析器的回退文案。
    @MainActor
    var localizedTitle: String {
        Localization.resolver.string(titleKey, fallbackValue: sourceName)
    }
}
