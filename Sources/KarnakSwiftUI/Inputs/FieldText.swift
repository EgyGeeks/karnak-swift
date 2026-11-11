import KarnakCore
import SwiftUI

/// What a text field's native text shows and holds (`docs/renderer-contract.md`, Display masks). With a display mask
/// the native text is the mask's text for the value, literals included, and the value sent to the engine never holds
/// one; without a mask the native text is the value. The rule itself is the shared `TextMask` of the protocol module,
/// the one Compose calls too.
struct FieldText {
  let mask: TextMask?

  /// What an edit of the native text comes to.
  struct Edit: Equatable {
    /// The value the text holds: what is sent as `valueChange`.
    let value: String
    /// The text the field shows for it.
    let text: String
    /// Where the mask puts the caret in `text`, a UTF-16 offset; `nil` when the native text stays as typed.
    let caret: Int?
  }

  /// The native text that shows `value`.
  func shows(_ value: String) -> String {
    mask?.format(value: value) ?? value
  }

  /// The value the native text `native` holds.
  func value(of native: String) -> String {
    mask?.valueOf(shown: native) ?? native
  }

  /// The person changed the native text to `typed` while the field held `value`. SwiftUI does not say where the caret
  /// is with the edit, so the mask finds the change by the text both share; `maxLength` is the mask's limit.
  func read(_ typed: String, after value: String, maxLength: Int?) -> Edit {
    guard let mask else { return Edit(value: typed, text: typed, caret: nil) }
    let edit = mask.edit(
      value: value, text: typed, caret: nil, limit: maxLength.map { KotlinInt(int: Int32($0)) })
    return Edit(
      value: edit.value, text: edit.text, caret: edit.text == typed ? nil : Int(edit.caret))
  }
}

/// A caret a mask placed: `offset` in the native text (UTF-16), for the edit number `edit`, so that two moves to the
/// same offset are two moves.
struct CaretMove: Equatable {
  let offset: Int
  let edit: Int
}

/// A masked field's one-line `TextField`, whose caret goes where the mask put it after it rewrote the text. The
/// selection binding is iOS 18's; below it the caret is where UIKit leaves it after a replaced text, at the end.
@available(iOS 18.0, *)
struct CaretTextField: View {
  @Binding var text: String
  let caret: CaretMove?
  @State private var selection: TextSelection?

  var body: some View {
    TextField("", text: $text, selection: $selection)
      .onChange(of: caret) { _, move in
        guard let move else { return }
        let offset = min(max(0, move.offset), text.utf16.count)
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: offset, in: text))
      }
  }
}
