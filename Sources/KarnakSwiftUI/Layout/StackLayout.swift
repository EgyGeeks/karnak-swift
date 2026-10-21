import SwiftUI

/// Layers children on top of each other, last on top, each at `alignment` on logical edges,
/// and sizes to the largest child (`docs/renderer-contract.md`, `stack`), as Compose's stack
/// policy does. Unlike `ZStack`, it aligns every child in its own bounds, so in a box smaller
/// than the largest child the others still sit at the box's edges, and a child larger than
/// the stack overflows from the aligned edge.
struct KarnakStackLayout: Layout {
  var wrapsWidth = true
  var wrapsHeight = true
  var alignment = ContentPosition.topStart

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let sizes = subviews.map { $0.sizeThatFits(proposal) }
    return CGSize(
      width: layoutExtent(
        proposed: proposal.width.finite, content: sizes.map(\.width).max() ?? 0, wraps: wrapsWidth),
      height: layoutExtent(
        proposed: proposal.height.finite, content: sizes.map(\.height).max() ?? 0,
        wraps: wrapsHeight))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for subview in subviews {
      let size = subview.sizeThatFits(proposal)
      // Logical x: SwiftUI mirrors it in RTL.
      subview.place(
        at: CGPoint(
          x: bounds.minX + (bounds.width - size.width) * alignment.horizontal,
          y: bounds.minY + (bounds.height - size.height) * alignment.vertical),
        anchor: .topLeading, proposal: ProposedViewSize(size))
    }
  }
}
