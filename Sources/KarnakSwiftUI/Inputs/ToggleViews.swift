import KarnakCore
import SwiftUI

/// `checkbox` (`docs/renderer-contract.md`, Inputs, `ResolvedCheckbox`): a `Toggle` with a checkbox style. The control
/// row is the indicator box, with the check mark while checked, then the label, 12 dp apart; the whole row is the
/// touch target, and the error sits under it. Activating a checkbox or a switch takes focus from the other inputs.
struct CheckboxView: View {
  let checkbox: ResolvedCheckbox
  let placement: ChildPlacement
  @State private var pressed = false
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    let drawn = restyled(
      checkbox, for: activeInteractions(pressed: pressed, hovered: hovered, focused: focused))
    InputFrame(input: drawn, placement: placement, label: nil, support: drawn.error) {
      Toggle(isOn: checkedBinding(drawn, checked: drawn.checked, inputs: inputs, focus: focus)) {
        if let label = drawn.label { InputTextView(label) }
      }
      .toggleStyle(
        IndicatorToggleStyle(
          input: drawn, indicatorLeads: true, labelFills: false, pressed: $pressed
        ) {
          ZStack {
            if drawn.checked { VectorIconView(drawn.mark) }
          }
          .partBox(drawn.indicator, alignment: .center)
        }
      )
      .focused($focused)
      .disabled(!drawn.enabled)
    }
    .onHover { hovered = $0 }
    .reportsFocus(checkbox.key, focused, to: inputs)
    .takesFocusRequests(checkbox.key.value, focus: focus, focused: $focused)
  }
}

/// `switch` (`docs/renderer-contract.md`, Inputs, `ResolvedSwitch`): a `Toggle` whose style draws the track and the
/// thumb. The control row is the label, then the track at the end edge, 12 dp apart. The thumb is centred on the
/// track's height, its start edge at the track's start padding while off and its end edge at the end padding while
/// on; start and end are logical, so RTL mirrors the travel. The thumb moves with a short animation unless Reduce
/// Motion is on.
struct SwitchView: View {
  let toggle: ResolvedSwitch
  let placement: ChildPlacement
  @State private var pressed = false
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let drawn = restyled(
      toggle, for: activeInteractions(pressed: pressed, hovered: hovered, focused: focused))
    InputFrame(input: drawn, placement: placement, label: nil, support: drawn.error) {
      Toggle(isOn: checkedBinding(drawn, checked: drawn.on, inputs: inputs, focus: focus)) {
        if let label = drawn.label { InputTextView(label) }
      }
      .toggleStyle(
        IndicatorToggleStyle(
          input: drawn, indicatorLeads: false,
          labelFills: !placement.wraps(.horizontal, of: toggle.layout), pressed: $pressed
        ) {
          Color.clear.partBox(drawn.thumb, alignment: .center)
            .partBox(drawn.track, alignment: drawn.on ? .trailing : .leading)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: drawn.on)
        }
      )
      .focused($focused)
      .disabled(!drawn.enabled)
    }
    .onHover { hovered = $0 }
    .reportsFocus(toggle.key, focused, to: inputs)
    .takesFocusRequests(toggle.key.value, focus: focus, focused: $focused)
  }
}

/// The value a checkbox or switch shows, `checked`, from the tree; a toggle moves focus to the input, sends
/// `checkedChange` and changes nothing itself, and a disabled or read-only input sends nothing.
@MainActor
func checkedBinding(
  _ input: ResolvedInput, checked: Bool, inputs: InputSink, focus: InputFocus
) -> Binding<Bool> {
  Binding(
    get: { checked },
    set: { value in
      focus.moved(to: input.key.value)
      if input.acceptsEdits, value != checked { inputs.send(.checkedChange(input.key, value)) }
    })
}

/// The control row of a checkbox or a switch: the indicator and the label 12 dp apart in the control box, one
/// button that toggles. VoiceOver reads it as the system's toggle, named by the input, with its error as the hint.
private struct IndicatorToggleStyle<Indicator: View>: ToggleStyle {
  let input: ResolvedInput
  /// Whether the indicator comes first (a checkbox) or the label (a switch, whose track sits at the end edge).
  let indicatorLeads: Bool
  /// Whether the label takes the row's free width, so the indicator sits at the end edge of a row that doesn't hug.
  let labelFills: Bool
  @Binding var pressed: Bool
  @ViewBuilder let indicator: () -> Indicator

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      HStack(spacing: indicatorGap) {
        if indicatorLeads {
          indicator()
          configuration.label
        } else {
          configuration.label.frame(maxWidth: labelFills ? .infinity : nil, alignment: .leading)
          indicator()
        }
      }
      .partBox(input.control)
    }
    .buttonStyle(PressTrackingStyle(pressed: $pressed))
    .accessibilityRepresentation {
      Toggle(input.accessibleName, isOn: configuration.$isOn).toggleStyle(.switch)
    }
    .accessibilityHint(input.accessibleHint)
  }
}

/// The fixed gap between an indicator and the text beside it (`docs/components.md`, Input variants).
let indicatorGap: CGFloat = 12
