import SwiftUI

/// The ideal height of each entry of a sheet's contained stack drawn so far, and the detent they set.
struct SheetHeights {
  private var heights: [String: CGFloat] = [:]

  mutating func record(_ height: CGFloat, for id: String) { heights[id] = height }

  /// The sheet is as tall as its top entry, once measured. A native route is not measured: its
  /// own `Form` or `List` has no ideal height to ask for, so it is presented at the large detent.
  func detent(top entry: OverlayEntry?) -> PresentationDetent {
    guard let entry, entry.route == nil else { return .large }
    return .measured(heights[entry.id])
  }
}

extension PresentationDetent {
  /// The detent at a measured height, which the system caps at the large detent. Until a screen is
  /// measured the sheet opens at the medium detent, as it did before sheets were fitted.
  static func measured(_ height: CGFloat?) -> PresentationDetent {
    height.map { .height($0) } ?? .medium
  }
}
