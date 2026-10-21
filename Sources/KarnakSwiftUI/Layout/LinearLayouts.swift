import SwiftUI

protocol KarnakLinearLayout: Layout where Cache == LinearLayoutCache {
  var configuration: LinearLayoutConfiguration { get }
}

extension KarnakLinearLayout {
  func makeCache(subviews: Subviews) -> LinearLayoutCache { LinearLayoutCache() }

  func updateCache(_ cache: inout LinearLayoutCache, subviews: Subviews) {
    cache = LinearLayoutCache()
  }

  func sizeThatFits(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout LinearLayoutCache
  ) -> CGSize {
    measurement(proposal: proposal, subviews: subviews, cache: &cache).size
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
    cache: inout LinearLayoutCache
  ) {
    let measured = measurement(proposal: proposal, subviews: subviews, cache: &cache)
    configuration.place(bounds: bounds, measured: measured, subviews: subviews)
  }

  private func measurement(
    proposal: ProposedViewSize, subviews: Subviews, cache: inout LinearLayoutCache
  ) -> LinearMeasurement {
    cache.measure(configuration: configuration, proposal: proposal) {
      configuration.measure(proposal: proposal, subviews: subviews)
    }
  }
}

struct KarnakRowLayout: KarnakLinearLayout {
  var wrapsWidth = true
  var wrapsHeight = true
  var spacing: CGFloat = 0
  var arrangement: KarnakArrangement = .start
  var alignment: KarnakCrossAlignment = .start

  var configuration: LinearLayoutConfiguration {
    LinearLayoutConfiguration(
      wrapsWidth: wrapsWidth, wrapsHeight: wrapsHeight, axis: .horizontal, spacing: spacing,
      arrangement: arrangement, alignment: alignment)
  }
}

struct KarnakColumnLayout: KarnakLinearLayout {
  var wrapsWidth = true
  var wrapsHeight = true
  var spacing: CGFloat = 0
  var arrangement: KarnakArrangement = .start
  var alignment: KarnakCrossAlignment = .start

  var configuration: LinearLayoutConfiguration {
    LinearLayoutConfiguration(
      wrapsWidth: wrapsWidth, wrapsHeight: wrapsHeight, axis: .vertical, spacing: spacing,
      arrangement: arrangement, alignment: alignment)
  }
}
