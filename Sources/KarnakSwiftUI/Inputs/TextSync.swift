/// Keeps a text field's native text and the engine's value in step (`docs/renderer-contract.md`, `ResolvedTextField`).
/// The field keeps its own editing state and sends every edit. A tree carries how many of the field's edits the engine
/// had taken in: while that is below the edits sent, more are on their way and the tree is no answer to them (an
/// echo, a restyle, or a value the next edit replaces), so the native text stays. Once it covers them, a value that
/// differs from what both sides last agreed on is the engine's own (a `reset`, a refresh, an edit it changed or
/// dropped) and replaces the text; a smaller count than the last tree's means the engine started the field over. It
/// never sends a value it took from the tree.
struct TextSync: Equatable {
  /// What the field does with an edit or a new tree value.
  enum Outcome: Equatable {
    /// Nothing.
    case keep
    /// Send `valueChange` with the text.
    case send(String)
    /// Write the text into the native field.
    case replace(String)
  }

  /// A tree's value of the field, and how many of the field's edits the engine had taken in when it resolved it.
  struct Tree: Equatable {
    let value: String
    let edits: Int
  }

  /// The value the native text and the engine agree on.
  private(set) var agreed: String
  /// The engine's count of the field's edits that covers every edit sent.
  private var awaited: Int
  /// The count of the last tree.
  private var seen: Int

  init(_ value: String, edits: Int = 0) {
    agreed = value
    awaited = edits
    seen = edits
  }

  /// The person changed the native text to `typed`. `tree` is the engine's value now; `accepts` is false while the
  /// input is disabled or read-only, when the tree's value is written back; `maxLength` (in code points) refuses an edit
  /// that leaves the text over it and no shorter than it was, so a value given over the limit is kept whole and every
  /// edit that shortens it is sent (`docs/renderer-contract.md`, Text limits). A refused edit writes the agreed text back.
  mutating func edited(_ typed: String, tree: String, accepts: Bool, maxLength: Int?) -> Outcome {
    guard typed != agreed else { return .keep }
    guard accepts else {
      agreed = tree
      return .replace(tree)
    }
    let length = typed.unicodeScalars.count
    if let maxLength, length > maxLength, length >= agreed.unicodeScalars.count {
      return .replace(agreed)
    }
    agreed = typed
    awaited += 1
    return .send(typed)
  }

  /// A tree brought `tree` while the field shows `shown`. It replaces the text only when the engine has taken in every
  /// edit sent, or `readOnly` (the engine takes no edit, so its value is the truth at once), and its value is news.
  mutating func treeValue(_ tree: Tree, readOnly: Bool = false, shown: String) -> Outcome {
    let restarted = tree.edits < seen
    seen = tree.edits
    guard readOnly || restarted || tree.edits >= awaited else { return .keep }
    awaited = tree.edits
    guard tree.value != agreed else { return .keep }
    agreed = tree.value
    return tree.value == shown ? .keep : .replace(tree.value)
  }

  /// The input stopped taking edits (disabled, or read-only while its form submits) while the field shows `shown`.
  /// `tree` is the truth now: an edit the engine ignored is undone, and no answer to an edit is awaited any more.
  mutating func locked(tree: Tree, shown: String) -> Outcome {
    seen = tree.edits
    awaited = tree.edits
    agreed = tree.value
    return tree.value == shown ? .keep : .replace(tree.value)
  }

  /// Where the caret goes (a UTF-16 offset in `restored`) when a refused edit turned the text `typed` back into
  /// `restored`. `typedCaret` is the caret after the edit, when the field knows it: an insertion put it past what was
  /// inserted, so that is taken off; a deletion left it where the deleted text began. Without it, the edit began where
  /// the two texts first differ.
  static func caretAfterRefusal(typed: String, restored: String, typedCaret: Int?) -> Int {
    let typedUnits = Array(typed.utf16)
    let end = restored.utf16.count
    let offset: Int
    if let typedCaret, typedCaret <= typedUnits.count {
      offset = min(max(0, typedCaret - max(0, typedUnits.count - end)), end)
    } else {
      offset = min(zip(typedUnits, restored.utf16).prefix { $0 == $1 }.count, end)
    }
    return characterBoundary(atOrBefore: offset, in: restored)
  }

  /// `offset` (UTF-16) moved back to the start of the character it falls inside, so a caret never lands in an emoji.
  private static func characterBoundary(atOrBefore offset: Int, in text: String) -> Int {
    var boundary = offset
    while boundary > 0, !startsScalar(boundary, in: text) { boundary -= 1 }
    return boundary
  }

  /// Whether `offset` (UTF-16) is the start of a Unicode scalar of `text`.
  private static func startsScalar(_ offset: Int, in text: String) -> Bool {
    String.Index(utf16Offset: offset, in: text).samePosition(in: text.unicodeScalars) != nil
  }
}
