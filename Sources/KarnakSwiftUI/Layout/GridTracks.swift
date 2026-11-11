import CoreGraphics

/// A child's place in a grid: its first `row` and `column`, and the `span` columns and `rowSpan`
/// rows it covers.
struct KarnakGridCell: Sendable, Equatable {
  var row: Int
  var column: Int
  var span: Int
  var rowSpan = 1
}

/// Where the children of a grid of `columns` columns sit (`docs/renderer-contract.md`, Display
/// primitives, `grid`, Placement). A child with a `gridArea` takes those cells. The others go in
/// order, row by row, each into the first cells from the last placed child's that are free and
/// fit its span: one that doesn't fit what is left of a row starts the next, and the gap stays
/// empty. There is no dense packing, so no child moves back before an earlier one. A span wider
/// than `columns` is clamped to it.
func placeInGrid(children: [KarnakLayoutInput], columns: Int) -> [KarnakGridCell] {
  let count = max(columns, 1)
  let pinned = children.map { $0.gridArea.map { $0.within(count) } }
  var taken = Set(pinned.compactMap { $0 }.flatMap { $0.indices(columns: count) })
  var last = KarnakGridCell(row: 0, column: 0, span: 1)
  return children.indices.map { index in
    if let cell = pinned[index] { return cell }
    var cell = KarnakGridCell(
      row: last.row, column: last.column, span: min(max(children[index].span, 1), count),
      rowSpan: max(children[index].rowSpan, 1))
    while true {
      if cell.column + cell.span > count {
        cell.row += 1
        cell.column = 0
      }
      if taken.isDisjoint(with: cell.indices(columns: count)) { break }
      cell.column += 1
    }
    taken.formUnion(cell.indices(columns: count))
    last = cell
    return cell
  }
}

/// The placement of children that only have `spans`.
func placeInGrid(spans: [Int], columns: Int) -> [KarnakGridCell] {
  placeInGrid(children: spans.map { KarnakLayoutInput(span: $0) }, columns: columns)
}

extension KarnakGridCell {
  /// This pinned cell kept inside `count` columns.
  fileprivate func within(_ count: Int) -> KarnakGridCell {
    let start = min(max(column, 0), count - 1)
    return KarnakGridCell(
      row: max(row, 0), column: start, span: min(max(span, 1), count - start),
      rowSpan: max(rowSpan, 1))
  }

  /// The row-major index of every cell this one covers in a grid of `columns` columns.
  fileprivate func indices(columns: Int) -> [Int] {
    (row..<row + rowSpan).flatMap { row in
      (column..<column + span).map { row * columns + $0 }
    }
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

/// The columns of a grid, `gap` apart.
struct KarnakGridTracks: Equatable {
  /// The start of every column from the grid's start edge, and after the last one the start a
  /// further column would have.
  var starts: [CGFloat]
  var gap: CGFloat

  /// `count` equal tracks, each `track` points wide.
  static func equal(count: Int, track: CGFloat, gap: CGFloat) -> KarnakGridTracks {
    KarnakGridTracks(starts: (0...max(count, 1)).map { CGFloat($0) * (track + gap) }, gap: gap)
  }

  /// `count` equal tracks filling `width`, which is at least the gaps.
  static func fitting(count: Int, width: CGFloat, gap: CGFloat) -> KarnakGridTracks {
    let count = max(count, 1)
    return equal(
      count: count, track: max(0, (width - gap * CGFloat(count - 1)) / CGFloat(count)), gap: gap)
  }

  /// One track per width in `widths`.
  static func of(widths: [CGFloat], gap: CGFloat) -> KarnakGridTracks {
    var starts: [CGFloat] = [0]
    for width in widths { starts.append((starts.last ?? 0) + width + gap) }
    return KarnakGridTracks(starts: starts, gap: gap)
  }

  /// The grid's width: all tracks and the gaps between them.
  var total: CGFloat { max(0, (starts.last ?? gap) - gap) }

  /// The start offset of `column` from the grid's start edge.
  func start(_ column: Int) -> CGFloat { starts[column] }

  /// The width of `span` columns from `column`, the gaps between them included.
  func width(column: Int, span: Int) -> CGFloat { starts[column + span] - gap - starts[column] }
}
