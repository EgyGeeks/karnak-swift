import SwiftUI

/// How many columns a grid has.
enum KarnakGridColumns: Equatable {
  /// Exactly this many equal columns.
  case fixed(Int)
  /// As many as the measured width fits; `unboundedColumns` where there is no width.
  case adaptive(minItemWidth: CGFloat, unboundedColumns: Int)
}

/// Lays out a `grid` (`docs/renderer-contract.md`, Display primitives, `grid`): equal tracks from
/// the proposed width, children placed row by row, each covering its `span`, every row as tall as
/// its tallest item, and every item at the top start of its cells unless it aligns itself.
/// SwiftUI's `Grid` can't change its column count with the width, so this is a custom layout.
///
/// The grid is as wide as the width it is proposed. Where there is none the tracks are all as
/// wide as the widest item needs (a spanning item contributes its share to each track it covers)
/// and the grid is as wide as they are.
struct KarnakGridLayout: Layout, Equatable {
  var columns = KarnakGridColumns.fixed(2)
  var rowSpacing: CGFloat = 0
  var columnSpacing: CGFloat = 0
  /// Half a device pixel in points: the adaptive count allows for a width rounded to pixels.
  var halfPixel: CGFloat = 0
  var wrapsWidth = true
  var wrapsHeight = true

  func makeCache(subviews: Subviews) -> GridLayoutCache { GridLayoutCache() }

  func updateCache(_ cache: inout GridLayoutCache, subviews: Subviews) {
    cache = GridLayoutCache()
  }

  /// How many columns for a proposed `width`; nil where the width is unbounded.
  func columnCount(width: CGFloat?) -> Int {
    switch columns {
    case .fixed(let count):
      return count
    case .adaptive(let minItemWidth, let unboundedColumns):
      guard let width else { return unboundedColumns }
      return adaptiveColumnCount(
        width: width, spacing: columnSpacing, minItemWidth: minItemWidth, halfPixel: halfPixel)
    }
  }

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout GridLayoutCache
  ) -> CGSize {
    let measured = measurement(proposal: proposal, subviews: subviews, cache: &cache)
    return CGSize(
      width: layoutExtent(
        proposed: proposal.width.finite, content: measured.size.width, wraps: wrapsWidth),
      height: layoutExtent(
        proposed: proposal.height.finite, content: measured.size.height, wraps: wrapsHeight))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout GridLayoutCache
  ) {
    let measured = measurement(
      proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
      subviews: subviews, cache: &cache)
    let tops = measured.rowTops
    for index in subviews.indices {
      let cell = measured.cells[index]
      let input = subviews[index][KarnakLayoutInputKey.self]
      let free = measured.tracks.width(span: cell.span) - measured.occupied[index].width
      let horizontal = (input.align ?? .start).offset(free: free)
      let inset = (measured.occupied[index].width - measured.drawn[index].width) / 2
      let vertical = (measured.occupied[index].height - measured.drawn[index].height) / 2
      // Logical x: SwiftUI mirrors it in RTL.
      subviews[index].place(
        at: CGPoint(
          x: bounds.minX + measured.tracks.start(cell.column) + horizontal + inset,
          y: bounds.minY + tops[cell.row] + vertical),
        anchor: .topLeading, proposal: ProposedViewSize(measured.drawn[index]))
    }
  }

  /// The grid measured for `proposal`. A width that is the one its adaptive columns take when it
  /// is unbounded is measured as unbounded: a parent that measured the grid with no width (a
  /// horizontal scroll view, or a container in one) proposes and places it at that size, and
  /// counting the columns again from it would change them.
  private func measurement(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout GridLayoutCache
  ) -> GridMeasurement {
    let unspecified = ProposedViewSize(width: nil, height: proposal.height)
    guard let width = proposal.width.finite else {
      return cached(unspecified, subviews: subviews, cache: &cache)
    }
    if case .adaptive = columns {
      let unbounded = cached(unspecified, subviews: subviews, cache: &cache)
      if abs(unbounded.tracks.total - width) < 0.5 { return unbounded }
    }
    return cached(proposal, subviews: subviews, cache: &cache)
  }

  private func cached(
    _ proposal: ProposedViewSize, subviews: Subviews, cache: inout GridLayoutCache
  ) -> GridMeasurement {
    cache.measure(configuration: self, proposal: proposal) {
      GridMeasurement(layout: self, subviews: subviews, width: proposal.width.finite)
    }
  }
}

typealias GridLayoutCache = LayoutMeasurementCache<KarnakGridLayout, GridMeasurement>
