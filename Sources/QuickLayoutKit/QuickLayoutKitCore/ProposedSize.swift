import CoreGraphics

/// 向元素提出的尺寸建议。
///
/// 维度为 `nil` 表示该轴未指定约束，元素应返回其理想长度。可以分别使用零和无穷大
/// 查询元素的最小尺寸和最大尺寸。
@frozen
public struct ProposedSize: Equatable, Sendable {

    /// 建议的水平尺寸；未指定时为 `nil`。
    public var width: CGFloat?

    /// 建议的垂直尺寸；未指定时为 `nil`。
    public var height: CGFloat?

    /// 两个维度均为零的尺寸建议。
    public static let zero = ProposedSize(width: 0, height: 0)

    /// 两个维度均为无穷大的尺寸建议。
    public static let infinity = ProposedSize(width: .infinity, height: .infinity)

    /// 两个维度均未指定的尺寸建议。
    public static let unspecified = ProposedSize(width: nil, height: nil)

    /// 使用可选维度创建尺寸建议。
    ///
    /// - Parameters:
    ///   - width: 建议的水平尺寸；传入 `nil` 表示不指定。
    ///   - height: 建议的垂直尺寸；传入 `nil` 表示不指定。
    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    /// 使用确定的尺寸创建尺寸建议。
    ///
    /// - Parameter size: 同时提供水平和垂直维度的尺寸。
    public init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    /// 使用备用尺寸中对应的维度替换未指定的维度。
    ///
    /// - Parameter size: 未指定维度使用的备用尺寸。
    /// - Returns: 不含未指定维度的确定尺寸。
    public func replacingUnspecifiedDimensions(
        by size: CGSize = CGSize(width: 10, height: 10)
    ) -> CGSize {
        CGSize(
            width: width ?? size.width,
            height: height ?? size.height
        )
    }
}

extension ProposedSize {

    /// 根据 QuickLayout 使用无穷大表示未指定约束的约定创建尺寸建议。
    init(quickLayoutProposal size: CGSize) {
        width = size.width.isFinite ? max(0, size.width) : nil
        height = size.height.isFinite ? max(0, size.height) : nil
    }

    var quickLayoutProposal: CGSize {
        CGSize(
            width: quickLayoutDimension(width),
            height: quickLayoutDimension(height)
        )
    }

    private func quickLayoutDimension(_ value: CGFloat?) -> CGFloat {
        guard let value else { return .infinity }
        guard !value.isNaN else { return 0 }
        return max(0, value)
    }
}
