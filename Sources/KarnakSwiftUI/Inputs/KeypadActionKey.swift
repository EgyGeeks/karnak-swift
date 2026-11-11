import KarnakCore
import SwiftUI

/// The action key of a field whose keypad has none (`docs/renderer-contract.md`, IME actions): iOS's number, decimal
/// and phone pads have no return key, so while such a field with an `imeAction` has focus, a bar above the keyboard
/// holds one button at its trailing edge that does what the return key would. Its label is the project's
/// `keyboard.<action>` string, else the host's string catalog ("Next", "Done", "Go", "Search", "Send"), and is the
/// button's accessible name.
struct KeypadActionKey: ViewModifier {
  let keyboard: InputKeyboard
  let imeAction: ImeAction?
  let focused: Bool
  let press: (ImeAction) -> Void
  @Environment(\.karnakResources) private var resources

  func body(content: Content) -> some View {
    content.toolbar {
      // Only the focused field adds the bar: SwiftUI gathers the keyboard items of every field on the screen.
      if focused, let action = keypadActionKey(keyboard: keyboard, imeAction: imeAction) {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button {
            press(action)
          } label: {
            let label = keypadKeyLabel(for: action)
            resources.text(label.key, fallback: LocalizedStringKey(label.fallback))
          }
        }
      }
    }
  }
}

/// The action key the keypad bar shows for a field: its `imeAction` when `keyboard` is a pad with no return key,
/// otherwise `nil` (the keyboard's own return key sends it).
func keypadActionKey(keyboard: InputKeyboard, imeAction: ImeAction?) -> ImeAction? {
  switch keyboard {
  case .number, .decimal, .phone: imeAction
  default: nil
  }
}

/// The string key of the keypad bar's button for `action`, and the host catalog's key when the project has none.
func keypadKeyLabel(for action: ImeAction) -> (key: String, fallback: String) {
  switch action {
  case .next: ("keyboard.next", "Next")
  case .go: ("keyboard.go", "Go")
  case .search: ("keyboard.search", "Search")
  case .send: ("keyboard.send", "Send")
  case .done: ("keyboard.done", "Done")
  // The enum is bridged from Kotlin as a class: `default` only takes a case added after this one was written.
  default: ("keyboard.done", "Done")
  }
}

/// Whether the keypad bar's `action` ends editing: `done` does, as the return key does, unless the engine moved focus
/// while answering (`focusMoved`). The other actions leave focus to `submitted` and to the engine.
func endsEditing(afterKeypadKey action: ImeAction, focusMoved: Bool) -> Bool {
  action == .done && !focusMoved
}
