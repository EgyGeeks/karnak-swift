import KarnakCore
import SwiftUI

/// A custom node (`docs/renderer-contract.md`, `Custom`): the view of the renderer the host registered for its type,
/// in the node's box with its common style. A container gives the place of a node the host doesn't draw to its
/// fallback before it lays its children out (``ComponentRegistry/drawnNode(_:)``), so such a node reaches here only
/// as a screen's root; its fallback is drawn then too, and nothing when it has none.
struct CustomNodeView: View {
  /// The node to draw.
  let node: ResolvedCustom
  /// What the parent decides about the box of whatever is drawn in the node's place.
  let placement: ChildPlacement
  @Environment(\.karnakComponents) private var components

  var body: some View {
    if let hostView = components.hostView(for: node) {
      let styled = hostView.nodeStyle(node, placement: placement)
      // A labelled node reports its box, as ``NodeView`` has every labelled node do.
      if node.semantics.label != nil {
        styled.modifier(FrameReport(key: node.key.value))
      } else {
        styled
      }
    } else if let fallback = node.fallback.flatMap({ components.drawnNode($0) }) {
      NodeView(node: fallback, placement: placement).equatable()
    }
  }
}

extension ComponentRegistry {
  /// What the host's renderer draws for this instance of `node`; nil when it asks for the fallback or the type has
  /// no renderer. A container asks before it draws the node, so a renderer runs more than once for one drawing, as
  /// any view builder may.
  @MainActor
  func hostView(for node: ResolvedCustom) -> AnyView? {
    guard let renderer = renderer(for: node.type) else { return nil }
    var askedForFallback = false
    let view = renderer(KarnakCustomNode(node)) {
      askedForFallback = true
      return KarnakCustomFallback()
    }
    return askedForFallback ? nil : view
  }

  /// The node drawn in `node`'s place, or nil when nothing is: an unsupported node is skipped, and a custom node the
  /// host doesn't draw gives its place to its fallback, with the fallback's own style and layout. Containers draw
  /// only these, so a node that draws nothing takes no slot and no spacing.
  @MainActor
  func drawnNode(_ node: ResolvedNode) -> ResolvedNode? {
    guard let drawn = NodeRenderers.drawnNode(node) else { return nil }
    guard let custom = drawn as? ResolvedCustom, hostView(for: custom) == nil else { return drawn }
    return custom.fallback.flatMap { drawnNode($0) }
  }
}
