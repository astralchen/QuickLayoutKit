import CoreGraphics

/// 用于记录 QuickLayoutKit 布局过程的调试诊断工具。
@MainActor
public enum QuickLayoutDiagnostics {

    /// 一次已记录的布局过程。
    public struct Entry: Equatable, Sendable {
        /// 与布局过程关联的类型名称或调用方名称。
        public let viewName: String

        /// 调用方报告的测量尺寸。
        public let measuredSize: CGSize
    }

    /// 指定时刻的诊断快照。
    public struct Snapshot: Equatable, Sendable {
        /// 所有已记录的布局条目。
        public let entries: [Entry]

        /// 已记录的布局次数。
        public var totalLayoutPasses: Int {
            entries.count
        }
    }

    /// 指示是否启用诊断记录的布尔值。
    public static var isEnabled = false

    private static var entries: [Entry] = []

    /// 在启用诊断时记录一次布局过程。
    ///
    /// - Parameters:
    ///   - viewName: 视图名称或调用方名称。
    ///   - measuredSize: 与布局过程关联的尺寸。
    public static func recordLayoutPass(for viewName: String, measuredSize: CGSize) {
        guard isEnabled else { return }
        entries.append(Entry(viewName: viewName, measuredSize: measuredSize))
    }

    /// 返回当前诊断快照。
    ///
    /// - Returns: 包含所有已记录布局条目的快照。
    public static func snapshot() -> Snapshot {
        Snapshot(entries: entries)
    }

    /// 移除所有已记录的诊断条目。
    public static func reset() {
        entries.removeAll()
    }
}
