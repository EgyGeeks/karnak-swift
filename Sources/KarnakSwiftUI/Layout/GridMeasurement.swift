import SwiftUI

/// What the grid layout measured for a proposed width: the tracks, where each child goes, how
/// big it is drawn and how tall every row is.
struct GridMeasurement {
  var tracks: KarnakGridTracks
  var cells: [KarnakGridCell]
  var drawn: [CGSize]
  var occupied: [CGSize]
  var rowHeights: [CGFloat]
  var rowSpacing: CGFloat

  /// The grid's size: all tracks wide and all rows tall.
  var size: CGSize {
    CGSize(
      width: tracks.total,
      height: rowHeights.reduce(0, +) + rowSpacing * CGFloat(max(0, rowHeights.count - 1)))
  }

  /// The top edge of every row.
  var rowTops: [CGFloat] {
    var top: CGFloat = 0
    return rowHeights.map { height in
      defer { top += height + rowSpacing }
      return top
    }
  }

  init(layout: KarnakGridLayout, subviews: LayoutSubviews, width: CGFloat?) {
    let inputs = subviews.map { $0[KarnakLayoutInputKey.self] }
    let count = layout.columnCount(width: width)
    let cells = placeInGrid(children: inputs, columns: count)
    let tracks = Self.tracks(layout: layout, subviews: subviews, cells: cells, width: width)
    var drawn = Self.measure(
      subviews: subviews, inputs: inputs,
      widths: cells.map { tracks.width(column: $0.column, span: $0.span) })
    var occupied = zip(drawn, inputs).map { size, input in
      CGSize(
        width: max(size.width, input.width.touchTarget),
        height: max(size.height, input.height.touchTarget))
    }
    let rowHeights = Self.rowHeights(
      cells: cells, heights: occupied.map(\.height), rowSpacing: layout.rowSpacing)
    // A child whose height is `Fill` takes the height of its rows.
    for index in subviews.indices where inputs[index].fillsHeight {
      let rows = cells[index].row..<cells[index].row + cells[index].rowSpan
      let height =
        rows.reduce(0) { $0 + rowHeights[$1] } + layout.rowSpacing * CGFloat(rows.count - 1)
      let filled = subviews[index].sizeThatFits(
        ProposedViewSize(width: drawn[index].width, height: height))
      drawn[index].height = inputs[index].height.clamp(filled.height)
      occupied[index].height = max(drawn[index].height, inputs[index].height.touchTarget)
    }
    self.tracks = tracks
    self.cells = cells
    self.drawn = drawn
    self.occupied = occupied
    self.rowHeights = rowHeights
    rowSpacing = layout.rowSpacing
  }

  /// The grid's tracks: the sized ones of `layout.tracks`, or equal ones that fill `width`, or
  /// where there is none are as wide as the widest child needs.
  private static func tracks(
    layout: KarnakGridLayout, subviews: LayoutSubviews, cells: [KarnakGridCell], width: CGFloat?
  ) -> KarnakGridTracks {
    let gap = layout.columnSpacing
    if case .tracks(let tracks) = layout.columns {
      let sizer = GridTrackSizer(tracks: tracks, cells: cells) { index in
        subviews[index][KarnakLayoutInputKey.self].width.occupied(
          subviews[index].sizeThatFits(.unspecified).width)
      }
      return sizer.sized(width: width, gap: gap)
    }
    let count = layout.columnCount(width: width)
    guard let width else {
      return .equal(
        count: count, track: widestShare(subviews: subviews, cells: cells, gap: gap), gap: gap)
    }
    return .fitting(count: count, width: width, gap: gap)
  }

  /// Every row's height: the tallest child in it alone, then a child over several rows adds the
  /// height it still misses to its rows in equal parts, fewer rows first.
  private static func rowHeights(
    cells: [KarnakGridCell], heights: [CGFloat], rowSpacing: CGFloat
  ) -> [CGFloat] {
    var rows = [CGFloat](repeating: 0, count: cells.map { $0.row + $0.rowSpan }.max() ?? 0)
    let fewestFirst = cells.indices.sorted { (cells[$0].rowSpan, $0) < (cells[$1].rowSpan, $1) }
    for index in fewestFirst {
      let covered = cells[index].row..<cells[index].row + cells[index].rowSpan
      let has = covered.reduce(0) { $0 + rows[$1] } + rowSpacing * CGFloat(covered.count - 1)
      let missing = heights[index] - has
      guard missing > 0 else { continue }
      for row in covered { rows[row] += missing / CGFloat(covered.count) }
    }
    return rows
  }

  /// Every child at the width the grid gives it: its cells' width for `Fill`, a stretched `Wrap`
  /// or a child that takes the width it is given (a grid), else its own (its content's, or its `Fixed` size) up to its cells' width. A `Fill`
  /// height has no row yet, so it measures to its content.
  private static func measure(
    subviews: LayoutSubviews, inputs: [KarnakLayoutInput], widths: [CGFloat]
  ) -> [CGSize] {
    subviews.indices.map { index in
      let input = inputs[index]
      let stretched = input.wrapsWidth && input.align == .stretch
      let fills = (!input.wrapsWidth && !input.fixedWidth) || input.takesGivenWidth
      let width =
        fills || stretched
        ? widths[index]
        : min(subviews[index].sizeThatFits(.unspecified).width, widths[index])
      let measured = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
      return CGSize(
        width: input.width.clamp(measured.width), height: input.height.clamp(measured.height))
    }
  }

  /// The track every column takes when the width is unbounded: the largest share of any child's
  /// max-content width (a spanning child contributes its share to each track it covers).
  private static func widestShare(
    subviews: LayoutSubviews, cells: [KarnakGridCell], gap: CGFloat
  ) -> CGFloat {
    subviews.indices.map { index in
      let input = subviews[index][KarnakLayoutInputKey.self]
      let ideal = input.width.occupied(subviews[index].sizeThatFits(.unspecified).width)
      let span = CGFloat(cells[index].span)
      return ((ideal - gap * (span - 1)) / span).rounded(.up)
    }.max().map { max(0, $0) } ?? 0
  }
}
