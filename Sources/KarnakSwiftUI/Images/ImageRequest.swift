import CoreGraphics
import Foundation

/// A validated load: the coalescing key for in-flight work and the downsampler's pixel target.
struct ImageRequest: Hashable, Sendable {
  /// The largest accepted pixel dimension; larger layout input is rejected before any load.
  static let maxPixelDimension = 16_384

  let url: URL
  let width: Int
  let height: Int
  let scaling: KarnakImageScaling

  init?(url: URL, size: CGSize, scaling: KarnakImageScaling) {
    let limit = CGFloat(Self.maxPixelDimension)
    // Reject invalid/oversized layout input before converting floating point values to integers.
    guard size.width.isFinite, size.height.isFinite,
      size.width > 0, size.height > 0, size.width <= limit, size.height <= limit
    else { return nil }
    self.url = url
    self.scaling = scaling
    width = Int(size.width.rounded(.up))
    height = Int(size.height.rounded(.up))
  }
}
