import KarnakCore
import SwiftUI

/// `radio_group` (`docs/renderer-contract.md`, Inputs, `ResolvedRadioGroup`): custom option rows in the options' box,
/// stacked by `orientation` with no gap of their own, in one accessibility container named by the input. Each row is
/// a button, the indicator circle (with its dot while selected) then the label, 12 dp apart, and is the option's touch
/// target; VoiceOver reads the selected one as selected. Picking an enabled option sends its value, and takes focus
/// from the other inputs. Focus moving between options sends nothing: the group reports focus entering and leaving it.
struct RadioGroupView: View {
  let group: ResolvedRadioGroup
  let placement: ChildPlacement
  @FocusState private var focusedOption: String?
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    let drawn = restyled(group, for: focusedOption != nil ? [.focused] : [])
    InputFrame(input: drawn, placement: placement, label: drawn.label, support: drawn.error) {
      options(drawn)
        .partBox(drawn.control)
        .accessibilityElement(children: .contain)
        .inputAccessibility(drawn)
    }
    .onChange(of: focusedOption != nil) { _, isFocused in
      inputs.send(.focusChange(group.key, isFocused))
      if isFocused { focus.moved(to: group.key.value) }
    }
    .onReceive(focus.moves) { if $0 != group.key.value { focusedOption = nil } }
    .onReceive(focus.requests) { key in
      if key == group.key.value, focus.take(key) { focusedOption = focusTarget }
    }
    .onAppear {
      if focus.take(group.key.value) { focusedOption = focusTarget }
    }
  }

  private func options(_ drawn: ResolvedRadioGroup) -> some View {
    let horizontal = drawn.orientation == .horizontal
    let fills = !horizontal && !placement.wraps(.horizontal, of: group.layout)
    let stack =
      horizontal
      ? AnyLayout(HStackLayout(alignment: .center, spacing: 0))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
    return stack {
      ForEach(drawn.options, id: \.value) { option in
        RadioOptionView(option: option, fills: fills, focused: $focusedOption) { pick(option) }
      }
    }
    .fixedSize(horizontal: horizontal, vertical: false)
  }

  /// The option a `FocusRequest` focuses: the selected one, else the first enabled one.
  private var focusTarget: String? {
    group.selected ?? group.options.first(where: \.enabled)?.value
  }

  private func pick(_ option: ResolvedOption) {
    focus.moved(to: group.key.value)
    guard group.acceptsEdits, option.enabled, !option.selected else { return }
    inputs.send(.valueChange(group.key, option.value))
  }
}

/// One option row of a radio group, styled for its own pressed, hovered and focused states.
private struct RadioOptionView: View {
  let option: ResolvedOption
  /// Whether the row takes the group's width.
  let fills: Bool
  let focused: FocusState<String?>.Binding
  let pick: () -> Void
  @State private var pressed = false
  @State private var hovered = false

  var body: some View {
    let drawn = option.styled(
      for: activeInteractions(
        pressed: pressed, hovered: hovered, focused: focused.wrappedValue == option.value))
    Button(action: pick) {
      HStack(spacing: indicatorGap) {
        if let indicator = drawn.indicator {
          ZStack {
            if drawn.selected, let dot = drawn.dot {
              InputDot(
                diameter: points(dp: dot.floatValue),
                color: indicator.content.map(resolvedColor) ?? .clear)
            }
          }
          .partBox(indicator, alignment: .center)
        }
        InputTextView(drawn.label)
      }
      .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
      .partBox(drawn.row)
    }
    .buttonStyle(PressTrackingStyle(pressed: $pressed))
    .focused(focused, equals: option.value)
    .disabled(!drawn.enabled)
    .onHover { hovered = $0 }
    .accessibilityLabel(option.label.words)
    .accessibilityAddTraits(drawn.selected ? .isSelected : [])
  }
}
