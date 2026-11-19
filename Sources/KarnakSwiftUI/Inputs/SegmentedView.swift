import KarnakCore
import SwiftUI

/// `segmented` (`docs/renderer-contract.md`, Inputs, `ResolvedSegmented`; ADR 0044). Options of plain labels are the
/// system segmented control, a `Picker` with `.pickerStyle(.segmented)`, so it looks, sizes and reads as iOS draws one;
/// the theme's look applies only to the node's box around it, and a disabled option is a disabled segment. When an
/// option has an icon, which a system segment can't show beside its label, the control is the theme's track
/// ([ResolvedSegmented.control]) of segments sharing its width, each its icon then its label in its own interaction
/// styles, read by VoiceOver as buttons in one container, the selected one as selected. Picking an enabled segment
/// sends its value and takes focus from the other inputs; a disabled option, a read-only control, or the segment
/// already selected sends nothing, and the control shows the engine's selection again.
struct SegmentedView: View {
  let control: ResolvedSegmented
  let placement: ChildPlacement
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    InputFrame(input: control, placement: placement, label: control.label, support: control.error) {
      Group {
        if control.options.contains(where: { $0.icon != nil }) {
          track
        } else {
          picker.inputAccessibility(control)
        }
      }
      .disabled(!control.enabled)
      .frame(maxWidth: placement.spans(control) ? .infinity : nil)
    }
  }

  private var picker: some View {
    Picker(control.accessibleName, selection: selection) {
      ForEach(control.options, id: \.value) { option in
        Text(option.label.words).tag(option.value).disabled(!option.enabled)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }

  private var track: some View {
    HStack(spacing: 0) {
      ForEach(control.options, id: \.value) { option in
        SegmentButton(option: option) { pick(option.value) }
      }
    }
    .partBox(control.control)
    .accessibilityElement(children: .contain)
    .inputAccessibility(control)
  }

  /// The engine's selection, read on every draw; a pick goes to the engine, which answers with the next tree.
  private var selection: Binding<String> {
    Binding(get: { control.selected ?? "" }, set: pick)
  }

  private func pick(_ value: String) {
    focus.moved(to: control.key.value)
    guard control.acceptsEdits, value != control.selected,
      control.options.first(where: { $0.value == value })?.enabled == true
    else { return }
    inputs.send(.valueChange(control.key, value))
  }
}

/// One segment of the theme's track: a button with its icon and label in its `row` box, styled for its own pressed and
/// hovered states, named by its label (the label's text is hidden from VoiceOver, as an input's texts are).
private struct SegmentButton: View {
  let option: ResolvedOption
  let pick: () -> Void
  @State private var pressed = false
  @State private var hovered = false

  var body: some View {
    let active = activeInteractions(pressed: pressed, hovered: hovered, focused: false)
    let drawn = option.styled(for: active)
    Button(action: pick) {
      HStack(spacing: segmentGap) {
        if let icon = drawn.icon { VectorIconView(icon) }
        InputTextView(drawn.label)
      }
      .frame(maxWidth: .infinity)
      .partBox(drawn.row, alignment: .center)
    }
    .buttonStyle(PressTrackingStyle(pressed: $pressed))
    .disabled(!drawn.enabled)
    .onHover { hovered = $0 }
    .accessibilityLabel(drawn.label.words)
    .accessibilityAddTraits(drawn.selected ? [.isSelected, .isButton] : .isButton)
  }
}

/// Between a segment's icon and its label, in points.
private let segmentGap: CGFloat = 6
