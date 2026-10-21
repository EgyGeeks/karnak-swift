import KarnakCore
import SwiftUI

/// A node's box: its size, bounds and where its content sits in it, as one layout, the way
/// Compose applies them in one layout modifier. SwiftUI's flexible `.frame(maxWidth:)` grows a
/// view to its proposal, which a wrapping box with a maximum must not do.
///
/// The content (the node's padded primitive) is placed at `position`, logically, and overflows
/// from the start edge when it is larger than the box. Content that fills its box, an image's,
/// is sized by the box alone (``BoxContent``).
struct NodeFrameLayout: Layout {
  var width = AxisSizing()
  var height = AxisSizing()
  var position = ContentPosition.topStart
  var content = BoxContent.measured

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let proposedWidth = proposal.width.finite
    let proposedHeight = proposal.height.finite
    let ratioSize = content.aspectRatio.flatMap {
      aspectRatioSize(
        width: width, height: height, proposed: (proposedWidth, proposedHeight), ratio: $0)
    }
    if let ratioSize { return ratioSize }
    // Filling content has no size of its own: measured against nothing, only its padding is left.
    let measured =
      subviews.first?.sizeThatFits(content.fillsBox ? .zero : contentProposal(proposal)) ?? .zero
    return CGSize(
      width: width.size(proposed: proposedWidth, content: measured.width),
      height: height.size(proposed: proposedHeight, content: measured.height))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    guard let content = subviews.first else { return }
    let offered = ProposedViewSize(bounds.size)
    let size = content.sizeThatFits(offered)
    // SwiftUI mirrors these logical x coordinates in RTL.
    content.place(
      at: CGPoint(
        x: bounds.minX + max(0, bounds.width - size.width) * position.horizontal,
        y: bounds.minY + max(0, bounds.height - size.height) * position.vertical),
      anchor: .topLeading, proposal: offered)
  }

  private func contentProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
    ProposedViewSize(
      width: width.contentProposal(proposed: proposal.width.finite),
      height: height.contentProposal(proposed: proposal.height.finite))
  }
}

/// Where content smaller than its box sits, as fractions of the free space from the logical
/// top start corner.
struct ContentPosition: Equatable {
  /// 0 at the start edge, 1 at the end edge.
  var horizontal: CGFloat
  /// 0 at the top, 1 at the bottom.
  var vertical: CGFloat

  static let topStart = ContentPosition(horizontal: 0, vertical: 0)
  /// Centered on both axes, as a button's content is.
  static let center = ContentPosition(horizontal: 0.5, vertical: 0.5)
}

extension ContentPosition {
  /// A stack's content alignment: the stack's children sit together at it.
  init(_ alignment: ContentAlignment) {
    let mapped = stackAlignment(alignment)
    self.init(horizontal: fraction(mapped.horizontal), vertical: fraction(mapped.vertical))
  }

  /// A paragraph's alignment: a text narrower than its box sits at it, top first.
  init(_ alignment: TextAlign) {
    self.init(horizontal: fraction(textAlignment(alignment)), vertical: 0)
  }
}

private func fraction(_ alignment: HorizontalAlignment) -> CGFloat {
  alignment == .leading ? 0 : alignment == .trailing ? 1 : 0.5
}

private func fraction(_ alignment: VerticalAlignment) -> CGFloat {
  alignment == .top ? 0 : alignment == .bottom ? 1 : 0.5
}

private func fraction(_ alignment: TextAlignment) -> CGFloat {
  switch alignment {
  case .leading: 0
  case .trailing: 1
  default: 0.5
  }
}
