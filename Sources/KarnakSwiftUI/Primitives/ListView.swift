import KarnakCore
import SwiftUI

/// `list`: the engine decides whether it scrolls (`ResolvedList.scrolls`) and this view obeys it
/// (`docs/renderer-contract.md`, Display primitives). A list that scrolls is a `ScrollView` of a
/// `LazyVStack`, so only the rows near the viewport are built; one that doesn't is a plain column
/// that draws every row and is as tall as its content. It needs no runtime guard: a `ScrollView`
/// proposed no height (a host that broke the bounded-viewport rule) takes its content's height, so
/// the list is drawn in full there and nothing crashes. Deciding that from proposals would be
/// wrong, as SwiftUI also measures and places with no height while it lays out (a column's width
/// probe, a right-to-left pass). The list's size is its accessibility value
/// (``accessibilitySemantics(of:)``) and its frame is reported by ``NodeView``.
struct ListView: View {
  /// The list.
  let list: ResolvedList
  /// Which axes of the list's box its own parent sizes.
  let placement: ChildPlacement

  var body: some View {
    if list.scrolls {
      ScrollingList(list: list, placement: placement)
    } else {
      ListColumn(list: list, placement: placement)
    }
  }
}

/// Every row at its natural height in the column layout, with the list's spacing and content padding.
private struct ListColumn: View {
  let list: ResolvedList
  let placement: ChildPlacement

  var body: some View {
    KarnakColumnLayout(
      wrapsWidth: placement.wraps(.horizontal, of: list.layout),
      wrapsHeight: placement.wraps(.vertical, of: list.layout),
      spacing: points(dp: list.spacing), arrangement: .start, alignment: .start
    ) {
      NodeChildren(nodes: list.children, parent: list.key.value) {
        ChildPlacement.linear($0, axis: .vertical, stretches: false)
      }
    }
    .padding(edgeInsets(list.contentPadding))
  }
}
