import KarnakCore
import SwiftUI

/// The traits of a role. A `radio` is a button and a `checkbox` a toggle (iOS 17); either is `isSelected` while
/// [checked], which VoiceOver reads as "selected" and, on a toggle, as "on". Any other role ignores [checked].
func accessibilityTraits(_ role: Role, checked: Bool = false) -> AccessibilityTraits {
  switch role {
  case .button: .isButton
  case .link: .isLink
  case .heading: .isHeader
  case .image: .isImage
  case .radio: checked ? [.isButton, .isSelected] : .isButton
  case .checkbox: checked ? [.isToggle, .isSelected] : .isToggle
  default: []
  }
}

func colorScheme(_ mode: ColorMode) -> ColorScheme {
  mode == .dark ? .dark : .light
}

struct ImageScaling {
  // nil means stretch to the box, without an aspectRatio modifier.
  let contentMode: ContentMode?
  let crops: Bool
}

func imageScaling(_ scale: ContentScale) -> ImageScaling {
  switch scale {
  case .fit: ImageScaling(contentMode: .fit, crops: false)
  case .crop: ImageScaling(contentMode: .fill, crops: true)
  default: ImageScaling(contentMode: nil, crops: false)
  }
}

func layoutDirection(_ direction: KarnakLayoutDirection) -> SwiftUI.LayoutDirection {
  direction == .rtl ? .rightToLeft : .leftToRight
}
