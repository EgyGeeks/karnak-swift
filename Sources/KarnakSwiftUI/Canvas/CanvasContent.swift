import KarnakCore
import SwiftUI

/// The draw ops that put glyphs and pixels on a canvas: `text` and `image`.
extension CanvasPainter {
  /// A `text` op: laid out at the platform's text scale, anchored at its point, with the view box's scale and the
  /// mirroring undone about the anchor, so that text is neither scaled nor mirrored with the drawing.
  func drawText(_ op: ResolvedDrawOpText, into context: GraphicsContext, opacity: CGFloat) {
    var layer = context
    layer.opacity *= opacity
    let anchor = frame.values.point(op.at)
    var resolved = layer.resolve(Text(verbatim: op.text).font(frame.font(op.font)))
    let room = CGSize(width: CGFloat.infinity, height: .infinity)
    let width = resolved.measure(in: room).width
    let left: CGFloat =
      switch op.align {
      case .center: -width / 2
      case .end: frame.rightToLeft ? 0 : -width
      default: frame.rightToLeft ? -width : 0
      }
    layer.translateBy(x: anchor.x, y: anchor.y)
    layer.scaleBy(
      x: (frame.mirrored ? -1 : 1) / frame.scale.width, y: 1 / frame.scale.height)
    let spot = CGRect(
      x: -anchor.x, y: -anchor.y, width: frame.bounds.width, height: frame.bounds.height)
    let fill = frame.values.frame(of: op.fill)
    if let color = fill.color {
      resolved.shading = .color(color.color.opacity(fill.alpha))
    } else if let spec = fill.spec {
      resolved.shading = spec.shading(in: spot, circular: false)
    }
    // The anchor is on the first baseline, as on the other renderers.
    layer.draw(
      resolved, at: CGPoint(x: left, y: -resolved.firstBaseline(in: room)), anchor: .topLeading)
  }

  /// An `image` op: the loaded image in its box by the op's `contentScale`, clipped to the box. An image still loading,
  /// or one that failed, draws nothing.
  func drawImage(_ op: ResolvedDrawOpImage, into context: GraphicsContext, opacity: CGFloat) {
    guard let image = frame.image(op.url) else { return }
    var layer = context
    layer.opacity *= opacity
    let box = CGRect(origin: frame.values.point(op.at), size: frame.values.size(op.size))
    let source = CGSize(width: image.width, height: image.height)
    let drawn = fitted(source, in: box.size, mode: op.contentScale)
    layer.clip(to: Path(box))
    layer.draw(
      Image(decorative: image, scale: 1),
      in: CGRect(
        x: box.minX + (box.width - drawn.width) / 2, y: box.minY + (box.height - drawn.height) / 2,
        width: drawn.width, height: drawn.height))
  }
}

/// The size `source` is drawn at inside `box`: `fit` keeps the aspect ratio inside, `crop` covers, `fill` stretches.
func fitted(_ source: CGSize, in box: CGSize, mode: ContentScale) -> CGSize {
  let x = box.width / source.width
  let y = box.height / source.height
  switch mode {
  case .fit:
    let side = min(x, y)
    return CGSize(width: source.width * side, height: source.height * side)
  case .crop:
    let side = max(x, y)
    return CGSize(width: source.width * side, height: source.height * side)
  default: return box
  }
}

extension StrokeCap {
  var cgLineCap: CGLineCap {
    switch self {
    case .round: .round
    case .square: .square
    default: .butt
    }
  }
}

extension StrokeJoin {
  var cgLineJoin: CGLineJoin {
    switch self {
    case .round: .round
    case .bevel: .bevel
    default: .miter
    }
  }
}
