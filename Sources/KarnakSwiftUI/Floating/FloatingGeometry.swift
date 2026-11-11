import CoreGraphics

/// Which of the three groups of ADR 0038, D6 a view stacks in, nearest the edge first.
enum StackGroup: Int, Comparable {
  /// `screen` views with `stack: "inner"`.
  case inner
  /// Transient views and toasts, in show order.
  case transient
  /// `screen` views with `stack: "outer"`, the default.
  case outer

  static func < (lhs: StackGroup, rhs: StackGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One view the layer stacks at an edge: its `key`, `group`, horizontal span (`left` and `width`), `height` and its
/// `margin` from the edge, all in points.
struct StackItem: Equatable {
  let key: String
  let group: StackGroup
  let left: CGFloat
  let width: CGFloat
  let height: CGFloat
  let margin: CGFloat

  fileprivate func overlapsHorizontally(_ other: StackItem) -> Bool {
    left < other.left + other.width && other.left < left + width
  }
}

/// The geometry of the floating layer as pure functions, so the rules of ADR 0038, D5 and D6 are tested without a
/// view.
enum FloatingGeometry {
  /// The distance of each of `items` from its edge (ADR 0038, D6): a view clears the highest outer side (distance
  /// plus height) among the earlier views, by group and then by order, whose horizontal span overlaps its own, plus
  /// `gap`; with none it sits at its margin. So two views side by side don't add up beneath a third, and a `fill`
  /// view clears both.
  static func stackDistances(_ items: [StackItem], gap: CGFloat) -> [String: CGFloat] {
    var distances: [String: CGFloat] = [:]
    var placed: [StackItem] = []
    // A stable sort: the order inside a group is the order of declaration or show.
    let ordered = items.enumerated().sorted {
      ($0.element.group, $0.offset) < ($1.element.group, $1.offset)
    }
    for (_, item) in ordered {
      let clearance = placed.filter { $0.overlapsHorizontally(item) }
        .compactMap { earlier in distances[earlier.key].map { $0 + earlier.height } }.max()
      distances[item.key] = clearance.map { $0 + gap } ?? item.margin
      placed.append(item)
    }
    return distances
  }

  /// The widest a `fill` view grows to, in points; beyond it the view is centred (ADR 0038, D5).
  static let fillMaxWidth: CGFloat = 600

  /// The gap between stacked views, in points.
  static let stackGap: CGFloat = 8

  /// A side of an anchored view's anchor.
  enum Side: Equatable {
    case above, below, left, right

    var opposite: Side {
      switch self {
      case .above: .below
      case .below: .above
      case .left: .right
      case .right: .left
      }
    }
  }

  /// How an anchored view lines up along its anchor, in physical terms.
  enum Align: Equatable {
    case start, center, end
  }

  /// Which side of its anchor an anchored view prefers, how it lines up there, and how far it keeps.
  struct Placement {
    let side: Side
    let align: Align
    let gap: CGFloat
  }

  /// Where an anchored view of `size` goes next to `anchor`, inside `bounds` (ADR 0038, D5): on `side`, `align`ed
  /// along the anchor and `gap` points away; on the opposite side when it doesn't fit on `side` but does there, then
  /// shifted along the side to stay inside `bounds`. `side` in the result is the one it ended on, for its arrow.
  static func anchoredFrame(
    anchor: CGRect, size: CGSize, bounds: CGRect, placement: Placement
  ) -> (frame: CGRect, side: Side) {
    let (side, align, gap) = (placement.side, placement.align, placement.gap)
    func frame(on side: Side) -> CGRect {
      CGRect(
        origin: origin(anchor: anchor, size: size, side: side, align: align, gap: gap), size: size)
    }
    var chosen = side
    let oppositeFits = fits(frame(on: side.opposite), on: side.opposite, in: bounds)
    if !fits(frame(on: side), on: side, in: bounds) && oppositeFits {
      chosen = side.opposite
    }
    return (shifted(frame(on: chosen), in: bounds), chosen)
  }

  private static func origin(
    anchor: CGRect, size: CGSize, side: Side, align: Align, gap: CGFloat
  ) -> CGPoint {
    switch side {
    case .above:
      CGPoint(
        x: along(anchor.minX, anchor.width, size.width, align), y: anchor.minY - gap - size.height)
    case .below:
      CGPoint(x: along(anchor.minX, anchor.width, size.width, align), y: anchor.maxY + gap)
    case .left:
      CGPoint(
        x: anchor.minX - gap - size.width, y: along(anchor.minY, anchor.height, size.height, align))
    case .right:
      CGPoint(x: anchor.maxX + gap, y: along(anchor.minY, anchor.height, size.height, align))
    }
  }

  private static func along(
    _ start: CGFloat, _ anchor: CGFloat, _ size: CGFloat, _ align: Align
  ) -> CGFloat {
    switch align {
    case .start: start
    case .center: start + (anchor - size) / 2
    case .end: start + anchor - size
    }
  }

  /// Whether `frame` fits in `bounds` along the axis `side` points on.
  private static func fits(_ frame: CGRect, on side: Side, in bounds: CGRect) -> Bool {
    switch side {
    case .above, .below: frame.minY >= bounds.minY && frame.maxY <= bounds.maxY
    case .left, .right: frame.minX >= bounds.minX && frame.maxX <= bounds.maxX
    }
  }

  /// `frame` moved the least that puts it inside `bounds`; one larger than `bounds` is kept at its start.
  private static func shifted(_ frame: CGRect, in bounds: CGRect) -> CGRect {
    var result = frame
    result.origin.x = min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width))
    result.origin.y = min(
      max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))
    return result
  }
}
