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
  /// Each run on its own, in order, for a paragraph drawn run by run (``RunBoxes``).
  let parts: [AttributedString]
  /// The box behind each run, in order; nil for a run without one.
  let boxes: [RunBox?]
  private let links: [ActionHandle]

  /// - Parameter postScriptName: The registered font of a theme face, if it is ready. Faces
  ///   without one draw in the system font until the registry has loaded them.
  /// - Parameters:
  ///   - nowMillis: The device clock for the countdown runs: each one reads the time left from it. Without it a
  ///     countdown run keeps its own text.
  ///   - layer: Which runs are drawn: all of them, or one of the gradient runs the paragraph paints over its base.
  init(
    _ paragraph: ResolvedParagraph, traits: UITraitCollection,
    postScriptName: (ResolvedFontFace) -> String? = { _ in nil },
    nowMillis: Int64? = nil, layer: TextLayer = .base
  ) {
    func name(_ font: ResolvedFont) -> String? { font.face.flatMap(postScriptName) }
    var text = AttributedString()
    var links: [ActionHandle] = []
    var runPoints: [CGFloat] = []
    var parts: [AttributedString] = []
    var boxes: [RunBox?] = []
    for (index, run) in paragraph.runs.enumerated() {
      let size = textPoints(sp: run.font.size, traits: traits)
      var part = AttributedString(Self.text(of: run, at: nowMillis))
      part.font = resolvedFont(run.font, scaledPoints: size, postScriptName: name(run.font))
      part.foregroundColor = layer.color(of: run, at: index)
      part.tracking = tracking(em: run.font.letterSpacing, fontPoints: size)
      if run.underline { part.underlineStyle = .single }
      if run.strikethrough { part.strikethroughStyle = .single }
      if run.baselineShift != 0 { part.baselineOffset = CGFloat(run.baselineShift) * size }
      if let link = run.link {
        part.link = URL(string: "\(Self.linkScheme):\(links.count)")
        links.append(link)
      }
      let box = run.background.map { RunBox(index: index, $0, layer: layer) }
      if let box, !RunBoxes.drawn { part.backgroundColor = box.color }
      text.append(part)
      parts.append(part)
      boxes.append(box)
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
    self.parts = parts
    self.boxes = boxes
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

  /// The text a run draws: its countdown's time left at `nowMillis`, or its own text.
  static func text(of run: TextRun, at nowMillis: Int64?) -> String {
    guard let countdown = run.countdown, let nowMillis else { return run.text }
    return countdown.textAt(deviceNowEpochMillis: nowMillis)
  }
}

/// Which runs of a paragraph one `Text` draws: a paragraph with gradient runs is drawn as its base, where those runs
/// are clear, and one layer per gradient run, masked by that run alone (`docs/renderer-contract.md`, Paints).
enum TextLayer: Equatable {
  /// The paragraph with its gradient runs clear.
  case base
  /// Only the gradient run at this index, opaque, for the gradient to show through.
  case gradientRun(Int)

  func color(of run: TextRun, at index: Int) -> Color {
    switch self {
    case .base: run.paint == nil ? resolvedColor(run.color) : .clear
    case .gradientRun(let only): only == index ? .black : .clear
    }
  }
}

/// The height of one line of the font named `postScriptName` (the system font when nil or
/// unknown) at `points` without extra spacing.
private func naturalLineHeight(_ postScriptName: String?, _ points: CGFloat) -> CGFloat {
  let named = postScriptName.flatMap { UIFont(name: $0, size: points) }
  return (named ?? .systemFont(ofSize: points)).lineHeight
}
