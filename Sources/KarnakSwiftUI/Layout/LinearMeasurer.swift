import SwiftUI

/// One measurement pass of a row or column for a single proposal.
/// `measure()` composes the steps: natural sizes, weighted allocation, a second
/// measurement at the allocated sizes, the cross extent and the drawn sizes.
struct LinearMeasurer {
  private let configuration: LinearLayoutConfiguration
  private let subviews: LayoutSubviews
  private let inputs: [KarnakLayoutInput]
  private let main: CGFloat?
  private let cross: CGFloat?

  init(
    configuration: LinearLayoutConfiguration, proposal: ProposedViewSize,
    subviews: LayoutSubviews
  ) {
    self.configuration = configuration
    self.subviews = subviews
    let inputs = subviews.map { $0[KarnakLayoutInputKey.self] }
    self.inputs = inputs
    main = configuration.axis.main(proposal)
    cross = Self.crossLimit(
      configuration: configuration, proposed: configuration.axis.cross(proposal),
      subviews: subviews, inputs: inputs)
  }

  /// A wrapping container that stretches children takes its widest child's cross size, and
  /// stretched children accept any cross size they are offered. So their contribution is their
  /// intrinsic size (unspecified cross proposal), as Compose's `IntrinsicSize.Max`, and every
  /// child is then measured against that extent, as if the container had it as a fixed size.
  private static func crossLimit(
    configuration: LinearLayoutConfiguration, proposed: CGFloat?,
    subviews: LayoutSubviews, inputs: [KarnakLayoutInput]
  ) -> CGFloat? {
    let axis = configuration.axis
    guard let proposed, configuration.wrapsCross,
      inputs.contains(where: { input in
        axis.wrapsCross(input) && (input.align ?? configuration.alignment) == .stretch
      })
    else { return proposed }
    let content = subviews.indices.map { index in
      let bounds = axis.crossBounds(inputs[index])
      let offered = axis.wrapsCross(inputs[index]) ? nil : bounds.clamp(proposed)
      let size = subviews[index].sizeThatFits(axis.proposal(main: nil, cross: offered))
      return bounds.occupied(axis.cross(size))
    }
    return min(proposed, content.max() ?? 0)
  }

  private var axis: Axis { configuration.axis }
  private var totalSpacing: CGFloat {
    configuration.spacing * CGFloat(max(0, subviews.count - 1))
  }

  func measure() -> LinearMeasurement {
    let natural = naturalSizes()
    let slots = allocateSlots(
      allocationInputs(natural: natural), extent: main, spacing: configuration.spacing)
    let measured = remeasure(at: slots, natural: natural)
    let crossExtent = crossExtent(measured: measured)
    let drawn = drawnSizes(slots: slots, measured: measured, crossExtent: crossExtent)
    let content = slots.reduce(CGFloat.zero) { $0 + $1.occupied } + totalSpacing
    return LinearMeasurement(
      slots: slots, drawn: drawn,
      occupiedCross: occupiedCross(drawn: drawn), content: content,
      size: axis.size(main: mainExtent(content: content), cross: crossExtent))
  }

  /// Unweighted children are measured in order against the main-axis space that
  /// spacing and the earlier unweighted children leave, as Compose `Row` does and
  /// CSS flex items shrink, so wrapping content fits instead of being offered the
  /// whole container. Bounds and touch targets apply afterwards, so minimums
  /// still overflow. Weighted children are measured again at their allocation.
  private func naturalSizes() -> [CGSize] {
    var remaining = main.map { $0 - totalSpacing }
    var sizes: [CGSize] = []
    for index in subviews.indices {
      guard inputs[index].weight <= 0, let available = remaining else {
        sizes.append(naturalSize(index, main: main))
        continue
      }
      let size = naturalSize(index, main: max(0, available))
      remaining = available - axis.bounds(inputs[index]).occupied(axis.main(size))
      sizes.append(size)
    }
    return sizes
  }

  /// Measures once to learn the cross size, then again with that size clamped to
  /// the child's cross bounds, since a bounded cross axis can change the main size.
  private func naturalSize(_ index: Int, main: CGFloat?) -> CGSize {
    let initial = subviews[index].sizeThatFits(
      axis.proposal(main: main, cross: crossProposal(index)))
    let boundedCross = axis.crossBounds(inputs[index]).clamp(axis.cross(initial))
    return subviews[index].sizeThatFits(axis.proposal(main: main, cross: boundedCross))
  }

  private func crossProposal(_ index: Int) -> CGFloat? {
    cross.map { axis.crossBounds(inputs[index]).clamp($0) }
  }

  private func allocationInputs(natural: [CGSize]) -> [AllocationInput] {
    inputs.indices.map {
      AllocationInput(
        weight: inputs[$0].weight, measured: axis.main(natural[$0]),
        bounds: axis.bounds(inputs[$0]))
    }
  }

  /// Measures again at the allocated main size: text can change its cross size.
  private func remeasure(at slots: [AllocatedSlot], natural: [CGSize]) -> [CGSize] {
    subviews.indices.map { index in
      let mainSize = slots[index].drawn
      let crossSize =
        mainSize == axis.main(natural[index])
        ? axis.crossBounds(inputs[index]).clamp(axis.cross(natural[index]))
        : crossProposal(index)
      return subviews[index].sizeThatFits(axis.proposal(main: mainSize, cross: crossSize))
    }
  }

  private func crossExtent(measured: [CGSize]) -> CGFloat {
    let occupied = inputs.indices.map {
      axis.crossBounds(inputs[$0]).occupied(axis.cross(measured[$0]))
    }
    return layoutExtent(
      proposed: cross, content: occupied.max() ?? 0, wraps: configuration.wrapsCross)
  }

  private func drawnSizes(
    slots: [AllocatedSlot], measured: [CGSize], crossExtent: CGFloat
  ) -> [CGSize] {
    inputs.indices.map { index in
      let stretch =
        (inputs[index].align ?? configuration.alignment) == .stretch
        && axis.wrapsCross(inputs[index])
      let crossSize = axis.crossBounds(inputs[index]).clamp(
        stretch ? crossExtent : axis.cross(measured[index]))
      return axis.size(main: slots[index].drawn, cross: crossSize)
    }
  }

  private func occupiedCross(drawn: [CGSize]) -> [CGFloat] {
    inputs.indices.map { axis.crossBounds(inputs[$0]).occupied(axis.cross(drawn[$0])) }
  }

  /// A weighted bounded main axis always fills its proposal.
  private func mainExtent(content: CGFloat) -> CGFloat {
    layoutExtent(
      proposed: main, content: content,
      wraps: configuration.wrapsMain && !inputs.contains { $0.weight > 0 })
  }
}
