import KarnakCore
import SwiftUI

/// How wide a carousel makes its items (`docs/renderer-contract.md`, Display primitives, `carousel`).
enum CarouselSlotWidth: Equatable {
  /// Every item's slot and box are this wide, in points.
  case fixed(CGFloat)
  /// `count` items are visible: `(W - padding - spacing x (ceil(count) - 1)) / count`, at least 1.
  case visible(CGFloat)
  /// Each item has its own width.
  case wrap

  init(_ width: CarouselItemWidth) {
    switch width {
    case let fixed as CarouselItemWidthFixed: self = .fixed(points(dp: fixed.dp))
    case let visible as CarouselItemWidthVisible: self = .visible(CGFloat(visible.count))
    default: self = .wrap
    }
  }
}

/// What a carousel's layouts work from, in points (``KarnakCarouselLayout``,
/// ``KarnakCarouselRuler``).
struct CarouselMetrics: Equatable {
  var itemWidth = CarouselSlotWidth.wrap
  var spacing: CGFloat = 0
  var padding = EdgeInsets()
  /// The dot row's height with the space above it; 0 without dots.
  var dotsBlock: CGFloat = 0
  /// The space between the items and the dots.
  var dotsSpacing: CGFloat = 0

  /// The width of every item's slot in a carousel `width` wide; nil for items with their own width, and for a width that
  /// is not known (a `visible` item behaves as `wrap` there).
  func slotWidth(in width: CGFloat?) -> CGFloat? {
    switch itemWidth {
    case .fixed(let value): return max(1, value)
    case .wrap: return nil
    case .visible(let count):
      guard let width else { return nil }
      return visibleSlotWidth(
        content: width - padding.leading - padding.trailing, spacing: spacing, count: count)
    }
  }
}

/// `Visible(v)`: `(W - spacing x (ceil(v) - 1)) / v` for the content width W, at least 1.
func visibleSlotWidth(content: CGFloat, spacing: CGFloat, count: CGFloat) -> CGFloat {
  max(1, (content - spacing * (count.rounded(.up) - 1)) / count)
}

/// The current item (`docs/renderer-contract.md`, Display primitives, `carousel`): the one whose start edge is nearest
/// the leading content padding edge, the lower index on a tie. Once a carousel that overflows has scrolled to its end
/// the last item is current, and one that doesn't overflow has the first.
///
/// - Parameters:
///   - offsets: How far each item that has been built starts along the content from the first item, by index. They do
///     not change as the carousel scrolls.
///   - scroll: How far the carousel has scrolled along its content, from where the first item is at the leading
///     content padding edge.
///   - count: How many items the carousel has.
func currentCarouselItem(
  offsets: [Int: CGFloat], scroll: CGFloat, count: Int, overflows: Bool, atEnd: Bool
) -> Int {
  guard overflows, count > 0 else { return 0 }
  if atEnd { return count - 1 }
  var best = 0
  var nearest = CGFloat.infinity
  for (index, offset) in offsets.sorted(by: { $0.key < $1.key }) {
    let distance = abs(offset - scroll)
    // Two distances closer than this are a tie, so rounding can't change the lower index.
    if distance < nearest - 0.01 {
      nearest = distance
      best = index
    }
  }
  return best
}

/// Where each dot starts from the start edge of a row `width` wide: centred while they fit, else from the start
/// edge, shifted the least that brings the `current` dot's far edge in.
func carouselDotStarts(
  count: Int, dot: CGFloat, gap: CGFloat, width: CGFloat, current: Int
) -> [CGFloat] {
  let row = CGFloat(count) * dot + CGFloat(max(0, count - 1)) * gap
  let reach = CGFloat(current + 1) * dot + CGFloat(current) * gap
  let first = row <= width ? (width - row) / 2 : -max(0, reach - width)
  return (0..<count).map { first + CGFloat($0) * (dot + gap) }
}

/// How far an item's own shadows reach beyond its box, in points: the largest blur plus spread plus offset. A margin
/// box (a `stack` holding the one node) reaches as far as the node inside it.
func shadowReach(of node: ResolvedNode) -> CGFloat {
  let own =
    node.layout.shadows.map {
      CGFloat($0.blur + $0.spread + max(abs($0.x), abs($0.y)))
    }.max() ?? 0
  guard let stack = node as? ResolvedStack, stack.children.count == 1,
    let only = stack.children.first
  else { return own }
  return max(own, shadowReach(of: only))
}
