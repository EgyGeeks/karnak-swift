/// Keeps a text field's native text and the engine's value in step (`docs/renderer-contract.md`, Inputs: the engine
/// owns the value). The field keeps its own editing state and sends every edit; it writes the tree's value into the
/// native text only when the engine chose a value of its own (a `reset`, a refresh, an edit it ignored), never for the
/// echo of an edit it sent, however late that echo arrives, and it never sends a value it took from the tree.
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

  /// The value the native text and the engine agree on.
  private(set) var agreed: String
  /// The edits sent whose trees haven't come back yet, oldest first.
  private var sent: [String] = []

  init(_ value: String) {
    agreed = value
  }

  /// The person changed the native text to `typed`. `tree` is the engine's value now; `accepts` is false while the
  /// input is disabled or read-only, when the tree's value is written back; `maxLength` cuts the text at that many
  /// code points (`docs/renderer-contract.md`, Text limits), and the cut text is the edit that is sent.
  mutating func edited(_ typed: String, tree: String, accepts: Bool, maxLength: Int?) -> Outcome {
    guard typed != agreed else { return .keep }
    guard accepts else {
      agreed = tree
      sent = []
      return .replace(tree)
    }
    if let maxLength, typed.unicodeScalars.count > maxLength {
      return .replace(String(String.UnicodeScalarView(typed.unicodeScalars.prefix(maxLength))))
    }
    agreed = typed
    sent.append(typed)
    return .send(typed)
  }

  /// A tree brought `value`, while the field shows `shown`. The echo of an edit sent drops it and the older ones and
  /// changes nothing; any other value is the engine's own and replaces the text when it differs.
  mutating func treeValue(_ value: String, shown: String) -> Outcome {
    if let echoed = sent.firstIndex(of: value) {
      sent.removeFirst(echoed + 1)
      return .keep
    }
    sent = []
    agreed = value
    return value == shown ? .keep : .replace(value)
  }

  /// The input stopped taking edits (disabled, or read-only while its form submits) while the field shows `shown`.
  /// `tree` is the truth now: an edit the engine ignored is undone, and no echo is awaited any more.
  mutating func locked(tree: String, shown: String) -> Outcome {
    sent = []
    agreed = tree
    return tree == shown ? .keep : .replace(tree)
  }
}
