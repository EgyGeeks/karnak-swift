import KarnakCore
import SwiftUI

/// `select` (`docs/renderer-contract.md`, Inputs, `ResolvedSelect`): a `Menu` whose label is the field box, with the
/// selected option's label or the placeholder and the expand icon at the end edge, and whose content is a `Picker`
/// of the options, so the platform draws the menu (the resolved `menu` and option rows aren't drawn). A disabled
/// option is shown and can't be picked; picking an option sends its value. The select is `focused`, and reports
/// focus, while its menu is open (``SelectMenu``) or it has keyboard focus; opening the menu takes focus from a text
/// field, so its keyboard goes away and the field reports the blur. With `presentation: "sheet"` the box opens
/// ``SelectSheet`` instead, and focus returns to the box when the sheet closes. While its options reload (`busy`) they
/// show as not pickable and a pick sends nothing; with nothing to offer the box shows the notice in place of the
/// placeholder, and an options error shows under the box with a retry (``ChoiceStatus``).
struct SelectView: View {
  let select: ResolvedSelect
  let placement: ChildPlacement
  @State private var pressed = false
  @State private var hovered = false
  @State private var menu = SelectMenu()
  @State private var sheetOpen = false
  @FocusState private var focused: Bool
  @Environment(\.karnakInputs) private var inputs
  @Environment(\.karnakInputFocus) private var focus

  var body: some View {
    let hasFocus = focused || menu.open || sheetOpen
    let drawn = restyled(
      select, for: activeInteractions(pressed: pressed, hovered: hovered, focused: hasFocus))
    let status = ChoiceStatus(drawn)
    InputFrame(input: drawn, placement: placement, label: drawn.label, support: drawn.error) {
      VStack(alignment: .leading, spacing: 0) {
        opener(drawn, status)
          .buttonStyle(PressTrackingStyle(pressed: $pressed))
          .focused($focused)
          .disabled(!drawn.enabled)
          .inputAccessibility(drawn)
          .accessibilityValue(drawn.display?.words ?? "")
          // Reloading options dim the box as they dim a group's (D11); the box stays interactive, since it still opens
          // the sheet or menu, whose options are the ones not pickable.
          .opacity(drawn.busy ? busyOptionsOpacity : 1)
        // The notice is in the box; the options error, with its retry, under it.
        if let error = status.optionsError { OptionsErrorView(error: error) }
      }
    }
    // Outside the opener, so the sheet's rows take neither its press tracking nor its disabled state.
    .sheet(
      isPresented: $sheetOpen, onDismiss: { focused = true },
      content: {
        SelectSheet(select: select) { value in
          sheetOpen = false
          send(value)
        }
      }
    )
    .postsAnnouncement(status.announcement)
    .onHover { hovered = $0 }
    .onReceive(focus.moves) { menu.focusMoved(to: $0, from: select.key.value) }
    .reportsFocus(select.key, hasFocus, to: inputs)
    .takesFocusRequests(select.key.value, focus: focus, focused: $focused)
  }

  /// What opens the options: the box as a menu, or as a button that opens the sheet (ADR 0062, D11).
  @ViewBuilder
  private func opener(_ drawn: ResolvedSelect, _ status: ChoiceStatus) -> some View {
    if drawn.presentation == .sheet {
      Button {
        focus.moved(to: select.key.value)
        sheetOpen = true
      } label: {
        box(drawn, status)
      }
    } else {
      Menu {
        Picker(selection: selection) {
          ForEach(drawn.options, id: \.value) { option in
            // A menu row disabled while busy takes no focus away (the menu holds it); `send` refuses the pick too.
            Text(option.label.words).tag(Optional(option.value))
              .disabled(!option.enabled || drawn.busy)
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
        box(drawn, status)
      }
      .menuStyle(.button)
    }
  }

  /// The field box: the choice, else the notice when the options have nothing to offer, else the placeholder (or
  /// nothing, at the box's height), then the expand icon.
  private func box(_ drawn: ResolvedSelect, _ status: ChoiceStatus) -> some View {
    HStack(spacing: 0) {
      Group {
        if let shown = drawn.display ?? status.notice ?? drawn.placeholder {
          InputTextView(shown)
        } else {
          // An empty `Group` is no view, so the frame below would not span a `fill` box with nothing in it.
          Color.clear.frame(width: 0, height: 0)
        }
      }
      .frame(maxWidth: placement.spans(drawn) ? .infinity : nil, alignment: .leading)
      VectorIconView(drawn.expandIcon)
    }
    .partBox(drawn.control)
    .underline(drawn.indicator, in: drawn.control)
  }

  /// The selection the picker shows, from the tree. Picking closes the menu and sends the value (``send(_:)``),
  /// changing nothing itself.
  private var selection: Binding<String?> {
    let select = select
    let menu = $menu
    let send = send
    return Binding(
      get: { select.selected },
      set: { value in
        menu.wrappedValue.picked()
        if let value { send(value) }
      })
  }

  /// Sends `valueChange` for an enabled option the select doesn't hold already; a disabled, read-only or reloading
  /// (busy) select sends nothing.
  private func send(_ value: String) {
    let enabled = select.options.first { $0.value == value }?.enabled == true
    if select.acceptsEdits, !select.busy, enabled, value != select.selected {
      inputs.send(.valueChange(select.key, value))
    }
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
