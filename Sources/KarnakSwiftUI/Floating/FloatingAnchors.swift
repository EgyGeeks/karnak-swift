import KarnakCore
import SwiftUI

/// The bounds of the nodes the engine marked `floatingAnchor`, by node key (ADR 0038, D5 and D19): a marked node's view
/// offers its bounds up the tree, and the layer reads them in the screen's overlay, so an anchored view follows its
/// anchor while it scrolls, in the layout phase, never through a new tree. The system `.popover` is not used.
struct FloatingAnchorKey: PreferenceKey {
  static let defaultValue: [String: Anchor<CGRect>] = [:]

  static func reduce(
    value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
  ) {
    value.merge(nextValue()) { _, new in new }
  }
}

/// Offers a node's bounds to the layer when the engine marked it (`ResolvedNode.floatingAnchor`). The mark is known from
/// the content alone, so it never changes on a show, and a node that isn't marked is left as it is.
struct FloatingAnchorModifier: ViewModifier {
  let key: String
  let isAnchor: Bool

  func body(content: Content) -> some View {
    if isAnchor {
      content.anchorPreference(key: FloatingAnchorKey.self, value: .bounds) { [key: $0] }
    } else {
      content
    }
  }
}

extension View {
  /// Makes this node's bounds available to the floating layer when `node` is an anchor.
  func floatingAnchor(of node: ResolvedNode) -> some View {
    modifier(FloatingAnchorModifier(key: node.key.value, isAnchor: node.floatingAnchor))
  }

  /// Offers none of the anchors inside this view: for copies of nodes that are measured but never placed (a
  /// carousel's ruler), whose bounds would otherwise replace those of the drawn node of the same key.
  func offeringNoFloatingAnchors() -> some View {
    transformPreference(FloatingAnchorKey.self) { $0 = [:] }
  }
}
