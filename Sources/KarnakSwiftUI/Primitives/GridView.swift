import KarnakCore
import SwiftUI

/// `grid`: equal columns, fixed or as many as the proposed width fits, children placed row by row
/// with their `span` through ``KarnakGridLayout`` (`docs/renderer-contract.md`, Display primitives,
/// `grid`).
struct GridView: View {
  /// The grid.
  let grid: ResolvedGrid
  /// Which axes of the grid's box its own parent sizes.
  let placement: ChildPlacement
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    KarnakGridLayout(
      columns: karnakGridColumns(grid.columns), rowSpacing: points(dp: grid.rowSpacing),
      columnSpacing: points(dp: grid.columnSpacing), halfPixel: 0.5 / max(displayScale, 1),
      wrapsWidth: placement.wraps(.horizontal, of: grid.layout),
      wrapsHeight: placement.wraps(.vertical, of: grid.layout)
    ) {
      NodeChildren(nodes: grid.children, parent: grid.key.value) { _ in .gridCell }
    }
  }
}

/// The layout's columns for the resolved ones.
func karnakGridColumns(_ columns: GridColumns) -> KarnakGridColumns {
  switch columns {
  case let adaptive as GridColumns.Adaptive:
    .adaptive(
      minItemWidth: points(dp: adaptive.minItemWidth),
      unboundedColumns: Int(adaptive.unboundedColumns))
  case let fixed as GridColumns.Fixed:
    .fixed(Int(fixed.count))
  default:
    .fixed(2)
  }
}
