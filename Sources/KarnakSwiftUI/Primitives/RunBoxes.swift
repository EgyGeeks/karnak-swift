import KarnakCore
import SwiftUI

/// The box behind a run (`docs/renderer-contract.md`, `TextRun`): its color, how far it reaches past the glyphs on
/// each side, and its corner radius, in points. The run's index tells the boxes of two neighbouring runs apart.
struct RunBox: Hashable {
  let index: Int
  let color: Color
  let padding: CGFloat
  let radius: CGFloat

  /// The box of run `index`; clear in a gradient run's own layer, which keeps only that run's glyphs.
  init(index: Int, _ background: RunBackground, layer: TextLayer) {
    self.index = index
    color = layer == .base ? resolvedColor(background.color) : .clear
    padding = CGFloat(background.padding)
    radius = CGFloat(background.radius)
  }
}

@available(iOS 18.0, *)
extension RunBox: TextAttribute {}

/// Draws a paragraph's run boxes. On iOS 18 and later each run with a box is tagged with it and a text renderer draws,
/// per line, one rounded box from the run's first glyph to its last, `padding` wider on both sides and as tall as the
/// run's font, behind the glyphs; the padding never moves the text. Before iOS 18 a run's box is its plain background
/// color, tight to the glyphs and square.
enum RunBoxes {
  /// Whether this system draws the boxes with their padding and radius.
  static var drawn: Bool {
    if #available(iOS 18.0, *) { return true }
    return false
  }

  /// The paragraph's text: run by run with their boxes drawn behind when it has any and this system draws them, as
  /// one `Text` otherwise.
  @ViewBuilder
  static func text(_ styled: StyledParagraph) -> some View {
    if #available(iOS 18.0, *) {
      if styled.boxes.contains(where: { $0 != nil }) {
        tagged(styled).textRenderer(BoxedRunsRenderer())
      } else {
        Text(styled.text)
      }
    } else {
      Text(styled.text)
    }
  }

  /// The paragraph as one `Text`, each run with a box tagged with it.
  @available(iOS 18.0, *)
  private static func tagged(_ styled: StyledParagraph) -> Text {
    let runs = zip(styled.parts, styled.boxes).map { part, box in
      box.map { Text(part).customAttribute($0) } ?? Text(part)
    }
    return runs.dropFirst().reduce(runs.first ?? Text(verbatim: "")) { Text("\($0)\($1)") }
  }
}

/// Draws the boxes of the runs tagged with a ``RunBox`` behind the text, then the text.
@available(iOS 18.0, *)
private struct BoxedRunsRenderer: TextRenderer {
  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    for line in layout {
      for (box, bounds) in boxes(of: line) {
        let rect = bounds.insetBy(dx: -box.padding, dy: 0)
        let shape = RoundedRectangle(cornerRadius: min(box.radius, rect.height / 2))
        context.fill(shape.path(in: rect), with: .color(box.color))
      }
    }
    for line in layout { context.draw(line) }
  }

  /// The box of each run on `line` and the bounds of its glyphs there. A run the system split (a fallback font, a
  /// change of direction) is joined back, so its box is one.
  private func boxes(of line: Text.Layout.Line) -> [(RunBox, CGRect)] {
    var joined: [(RunBox, CGRect)] = []
    for run in line {
      guard let box = run[RunBox.self] else { continue }
      let bounds = run.typographicBounds.rect
      if let last = joined.indices.last, joined[last].0.index == box.index {
        joined[last].1 = joined[last].1.union(bounds)
      } else {
        joined.append((box, bounds))
      }
    }
    return joined
  }
}
