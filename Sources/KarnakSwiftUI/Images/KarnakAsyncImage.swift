import SwiftUI

/// The renderer supplies the resolved placeholder and a box sized before image loading. The placeholder fills the box
/// while loading and on failure only.
struct KarnakAsyncImage: View {
  let url: URL
  var loader: any KarnakImageLoader = URLSessionImageLoader.shared
  let placeholder: Color
  /// How the image fits its box; nil stretches it to the box (`contentScale` `fill`).
  var contentMode: ContentMode? = .fit
  @Environment(\.displayScale) private var displayScale
  @State private var loaded: LoadedImage?

  var body: some View {
    GeometryReader { geometry in
      let request = ImageViewRequest(
        url: url, boxSize: geometry.size, displayScale: displayScale, contentMode: contentMode)
      let image = shownImage(for: request)
      // The placeholder is the box while it has no pixels: once an image is drawn, its transparent pixels and a `fit`
      // image's letterbox bands show what is under the node (`docs/renderer-contract.md`, image; #3583).
      (image == nil ? placeholder : Color.clear).overlay {
        if let image {
          Image(decorative: image, scale: displayScale)
            .resizable()
            .keepingAspectRatio(contentMode)
        }
      }
      .clipped()
      .task(id: request.key) {
        guard request.key != nil,
          let image = await loader.image(
            for: url, targetPixelSize: request.pixelSize, scaling: request.scaling),
          !Task.isCancelled
        else { return }
        loaded = LoadedImage(url: url, image: image)
      }
    }
  }

  /// A kept decode at this exact size shows in the first frame, with no placeholder flash;
  /// otherwise the last image loaded for this URL, at whatever size.
  private func shownImage(for request: ImageViewRequest) -> CGImage? {
    loader.cachedImage(for: url, targetPixelSize: request.pixelSize, scaling: request.scaling)
      ?? loaded?.image(for: url)
  }
}

extension View {
  /// Keeps the image's aspect ratio within its frame by `contentMode`; nil stretches it.
  @ViewBuilder
  fileprivate func keepingAspectRatio(_ contentMode: ContentMode?) -> some View {
    if let contentMode { aspectRatio(contentMode: contentMode) } else { self }
  }
}
