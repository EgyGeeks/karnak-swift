import KarnakCore
import SwiftUI

/// The images of a canvas's `image` ops, by URL, as the host's loader decoded them. A draw reads them.
@Observable
@MainActor
final class CanvasImages {
  private var loaded: [String: CGImage] = [:]

  /// The loaded image of `url`; an image still loading, or one that failed, has none.
  func image(for url: String) -> CGImage? { loaded[url] }

  /// Loads the images of `canvas` at the size they are drawn, in pixels: the view box's scale to the node's box
  /// decides it.
  func load(
    _ canvas: ResolvedCanvas, box: CGSize, scale: CGFloat, loader: KarnakImageLoader
  ) async {
    guard box.width > 0, box.height > 0 else { return }
    let ratio = CanvasView.scale(
      canvas.contentScale,
      viewBox: CGSize(width: canvas.viewBoxWidth, height: canvas.viewBoxHeight),
      box: box)
    for op in canvas.draw.flatMap(Self.imageOps) {
      guard let url = httpsURL(op.url) else { continue }
      let target = CGSize(
        width: max(1, (op.size.x.atRest * ratio.width * scale).rounded()),
        height: max(1, (op.size.y.atRest * ratio.height * scale).rounded()))
      let scaling: KarnakImageScaling = op.contentScale == .fit ? .fit : .fill
      if let image = await loader.image(for: url, targetPixelSize: target, scaling: scaling) {
        loaded[op.url] = image
      }
    }
  }

  private static func imageOps(_ op: ResolvedDrawOp) -> [ResolvedDrawOpImage] {
    switch op {
    case let image as ResolvedDrawOpImage: [image]
    case let group as ResolvedDrawOpGroup: group.draw.flatMap(imageOps)
    default: []
    }
  }
}
