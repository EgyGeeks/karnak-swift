import KarnakCore
import SwiftUI

extension EnvironmentValues {
  /// The screen's locale, whose rules a typography style's `textTransform` cases text with
  /// (`docs/renderer-contract.md`, Text case); the device's outside a screen.
  @Entry var karnakScreenLocale = Locale.current
}

/// The screen's locale of the BCP 47 tag `tag`: the device's for nil or an empty tag.
func screenLocale(_ tag: String?) -> Locale {
  guard let tag, !tag.isEmpty else { return .current }
  return Locale(identifier: tag)
}

extension String {
  /// The text in the case `transform` draws, with the casing rules of `locale` (`tr` upper-cases `i` to `İ`).
  func cased(_ transform: KarnakTextTransform, locale: Locale) -> String {
    switch transform {
    case .uppercase: uppercased(with: locale)
    case .lowercase: lowercased(with: locale)
    default: self
    }
  }
}

extension ResolvedParagraph {
  /// Whether a run draws in another case than its text's, so VoiceOver reads the text as written.
  var isRecased: Bool { runs.contains { $0.font.textTransform != .asWritten } }

  /// The paragraph's text as written at `nowMillis`: what VoiceOver reads when ``isRecased``.
  func written(at nowMillis: Int64?) -> String {
    runs.map { StyledParagraph.text(of: $0, at: nowMillis) }.joined()
  }
}

/// A paragraph drawn in another case reads as written (ADR 0057, D3); one in its own case keeps the accessibility tree
/// it had, with no label added.
struct WrittenText: ViewModifier {
  let written: String?

  func body(content: Content) -> some View {
    if let written {
      content.accessibilityLabel(Text(verbatim: written))
    } else {
      content
    }
  }
}
