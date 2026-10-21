import SwiftUI

enum KarnakArrangement: CaseIterable, Sendable {
  case start, center, end, spaceBetween, spaceAround, spaceEvenly

  func distribution(count: Int, free: CGFloat) -> (leading: CGFloat, gap: CGFloat) {
    guard count > 0, free > 0 else { return (0, 0) }
    switch self {
    case .start: return (0, 0)
    case .center: return (free / 2, 0)
    case .end: return (free, 0)
    case .spaceBetween: return (0, count > 1 ? free / CGFloat(count - 1) : 0)
    case .spaceAround: return (free / CGFloat(count) / 2, free / CGFloat(count))
    case .spaceEvenly: return (free / CGFloat(count + 1), free / CGFloat(count + 1))
    }
  }
}

enum KarnakCrossAlignment: CaseIterable, Sendable {
  case start, center, end, stretch

  func offset(free: CGFloat) -> CGFloat {
    switch self {
    case .start, .stretch: return 0
    case .center: return free / 2
    case .end: return free
    }
  }
}
