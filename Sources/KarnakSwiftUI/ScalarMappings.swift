import KarnakCore
import SwiftUI

func points(dp value: Float) -> CGFloat { CGFloat(value) }

func resolvedColor(argb: Int32) -> Color {
  let bits = UInt32(bitPattern: argb)
  return Color(
    .sRGB,
    red: Double((bits >> 16) & 255) / 255,
    green: Double((bits >> 8) & 255) / 255,
    blue: Double(bits & 255) / 255,
    opacity: Double((bits >> 24) & 255) / 255)
}

func edgeInsets(start: Float, top: Float, end: Float, bottom: Float) -> EdgeInsets {
  EdgeInsets(
    top: points(dp: top), leading: points(dp: start),
    bottom: points(dp: bottom), trailing: points(dp: end))
}

func edgeInsets(_ insets: KarnakInsets) -> EdgeInsets {
  edgeInsets(start: insets.start, top: insets.top, end: insets.end, bottom: insets.bottom)
}

func resolvedColor(_ color: Argb) -> Color { resolvedColor(argb: color.value) }
