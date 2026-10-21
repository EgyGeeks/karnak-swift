import KarnakCore
import SwiftUI
import UIKit

// Pass explicit traits so a Dynamic Type change can remeasure the same tree.
func textPoints(sp value: Float, traits: UITraitCollection) -> CGFloat {
  UIFontMetrics(forTextStyle: .body).scaledValue(for: CGFloat(value), compatibleWith: traits)
}

func fontWeight(_ weight: Int32) -> Font.Weight {
  switch weight {
  case ..<150: .ultraLight
  case ..<250: .thin
  case ..<350: .light
  case ..<450: .regular
  case ..<550: .medium
  case ..<650: .semibold
  case ..<750: .bold
  case ..<850: .heavy
  default: .black
  }
}

func tracking(em value: Float, fontPoints: CGFloat) -> CGFloat {
  CGFloat(value) * fontPoints
}

// The caller scales once with textPoints; fixedSize prevents SwiftUI scaling again.
func resolvedFont(scaledPoints: CGFloat, weight: Int32, italic: Bool) -> Font {
  let weighted = Font.system(size: scaledPoints).weight(fontWeight(weight))
  return italic ? weighted.italic() : weighted
}

/// `font` at `scaledPoints`: its theme face when `postScriptName` names one that is registered,
/// else the system font at the same size and weight (`docs/theme.md`, Fonts: never invisible).
/// A registered face is one file, so the requested weight and italic are applied only where
/// the face doesn't already have them.
func resolvedFont(_ font: ResolvedFont, scaledPoints: CGFloat, postScriptName: String?) -> Font {
  guard let name = postScriptName, let face = font.face else {
    return resolvedFont(scaledPoints: scaledPoints, weight: font.weight, italic: font.italic)
  }
  var custom = Font.custom(name, fixedSize: scaledPoints)
  if fontWeight(font.weight) != fontWeight(face.weight) {
    custom = custom.weight(fontWeight(font.weight))
  }
  return font.italic && !face.italic ? custom.italic() : custom
}
