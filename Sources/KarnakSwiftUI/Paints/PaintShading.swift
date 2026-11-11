import CoreGraphics
import KarnakCore
import SwiftUI

extension PaintFrame {
  /// Fills `path` with the paint, laid out over `box`: a gradient's line spans the box so that its corners take the
  /// first and last stop (`PaintMath.linearEndpoints`). A radial gradient of a box that isn't square is an ellipse;
  /// a mesh is stretched over the box.
  func fill(_ path: Path, in box: CGRect, context: GraphicsContext) {
    var layer = context
    layer.opacity *= alpha
    if let color {
      layer.fill(path, with: .color(color.color))
    } else if let spec {
      spec.fill(path, in: box, context: layer)
    } else if let mesh {
      mesh.fill(path, in: box, context: layer)
    }
  }

  /// Strokes `path` with the paint, laid out over `box`.
  func stroke(_ path: Path, style: StrokeStyle, in box: CGRect, context: GraphicsContext) {
    var layer = context
    layer.opacity *= alpha
    if let color {
      layer.stroke(path, with: .color(color.color), style: style)
    } else if let spec {
      // A stroke has no ellipse of its own: a radial gradient reaches the mean of the half-sides.
      layer.stroke(path, with: spec.shading(in: box, circular: true), style: style)
    } else if let mesh {
      mesh.fill(path.strokedPath(style), in: box, context: layer)
    }
  }
}

extension GradientSpec {
  fileprivate func fill(_ path: Path, in box: CGRect, context: GraphicsContext) {
    guard kind == .radial, box.width > 0, box.height > 0, box.width != box.height else {
      context.fill(path, with: shading(in: box, circular: false))
      return
    }
    // The circle that reaches the sides horizontally, scaled about its center by `height ÷ width`, reaches the top and
    // the bottom too.
    let origin = centerPoint(in: box)
    let scale = CGAffineTransform(translationX: origin.x, y: origin.y)
      .scaledBy(x: 1, y: box.height / box.width).translatedBy(x: -origin.x, y: -origin.y)
    var scaled = context
    scaled.concatenate(scale)
    scaled.fill(
      path.applying(scale.inverted()),
      with: .radialGradient(
        gradient, center: origin, startRadius: 0,
        endRadius: max(radius * box.width / 2, minimumRadius)))
  }

  /// The shading of the gradient over `box`. With `circular`, a radial gradient reaches the mean of the half-sides.
  func shading(in box: CGRect, circular: Bool) -> GraphicsContext.Shading {
    switch kind {
    case .linear:
      let ends = PaintMath.shared.linearEndpoints(
        width: box.width, height: box.height, angleDegrees: angle)
      return .linearGradient(
        gradient, startPoint: CGPoint(x: box.minX + ends.startX, y: box.minY + ends.startY),
        endPoint: CGPoint(x: box.minX + ends.endX, y: box.minY + ends.endY))
    case .radial:
      let reach = circular ? (box.width + box.height) / 4 : box.width / 2
      return .radialGradient(
        gradient, center: centerPoint(in: box), startRadius: 0,
        endRadius: max(radius * reach, minimumRadius))
    case .sweep:
      // A conic gradient starts at 3 o'clock; the wire's `0` is at the top.
      return .conicGradient(
        gradient, center: centerPoint(in: box), angle: .degrees(angle - 90))
    }
  }

  private func centerPoint(in box: CGRect) -> CGPoint {
    CGPoint(x: box.minX + center.x * box.width, y: box.minY + center.y * box.height)
  }

  private var minimumRadius: Double { 0.01 }
}
