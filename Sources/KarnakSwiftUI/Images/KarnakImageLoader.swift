import CoreGraphics
import Foundation

/// An image adapter independent of the shared engine. Implementations must be safe for concurrent use.
public protocol KarnakImageLoader: Sendable {
  /// Decodes an orientation-correct image at the target pixel size, preserving aspect ratio and
  /// never upscaling. `scaling` says which dimension bounds the result. Callers multiply layout
  /// points by display scale. Invalid input and failures return nil.
  /// Task cancellation releases this caller's interest in the load and returns nil.
  func image(for url: URL, targetPixelSize: CGSize, scaling: KarnakImageScaling) async -> CGImage?

  /// A decoded image the loader already holds for these arguments, returned synchronously so a
  /// view can show it in its first frame instead of a placeholder. Never loads or decodes, so it
  /// is cheap enough to call while rendering; nil when nothing is held. Defaults to nil.
  func cachedImage(for url: URL, targetPixelSize: CGSize, scaling: KarnakImageScaling) -> CGImage?
}

extension KarnakImageLoader {
  /// No synchronous cache: views show their placeholder until `image(for:targetPixelSize:scaling:)`
  /// returns.
  public func cachedImage(
    for url: URL, targetPixelSize: CGSize, scaling: KarnakImageScaling
  ) -> CGImage? {
    nil
  }
}

/// How a decoded image relates to its target pixel box.
public enum KarnakImageScaling: Hashable, Sendable {
  /// The image fits inside the box: both dimensions are at most the target. Use it for images the
  /// view letterboxes (`contentScale` `fit`).
  case fit
  /// The image covers the box: both dimensions are at least the target, unless the source is
  /// smaller. Use it for images the view crops or stretches (`contentScale` `crop` or `fill`).
  case fill
}
