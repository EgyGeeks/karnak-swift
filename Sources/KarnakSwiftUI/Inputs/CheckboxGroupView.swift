import KarnakCore
import SwiftUI

/// `checkbox_group` (`docs/renderer-contract.md`, Inputs, `ResolvedCheckboxGroup`): custom option rows in the options'
/// box, stacked from the top with no gap of their own, in one accessibility container named by the input. Each row is
/// a button, the indicator box (with its check mark while selected) then the label, 12 dp apart, and is the option's
/// touch target; VoiceOver reads each as a toggle with its label and, while picked, as selected. Toggling an enabled
/// option sends every value selected then, in the options' order, and takes focus from the other inputs. Focus moving
/// between options sends nothing: the group reports focus entering and leaving it.
struct CheckboxGroupView: View {
  let group: ResolvedCheckboxGroup
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

  private func options(_ drawn: ResolvedCheckboxGroup) -> some View {
    let fills = !placement.wraps(.horizontal, of: group.layout)
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(drawn.options, id: \.value) { option in
        CheckboxOptionView(option: option, fills: fills, focused: $focusedOption) { toggle(option) }
      }
    }
  }

  /// The option a `FocusRequest` focuses: the first selected one, else the first enabled one.
  private var focusTarget: String? {
    group.options.first(where: { $0.selected && $0.enabled })?.value
      ?? group.options.first(where: \.enabled)?.value
  }

  private func toggle(_ option: ResolvedOption) {
    focus.moved(to: group.key.value)
    guard group.acceptsEdits, option.enabled else { return }
    let chosen = group.options.filter { $0.value == option.value ? !$0.selected : $0.selected }
    inputs.send(.selectionChange(group.key, chosen.map(\.value)))
  }
}

/// One option row of a checkbox group, styled for its own pressed, hovered and focused states.
private struct CheckboxOptionView: View {
  let option: ResolvedOption
  /// Whether the row takes the group's width.
  let fills: Bool
  let focused: FocusState<String?>.Binding
  let toggle: () -> Void
  @State private var pressed = false
  @State private var hovered = false

  var body: some View {
    let drawn = option.styled(
      for: activeInteractions(
        pressed: pressed, hovered: hovered, focused: focused.wrappedValue == option.value))
    Button(action: toggle) {
      HStack(spacing: indicatorGap) {
        if let indicator = drawn.indicator {
          ZStack {
            if drawn.selected, let mark = drawn.mark { VectorIconView(mark) }
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
    .modifier(CheckboxTraits(selected: drawn.selected))
  }
}

/// The accessibility traits of a checkbox option: the toggle trait, and selected while picked, which VoiceOver reads as
/// checked.
private struct CheckboxTraits: ViewModifier {
  let selected: Bool

  func body(content: Content) -> some View {
    let traits: AccessibilityTraits = selected ? .isSelected : []
    content.accessibilityAddTraits(traits.union(.isToggle))
  }
}
