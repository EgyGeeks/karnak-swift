import KarnakCore
import SwiftUI

/// What a node draws behind its content: its shadows, then its background, in its shape
/// (`docs/renderer-contract.md`, `ResolvedLayout`). A shadow is the shape grown by its spread,
/// offset and blurred, as CSS `box-shadow` draws it, so a node without a background still casts
/// one. Shadow offsets are physical, as on the other platforms, so they don't mirror in RTL.
struct NodeBackground: View {
  /// The node's shape.
  let shape: NodeShape
  /// The background, or nil for none.
  let fill: Color?
  /// Up to two shadows, painted in order.
  let shadows: [KarnakShadow]
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    ZStack {
      ForEach(shadows.indices, id: \.self) { index in
        let shadow = shadows[index]
        shape.inset(by: -points(dp: shadow.spread))
          .fill(resolvedColor(shadow.color))
          // SwiftUI mirrors a horizontal offset in RTL.
          .offset(
            x: points(dp: shadow.x) * (direction == .rightToLeft ? -1 : 1), y: points(dp: shadow.y)
          )
          .blur(radius: points(dp: shadow.blur) / 2)
      }
      if let fill {
        shape.fill(fill)
      }
    }
  }
}

/// A border stroked inside the node's bounds, over its content.
struct NodeBorder: View {
  /// The node's shape.
  let shape: NodeShape
  /// The border.
  let border: KarnakBorder

  var body: some View {
    shape.strokeBorder(resolvedColor(border.color), lineWidth: points(dp: border.width))
  }
}
