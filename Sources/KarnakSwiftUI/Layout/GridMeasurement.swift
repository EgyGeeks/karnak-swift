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
    let cells = placeInGrid(spans: inputs.map(\.span), columns: count)
    let tracks =
      width.map { KarnakGridTracks.fitting(count: count, width: $0, gap: layout.columnSpacing) }
      ?? KarnakGridTracks(
        count: count,
        track: Self.widestShare(subviews: subviews, cells: cells, gap: layout.columnSpacing),
        gap: layout.columnSpacing)
    var drawn = Self.measure(
      subviews: subviews, inputs: inputs, widths: cells.map { tracks.width(span: $0.span) })
    var occupied = zip(drawn, inputs).map { size, input in
      CGSize(
        width: max(size.width, input.width.touchTarget),
        height: max(size.height, input.height.touchTarget))
    }
    var rowHeights = [CGFloat](repeating: 0, count: (cells.last?.row ?? -1) + 1)
    for (index, cell) in cells.enumerated() {
      rowHeights[cell.row] = max(rowHeights[cell.row], occupied[index].height)
    }
    // A child whose height is `Fill` takes the height of its row.
    for index in subviews.indices where inputs[index].fillsHeight {
      let filled = subviews[index].sizeThatFits(
        ProposedViewSize(width: drawn[index].width, height: rowHeights[cells[index].row]))
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
