import KarnakCore
import SwiftUI
import UIKit

/// A `Color` that follows the system's light and dark appearance.
enum DynamicColor {
  /// The color `read` answers for each mode, as a dynamic `Color`; `nil` when it knows neither mode.
  /// `read` runs when SwiftUI resolves the color, so a newer theme and the other appearance apply
  /// without a request. A mode `read` doesn't know takes the other mode's value.
  static func make(_ read: @escaping (ColorMode) -> Argb?) -> Color? {
    guard let known = read(.light) ?? read(.dark) else { return nil }
    return Color(
      uiColor: UIColor { traits in
        let dark = traits.userInterfaceStyle == .dark
        let mode: ColorMode = dark ? .dark : .light
        let other: ColorMode = dark ? .light : .dark
        return uiColor(read(mode) ?? read(other) ?? known)
      })
  }

  private static func uiColor(_ color: Argb) -> UIColor {
    let bits = UInt32(bitPattern: color.value)
    return UIColor(
      red: CGFloat((bits >> 16) & 0xFF) / 255, green: CGFloat((bits >> 8) & 0xFF) / 255,
      blue: CGFloat(bits & 0xFF) / 255, alpha: CGFloat(bits >> 24) / 255)
  }
}
