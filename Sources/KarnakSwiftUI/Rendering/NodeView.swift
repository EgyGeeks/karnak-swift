import KarnakCore
import SwiftUI

/// One resolved node as one native element, with its common style as modifiers
/// (`docs/renderer-contract.md`, No extra layers).
///
/// `Equatable` on the node, identity first: the engine shares unchanged subtrees between trees,
/// so wrapped in `.equatable()` an unchanged node skips `body` and its whole subtree. A node
/// type this renderer doesn't draw is skipped; the root view reports it. The drawing is the one registered for the
/// node's kind in ``NodeRenderers``.
struct NodeView: View, Equatable {
  /// The node to draw.
  let node: ResolvedNode
  /// What the parent decides about the node's box.
  let placement: ChildPlacement
  @Environment(\.karnakReportsLabelledFrames) private var reportsLabelled

  nonisolated static func == (lhs: NodeView, rhs: NodeView) -> Bool {
    lhs.placement == rhs.placement && (lhs.node === rhs.node || lhs.node.isEqual(rhs.node))
  }

  var body: some View {
    drawn.floatingAnchor(of: node)
  }

  @ViewBuilder
  private var drawn: some View {
    let registration = NodeRenderers.registration(for: node)
    // Containers and the root draw `drawnNode(_:)`, so unsupported nodes don't reach here.
    if registration.drawsOwnBox {
      // A button draws its box for its interaction state itself, and an input draws its box around its parts; its
      // control is the accessibility element.
      registration.draw(node, placement)
    } else if registration.isDrawn {
      if node.interactive {
        // A node with interaction styles of its own (`style.hovered`, ...) is drawn as `styleFor` of what it tracks.
        InteractionTracking(node: node) { shown in styled(shown, registration) }
      } else {
        styled(node, registration)
      }
    }
  }

  /// `node` drawn with its common style, reporting its frame where the root or a carousel needs it.
  @ViewBuilder
  private func styled(_ node: ResolvedNode, _ registration: NodeRegistration) -> some View {
    let styled = registration.draw(node, placement)
      .nodeStyle(
        node, placement: placement, contentPosition: registration.contentPosition(node),
        content: registration.boxContent(node))
    if registration.reportsFrame || (reportsLabelled && node.semantics.label != nil) {
      // A list or a carousel reports its whole box, its own padding included, as its rows do; so does a labelled
      // node in a carousel's item.
      styled.modifier(FrameReport(key: node.key.value))
    } else if node.semantics.label != nil {
      // A labelled node reports its box too: the conformance runner measures a labelled container by its
      // layout, as its accessibility frame is the union of its accessible children.
      styled.modifier(FrameReport(key: node.key.value))
    } else {
      styled
    }
  }
}

/// Draws `nodes` in order, keyed by `NodeKey.value`, as the direct subviews of a container's
/// layout, each with the inputs the row, column and flow layouts read. Unsupported nodes are
/// skipped, and a custom node the host doesn't draw gives its place to its fallback
/// (``ComponentRegistry/drawnNode(_:)``). The key is the row's identity,
/// so a reordered or grown list keeps each row's state; the roots of `repeat` rows report their
/// frames for scroll anchoring (``RowAnchors``).
struct NodeChildren: View {
  /// The children, painted and read in order.
  let nodes: [ResolvedNode]
  /// The key of the container that draws them.
  let parent: String
  /// How the parent places each child.
  let placement: (ResolvedNode) -> ChildPlacement
  @Environment(\.karnakComponents) private var components

  var body: some View {
    ForEach(nodes.compactMap { components.drawnNode($0) }, id: \.key.value) { child in
      NodeView(node: child, placement: placement(child)).equatable()
        .rowAnchor(child.key.value, parent: parent)
        .karnakLayoutInput(KarnakLayoutInput(child))
    }
  }
}

extension View {
  /// Reports this node's frame for scroll anchoring when it is the root of a `repeat` row inside
  /// `parent`; any other node is left as it is.
  @ViewBuilder
  func rowAnchor(_ key: String, parent: String) -> some View {
    if TreeStructure.isRowRoot(key, parent: parent) {
      modifier(RowAnchorModifier(key: key))
    } else {
      self
    }
  }
}
