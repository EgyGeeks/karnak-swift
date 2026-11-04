import KarnakCore
import SwiftUI

/// How a `text_field`'s text, typed or placeholder, is laid out (`docs/renderer-contract.md`, Text direction).
///
/// - ``direction`` is left to right for the keyboards whose text is Latin digits and symbols in every language
///   (`email`, `number`, `decimal`, `phone`, `url`), so `+20 100 123 4567` keeps its order in an Arabic screen, and the
///   screen's own for the others, whose text the platform lays out from its first strong character.
/// - ``alignment`` puts the lines at the screen's start edge whatever the first strong character is: `.leading` of the
///   screen, which for a left-to-right text in a right-to-left screen is `.trailing` in the text's own direction.
///
/// The placeholder takes the same layout as the value it stands for.
struct FieldTextLayout: Equatable {
  /// The direction the text runs in.
  let direction: LayoutDirection
  /// Where its lines start, read in ``direction``.
  let alignment: TextAlignment

  /// The layout of a field with `keyboard` in a screen laid out `screen`.
  init(keyboard: InputKeyboard, screen: LayoutDirection) {
    let leftToRight = keyboard.readsLeftToRight
    direction = leftToRight ? .leftToRight : screen
    alignment = leftToRight && screen == .rightToLeft ? .trailing : .leading
  }
}

extension InputKeyboard {
  /// Whether the text of this keyboard reads left to right in every language.
  var readsLeftToRight: Bool {
    switch self {
    case .email, .number, .decimal, .phone, .url: true
    default: false
    }
  }
}

extension View {
  /// Lays a text field's text out as `layout` says: its direction, and where its lines start.
  func fieldText(_ layout: FieldTextLayout) -> some View {
    environment(\.layoutDirection, layout.direction).multilineTextAlignment(layout.alignment)
  }
}
