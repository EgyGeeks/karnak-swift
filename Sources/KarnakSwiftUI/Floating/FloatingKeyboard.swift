import SwiftUI

/// Whether the keyboard is up, for the views that `hide` it (ADR 0038, D7 and D19): two backgrounds of the layer, one
/// that respects the keyboard's safe area and one that ignores it. The second still holds the home indicator, so the
/// keyboard is up when the first one's bottom inset is the larger. Each is read once per change, in the layout phase.
/// The keyboard rule as a value: it is up when the bottom inset that respects it is larger than the one that ignores it.
enum FloatingKeyboardRule {
  static func isUp(respecting: CGFloat, ignoring: CGFloat) -> Bool { respecting > ignoring }
}

struct FloatingKeyboardProbe: ViewModifier {
  @Binding var isUp: Bool
  @State private var respecting: CGFloat = 0
  @State private var ignoring: CGFloat = 0

  private var keyboardUp: Bool {
    FloatingKeyboardRule.isUp(respecting: respecting, ignoring: ignoring)
  }

  func body(content: Content) -> some View {
    content
      .background {
        Color.clear.onGeometryChange(for: CGFloat.self) {
          $0.safeAreaInsets.bottom
        } action: {
          respecting = $0
        }
      }
      .background {
        Color.clear.ignoresSafeArea(.keyboard).onGeometryChange(for: CGFloat.self) {
          $0.safeAreaInsets.bottom
        } action: {
          ignoring = $0
        }
      }
      .onChange(of: keyboardUp) { _, isNowUp in
        isUp = isNowUp
      }
  }
}

extension View {
  /// Reports into `isUp` whether the keyboard is up, when `isEnabled` (a layer with no view that hides it reads
  /// nothing).
  @ViewBuilder
  func readsKeyboard(_ isUp: Binding<Bool>, isEnabled: Bool) -> some View {
    if isEnabled { modifier(FloatingKeyboardProbe(isUp: isUp)) } else { self }
  }
}
