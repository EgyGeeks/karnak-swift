import KarnakCore
import SwiftUI

/// `carousel`: the items in a horizontal lazy row, with the snap and the dots the engine resolved
/// (`docs/renderer-contract.md`, Display primitives). It is a ``KarnakCarouselLayout`` of the scroll view
/// (``CarouselItems``), the ruler that measures the first viewport for a `wrap` height (``KarnakCarouselRuler``) and
/// the dots; the carousel's size is its accessibility value (``accessibilitySemantics(of:)``).
struct CarouselView: View {
  /// The carousel.
  let carousel: ResolvedCarousel
  /// Which axes of the carousel's box its own parent sizes.
  let placement: ChildPlacement
  @State private var current = 0

  var body: some View {
    let nodes = carousel.children.compactMap(drawnNode)
    let metrics = carouselMetrics(carousel, count: nodes.count)
    KarnakCarouselLayout(
      metrics: metrics, wrapsHeight: placement.wraps(.vertical, of: carousel.layout)
    ) {
      CarouselItems(carousel: carousel, nodes: nodes, metrics: metrics, current: $current)
        .carouselRole(.items)
      KarnakCarouselRuler(metrics: metrics) {
        ForEach(nodes, id: \.key.value) { node in
          NodeView(node: node, placement: .carouselItem(node)).equatable()
        }
      }
      // Never placed, but its items are views, which SwiftUI would draw at its centre: hidden (still measured), out of
      // accessibility, hit testing and the frame observer, and with no viewport, so no `appear` fires for a copy.
      .hidden()
      .accessibilityHidden(true)
      .allowsHitTesting(false)
      .environment(\.karnakFrameObserver, nil)
      .environment(\.karnakViewport, nil)
      .carouselRole(.ruler)
      if let indicator = carousel.indicator, nodes.count > 1 {
        CarouselDots(
          key: carousel.key.value, indicator: indicator, count: nodes.count, current: current
        )
        .carouselRole(.dots)
      }
    }
  }
}

/// The metrics of a carousel in points.
func carouselMetrics(_ carousel: ResolvedCarousel, count: Int) -> CarouselMetrics {
  let indicator = count > 1 ? carousel.indicator : nil
  return CarouselMetrics(
    itemWidth: CarouselSlotWidth(carousel.itemWidth), spacing: points(dp: carousel.spacing),
    padding: edgeInsets(carousel.contentPadding),
    dotsBlock: indicator.map { points(dp: $0.spacing + $0.dotSize) } ?? 0,
    dotsSpacing: indicator.map { points(dp: $0.spacing) } ?? 0)
}

extension ChildPlacement {
  /// A child of a carousel: it takes the item area's height when it `stretch`es, and is otherwise measured. Its slot
  /// reserves its touch target as the item does anywhere else.
  static func carouselItem(_ node: ResolvedNode) -> ChildPlacement {
    let stretches = node.layout.align.map { $0 == .stretch } ?? false
    return ChildPlacement(acceptsProposal: stretches ? [.vertical] : [])
  }
}
