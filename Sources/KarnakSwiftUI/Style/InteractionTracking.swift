import KarnakCore
import SwiftUI

/// Draws an interactive node that is neither a button nor an input, which track their own, as `styleFor` of the
/// interactions it tracks (`docs/renderer-contract.md`, Style resolution and interaction states): `hovered` while an
/// iPadOS pointer is over it, and `pressed` while a finger is down on a node with a click. A press is a long press
/// that never completes, beside the node's tap: it ends, and the style with it, when the finger lifts, moves away or
/// a scroll takes the touch, and it never takes the tap. iOS has no keyboard focus on such a node, so `focused` never
/// shows.
struct InteractionTracking<Drawn: View>: View {
  /// The node as resolved, without interactions.
  let node: ResolvedNode
  /// Draws the node as it looks now.
  let draw: (ResolvedNode) -> Drawn
  @State private var hovered = false
  @GestureState private var pressed = false

  var body: some View {
    draw(Self.shown(node, hovered: hovered, pressed: pressed))
      .onHover { hovered = $0 }
      .simultaneousGesture(
        LongPressGesture(minimumDuration: .infinity, maximumDistance: pressSlop)
          .updating($pressed) { pressing, state, _ in state = pressing },
        including: node.onClick != nil ? .all : .subviews)
  }

  /// The node as it looks with these interactions: a press counts only on a node with a click, and with none
  /// active the node is drawn as resolved.
  nonisolated static func shown(
    _ node: ResolvedNode, hovered: Bool, pressed: Bool
  ) -> ResolvedNode {
    let active = activeInteractions(
      pressed: pressed && node.onClick != nil, hovered: hovered, focused: false)
    return active.isEmpty ? node : node.styleFor(interaction: active)
  }
}

/// How far a finger may move before a press ends, in points: the system's tap slop.
private let pressSlop: CGFloat = 10
