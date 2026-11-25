import KarnakCore
import SwiftUI

/// What a text field's native text shows and holds (`docs/renderer-contract.md`, Display masks). With a display mask
/// the native text is the mask's text for the value, literals included, and the value sent to the engine never holds
/// one; without a mask the native text is the value. The rule itself is the shared `TextMask` of the protocol module,
/// the one Compose calls too.
struct FieldText {
  let mask: TextMask?
  /// Whether the field holds Latin digits only (a phone or digits field): Arabic-Indic digits typed or pasted are read
  /// as `0`-`9` before the mask or the value sees them (`docs/renderer-contract.md`, Latin digits).
  var latinDigits = false

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

  /// The person changed the native text to `typed` while the field held `value`, with the caret at `caret` (a UTF-16
  /// offset) when the field knows it (``CaretTextField``); `maxLength` is the mask's limit. Without a caret the mask
  /// finds the change by the text both share, which among repeated digits can be the wrong one of them (`٠١٠` then a
  /// `٠`), so the caret is passed whenever the platform has it.
  func read(_ native: String, after value: String, caret: Int? = nil, maxLength: Int?) -> Edit {
    let typed = latinDigits ? Digits.shared.ascii(text: native) : native
    guard let mask else { return Edit(value: typed, text: typed, caret: nil) }
    let edit = mask.edit(
      value: value, text: typed, caret: caret.map { KotlinInt(int: Int32($0)) },
      limit: maxLength.map { KotlinInt(int: Int32($0)) })
    return Edit(
      value: edit.value, text: edit.text, caret: edit.text == native ? nil : Int(edit.caret))
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
///
/// `typedCaret` is the caret the field had when the person last changed the text: SwiftUI moves the selection before
/// it reports the text, so the mask can read the edit where it was made instead of guessing it from the text.
@available(iOS 18.0, *)
struct CaretTextField: View {
  @Binding var text: String
  @Binding var typedCaret: Int?
  let caret: CaretMove?
  @State private var selection: TextSelection?

  var body: some View {
    TextField("", text: $text, selection: $selection)
      .onChange(of: selection) { _, selection in typedCaret = selection.flatMap(caretOffset) }
      .onChange(of: caret) { _, move in
        guard let move else { return }
        let offset = min(max(0, move.offset), text.utf16.count)
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: offset, in: text))
      }
  }

  /// The end of the selection, the caret of an edit, as a UTF-16 offset in the text.
  private func caretOffset(of selection: TextSelection) -> Int? {
    switch selection.indices {
    case .selection(let range):
      // The selection can be ahead of the text SwiftUI reports next: an index past it would trap.
      range.upperBound <= text.endIndex ? range.upperBound.utf16Offset(in: text) : nil
    default: nil
    }
  }
}
