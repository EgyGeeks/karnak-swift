import Observation
import SwiftUI

/// The room the layer asks the screen's scrolling lists to leave at each edge, so the last row clears a FAB (ADR 0038,
/// D6). A view that reserves leaves its last measured height plus its margin, **kept while the view is hidden** and for
/// as long as the screen is on: a FAB that hides on scroll at the end of a list must not drop the reserve, or the list's
/// end would move, the platform would clamp the offset back, the hysteresis would read that as `back` and the FAB would
/// return. `@Observable`, so only a list that reads ``bottom`` or ``top`` redraws when it changes.
@Observable
@MainActor
final class FloatingReserve {
  private var bottoms: [String: CGFloat] = [:]
  private var tops: [String: CGFloat] = [:]

  /// The points to leave at the bottom: the largest reservation of any view that has been shown there.
  var bottom: CGFloat { bottoms.values.max() ?? 0 }

  /// The points to leave at the top.
  var top: CGFloat { tops.values.max() ?? 0 }

  /// `key`'s view, `height` tall with its margin, was measured at the top edge or the bottom one.
  func measured(_ key: String, top isTop: Bool, height: CGFloat) {
    if isTop {
      bottoms[key] = nil
      if tops[key] != height { tops[key] = height }
    } else {
      tops[key] = nil
      if bottoms[key] != height { bottoms[key] = height }
    }
  }
}

extension EnvironmentValues {
  /// The reserve a screen's first scrolling lists leave room for; nil outside a screen with a floating layer, and
  /// nil again below a list that took it, so a nested scroll view never gets it (ADR 0038, D19).
  @Entry var karnakFloatingReserve: FloatingReserve?
}

extension View {
  /// Leaves the room the floating layer reserves at the end of this scroll view's content: the screen-level vertical
  /// scroll view only, so only scrolling content moves (the other platforms' contentPadding). Scroll views below it
  /// see no reserve, which is what resets `.contentMargins` for a carousel or a nested list.
  func floatingReserved() -> some View { modifier(FloatingReservedModifier()) }
}

private struct FloatingReservedModifier: ViewModifier {
  @Environment(\.karnakFloatingReserve) private var reserve

  func body(content: Content) -> some View {
    content
      .contentMargins(.bottom, reserve?.bottom ?? 0, for: .scrollContent)
      .contentMargins(.top, reserve?.top ?? 0, for: .scrollContent)
      .environment(\.karnakFloatingReserve, nil)
  }
}
