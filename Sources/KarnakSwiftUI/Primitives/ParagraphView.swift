import KarnakCore
import SwiftUI
import UIKit

/// `text`: a resolved paragraph as `Text(AttributedString)` (`docs/renderer-contract.md`,
/// `text`). It follows Dynamic Type from the environment, remeasuring the same tree when the
/// setting changes, and never shrinks to fit. Overflow past `maxLines` ends with an ellipsis.
/// Link runs are links: activating one sends `click` through the `openURL` environment, and
/// VoiceOver reaches them with the links rotor. An empty paragraph draws no glyphs but keeps
/// one line of its font, and its semantics: it is hidden from VoiceOver only without a label.
struct ParagraphView: View {
  /// The paragraph.
  let paragraph: ResolvedParagraph
  /// Whether the node has its own accessibility label, which an empty paragraph keeps.
  var isLabelled = false
  @Environment(\.karnakFonts) private var fonts

  var body: some View {
    ThemedParagraph(paragraph: paragraph, isLabelled: isLabelled, fonts: fonts ?? .unavailable)
  }
}

/// The paragraph drawn with the theme fonts that are ready. It observes the registry, so the
/// same tree is drawn again in a theme font as soon as the font is registered.
private struct ThemedParagraph: View {
  let paragraph: ResolvedParagraph
  let isLabelled: Bool
  @ObservedObject var fonts: ThemeFontRegistry
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.karnakActions) private var actions

  var body: some View {
    let styled = StyledParagraph(
      paragraph,
      traits: UITraitCollection(
        preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize)),
      postScriptName: fonts.postScriptName(for:))
    Group {
      if paragraph.runs.isEmpty {
        // A zero-width space: one line of the base font and no glyphs, with nothing to read
        // unless the node has a label.
        Text(verbatim: "\u{200B}").font(styled.font).accessibilityHidden(!isLabelled)
      } else {
        Text(styled.text)
      }
    }
    .lineLimit(paragraph.maxLines.map { Int($0.int32Value) })
    .truncationMode(.tail)
    .multilineTextAlignment(textAlignment(paragraph.textAlign))
    .lineSpacing(styled.lineSpacing)
    .padding(.vertical, styled.edgeSpacing)
    // `minLines` lines of the drawn line height, which follows Dynamic Type with the text.
    .modifier(
      MinimumHeight(points: paragraph.minLines.map { CGFloat($0.int32Value) * styled.lineHeight })
    )
    .tint(styled.linkColor)
    .environment(
      \.openURL,
      OpenURLAction { url in
        guard let handle = styled.handle(for: url) else { return .discarded }
        actions.click(handle)
        return .handled
      })
  }
}

/// Reserves at least `points` of height, with the content at the top; nothing without a minimum,
/// so a text without `minLines` is laid out exactly as before.
private struct MinimumHeight: ViewModifier {
  let points: CGFloat?

  func body(content: Content) -> some View {
    if let points {
      content.frame(minHeight: points, alignment: .topLeading)
    } else {
      content
    }
  }
}
