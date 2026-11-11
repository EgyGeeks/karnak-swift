import KarnakCore
import SwiftUI

/// The container of a floating view, drawn by the layer (ADR 0038, D12): the surface's paint, border and shadows behind
/// the content, in its radius. A transparent surface (a FAB's) lets the content draw itself.
struct FloatingSurface<Content: View>: View {
  let surface: ResolvedSurface
  @ViewBuilder let content: Content

  var body: some View {
    let shape = NodeShape(radius: points(dp: surface.radius))
    content
      .clipShape(shape)
      .background {
        NodeBackground(
          shape: shape, fill: nil, paint: surface.background.map(PaintTarget.of), transition: nil,
          shadows: surface.shadows)
      }
      .overlay {
        if let border = surface.border { NodeBorder(shape: shape, border: border) }
      }
  }
}
