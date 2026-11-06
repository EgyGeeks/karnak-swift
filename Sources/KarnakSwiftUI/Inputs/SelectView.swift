import KarnakCore
import SwiftUI

/// `select` (`docs/renderer-contract.md`, Inputs, `ResolvedSelect`): a `Menu` whose label is the field box, with the
/// selected option's label or the placeholder and the expand icon at the end edge, and whose content is a `Picker`
/// of the options, so the platform draws the menu (the resolved `menu` and option rows aren't drawn). A disabled
/// option is shown and can't be picked; picking an option sends its value. The select is `focused`, and reports
/// focus, while its menu is open (``SelectMenu``) or it has keyboard focus; opening the menu takes focus from a text
/// field, so its keyboard goes away and the field reports the blur.
struct SelectView: View {
  let select: ResolvedSelect
  let placement: ChildPlacement
  @State private var pressed = false
  @State private var hovered = false
  @State private var menu = SelectMenu()
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    let hasFocus = focused || menu.open
    let drawn = restyled(
      select, for: activeInteractions(pressed: pressed, hovered: hovered, focused: hasFocus))
    InputFrame(input: drawn, placement: placement, label: drawn.label, support: drawn.error) {
      Menu {
        Picker(selection: selection) {
          ForEach(drawn.options, id: \.value) { option in
            Text(option.label.words).tag(Optional(option.value)).disabled(!option.enabled)
          }
        } label: {
          Text(drawn.accessibleName)
        }
        .labelsHidden()
        .onAppear {
          menu.appeared()
          focus.moved(to: select.key.value)
        }
      } label: {
        box(drawn)
      }
      .menuStyle(.button)
      .buttonStyle(PressTrackingStyle(pressed: $pressed))
      .focused($focused)
      .disabled(!drawn.enabled)
      .inputAccessibility(drawn)
      .accessibilityValue(drawn.display?.words ?? "")
    }
    .onHover { hovered = $0 }
    .onReceive(focus.moves) { menu.focusMoved(to: $0, from: select.key.value) }
    .reportsFocus(select.key, hasFocus, to: inputs)
    .takesFocusRequests(select.key.value, focus: focus, focused: $focused)
  }

  /// The field box: the choice or the placeholder (or nothing, at the box's height), then the expand icon.
  private func box(_ drawn: ResolvedSelect) -> some View {
    HStack(spacing: 0) {
      Group {
        if let shown = drawn.display ?? drawn.placeholder { InputTextView(shown) }
      }
      .frame(maxWidth: placement.spans(drawn) ? .infinity : nil, alignment: .leading)
      VectorIconView(drawn.expandIcon)
    }
    .partBox(drawn.control)
    .underline(drawn.indicator, in: drawn.control)
  }

  /// The selection the picker shows, from the tree. Picking closes the menu and sends `valueChange` for an enabled
  /// option the select doesn't hold already, changing nothing itself; a disabled or read-only select sends nothing.
  private var selection: Binding<String?> {
    let select = select
    let inputs = inputs
    let menu = $menu
    return Binding(
      get: { select.selected },
      set: { value in
        menu.wrappedValue.picked()
        let enabled = select.options.first { $0.value == value }?.enabled == true
        if select.acceptsEdits, enabled, value != select.selected {
          inputs.send(.valueChange(select.key, value))
        }
      })
  }
}

/// Whether a select's menu is open, as far as SwiftUI tells: from the menu's content appearing until a pick, or
/// until another input takes focus. SwiftUI's `Menu` reports no dismissal (its content's `onDisappear` doesn't run
/// when it closes, seen on iOS 27), so a menu closed without a pick, or with a pick of the option already chosen if
/// the picker doesn't set its selection again, counts as open until one of those.
struct SelectMenu: Equatable {
  private(set) var open = false

  /// The menu's content appeared: the menu opened.
  mutating func appeared() {
    open = true
  }

  /// An option was picked, which closes the menu.
  mutating func picked() {
    open = false
  }

  /// Focus moved to the input with `key`; the menu of the select with key `own` is closed unless that's itself.
  mutating func focusMoved(to key: String, from own: String) {
    if key != own { open = false }
  }
}
