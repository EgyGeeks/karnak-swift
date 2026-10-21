import SwiftUI

/// What a subview of a carousel's layout is.
enum CarouselRole {
  /// The scroll view with the items.
  case items
  /// The items measured to fit the height: never placed.
  case ruler
  /// The row of dots.
  case dots
}

struct CarouselRoleKey: LayoutValueKey {
  static let defaultValue = CarouselRole.items
}

extension View {
  func carouselRole(_ role: CarouselRole) -> some View {
    layoutValue(key: CarouselRoleKey.self, value: role)
  }
}

/// Lays out a `carousel` (`docs/renderer-contract.md`, Display primitives, `carousel`): the scroll view of the items
/// and, below it, the dots. The scroll view is the height of the item area: the carousel's height less the dot row when
/// that is given (a fixed or `fill` height, or a stretched one), else the first viewport's tallest item plus the
/// vertical content padding, which the ruler measures (``KarnakCarouselRuler``) and which no scroll changes. Where the
/// width is not given the carousel is as wide as all its items.
struct KarnakCarouselLayout: Layout, Equatable {
  var metrics = CarouselMetrics()
  /// The height wraps: it is the tallest item of the first viewport, not the space proposed.
  var wrapsHeight = true

  /// The width the subviews get: the proposed width, else the ruler's, which counts every item.
  private func width(_ proposal: ProposedViewSize, ruler: LayoutSubview?) -> CGFloat {
    proposal.width.finite ?? ruler?.sizeThatFits(.unspecified).width ?? 0
  }

  private func areaHeight(
    _ proposal: ProposedViewSize, width: CGFloat?, ruler: LayoutSubview?
  ) -> CGFloat {
    let proposed = proposal.height.finite.map { max(0, $0 - metrics.dotsBlock) }
    if !wrapsHeight, let proposed { return proposed }
    let tallest = ruler?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
    let fitted = tallest + metrics.padding.top + metrics.padding.bottom
    return proposed.map { min(fitted, $0) } ?? fitted
  }

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let ruler = subviews.first { $0[CarouselRoleKey.self] == .ruler }
    let width = width(proposal, ruler: ruler)
    let area = areaHeight(proposal, width: proposal.width.finite, ruler: ruler)
    return CGSize(width: width, height: area + metrics.dotsBlock)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let area = max(0, bounds.height - metrics.dotsBlock)
    for subview in subviews {
      switch subview[CarouselRoleKey.self] {
      case .items:
        subview.place(
          at: bounds.origin, anchor: .topLeading,
          proposal: ProposedViewSize(width: bounds.width, height: area))
      case .dots:
        let dots = metrics.dotsBlock - metrics.dotsSpacing
        subview.place(
          at: CGPoint(x: bounds.minX, y: bounds.minY + area + metrics.dotsSpacing),
          anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: dots))
      case .ruler:
        break
      }
    }
  }
}

/// Measures the first viewport of a carousel, for its height: the tallest of the items whose slot starts inside the
/// width it is proposed, each at its slot width (its natural width for `wrap`). With no width it measures every item
/// and is as wide as they all are. It is never placed: the items it holds exist to be measured, and are the ones
/// that scroll lazily elsewhere.
struct KarnakCarouselRuler: Layout {
  var metrics = CarouselMetrics()

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) -> CGSize {
    let width = proposal.width.finite
    let slot = metrics.slotWidth(in: width)
    var start = metrics.padding.leading
    var tallest: CGFloat = 0
    for subview in subviews {
      if let width, start >= width { break }
      let size = subview.sizeThatFits(ProposedViewSize(width: slot, height: nil))
      tallest = max(tallest, size.height)
      start += (slot ?? size.width) + metrics.spacing
    }
    let total = start - metrics.spacing + metrics.padding.trailing
    return CGSize(width: width ?? max(total, 0), height: tallest)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {}
}
