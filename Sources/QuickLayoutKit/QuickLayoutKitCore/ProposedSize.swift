import CoreGraphics

/// A proposal for the size of an element.
///
/// A `nil` dimension is unspecified and asks an element for its ideal length
/// on that axis. Zero and infinity can be used to query an element's minimum
/// and maximum sizes respectively.
@frozen
public struct ProposedSize: Equatable, Sendable {

    /// The proposed horizontal size, or `nil` when it is unspecified.
    public var width: CGFloat?

    /// The proposed vertical size, or `nil` when it is unspecified.
    public var height: CGFloat?

    /// A proposal containing zero in both dimensions.
    public static let zero = ProposedSize(width: 0, height: 0)

    /// A proposal containing infinity in both dimensions.
    public static let infinity = ProposedSize(width: .infinity, height: .infinity)

    /// A proposal with both dimensions unspecified.
    public static let unspecified = ProposedSize(width: nil, height: nil)

    /// Creates a proposal from optional dimensions.
    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    /// Creates a proposal from a concrete size.
    public init(_ size: CGSize) {
        width = size.width
        height = size.height
    }

    /// Replaces unspecified dimensions with the corresponding fallback
    /// dimension.
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

    /// QuickLayout represents an unspecified constraint with infinity.
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
