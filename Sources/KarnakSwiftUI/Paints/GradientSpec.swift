import KarnakCore
import SwiftUI

/// One stop of a gradient at rest or at a frame of a transition: a color with its offset along the gradient.
struct PaintStop: Equatable {
  /// The color, as `#AARRGGBB` bits.
  let color: DrawnColor
  /// Where the stop sits, from 0 to 1.
  let offset: Double
}

/// A color the paints draw, as the engine's `Argb` bits: the one value type a gradient, a flat fill and a transition
/// frame share, `Equatable` so a view that holds one compares cheaply.
struct DrawnColor: Equatable {
  /// The `#AARRGGBB` bits.
  let bits: UInt32

  init(bits: UInt32) { self.bits = bits }

  init(_ argb: Argb) { bits = UInt32(bitPattern: argb.value) }

  /// The color in SwiftUI, in sRGB.
  var color: Color { resolvedColor(argb: Int32(bitPattern: bits)) }

  /// The engine's value, for `PaintMath`.
  var argb: Argb { Argb(value: Int32(bitPattern: bits)) }
}

/// A gradient ready to draw (`docs/renderer-contract.md`, Paints): the kind, its geometry as the wire gives it and the
/// stops. ``init(_:)`` keeps the engine's expanded stops, so a gradient at rest draws what the premultiplied mix gives;
/// ``mix(_:_:fraction:)`` is one frame of a transition and mixes the wire stops in Oklab with the engine's own
/// `PaintMath.oklabLerp`, so the three renderers agree within 1/255.
struct GradientSpec: Equatable {
  /// The kinds of gradient.
  enum Kind: Equatable {
    case linear, radial, sweep
  }

  let kind: Kind
  /// A linear gradient's angle, or a sweep's start, in degrees (`0` at the top, clockwise).
  let angle: Double
  /// A radial or sweep center, as fractions of the width and the height.
  let center: CGPoint
  /// A radial gradient's radius as a fraction of the half-sides.
  let radius: Double
  let stops: [PaintStop]

  /// The gradient `paint` draws at rest: its expanded stops.
  init(_ paint: ResolvedPaintGradient) { self.init(paint, stops: paint.stops) }

  private init(_ paint: ResolvedPaintGradient, stops drawn: [ResolvedStop]) {
    let stops = drawn.map { PaintStop(color: DrawnColor($0.color), offset: $0.offset) }
    switch paint {
    case let linear as ResolvedPaintLinear:
      self.init(kind: .linear, angle: linear.angle, center: .zero, radius: 0, stops: stops)
    case let radial as ResolvedPaintRadial:
      self.init(
        kind: .radial, angle: 0, center: CGPoint(x: radial.centerX, y: radial.centerY),
        radius: radial.radius, stops: stops)
    case let sweep as ResolvedPaintSweep:
      self.init(
        kind: .sweep, angle: sweep.angle, center: CGPoint(x: sweep.centerX, y: sweep.centerY),
        radius: 0, stops: stops)
    default:
      self.init(kind: .linear, angle: 180, center: .zero, radius: 0, stops: stops)
    }
  }

  init(kind: Kind, angle: Double, center: CGPoint, radius: Double, stops: [PaintStop]) {
    self.kind = kind
    self.angle = angle
    self.center = center
    self.radius = radius
    self.stops = stops
  }

  /// The gradient `fraction` of the way from `from` to `to`, or nil when the two aren't the same kind with the same
  /// number of wire stops, which a caller mixes as flat fallback colors. Geometry mixes numerically and the stops in
  /// Oklab, then `PaintMath.expandStops` expands the frame as the contract asks.
  static func mix(
    _ from: ResolvedPaintGradient, _ to: ResolvedPaintGradient, fraction: Double
  ) -> GradientSpec? {
    let start = GradientSpec(from, stops: from.wireStops)
    let end = GradientSpec(to, stops: to.wireStops)
    guard start.kind == end.kind, start.stops.count == end.stops.count else { return nil }
    let t = min(max(fraction, 0), 1)
    let wire = zip(start.stops, end.stops).map { a, b in
      ResolvedStop.companion.invoke(
        color: DrawnColor.oklabMix(a.color, b.color, fraction: t).argb,
        offset: Self.mixed(a.offset, b.offset, t))
    }
    return GradientSpec(
      kind: start.kind, angle: Self.mixed(start.angle, end.angle, t),
      center: CGPoint(
        x: Self.mixed(start.center.x, end.center.x, t),
        y: Self.mixed(start.center.y, end.center.y, t)),
      radius: Self.mixed(start.radius, end.radius, t),
      stops: PaintMath.shared.expandStops(stops: wire).map {
        PaintStop(color: DrawnColor($0.color), offset: $0.offset)
      })
  }

  private static func mixed<Value: BinaryFloatingPoint>(
    _ from: Value, _ to: Value, _ t: Double
  ) -> Value {
    from + (to - from) * Value(t)
  }

  /// The stops as a SwiftUI `Gradient`.
  var gradient: Gradient {
    Gradient(stops: stops.map { Gradient.Stop(color: $0.color.color, location: $0.offset) })
  }
}

extension DrawnColor {
  /// The Oklab mix of a transition or a loop (`PaintMath.oklabLerp`, the engine's one implementation).
  static func oklabMix(_ from: DrawnColor, _ to: DrawnColor, fraction: Double) -> DrawnColor {
    DrawnColor(PaintMath.shared.oklabLerp(from: from.argb, to: to.argb, fraction: fraction))
  }
}
