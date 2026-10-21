import SwiftUI

/// What `KarnakAsyncImage` asks its loader for, derived from its laid-out box.
struct ImageViewRequest: Equatable {
  let url: URL
  /// The box in pixels: layout points times display scale.
  let pixelSize: CGSize
  /// A filled (cropped or stretched) box needs a bitmap that covers it, not one that fits inside.
  let scaling: KarnakImageScaling

  /// `contentMode` nil stretches the image to the box, which, like `.fill`, needs a bitmap
  /// that covers it.
  init(url: URL, boxSize: CGSize, displayScale: CGFloat, contentMode: ContentMode?) {
    self.url = url
    pixelSize = CGSize(width: boxSize.width * displayScale, height: boxSize.height * displayScale)
    scaling = contentMode == .fit ? .fit : .fill
  }

  /// Identifies the load, so the view reloads only when this changes: sizes that round to the
  /// same pixels share a key. Nil when the loader would reject the size, which skips loading.
  var key: ImageRequest? { ImageRequest(url: url, size: pixelSize, scaling: scaling) }
}

/// A decoded image and the URL it came from.
struct LoadedImage {
  let url: URL
  let image: CGImage

  /// The image, but only for its own URL: an image of the previous URL is never shown, while one
  /// of this URL stays through size changes.
  func image(for url: URL) -> CGImage? { self.url == url ? image : nil }
}
