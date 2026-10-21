import SwiftUI

/// Remembers a layout's recent measurements per proposal, so the probes SwiftUI
/// sends to `sizeThatFits` and the final `placeSubviews` measure each child once.
/// A different configuration discards every stored measurement.
struct LayoutMeasurementCache<Configuration: Equatable, Measurement> {
  /// SwiftUI probes a layout with a few proposals (unspecified, zero, infinite and
  /// the offered size) before placing it; older entries are dropped first.
  private static var capacity: Int { 4 }

  private var configuration: Configuration?
  private var entries: [(proposal: ProposedViewSize, measurement: Measurement)] = []

  mutating func measure(
    configuration: Configuration, proposal: ProposedViewSize,
    using measure: () -> Measurement
  ) -> Measurement {
    if self.configuration != configuration {
      self.configuration = configuration
      entries = []
    }
    if let entry = entries.first(where: { $0.proposal == proposal }) {
      return entry.measurement
    }
    let measured = measure()
    if entries.count == Self.capacity { entries.removeFirst() }
    entries.append((proposal, measured))
    return measured
  }
}

typealias LinearLayoutCache = LayoutMeasurementCache<LinearLayoutConfiguration, LinearMeasurement>
typealias FlowLayoutCache = LayoutMeasurementCache<KarnakFlowLayout, FlowMeasurement>
