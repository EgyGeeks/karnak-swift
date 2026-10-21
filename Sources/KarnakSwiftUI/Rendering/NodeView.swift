import KarnakCore
import SwiftUI

/// One resolved node as one native element, with its common style as modifiers
/// (`docs/renderer-contract.md`, No extra layers).
///
/// `Equatable` on the node, identity first: the engine shares unchanged subtrees between trees,
/// so wrapped in `.equatable()` an unchanged node skips `body` and its whole subtree. A node
/// type this renderer doesn't draw is skipped; the root view reports it.
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
    let kind = NodeKind(node)
    // Containers and the root draw `drawnNode(_:)`, so custom and unsupported nodes don't
    // reach here.
    if case .button(let button) = kind {
      // A button draws its box for its interaction state itself.
      ButtonView(button: button, placement: placement)
    } else if kind.isDrawn {
      let drawn = primitive(kind)
        .nodeStyle(
          node, placement: placement, contentPosition: kind.contentPosition,
          content: kind.boxContent)
      if kind.reportsFrame || (reportsLabelled && node.semantics.label != nil) {
        // A list or a carousel reports its whole box, its own padding included, as its rows do; so does a labelled
        // node in a carousel's item.
        drawn.modifier(FrameReport(key: node.key.value))
      } else if node.semantics.label != nil {
        // A labelled node reports its box too: the conformance runner measures a labelled container by its
        // layout, as its accessibility frame is the union of its accessible children.
        drawn.modifier(FrameReport(key: node.key.value))
      } else {
        drawn
      }
    }
  }

  @ViewBuilder
  private func primitive(_ kind: NodeKind) -> some View {
    switch kind {
    case .column, .form, .row, .grid, .stack, .list, .carousel:
      container(kind)
    default:
      content(kind)
    }
  }

  /// The primitives that lay out children.
  @ViewBuilder
  private func container(_ kind: NodeKind) -> some View {
    switch kind {
    case .column(let column):
      ColumnView(
        children: column.children, fields: LinearFields(column), placement: placement,
        key: column.key.value)
    case .form(let form):
      ColumnView(
        children: form.children, fields: LinearFields(form), placement: placement,
        key: form.key.value)
    case .row(let row):
      RowView(row: row, placement: placement)
    case .grid(let grid):
      GridView(grid: grid, placement: placement)
    case .stack(let stack):
      StackView(stack: stack, placement: placement)
    case .list(let list):
      ListView(list: list, placement: placement)
    case .carousel(let carousel):
      CarouselView(carousel: carousel, placement: placement)
    default:
      EmptyView()
    }
  }

  /// The primitives that draw their own content.
  @ViewBuilder
  private func content(_ kind: NodeKind) -> some View {
    switch kind {
    case .text(let text):
      ParagraphView(paragraph: text.paragraph, isLabelled: node.semantics.label != nil)
    case .image(let image):
      ImageView(image: image)
    case .icon(let icon):
      IconView(node: icon)
    case .progress(let progress):
      ProgressIndicatorView(progress.progress)
    default:
      EmptyView()
    }
  }
}

/// Draws `nodes` in order, keyed by `NodeKey.value`, as the direct subviews of a container's
/// layout, each with the inputs the row, column and flow layouts read. Custom nodes draw their
/// fallback and unsupported nodes are skipped (`drawnNode(_:)`). The key is the row's identity,
/// so a reordered or grown list keeps each row's state; the roots of `repeat` rows report their
/// frames for scroll anchoring (``RowAnchors``).
struct NodeChildren: View {
  /// The children, painted and read in order.
  let nodes: [ResolvedNode]
  /// The key of the container that draws them.
  let parent: String
  /// How the parent places each child.
  let placement: (ResolvedNode) -> ChildPlacement

  var body: some View {
    ForEach(nodes.compactMap(drawnNode), id: \.key.value) { child in
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
