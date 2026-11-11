import CoreGraphics

/// A child's inputs to ``FlexLine/widths(space:items:)``, in points.
struct FlexLineItem: Sendable {
  /// The width growing and shrinking start from: the basis, or the child's own width.
  var base: CGFloat
  /// The share of the line's free width the child takes.
  var grow: CGFloat = 0
  /// The share of the line's missing width the child gives up.
  var shrink: CGFloat = 0
  /// The occupied lower bound.
  var lower: CGFloat = 0
  /// The occupied upper bound.
  var upper: CGFloat = .infinity

  /// The width lines break with: the base within the bounds.
  var hypothetical: CGFloat { max(lower, min(base, upper)) }
}

/// Flexible widths of one line of a wrapping row (`docs/renderer-contract.md`, Flexible widths):
/// CSS flexbox's "resolve flexible lengths" loop, which the web renderer gets from the browser.
enum FlexLine {
  /// The widths of `items` sharing `space`, the line's width without its gaps.
  static func widths(space: CGFloat, items: [FlexLineItem]) -> [CGFloat] {
    var line = Resolution(space: space, items: items)
    while line.frozen.contains(false) { line.freezePass() }
    return line.targets
  }

  private struct Resolution {
    let space: CGFloat
    let items: [FlexLineItem]
    let growing: Bool
    let initialFree: CGFloat
    var targets: [CGFloat]
    var frozen: [Bool]

    init(space: CGFloat, items: [FlexLineItem]) {
      self.space = space
      self.items = items
      let hypothetical = items.map(\.hypothetical)
      let growing = hypothetical.reduce(0, +) < space
      self.growing = growing
      targets = hypothetical
      // A child with no factor keeps its width, and so does one its bounds already moved the other way.
      frozen = items.indices.map { index in
        let item = items[index]
        let factor = growing ? item.grow : item.shrink
        return factor <= 0
          || (growing ? item.base > hypothetical[index] : item.base < hypothetical[index])
      }
      var used: CGFloat = 0
      for index in items.indices { used += frozen[index] ? targets[index] : items[index].base }
      initialFree = space - used
    }

    private func factor(_ index: Int) -> CGFloat {
      growing ? items[index].grow : items[index].shrink
    }

    /// The space left for the unfrozen children; factors that sum to less than 1 share only that
    /// fraction of the line's free space.
    private func free(open: [Int]) -> CGFloat {
      var used: CGFloat = 0
      for index in items.indices { used += frozen[index] ? targets[index] : items[index].base }
      let remaining = space - used
      let factors = open.reduce(CGFloat.zero) { $0 + factor($1) }
      let scaled = initialFree * factors
      return factors < 1 && abs(scaled) < abs(remaining) ? scaled : remaining
    }

    /// One pass: shares the free space among the unfrozen children and freezes the ones a bound
    /// held (every one when no bound did), so the space one gives up goes to the others.
    mutating func freezePass() {
      let open = items.indices.filter { !frozen[$0] }
      let free = free(open: open)
      let weights = open.map { growing ? items[$0].grow : items[$0].base * items[$0].shrink }
      let total = weights.reduce(0, +)
      var violation: CGFloat = 0
      var clamped: [CGFloat] = []
      var shares: [CGFloat] = []
      for (slot, index) in open.enumerated() {
        let share = items[index].base + (total > 0 ? free * weights[slot] / total : 0)
        let held = max(items[index].lower, min(share, items[index].upper))
        shares.append(share)
        clamped.append(held)
        violation += held - share
      }
      var froze = false
      for (slot, index) in open.enumerated() {
        let holds =
          violation == 0
          || (violation > 0 ? clamped[slot] > shares[slot] : clamped[slot] < shares[slot])
        if holds {
          targets[index] = clamped[slot]
          frozen[index] = true
          froze = true
        }
      }
      // Rounding can leave a violation no child caused; then every child is final.
      if !froze {
        for (slot, index) in open.enumerated() {
          targets[index] = clamped[slot]
          frozen[index] = true
        }
      }
    }
  }
}

/// How the lines of a wrapping row share a height larger than they need.
enum KarnakAlignContent: CaseIterable, Sendable {
  case start, center, end, spaceBetween, spaceAround, spaceEvenly, stretch

  /// Where `count` lines sit in `free` extra height: the offset of the first line, the extra gap
  /// between lines and the height each line grows by. Lines taller than the row start at its top.
  func distribution(count: Int, free: CGFloat) -> LineSpread {
    guard count > 0, free > 0 else { return LineSpread(leading: 0, gap: 0, grow: 0) }
    let arrangement: KarnakArrangement
    switch self {
    case .start: arrangement = .start
    case .center: arrangement = .center
    case .end: arrangement = .end
    case .spaceBetween: arrangement = .spaceBetween
    case .spaceAround: arrangement = .spaceAround
    case .spaceEvenly: arrangement = .spaceEvenly
    case .stretch: return LineSpread(leading: 0, gap: 0, grow: free / CGFloat(count))
    }
    let spread = arrangement.distribution(count: count, free: free)
    return LineSpread(leading: spread.leading, gap: spread.gap, grow: 0)
  }
}

/// How `align-content` shares extra height among the lines of a wrapping row.
struct LineSpread: Equatable, Sendable {
  /// The offset of the first line from the top.
  let leading: CGFloat
  /// The extra gap between two lines.
  let gap: CGFloat
  /// The height every line grows by.
  let grow: CGFloat
}
