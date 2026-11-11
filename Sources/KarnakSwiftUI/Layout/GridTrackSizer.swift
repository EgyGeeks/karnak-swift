import CoreGraphics

/// The width of one column of a grid with `layout.tracks`.
enum KarnakGridTrack: Equatable {
  /// A fixed width in points.
  case fixed(CGFloat)
  /// A share of the width the other columns leave.
  case fraction(CGFloat)
  /// As wide as the widest content of the column.
  case wrap
}

/// Sizes the columns of a grid with `layout.tracks` (`docs/renderer-contract.md`, Display
/// primitives, `grid`, Track widths). A fixed track is its width. A `wrap` track is as wide as
/// the widest max-content width of the children in it alone; a child over several tracks, none
/// of them a share, then adds the width it still misses to its `wrap` tracks in equal parts,
/// narrower spans first. The shares divide the width that is left, one part being that width
/// over the sum of the shares, or over 1 when they sum to less. Where the width is unbounded
/// there is nothing to divide, so a share is a `wrap` track.
struct GridTrackSizer {
  var tracks: [KarnakGridTrack]
  var cells: [KarnakGridCell]
  /// The max-content width of the child at an index.
  var ideal: (Int) -> CGFloat

  /// The tracks in `width`, or as wide as their content when it is nil, `gap` apart.
  func sized(width: CGFloat?, gap: CGFloat) -> KarnakGridTracks {
    var widths = tracks.map { track -> CGFloat in
      if case .fixed(let fixed) = track { fixed } else { 0 }
    }
    let shares = width == nil ? [] : tracks.indices.filter { share($0) != nil }
    let wraps = tracks.indices.filter { index in
      if case .fixed = tracks[index] { false } else { !shares.contains(index) }
    }
    if !wraps.isEmpty { fitContent(&widths, wraps: wraps, shares: shares, gap: gap) }
    if let width {
      let total = shares.reduce(0) { $0 + (share($1) ?? 0) }
      let rest = max(0, width - gap * CGFloat(tracks.count - 1) - widths.reduce(0, +))
      for column in shares { widths[column] = rest / max(total, 1) * (share(column) ?? 0) }
    }
    return .of(widths: widths, gap: gap)
  }

  private func share(_ column: Int) -> CGFloat? {
    if case .fraction(let share) = tracks[column] { share } else { nil }
  }

  /// Grows the `wraps` tracks to their children's max-content widths; a child on a `shares`
  /// track asks nothing.
  private func fitContent(_ widths: inout [CGFloat], wraps: [Int], shares: [Int], gap: CGFloat) {
    let narrowestFirst = cells.indices.sorted { (cells[$0].span, $0) < (cells[$1].span, $1) }
    for index in narrowestFirst {
      let columns = cells[index].column..<cells[index].column + cells[index].span
      let growing = wraps.filter(columns.contains)
      guard !growing.isEmpty, !shares.contains(where: columns.contains) else { continue }
      let has = columns.reduce(0) { $0 + widths[$1] } + gap * CGFloat(columns.count - 1)
      let missing = ideal(index) - has
      guard missing > 0 else { continue }
      for column in growing { widths[column] += (missing / CGFloat(growing.count)).rounded(.up) }
    }
  }
}
