import AppLocalization

extension Gift {
    /// 优先使用现有翻译；配置新增礼物缺少翻译时展示配置原名，避免显示内部键。
    @MainActor
    var localizedTitle: String {
        Localization.resolver.string(titleKey, fallbackValue: sourceName)
    }
}
