import SwiftUI

struct KarnakFlowLayout: Layout, Equatable {
  var wrapsWidth = true
  var wrapsHeight = true
  var spacing: CGFloat = 0
  var arrangement: KarnakArrangement = .start
  var alignment: KarnakCrossAlignment = .start

  func makeCache(subviews: Subviews) -> FlowLayoutCache { FlowLayoutCache() }

  func updateCache(_ cache: inout FlowLayoutCache, subviews: Subviews) {
    cache = FlowLayoutCache()
  }

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout FlowLayoutCache
  ) -> CGSize {
    let measured = measurement(proposal: proposal, subviews: subviews, cache: &cache)
    return CGSize(
      width: layoutExtent(
        proposed: proposal.width.finite, content: measured.size.width, wraps: wrapsWidth),
      height: layoutExtent(
        proposed: proposal.height.finite, content: measured.size.height, wraps: wrapsHeight))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout FlowLayoutCache
  ) {
    let measured = measurement(proposal: proposal, subviews: subviews, cache: &cache)
    var top = bounds.minY
    for line in measured.lines {
      let distribution = arrangement.distribution(
        count: line.indices.count, free: bounds.width - line.width)
      var leading = bounds.minX + distribution.leading
      for index in line.indices {
        let input = subviews[index][KarnakLayoutInputKey.self]
        var drawn = measured.drawn[index]
        let own = input.align ?? alignment
        if own == .stretch && input.wrapsHeight {
          drawn.height = input.height.clamp(line.height)
        }
        let occupiedHeight = max(drawn.height, input.height.touchTarget)
        let cross =
          own.offset(free: line.height - occupiedHeight) + (occupiedHeight - drawn.height) / 2
        subviews[index].place(
          at: CGPoint(
            x: leading + (measured.occupied[index].width - drawn.width) / 2, y: top + cross),
          anchor: .topLeading, proposal: ProposedViewSize(drawn))
        leading += measured.occupied[index].width + spacing + distribution.gap
      }
      top += line.height + spacing
    }
  }

  private func measurement(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout FlowLayoutCache
  ) -> FlowMeasurement {
    cache.measure(configuration: self, proposal: proposal) {
      FlowMeasurement(subviews: subviews, width: proposal.width.finite, spacing: spacing)
    }
  }
}
