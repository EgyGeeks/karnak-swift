import KarnakCore
import SwiftUI

/// The paths of a canvas's shape ops in view-box units, written from the top and clockwise, so that a `trim` starts
/// where the other renderers' does.
enum CanvasGeometry {
  /// The outline of `op` at this frame.
  /// With `pie`, an arc closes through its center, as a fill needs.
  static func path(of op: ResolvedDrawOpShape, values: DrawValues, pie: Bool = false) -> Path {
    switch op {
    case let rect as ResolvedDrawOpRect: roundedRect(rect, values)
    case let circle as ResolvedDrawOpCircle:
      ellipse(
        in: CGRect(
          center: values.point(circle.center), radius: values.number(circle.radius)))
    case let oval as ResolvedDrawOpOval:
      ellipse(in: CGRect(origin: values.point(oval.at), size: values.size(oval.size)))
    case let arc as ResolvedDrawOpArc: arcPath(arc, values, pie: pie)
    case let line as ResolvedDrawOpLine:
      Path {
        $0.move(to: values.point(line.from))
        $0.addLine(to: values.point(line.to))
      }
    case let path as ResolvedDrawOpPath: Path(commands: path.commands)
    default: Path()
    }
  }

  /// Whether the shape has an inside a fill covers: a line has none.
  static func isFillable(_ op: ResolvedDrawOpShape) -> Bool { !(op is ResolvedDrawOpLine) }

  private static func roundedRect(_ rect: ResolvedDrawOpRect, _ values: DrawValues) -> Path {
    let box = CGRect(origin: values.point(rect.at), size: values.size(rect.size))
    let radius = values.number(rect.radius)
    return radius > 0
      ? Path(roundedRect: box, cornerRadius: radius, style: .circular) : Path(box)
  }

  /// An ellipse in `box`, from the top and clockwise: the unit circle scaled into the box.
  static func ellipse(in box: CGRect) -> Path {
    unitCircle(in: box)
  }

  private static func unitCircle(in box: CGRect) -> Path {
    var circle = Path()
    circle.addArc(
      center: .zero, radius: 1, startAngle: .degrees(-90), endAngle: .degrees(270),
      clockwise: false)
    circle.closeSubpath()
    return circle.applying(
      CGAffineTransform(translationX: box.midX, y: box.midY).scaledBy(
        x: box.width / 2, y: box.height / 2))
  }

  /// The arc that starts `start` degrees from the top and sweeps clockwise; a fill closes it through the center.
  private static func arcPath(_ arc: ResolvedDrawOpArc, _ values: DrawValues, pie: Bool) -> Path {
    let center = values.point(arc.center)
    let start = values.number(arc.start) - 90
    return Path {
      if pie { $0.move(to: center) }
      $0.addArc(
        center: center, radius: values.number(arc.radius), startAngle: .degrees(start),
        endAngle: .degrees(start + values.number(arc.sweep)), clockwise: false)
    }
  }
}

extension DrawValues {
  /// The size `point` names at this frame.
  func size(_ point: ResolvedPoint) -> CGSize {
    CGSize(width: number(point.x), height: number(point.y))
  }
}

extension CGRect {
  /// The square of `radius` around `center`.
  init(center: CGPoint, radius: CGFloat) {
    self.init(
      x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
  }
}
