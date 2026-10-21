import KarnakCore
import SwiftUI

/// How a node's box sizes on one axis (`docs/components.md`, Size constraints): its `Size`, its
/// min/max bounds, and whether its parent allocates the size.
struct AxisSizing: Equatable {
  /// The resolved `Size`.
  enum Mode: Equatable {
    case wrap
    case fill
    case fixed(CGFloat)
  }

  var mode: Mode = .wrap
  var minimum: CGFloat = 0
  var maximum: CGFloat = .infinity
  /// The parent allocated this axis (a weight or `stretch`), so the box takes its proposal.
  var acceptsProposal = false

  /// The bounds win over everything, so a minimum that doesn't fit overflows.
  func clamp(_ value: CGFloat) -> CGFloat {
    max(minimum, min(value, maximum))
  }

  /// The box's size when it doesn't depend on its content: an allocated or `Fixed` size, or a
  /// `Fill` size in a bounded parent. Nil when the box fits its content.
  func exact(proposed: CGFloat?) -> CGFloat? {
    switch (mode, proposed) {
    case (_, let proposed?) where acceptsProposal: clamp(proposed)
    case (.fixed(let size), _): clamp(size)
    case (.fill, let proposed?): clamp(proposed)
    default: nil
    }
  }

  /// What the box offers its content: its exact size, else the proposal within its bounds; an
  /// unbounded proposal becomes the maximum, so text wraps at it.
  func contentProposal(proposed: CGFloat?) -> CGFloat? {
    exact(proposed: proposed) ?? (proposed ?? (maximum.isFinite ? maximum : nil)).map(clamp)
  }

  /// The box's size given what its content measured.
  func size(proposed: CGFloat?, content: CGFloat) -> CGFloat {
    exact(proposed: proposed) ?? clamp(content)
  }
}

extension AxisSizing {
  /// One axis of `layout`: `size` with its `minimum` and `maximum` in dp.
  init(size: KarnakSize, minimum: KotlinFloat?, maximum: KotlinFloat?, acceptsProposal: Bool) {
    let mode: Mode =
      switch size {
      case let fixed as KarnakSizeFixed: .fixed(points(dp: fixed.dp))
      case is KarnakSizeFill: .fill
      default: .wrap
      }
    self.init(
      mode: mode, minimum: bound(minimum) ?? 0, maximum: bound(maximum) ?? .infinity,
      acceptsProposal: acceptsProposal)
  }
}
