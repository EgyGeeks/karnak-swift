import CoreGraphics

/// How a node's content relates to its box (`docs/renderer-contract.md`, `image`).
///
/// Most primitives are measured: a `Wrap` box fits them. An image has no size before it loads,
/// so its box is sized from the node's layout alone, optionally through an aspect ratio, and the
/// image fills whatever box that gives.
struct BoxContent: Equatable {
  /// Whether the content takes the box's size instead of being measured.
  var fillsBox = false
  /// Width ÷ height applied to the box when one dimension is `Wrap` or `Fill`; nil for none.
  var aspectRatio: CGFloat?

  /// Content the box measures, such as text or a container's children.
  static let measured = BoxContent()

  /// An image's content: it fills the box, which keeps `aspectRatio` when there is one.
  static func image(aspectRatio: CGFloat?) -> BoxContent {
    BoxContent(
      fillsBox: true, aspectRatio: aspectRatio.flatMap { $0 > 0 && $0.isFinite ? $0 : nil })
  }
}

/// One box size with `ratio` (width ÷ height), as Compose's image box sizes it: from an exact
/// width, else from an exact height, else the widest width the proposal and the height's maximum
/// allow. An exact size is an allocated, `Fixed` or bounded `Fill` one (``AxisSizing/exact(proposed:)``).
/// The derived side obeys only the node's own bounds, not the space the parent offers, so the
/// box keeps its ratio and overflows like any box that doesn't fit; when the bounds allow no
/// size with the ratio, they win. Nil when neither axis bounds the other, so there is no size to
/// derive: the box then sizes as if it had no ratio.
func aspectRatioSize(
  width: AxisSizing, height: AxisSizing, proposed: (width: CGFloat?, height: CGFloat?),
  ratio: CGFloat
) -> CGSize? {
  let exactWidth = width.exact(proposed: proposed.width)
  let exactHeight = height.exact(proposed: proposed.height)
  let derivedWidth: CGFloat
  if let exactWidth {
    derivedWidth = exactWidth
  } else if let exactHeight {
    derivedWidth = width.clamp(exactHeight * ratio)
  } else {
    let available = width.contentProposal(proposed: proposed.width) ?? .infinity
    derivedWidth = width.clamp(min(available, height.maximum * ratio))
  }
  guard derivedWidth.isFinite else { return nil }
  return CGSize(width: derivedWidth, height: exactHeight ?? height.clamp(derivedWidth / ratio))
}
