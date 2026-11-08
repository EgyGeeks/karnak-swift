import KarnakCore
import SwiftUI

/// The node's box around an input's parts: `label` above the control (nil for a checkbox and a switch, whose label
/// sits in the control row), then the control, then `support`, the error or else the helper. The texts are hidden
/// from VoiceOver, since the control reads them.
struct InputFrame<Control: View>: View {
  /// The input to draw, already styled for its active interactions.
  let input: ResolvedInput
  let placement: ChildPlacement
  let label: InputText?
  let support: InputText?
  @ViewBuilder let control: () -> Control

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let label { InputTextView(label) }
      control()
      if let support { InputTextView(support) }
    }
    .nodeBox(input, placement: placement)
    .modifier(HiddenInput(hidden: input.semantics.hidden))
    .modifier(
      ReservedTouchTarget(minimum: placement.reservesTouchTarget ? touchTarget(of: input) : 0)
    )
    .modifier(NodeAppear(handle: input.onAppear))
  }
}

extension ChildPlacement {
  /// Whether the controls of `input` span its box: they do unless the input wraps its content on the horizontal axis.
  /// The engine resolves a width that is a number or `fill` for an input that should span, and leaves `wrap` for a
  /// child of a row or of a scrolling carousel (`docs/renderer-contract.md`, Inputs).
  func spans(_ input: ResolvedInput) -> Bool { !wraps(.horizontal, of: input.layout) }
}

/// Hides a hidden input from VoiceOver. Applied only when hidden: `accessibilityHidden(false)` would expose the texts
/// the control reads.
private struct HiddenInput: ViewModifier {
  let hidden: Bool

  func body(content: Content) -> some View {
    if hidden { content.accessibilityHidden(true) } else { content }
  }
}

extension ResolvedInput {
  /// The accessible name: `semantics.label`, which the engine sets from the label when the node has none of its own.
  var accessibleName: String { semantics.label ?? label?.words ?? "" }

  /// What VoiceOver reads after the name and value: the error while there is one, else a text field's helper.
  var accessibleHint: String {
    (error ?? (self as? ResolvedTextField)?.helper)?.words ?? ""
  }

  /// Whether the person can change the value now: enabled and not read-only (`readOnly` also covers a submission in
  /// flight).
  var acceptsEdits: Bool { enabled && !readOnly }
}

/// `input` with `active` interactions also on its parts (`styleFor`) while it is interactive, else `input` itself.
func restyled<Input: ResolvedInput>(_ input: Input, for active: Set<Interaction>) -> Input {
  guard input.interactive, !active.isEmpty else { return input }
  return input.styleFor(interaction: active) as? Input ?? input
}

extension ResolvedOption {
  /// The option with `active` interactions also on its own parts while it is interactive.
  func styled(for active: Set<Interaction>) -> ResolvedOption {
    guard interactive, !active.isEmpty else { return self }
    return styleFor(interaction: active)
  }
}

/// A button style that draws its label as it is and reports whether it is pressed, for the inputs that restyle on
/// `pressed`.
struct PressTrackingStyle: ButtonStyle {
  @Binding var pressed: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .onChange(of: configuration.isPressed) { pressed = $0 }
  }
}

extension View {
  /// The VoiceOver name and hint of an input's control.
  func inputAccessibility(_ input: ResolvedInput) -> some View {
    accessibilityLabel(input.accessibleName).accessibilityHint(input.accessibleHint)
  }
}
