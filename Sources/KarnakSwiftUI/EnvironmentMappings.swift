import KarnakCore
import SwiftUI

func accessibilityTraits(_ role: Role) -> AccessibilityTraits {
  switch role {
  case .button: .isButton
  case .link: .isLink
  case .heading: .isHeader
  case .image: .isImage
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
