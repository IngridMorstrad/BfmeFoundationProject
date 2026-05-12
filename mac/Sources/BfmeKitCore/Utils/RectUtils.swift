import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A Foundation-only 2D size used on Linux where CoreGraphics is absent.
public struct SizeF: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum RectUtils {
    /// Uniformly scales `sourceSize` to fit inside `targetSize`, preserving
    /// the source aspect ratio. Mirrors the C# `RectUtils.ResizeToFit`.
    public static func resizeToFit(sourceSize: SizeF, targetSize: SizeF) -> SizeF {
        let widthScale = targetSize.width / sourceSize.width
        let heightScale = targetSize.height / sourceSize.height
        let scale = min(widthScale, heightScale)
        return SizeF(width: sourceSize.width * scale, height: sourceSize.height * scale)
    }

    #if canImport(CoreGraphics)
    public static func resizeToFit(sourceSize: CGSize, targetSize: CGSize) -> CGSize {
        let resized = resizeToFit(
            sourceSize: SizeF(width: Double(sourceSize.width), height: Double(sourceSize.height)),
            targetSize: SizeF(width: Double(targetSize.width), height: Double(targetSize.height))
        )
        return CGSize(width: resized.width, height: resized.height)
    }
    #endif
}
