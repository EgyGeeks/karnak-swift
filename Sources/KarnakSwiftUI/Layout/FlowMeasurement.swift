import SwiftUI

struct FlowLine {
  var indices: [Int] = []
  var width: CGFloat = 0
  var height: CGFloat = 0
}

struct FlowMeasurement {
  var drawn: [CGSize]
  var occupied: [CGSize]
  var lines: [FlowLine]
  var size: CGSize

  init(subviews: LayoutSubviews, width: CGFloat?, spacing: CGFloat) {
    let drawn = subviews.map { subview in
      let input = subview[KarnakLayoutInputKey.self]
      let natural = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
      let measuredWidth = input.width.clamp(natural.width)
      let measured = subview.sizeThatFits(ProposedViewSize(width: measuredWidth, height: nil))
      return CGSize(width: measuredWidth, height: input.height.clamp(measured.height))
    }
    self.drawn = drawn
    let occupied = subviews.indices.map { index in
      let input = subviews[index][KarnakLayoutInputKey.self]
      return CGSize(
        width: max(drawn[index].width, input.width.touchTarget),
        height: max(drawn[index].height, input.height.touchTarget))
    }
    self.occupied = occupied
    lines = []
    var line = FlowLine()
    for index in subviews.indices {
      let item = occupied[index]
      let gap = line.indices.isEmpty ? 0 : spacing
      if !line.indices.isEmpty, let width, line.width + gap + item.width > width {
        lines.append(line)
        line = FlowLine()
      }
      line.width += (line.indices.isEmpty ? 0 : spacing) + item.width
      line.height = max(line.height, item.height)
      line.indices.append(index)
    }
    if !line.indices.isEmpty { lines.append(line) }
    size = CGSize(
      width: lines.map(\.width).max() ?? 0,
      height: lines.reduce(CGFloat.zero) { $0 + $1.height } + spacing
        * CGFloat(max(0, lines.count - 1)))
  }
}
