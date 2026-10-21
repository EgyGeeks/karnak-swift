import KarnakCore
import SwiftUI
import UIKit

/// A resolved paragraph prepared for `Text`, at one Dynamic Type setting
/// (`docs/renderer-contract.md`, `ResolvedParagraph`): one attributed run per `TextRun`, with
/// sizes scaled once through `UIFontMetrics`, and the paragraph's line height as spacing.
struct StyledParagraph {
  /// The runs, each with its font, color, decorations and tracking. Link runs carry an
  /// internal `karnak-link:` URL that ``handle(for:)`` maps back to the run's handle.
  let text: AttributedString
  /// The base font, for an empty paragraph's one line.
  let font: Font
  /// Space between lines, so each line is `lineHeight` tall.
  let lineSpacing: CGFloat
  /// Space above the first line and below the last, so they are `lineHeight` tall too.
  let edgeSpacing: CGFloat
  /// The height of one line as drawn: the font's own, plus the space between lines.
  let lineHeight: CGFloat
  /// The color links are drawn in: SwiftUI draws every link of a `Text` in its tint.
  let linkColor: Color?
  /// The scaled font size of each run, in order.
  let runPoints: [CGFloat]
  private let links: [ActionHandle]

  /// - Parameter postScriptName: The registered font of a theme face, if it is ready. Faces
  ///   without one draw in the system font until the registry has loaded them.
  init(
    _ paragraph: ResolvedParagraph, traits: UITraitCollection,
    postScriptName: (ResolvedFontFace) -> String? = { _ in nil }
  ) {
    func name(_ font: ResolvedFont) -> String? { font.face.flatMap(postScriptName) }
    var text = AttributedString()
    var links: [ActionHandle] = []
    var runPoints: [CGFloat] = []
    for run in paragraph.runs {
      let size = textPoints(sp: run.font.size, traits: traits)
      var part = AttributedString(run.text)
      part.font = resolvedFont(run.font, scaledPoints: size, postScriptName: name(run.font))
      part.foregroundColor = resolvedColor(run.color)
      part.tracking = tracking(em: run.font.letterSpacing, fontPoints: size)
      if run.underline { part.underlineStyle = .single }
      if run.strikethrough { part.strikethroughStyle = .single }
      if let link = run.link {
        part.link = URL(string: "\(Self.linkScheme):\(links.count)")
        links.append(link)
      }
      text.append(part)
      runPoints.append(size)
    }
    let basePoints = textPoints(sp: paragraph.font.size, traits: traits)
    let leading = paragraph.lineHeight.map {
      max(
        0,
        textPoints(sp: $0.floatValue, traits: traits)
          - naturalLineHeight(name(paragraph.font), basePoints))
    }
    self.text = text
    self.font = resolvedFont(
      paragraph.font, scaledPoints: basePoints, postScriptName: name(paragraph.font))
    lineSpacing = leading ?? 0
    lineHeight = naturalLineHeight(name(paragraph.font), basePoints) + (leading ?? 0)
    edgeSpacing = (leading ?? 0) / 2
    linkColor = paragraph.runs.first { $0.link != nil }.map { resolvedColor($0.color) }
    self.runPoints = runPoints
    self.links = links
  }

  /// The handle of the link run `url` names; nil for any other URL.
  func handle(for url: URL) -> ActionHandle? {
    guard url.scheme == Self.linkScheme,
      let index = Int(url.absoluteString.dropFirst(Self.linkScheme.count + 1)),
      links.indices.contains(index)
    else { return nil }
    return links[index]
  }

  private static let linkScheme = "karnak-link"
}

/// The height of one line of the font named `postScriptName` (the system font when nil or
/// unknown) at `points` without extra spacing.
private func naturalLineHeight(_ postScriptName: String?, _ points: CGFloat) -> CGFloat {
  let named = postScriptName.flatMap { UIFont(name: $0, size: points) }
  return (named ?? .systemFont(ofSize: points)).lineHeight
}
