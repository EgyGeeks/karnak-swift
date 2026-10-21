import KarnakCore
import SwiftUI

/// The lazy list: a vertical `ScrollView` of a `LazyVStack` whose rows are built by key, so a row keeps its
/// state and the scroll keeps its place when an update keeps the keys (``ListAnchoring``). A row sits in the
/// list's width at its own `align`; one that `stretch`es or `fill`s takes all of it. Each row sees the list's
/// own viewport for `actions.appear`, and the content padding scrolls with the rows.
struct ScrollingList: View {
  let list: ResolvedList
  let placement: ChildPlacement

  @Environment(\.karnakViewport) private var outerViewport
  @State private var viewport: CGRect?
  @State private var contentHeight: CGFloat = .infinity
  @State private var anchoring = ListAnchoring()

  /// A list that hugs its height (`wrap` with a `maxHeight`) is as tall as its rows up to the maximum.
  private var hugsContent: Bool { placement.wraps(.vertical, of: list.layout) }

  var body: some View {
    let measures = outerViewport != nil
    // In `body`, not `onChange`: the row at the top must be captured before the new rows are laid out, as the
    // screen's `ContentGate` captures it before an update, and `onChange` runs after that layout.
    anchoring.rowsChanged(to: list.children.map(\.key.value))
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: points(dp: list.spacing)) {
        ForEach(list.children.compactMap(drawnNode), id: \.key.value) { child in
          ListRow(node: child)
            .modifier(RowAnchorModifier(key: child.key.value))
        }
      }
      .padding(edgeInsets(list.contentPadding))
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        contentHeight = $0
      }
      .background {
        if measures {
          ScrollProbe { anchoring.attach($0) }
          ViewportProbe { viewport = $0 }
        }
      }
    }
    .frame(maxHeight: hugsContent ? contentHeight : .infinity)
    .environment(\.karnakViewport, measures ? viewport : nil)
    .environment(\.karnakRowAnchors, anchoring.anchors)
  }
}

/// One row of a lazy list: its node in a slot as wide as the list, placed by the row's own `align`.
private struct ListRow: View {
  let node: ResolvedNode

  var body: some View {
    let align = node.layout.align
    let stretches = align.map { $0 == .stretch } ?? false
    NodeView(
      node: node,
      placement: ChildPlacement(acceptsProposal: stretches ? [.horizontal] : [])
    )
    .equatable()
    .modifier(FrameReport(key: node.key.value))
    .frame(maxWidth: .infinity, alignment: alignment(align))
  }

  private func alignment(_ align: KarnakSelfAlignment?) -> Alignment {
    switch align {
    case .center: .center
    case .end: .trailing
    default: .leading
    }
  }
}
