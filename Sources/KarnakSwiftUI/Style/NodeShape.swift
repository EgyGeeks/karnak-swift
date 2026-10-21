import SwiftUI

/// The rounded box that a node's background, border, shadows and clip share. The radius clamps
/// to half the shorter side, so a large radius draws a capsule.
struct NodeShape: InsettableShape {
  /// The corner radius in points before clamping.
  var radius: CGFloat
  /// How far the shape is inset from its frame; negative values grow it, as a shadow's spread.
  var inset: CGFloat = 0

  func path(in rect: CGRect) -> Path {
    let box = rect.insetBy(dx: inset, dy: inset)
    guard box.width > 0, box.height > 0 else { return Path() }
    let corner = min(max(0, radius - inset), min(box.width, box.height) / 2)
    return Path(roundedRect: box, cornerRadius: corner, style: .circular)
  }

  func inset(by amount: CGFloat) -> NodeShape {
    NodeShape(radius: radius, inset: inset + amount)
  }
}

/// A node's hit area: its box, grown to at least a `minimum` square centered on it
/// (`docs/renderer-contract.md`, `touchTarget`), without growing the drawn box.
struct TouchTargetShape: Shape {
  /// The touch target's side in points.
  var minimum: CGFloat

  func path(in rect: CGRect) -> Path {
    let horizontal = max(0, minimum - rect.width) / 2
    let vertical = max(0, minimum - rect.height) / 2
    return Path(rect.insetBy(dx: -horizontal, dy: -vertical))
  }
}
