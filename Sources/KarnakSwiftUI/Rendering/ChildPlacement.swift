import KarnakCore
import SwiftUI

/// What a node's parent decides about its box.
///
/// SwiftUI views size themselves, so a parent whose custom `Layout` allocates a size (a weight
/// on the main axis, `stretch` on the cross axis) needs the child to take exactly the size it
/// proposes on those axes, and to measure its content everywhere else.
struct ChildPlacement: Equatable {
  /// The axes on which the node takes the size its parent proposes.
  var acceptsProposal: Axis.Set = []
  /// Whether the node reserves its own touch target. The row, column and flow layouts reserve
  /// their children's touch targets in their slots, so their children don't.
  var reservesTouchTarget = true
  /// Whether the node is a screen's root that fills the space the host proposes on both axes,
  /// whatever its own sizes and bounds say (`docs/renderer-contract.md`, The root fills the
  /// screen).
  var fillsHost = false

  /// A node its parent doesn't size: a stack's child, a fallback, a section's root.
  static let standalone = ChildPlacement()

  /// The root of a screen: it takes the whole space the host proposes.
  static let root = ChildPlacement(fillsHost: true)

  /// A child of a row (`axis` horizontal) or a column or form (`axis` vertical) that `stretches`
  /// children on its cross axis. A weighted child takes its allocation on the main axis, and a
  /// child that wraps on the cross axis is stretched.
  static func linear(_ node: ResolvedNode, axis: Axis, stretches: Bool) -> ChildPlacement {
    let layout = node.layout
    var accepts: Axis.Set = []
    if layout.weight != nil { accepts.insert(axis == .horizontal ? .horizontal : .vertical) }
    let cross = axis == .horizontal ? layout.height : layout.width
    let stretching = layout.align.map { $0 == .stretch } ?? stretches
    if stretching && cross is KarnakSizeWrap {
      accepts.insert(axis == .horizontal ? .vertical : .horizontal)
    }
    return ChildPlacement(acceptsProposal: accepts, reservesTouchTarget: false)
  }

  /// A child of a grid: the grid decides every child's width (its own, at most its cells' width;
  /// all of them for `Fill` or a stretched `Wrap`), so the child takes the width it proposes. The
  /// grid reserves its children's touch targets in their slots.
  static let gridCell = ChildPlacement(acceptsProposal: [.horizontal], reservesTouchTarget: false)
}

extension ChildPlacement {
  /// Whether a container's layout hugs its content on `axis`: only on a `Wrap` axis its parent
  /// doesn't allocate. Otherwise it takes the size its box proposes, as a `Fixed` or `Fill`
  /// size does.
  func wraps(_ axis: Axis, of layout: ResolvedLayout) -> Bool {
    if fillsHost { return false }
    let size = axis == .horizontal ? layout.width : layout.height
    return size is KarnakSizeWrap
      && !acceptsProposal.contains(axis == .horizontal ? .horizontal : .vertical)
  }
}

extension KarnakLayoutInput {
  /// The resolved box as the row, column and flow layouts read it: bounds are the drawn box's,
  /// with the padding floor the engine already applied.
  init(_ layout: ResolvedLayout) {
    let touchTarget = CGFloat(layout.touchTarget?.floatValue ?? 0)
    self.init(
      weight: CGFloat(layout.weight?.floatValue ?? 0),
      width: AxisBounds(
        minimum: bound(layout.minWidth) ?? 0, maximum: bound(layout.maxWidth) ?? .infinity,
        touchTarget: touchTarget),
      height: AxisBounds(
        minimum: bound(layout.minHeight) ?? 0, maximum: bound(layout.maxHeight) ?? .infinity,
        touchTarget: touchTarget),
      wrapsWidth: layout.width is KarnakSizeWrap,
      wrapsHeight: layout.height is KarnakSizeWrap,
      fixedWidth: layout.width is KarnakSizeFixed,
      align: layout.align.map(crossAlignment),
      span: layout.span.map { Int(truncating: $0) } ?? 1,
      fillsHeight: layout.height is KarnakSizeFill)
  }
}

extension KarnakLayoutInput {
  /// The input of `node`'s layout, which also knows the nodes that take the width they are given
  /// (`docs/renderer-contract.md`, Display primitives, `grid`, Width).
  init(_ node: ResolvedNode) {
    self.init(node.layout)
    takesGivenWidth = node is ResolvedGrid && node.layout.width is KarnakSizeWrap
  }
}

/// An optional dp bound in points.
func bound(_ value: KotlinFloat?) -> CGFloat? {
  value.map { points(dp: $0.floatValue) }
}
