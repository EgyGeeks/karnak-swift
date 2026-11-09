import SwiftUI

extension View {
  /// Sizes the sheet this view is the content of to the view's own height, up to the sheet's
  /// large detent. The view is laid out inside the sheet's bound, so a weighted `list` takes its
  /// content height and then scrolls, and the height follows the content as it changes.
  func fitsSheet() -> some View { modifier(SheetFit()) }
}

private struct SheetFit: ViewModifier {
  /// The content's ideal height, once measured.
  @State private var height: CGFloat?

  func body(content: Content) -> some View {
    content.measuredForSheet { height = $0 }.presentationDetents([.measured(height)])
  }
}

extension View {
  /// Lays this view out inside the sheet's bound, whatever its ideal height is, and reports that
  /// ideal height: the view, plus the insets around it the sheet covers (a navigation bar above, the
  /// home indicator below). The keyboard is not one of them: it covers the sheet, and a height that
  /// followed it would grow with the keyboard and shrink with it, so the probe leaves it out. The
  /// content itself still avoids the keyboard.
  func measuredForSheet(_ report: @escaping (CGFloat) -> Void) -> some View {
    SheetFitLayout {
      self
      // Takes the ideal height, whatever the sheet offers, so it is measured from there.
      Color.clear
        .ignoresSafeArea(.keyboard)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom
        } action: {
          report($0)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

/// A content view and a probe: the content is as tall as it needs, up to the height offered, and
/// the probe is as tall as the content needs, offered or not.
private struct SheetFitLayout: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let ideal = idealSize(of: subviews[0], width: proposal.width)
    return CGSize(
      width: proposal.width ?? ideal.width, height: min(ideal.height, proposal.height ?? .infinity))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews[0].place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    let ideal = idealSize(of: subviews[0], width: bounds.width)
    subviews[1].place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: ideal.height))
  }

  private func idealSize(of content: LayoutSubview, width: CGFloat?) -> CGSize {
    content.sizeThatFits(ProposedViewSize(width: width, height: nil))
  }
}
