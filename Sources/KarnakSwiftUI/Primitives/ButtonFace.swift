import KarnakCore
import SwiftUI

/// What a button draws inside its padded box: its icon and label, centered and `iconGap` apart,
/// with the icon on the `iconPosition` side in layout direction (`docs/renderer-contract.md`,
/// `button`). The label wraps in the width the icon leaves and scales with Dynamic Type; it
/// never shrinks to fit.
///
/// While loading, the indicator is drawn centered over the label and icon, which stay laid out
/// but invisible: they alone size the button, whatever the indicator's size.
struct ButtonFace: View {
  /// The icon; nil for a text-only button.
  let icon: ResolvedIcon?
  /// The label; nil for an icon-only button.
  let label: ResolvedParagraph?
  /// Whether the icon comes before the label in layout direction.
  let iconAtStart: Bool
  /// Space between the icon and the label in points.
  let iconGap: CGFloat
  /// The indicator drawn while loading; nil when the button isn't loading.
  let loading: ProgressIndicatorView?

  init(button: ResolvedButton) {
    self.init(
      icon: button.icon, label: button.label, iconAtStart: button.iconPosition == .start,
      iconGap: points(dp: button.iconGap), loading: button.loading.map(ProgressIndicatorView.init))
  }

  init(
    icon: ResolvedIcon?, label: ResolvedParagraph?, iconAtStart: Bool, iconGap: CGFloat,
    loading: ProgressIndicatorView?
  ) {
    self.icon = icon
    self.label = label
    self.iconAtStart = iconAtStart
    self.iconGap = iconGap
    self.loading = loading
  }

  var body: some View {
    HStack(spacing: iconGap) {
      if let icon, iconAtStart { VectorIconView(icon) }
      if let label { ParagraphView(paragraph: label) }
      if let icon, !iconAtStart { VectorIconView(icon) }
    }
    .opacity(loading == nil ? 1 : 0)
    .overlay { loading }
  }
}
