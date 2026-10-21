import CoreGraphics

/// A child's place in a grid: its `row`, its first `column` and the `span` columns it covers.
struct KarnakGridCell: Equatable {
  var row: Int
  var column: Int
  var span: Int
}

/// Row-major placement (`docs/renderer-contract.md`, Display primitives, `grid`): children go in
/// order from the first column; one that doesn't fit what is left of its row starts the next, and
/// the gap stays empty. There is no dense packing, so the order never changes. A span wider than
/// `columns` is clamped to it.
func placeInGrid(spans: [Int], columns: Int) -> [KarnakGridCell] {
  let count = max(columns, 1)
  var row = 0
  var column = 0
  return spans.map { requested in
    let span = min(max(requested, 1), count)
    if column + span > count {
      row += 1
      column = 0
    }
    defer { column += span }
    return KarnakGridCell(row: row, column: column, span: span)
  }
}

/// The adaptive column count for a measured `width` and the `spacing` between columns:
/// `max(1, ⌊(W + ½ px + s) ÷ (minItemWidth + s)⌋)` (`docs/renderer-contract.md`, Display
/// primitives, `grid`), `halfPixel` being half a device pixel in points, so a width rounded to
/// pixels just short of a boundary still fits its columns. Below one item's width there is one
/// column.
func adaptiveColumnCount(
  width: CGFloat, spacing: CGFloat, minItemWidth: CGFloat, halfPixel: CGFloat = 0
) -> Int {
  max(1, Int(((width + halfPixel + spacing) / (minItemWidth + spacing)).rounded(.down)))
}

/// Equal tracks of `count` columns, each `track` points wide and `gap` apart.
struct KarnakGridTracks: Equatable {
  var count: Int
  var track: CGFloat
  var gap: CGFloat

  /// `count` tracks filling `width`, which is at least the gaps.
  static func fitting(count: Int, width: CGFloat, gap: CGFloat) -> KarnakGridTracks {
    let count = max(count, 1)
    return KarnakGridTracks(
      count: count, track: max(0, (width - gap * CGFloat(count - 1)) / CGFloat(count)), gap: gap)
  }

  /// The grid's width: all tracks and the gaps between them.
  var total: CGFloat { CGFloat(count) * track + CGFloat(count - 1) * gap }

  /// The start offset of `column` from the grid's start edge.
  func start(_ column: Int) -> CGFloat { CGFloat(column) * (track + gap) }

  /// The width of `span` columns, the gaps between them included.
  func width(span: Int) -> CGFloat { CGFloat(span) * track + CGFloat(span - 1) * gap }
}
