import SwiftUI

/// A paint drawn over a shape: a flat color or a gradient laid out over the shape's box. A `Canvas` draws it, so a
/// frame of a transition costs one draw and no layout.
struct PaintedFill: View, @preconcurrency Animatable {
  /// What the box is painted with before the transition (or at rest, when nothing moves).
  var from: PaintTarget?
  /// What the box is painted with after it.
  var to: PaintTarget?
  /// How far the box has moved from `from` to `to`, from 0 to 1.
  var progress = 1.0
  /// The shape the paint fills.
  let shape: NodeShape

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    Canvas { context, size in
      let box = CGRect(origin: .zero, size: size)
      PaintFrame.mix(from, to, fraction: progress)?
        .fill(shape.path(in: box), in: box, context: context)
    }
  }
}

/// A paint along a shape's inside edge, for a border.
struct PaintedStroke: View {
  let target: PaintTarget
  let shape: NodeShape
  /// The line's width in points.
  let width: CGFloat

  var body: some View {
    Canvas { context, size in
      let box = CGRect(origin: .zero, size: size)
      let line = shape.inset(by: width / 2).path(in: box)
      target.frame().stroke(line, style: StrokeStyle(lineWidth: width), in: box, context: context)
    }
  }
}
