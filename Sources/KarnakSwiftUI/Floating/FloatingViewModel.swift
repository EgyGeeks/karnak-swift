import CoreGraphics
import KarnakCore

/// What the layer reads off a ``ResolvedFloating``, in the shapes SwiftUI code wants: where it sits, which group it
/// stacks in and how it ends. The engine resolved every value; nothing is decided here.
extension ResolvedFloating {
  /// The edge it sits at, or nil for the center and an anchored view.
  var edge: ResolvedFloatingPlacementEdge? { placement as? ResolvedFloatingPlacementEdge }

  /// The anchor it follows, or nil for an edge or center view.
  var anchored: ResolvedFloatingPlacementAnchored? {
    placement as? ResolvedFloatingPlacementAnchored
  }

  /// Whether a person is blocked from the screen beneath until it ends.
  var isModal: Bool { behavior.modal }

  /// Whether the layer's own layout places it: an edge, or the center when it isn't modal.
  var isInLayout: Bool { anchored == nil && !isModal }

  /// The group it stacks in (ADR 0038, D6): `screen` views stack outside the transient ones unless they ask `inner`.
  var stackGroup: StackGroup {
    if !screenLifetime { return .transient }
    return behavior.inner ? .inner : .outer
  }

  /// Whether the content holds an actionable node, so its time is the long one and a screen reader keeps it (D10).
  var holdsAction: Bool { content.holdsAction }

  /// The time it stays in milliseconds; nil for sticky.
  var durationMillis: Int? { behavior.durationMillis.map { Int(truncating: $0) } }

  /// Whether an outside tap that reaches the screen below ends it: a view with no focus of its own (a tooltip, a
  /// non-modal center view) lets the tap through, and the screen's gesture ends it (ADR 0038, D7).
  var endsOnTapThrough: Bool {
    behavior.tapOutside && !isModal && !(anchored != nil && holdsAction)
  }

  /// The reason a dismissal gesture ends it with: a swipe when it takes one, else a tap outside.
  var dismissGestureReason: FloatingDismissReason { behavior.swipe ? .swipe : .tapoutside }
}

extension ResolvedNode {
  /// Whether this node, or one below it, can be activated.
  fileprivate var holdsAction: Bool {
    if onClick != nil { return true }
    guard let container = self as? ResolvedContainer else { return false }
    return container.children.contains { $0.holdsAction }
  }
}

/// A floating view as the layer's `ForEach` keeps it: its identity is the engine's key, so a view keeps its state
/// and its timer while later trees arrive, and compares by the engine's value.
struct FloatingItem: Identifiable, Equatable {
  let view: ResolvedFloating
  var id: String { view.key }

  static func == (lhs: FloatingItem, rhs: FloatingItem) -> Bool {
    lhs.view === rhs.view || lhs.view.isEqual(rhs.view)
  }
}

/// The physical alignment of an edge view or anchored view, from the engine's.
extension ResolvedFloatingPlacementAlign {
  /// The alignment along an anchor; `fill` reads as `start`.
  var alongAnchor: FloatingGeometry.Align {
    switch self {
    case .center: .center
    case .right: .end
    default: .start
    }
  }
}

extension ResolvedFloatingPlacementSide {
  /// The side as geometry.
  var geometry: FloatingGeometry.Side {
    switch self {
    case .above: .above
    case .below: .below
    case .left: .left
    default: .right
    }
  }
}
