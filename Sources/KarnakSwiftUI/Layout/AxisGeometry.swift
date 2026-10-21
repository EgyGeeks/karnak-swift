import SwiftUI

extension Axis {
  func main(_ proposal: ProposedViewSize) -> CGFloat? {
    (self == .horizontal ? proposal.width : proposal.height).finite
  }
  func cross(_ proposal: ProposedViewSize) -> CGFloat? {
    (self == .horizontal ? proposal.height : proposal.width).finite
  }
  func main(_ size: CGSize) -> CGFloat { self == .horizontal ? size.width : size.height }
  func cross(_ size: CGSize) -> CGFloat { self == .horizontal ? size.height : size.width }
  func size(main: CGFloat, cross: CGFloat) -> CGSize {
    self == .horizontal ? CGSize(width: main, height: cross) : CGSize(width: cross, height: main)
  }
  func proposal(main: CGFloat?, cross: CGFloat?) -> ProposedViewSize {
    self == .horizontal
      ? ProposedViewSize(width: main, height: cross) : ProposedViewSize(width: cross, height: main)
  }
  func bounds(_ input: KarnakLayoutInput) -> AxisBounds {
    self == .horizontal ? input.width : input.height
  }
  func crossBounds(_ input: KarnakLayoutInput) -> AxisBounds {
    self == .horizontal ? input.height : input.width
  }
  func wrapsCross(_ input: KarnakLayoutInput) -> Bool {
    self == .horizontal ? input.wrapsHeight : input.wrapsWidth
  }
}

extension Optional where Wrapped == CGFloat {
  var finite: CGFloat? { flatMap { $0.isFinite ? max(0, $0) : nil } }
}

func layoutExtent(proposed: CGFloat?, content: CGFloat, wraps: Bool) -> CGFloat {
  guard let proposed else { return content }
  return wraps ? min(proposed, content) : proposed
}
