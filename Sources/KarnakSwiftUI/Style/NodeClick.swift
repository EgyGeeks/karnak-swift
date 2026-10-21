import KarnakCore
import SwiftUI

/// Sends `click(handle)` when a clickable node is tapped or activated by an assistive
/// technology. Hits land anywhere in the node's touch target, not only in its drawn box.
///
/// A clickable container whose children stay separately reachable (one of them is actionable
/// itself, so it doesn't merge) is a group, not an element, and VoiceOver can't activate a
/// group. So it gets its own element behind its children, named by its semantics, which
/// VoiceOver reaches first and activates without a hit test: a child's touch target never
/// takes the container's activation.
struct NodeClick: ViewModifier {
  /// The node's click handle; nil when it isn't clickable.
  let handle: ActionHandle?
  /// The touch target's side in points; 0 for none.
  let touchTarget: CGFloat
  /// The semantics of a container whose children stay reachable; nil for a node that is one
  /// accessibility element.
  var group: AccessibilitySemantics?
  @Environment(\.karnakActions) private var actions

  func body(content: Content) -> some View {
    if let handle {
      let tappable =
        content
        .contentShape(TouchTargetShape(minimum: touchTarget))
        .onTapGesture { actions.click(handle) }
      if let group {
        tappable.background {
          Rectangle().fill(.clear)
            .accessibilityElement(children: .ignore)
            .modifier(NodeSemantics(semantics: group, isContainer: false))
            .accessibilityAction { actions.click(handle) }
            // Before its children, as the tree orders a container.
            .accessibilitySortPriority(1)
        }
        // Its own container, so the priority orders the element only among the node's children.
        .accessibilityElement(children: .contain)
      } else {
        tappable.accessibilityAction { actions.click(handle) }
      }
    } else {
      content
    }
  }
}

/// Reserves at least a `minimum` square for a node whose parent doesn't, with the node
/// centered in it (`docs/renderer-contract.md`, `touchTarget`). Unlike
/// `.frame(minWidth:minHeight:)`, it never shrinks the node below its own size when the parent
/// offers less.
struct ReservedTouchTarget: ViewModifier {
  /// The touch target's side in points; 0 reserves nothing.
  let minimum: CGFloat

  func body(content: Content) -> some View {
    if minimum > 0 {
      TouchTargetLayout(minimum: minimum) { content }
    } else {
      content
    }
  }
}

private struct TouchTargetLayout: Layout {
  let minimum: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let size = subviews.first?.sizeThatFits(proposal) ?? .zero
    return CGSize(width: max(size.width, minimum), height: max(size.height, minimum))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let content = subviews.first else { return }
    let size = content.sizeThatFits(proposal)
    content.place(
      at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: ProposedViewSize(size)
    )
  }
}
