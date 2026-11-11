import KarnakCore
import SwiftUI

/// What a box is painted with as the engine resolved it: a flat color, or a gradient or a mesh, which wins when both
/// exist (`docs/renderer-contract.md`, Paints).
enum PaintTarget: Equatable {
  case flat(DrawnColor)
  case gradient(ResolvedPaintGradient)
  case mesh(ResolvedPaintMesh)

  /// The target of a `color` with an optional `shaded` gradient or mesh; nil for no paint at all.
  static func of(color: Argb?, shaded: ResolvedPaintShaded?) -> PaintTarget? {
    if let shaded { return of(shaded) }
    return color.map { .flat(DrawnColor($0)) }
  }

  /// The target a resolved paint draws as.
  static func of(_ paint: ResolvedPaint) -> PaintTarget {
    switch paint {
    case let gradient as ResolvedPaintGradient: .gradient(gradient)
    case let mesh as ResolvedPaintMesh: .mesh(mesh)
    default: .flat(DrawnColor(paint.fallback))
    }
  }

  /// The color of a flat target, or the fallback of a gradient or a mesh.
  var flat: DrawnColor {
    switch self {
    case .flat(let color): color
    case .gradient(let paint): DrawnColor(paint.fallback)
    case .mesh(let paint): DrawnColor(paint.fallback)
    }
  }

  /// What the target draws at rest: a gradient's expanded stops, or a mesh's raster.
  func frame(alpha: Double = 1) -> PaintFrame {
    switch self {
    case .flat(let color): PaintFrame(color: color, spec: nil, alpha: alpha)
    case .gradient(let paint): PaintFrame(color: nil, spec: GradientSpec(paint), alpha: alpha)
    case .mesh(let paint): PaintFrame(color: nil, spec: nil, mesh: MeshImage(paint), alpha: alpha)
    }
  }

  static func == (lhs: PaintTarget, rhs: PaintTarget) -> Bool {
    switch (lhs, rhs) {
    case (.flat(let a), .flat(let b)): a == b
    case (.gradient(let a), .gradient(let b)): (a as AnyObject).isEqual(b)
    case (.mesh(let a), .mesh(let b)): a.isEqual(b)
    default: false
    }
  }
}

/// One frame of a paint, ready to draw: a flat `color`, a gradient `spec` or a `mesh`, drawn at `alpha`.
struct PaintFrame: Equatable {
  var color: DrawnColor?
  var spec: GradientSpec?
  var mesh: MeshImage?
  var alpha = 1.0

  /// The paint `fraction` of the way from `from` to `to` (`docs/renderer-contract.md`, Paints, the Oklab mix of a
  /// transition). A missing side fades the other in or out; two gradients of one kind and stop count mix stop by
  /// stop, and two meshes of one grid point by point (`PaintMath.meshMix`: the engine draws each frame); anything
  /// else mixes the flat colors on the way and is the paint itself at either end.
  static func mix(_ from: PaintTarget?, _ to: PaintTarget?, fraction: Double) -> PaintFrame? {
    switch (from, to) {
    case (nil, nil): nil
    case (nil, let to?): to.frame(alpha: fraction)
    case (let from?, nil): from.frame(alpha: 1 - fraction)
    case (let from?, let to?): mixed(from, to, fraction)
    }
  }

  private static func gradientMix(
    _ from: PaintTarget, _ to: PaintTarget, _ fraction: Double
  ) -> GradientSpec? {
    guard case .gradient(let a) = from, case .gradient(let b) = to else { return nil }
    return GradientSpec.mix(a, b, fraction: fraction)
  }

  private static func meshMix(
    _ from: PaintTarget, _ to: PaintTarget, _ fraction: Double
  ) -> MeshImage? {
    guard case .mesh(let a) = from, case .mesh(let b) = to else { return nil }
    return PaintMath.shared.meshMix(from: a, to: b, fraction: fraction).map(MeshImage.init)
  }

  private static func mixed(
    _ from: PaintTarget, _ to: PaintTarget, _ fraction: Double
  ) -> PaintFrame {
    if let spec = gradientMix(from, to, fraction) { return PaintFrame(color: nil, spec: spec) }
    if let mesh = meshMix(from, to, fraction) {
      return PaintFrame(color: nil, spec: nil, mesh: mesh)
    }
    if fraction <= 0 { return from.frame() }
    if fraction >= 1 { return to.frame() }
    return PaintFrame(
      color: DrawnColor.oklabMix(from.flat, to.flat, fraction: fraction), spec: nil)
  }
}

extension ResolvedLayout {
  /// What the node's background paints: its gradient or mesh, or its flat color.
  var backgroundTarget: PaintTarget? {
    PaintTarget.of(color: background, shaded: backgroundPaint)
  }

  /// The node's transition of `field`, if it has one with a duration.
  func transition(of field: String) -> ResolvedTransition? {
    transitions.first { $0.field == field && $0.durationMillis > 0 }
  }
}

extension PaintTarget {
  /// The color of a flat target, nil for a gradient or a mesh.
  var flatColor: Color? {
    if case .flat(let color) = self { color.color } else { nil }
  }
}
