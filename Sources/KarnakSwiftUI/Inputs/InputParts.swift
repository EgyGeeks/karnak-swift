import KarnakCore
import SwiftUI

extension View {
  /// Draws `part` around this content (`docs/renderer-contract.md`, Inputs, `PartBox`): its padding, its size or
  /// minimum height with the content at `alignment`, its shadows and background in its shape, its border inside it
  /// and its alpha.
  func partBox(_ part: PartBox, alignment: Alignment = .leading) -> some View {
    modifier(PartBoxModifier(part: part, alignment: alignment))
  }

  /// Draws a `text_field`'s or `select`'s underline along the box's bottom edge, inside its border; nothing without
  /// one.
  func underline(_ indicator: PartBox?, in box: PartBox) -> some View {
    overlay(alignment: .bottom) {
      if let indicator, let thickness = indicator.height {
        let inset = box.border.map { points(dp: $0.width) } ?? 0
        Rectangle()
          .fill(indicator.background.map(resolvedColor) ?? .clear)
          .frame(height: points(dp: thickness.floatValue))
          .opacity(Double(indicator.alpha))
          .padding([.horizontal, .bottom], inset)
          .clipShape(NodeShape(radius: points(dp: box.radius)))
          .accessibilityHidden(true)
      }
    }
  }
}

private struct PartBoxModifier: ViewModifier {
  let part: PartBox
  let alignment: Alignment

  func body(content: Content) -> some View {
    let shape = NodeShape(radius: points(dp: part.radius))
    content
      .padding(edgeInsets(part.padding))
      .modifier(PartSize(part: part, alignment: alignment))
      .background {
        NodeBackground(
          shape: shape, fill: part.background.map(resolvedColor), shadows: part.shadows)
      }
      .overlay {
        if let border = part.border { NodeBorder(shape: shape, border: border) }
      }
      .opacity(Double(part.alpha))
  }
}

/// A part's fixed width and height, or its minimum height, with the content at `alignment` in the box.
private struct PartSize: ViewModifier {
  let part: PartBox
  let alignment: Alignment

  func body(content: Content) -> some View {
    let width = bound(part.width)
    let height = bound(part.height)
    if width != nil || height != nil {
      content.frame(width: width, height: height, alignment: alignment)
    } else if let minimum = bound(part.minHeight) {
      content.frame(minHeight: minimum, alignment: alignment)
    } else {
      content
    }
  }
}

/// An input's text part (`docs/renderer-contract.md`, `InputText`): the paragraph in its padding, at its alpha. It is
/// hidden from VoiceOver: the control it belongs to reads it as its name, value or hint. A text field's placeholder
/// takes the field's ``FieldTextLayout``, so it reads and sits as the value will.
struct InputTextView: View {
  let text: InputText
  let layout: FieldTextLayout?
  @Environment(\.layoutDirection) private var screenDirection

  init(_ text: InputText, layout: FieldTextLayout? = nil) {
    self.text = text
    self.layout = layout
  }

  var body: some View {
    ParagraphView(paragraph: text.paragraph, alignment: layout?.alignment)
      .environment(\.layoutDirection, layout?.direction ?? screenDirection)
      .padding(edgeInsets(text.padding))
      .opacity(Double(text.alpha))
      .accessibilityHidden(true)
  }
}

extension InputText {
  /// The words, as an accessibility label, value or hint reads them.
  var words: String { paragraph.runs.map(\.text).joined() }
}

/// A filled circle, a radio option's dot.
struct InputDot: View {
  let diameter: CGFloat
  let color: Color

  var body: some View {
    Circle().fill(color).frame(width: diameter, height: diameter).accessibilityHidden(true)
  }
}
