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

  /// `hugsWidth`: the row is as wide as its content, so its lines flex in what the children need
  /// on one line (at most `width`) and a row that fits on one line has no free width to share.
  init(subviews: LayoutSubviews, width: CGFloat?, spacing: CGFloat, hugsWidth: Bool = false) {
    let inputs = subviews.map { $0[KarnakLayoutInputKey.self] }
    let items = subviews.indices.map { FlowItem(subviews[$0], input: inputs[$0], line: width) }
    var lines = FlowLine.breaking(items.map(\.flex.hypothetical), width: width, spacing: spacing)
    var widths = items.map(\.flex.hypothetical)
    if let width {
      let content = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
      let rowWidth = hugsWidth ? min(width, content) : width
      for line in lines where line.indices.contains(where: { inputs[$0].flex != nil }) {
        let space = rowWidth - spacing * CGFloat(line.indices.count - 1)
        let resolved = FlexLine.widths(space: space, items: line.indices.map { items[$0].flex })
        for (slot, index) in line.indices.enumerated() { widths[index] = resolved[slot] }
      }
    }
    let drawn = subviews.indices.map { index in
      let input = inputs[index]
      let drawnWidth = items[index].drawnWidth ?? input.width.clamp(widths[index])
      let measured = subviews[index].sizeThatFits(ProposedViewSize(width: drawnWidth, height: nil))
      return CGSize(width: drawnWidth, height: input.height.clamp(measured.height))
    }
    self.drawn = drawn
    let occupied = subviews.indices.map { index in
      CGSize(
        width: max(drawn[index].width, inputs[index].width.touchTarget),
        height: max(drawn[index].height, inputs[index].height.touchTarget))
    }
    self.occupied = occupied
    for line in lines.indices {
      let members = lines[line].indices
      lines[line].width =
        members.reduce(CGFloat.zero) { $0 + occupied[$1].width }
        + spacing * CGFloat(members.count - 1)
      lines[line].height = members.map { occupied[$0].height }.max() ?? 0
    }
    self.lines = lines
    size = CGSize(
      width: lines.map(\.width).max() ?? 0,
      height: lines.reduce(CGFloat.zero) { $0 + $1.height } + spacing
        * CGFloat(max(0, lines.count - 1)))
  }
}

extension FlowLine {
  /// Children of occupied `widths` broken greedily onto lines no wider than `width`.
  static func breaking(_ widths: [CGFloat], width: CGFloat?, spacing: CGFloat) -> [FlowLine] {
    var lines: [FlowLine] = []
    var line = FlowLine()
    for (index, item) in widths.enumerated() {
      let gap = line.indices.isEmpty ? 0 : spacing
      if !line.indices.isEmpty, let width, line.width + gap + item > width {
        lines.append(line)
        line = FlowLine()
      }
      line.width += (line.indices.isEmpty ? 0 : spacing) + item
      line.indices.append(index)
    }
    if !line.indices.isEmpty { lines.append(line) }
    return lines
  }
}

/// A child of a wrapping row before its line is known.
private struct FlowItem {
  /// Its inputs to its line's flexible widths, in occupied sizes. A child that doesn't flex has
  /// no factors, so it keeps its width.
  var flex: FlexLineItem
  /// The width a child that doesn't flex draws at; nil for one that flexes.
  var drawnWidth: CGFloat?

  init(_ subview: LayoutSubview, input: KarnakLayoutInput, line: CGFloat?) {
    guard let flex = input.flex else {
      let natural = subview.sizeThatFits(ProposedViewSize(width: line, height: nil))
      let measured = input.width.clamp(natural.width)
      drawnWidth = measured
      self.flex = FlexLineItem(base: max(measured, input.width.touchTarget))
      return
    }
    self.flex = FlexLineItem(
      base: flex.basis ?? Self.ownWidth(subview, input: input, line: line), grow: flex.grow,
      shrink: flex.shrink, lower: input.width.lower, upper: input.width.upper)
  }

  /// The width of a flexed child without a basis: its line's when it fills, else its content's,
  /// at most its line's.
  private static func ownWidth(
    _ subview: LayoutSubview, input: KarnakLayoutInput, line: CGFloat?
  ) -> CGFloat {
    if let line, !input.wrapsWidth, !input.fixedWidth { return line }
    let natural = subview.sizeThatFits(.unspecified).width
    return line.map { min(natural, $0) } ?? natural
  }
}
