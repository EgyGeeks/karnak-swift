import KarnakCore
import SwiftUI

/// What a draw of a canvas shares between its ops (`docs/renderer-contract.md`, Canvas): the values at this frame, the
/// view box gradients are laid out over, and what text and images are drawn with.
struct CanvasFrame {
  var values: DrawValues
  /// The view box, over which gradients are laid out.
  let bounds: CGRect
  /// The view box's scale to the node's box, which a `text` op undoes: text is never scaled.
  var scale = CGSize(width: 1, height: 1)
  /// Whether the whole drawing is flipped horizontally; a `text` op flips itself back.
  var mirrored = false
  /// The layout direction, which `start` and `end` text alignment follow.
  var rightToLeft = false
  /// How a text op's font is made, per Dynamic Type and the theme fonts that are ready.
  let font: (ResolvedFont) -> Font
  /// The loaded image of an `image` op, by URL.
  let image: (String) -> CGImage?
}

/// Draws the ops of a canvas into a `GraphicsContext`, in view-box units, in order.
struct CanvasPainter {
  let frame: CanvasFrame

  /// Draws `ops` at `alpha`, a group's opacity that multiplies into each child's.
  func draw(_ ops: [ResolvedDrawOp], into context: inout GraphicsContext, alpha: CGFloat = 1) {
    for op in ops { draw(op, into: &context, alpha: alpha) }
  }

  private func draw(_ op: ResolvedDrawOp, into context: inout GraphicsContext, alpha: CGFloat) {
    let opacity = alpha * frame.values.number(op.alpha)
    guard opacity > 0 else { return }
    switch op {
    case let shape as ResolvedDrawOpShape: drawShape(shape, into: context, opacity: opacity)
    case let text as ResolvedDrawOpText: drawText(text, into: context, opacity: opacity)
    case let image as ResolvedDrawOpImage: drawImage(image, into: context, opacity: opacity)
    case let group as ResolvedDrawOpGroup: drawGroup(group, into: &context, opacity: opacity)
    default: break
    }
  }

  private func drawShape(
    _ op: ResolvedDrawOpShape, into context: GraphicsContext, opacity: CGFloat
  ) {
    var layer = context
    layer.opacity *= opacity
    let values = frame.values
    if let fill = op.fill, CanvasGeometry.isFillable(op) {
      values.frame(of: fill).fill(
        CanvasGeometry.path(of: op, values: values, pie: true), in: frame.bounds, context: layer)
    }
    guard let stroke = op.stroke else { return }
    var outline = CanvasGeometry.path(of: op, values: values)
    if let trim = op.trim {
      outline = outline.trimmedPath(
        from: min(max(values.number(trim.from), 0), 1), to: min(max(values.number(trim.to), 0), 1))
    }
    values.frame(of: stroke.paint).stroke(
      outline, style: strokeStyle(stroke), in: frame.bounds, context: layer)
  }

  private func strokeStyle(_ stroke: ResolvedStroke) -> StrokeStyle {
    StrokeStyle(
      lineWidth: frame.values.number(stroke.width), lineCap: stroke.cap.cgLineCap,
      lineJoin: stroke.join.cgLineJoin, dash: stroke.dash.map { CGFloat($0.doubleValue) })
  }

  private func drawGroup(
    _ group: ResolvedDrawOpGroup, into context: inout GraphicsContext, opacity: CGFloat
  ) {
    var inner = context
    if let transform = group.transform { apply(transform, to: &inner) }
    if let clip = group.clip { apply(clip, to: &inner) }
    draw(group.draw, into: &inner, alpha: opacity)
  }

  private func apply(_ transform: ResolvedTransform, to context: inout GraphicsContext) {
    let values = frame.values
    if let move = transform.translate {
      context.translateBy(x: values.number(move.x), y: values.number(move.y))
    }
    let pivot = transform.origin.map(values.point) ?? .zero
    if let rotate = transform.rotate {
      context.translateBy(x: pivot.x, y: pivot.y)
      context.rotate(by: .degrees(values.number(rotate)))
      context.translateBy(x: -pivot.x, y: -pivot.y)
    }
    if let scale = transform.scale {
      let factor = values.number(scale)
      context.translateBy(x: pivot.x, y: pivot.y)
      context.scaleBy(x: factor, y: factor)
      context.translateBy(x: -pivot.x, y: -pivot.y)
    }
  }

  private func apply(_ clip: ResolvedClip, to context: inout GraphicsContext) {
    let values = frame.values
    switch clip {
    case let rect as ResolvedClipRect:
      let box = CGRect(origin: values.point(rect.at), size: values.size(rect.size))
      let radius = values.number(rect.radius)
      context.clip(
        to: radius > 0 ? Path(roundedRect: box, cornerRadius: radius, style: .circular) : Path(box))
    case let circle as ResolvedClipCircle:
      context.clip(
        to: CanvasGeometry.ellipse(
          in: CGRect(center: values.point(circle.center), radius: values.number(circle.radius))))
    case let path as ResolvedClipPath:
      context.clip(to: Path(commands: path.commands))
    default: break
    }
  }
}
