import SwiftUI

struct LinearMeasurement {
  var slots: [AllocatedSlot]
  var drawn: [CGSize]
  var occupiedCross: [CGFloat]
  var content: CGFloat
  var size: CGSize
}

struct LinearLayoutConfiguration: Equatable {
  var wrapsWidth: Bool
  var wrapsHeight: Bool
  var axis: Axis
  var spacing: CGFloat
  var arrangement: KarnakArrangement
  var alignment: KarnakCrossAlignment

  var wrapsMain: Bool { axis == .horizontal ? wrapsWidth : wrapsHeight }
  var wrapsCross: Bool { axis == .horizontal ? wrapsHeight : wrapsWidth }

  func measure(proposal: ProposedViewSize, subviews: LayoutSubviews) -> LinearMeasurement {
    LinearMeasurer(configuration: self, proposal: proposal, subviews: subviews).measure()
  }

  func place(bounds: CGRect, measured: LinearMeasurement, subviews: LayoutSubviews) {
    let distribution = arrangement.distribution(
      count: subviews.count, free: axis.main(bounds.size) - measured.content)
    var cursor = distribution.leading
    for index in subviews.indices {
      let own = subviews[index][KarnakLayoutInputKey.self].align ?? alignment
      let cross =
        own.offset(free: axis.cross(bounds.size) - measured.occupiedCross[index])
        + (measured.occupiedCross[index] - axis.cross(measured.drawn[index])) / 2
      let origin = axis.size(main: cursor + measured.slots[index].inset, cross: cross)
      // SwiftUI mirrors these logical x coordinates in RTL, including overflow.
      subviews[index].place(
        at: CGPoint(x: bounds.minX + origin.width, y: bounds.minY + origin.height),
        anchor: .topLeading, proposal: ProposedViewSize(measured.drawn[index]))
      cursor += measured.slots[index].occupied + spacing + distribution.gap
    }
  }
}
