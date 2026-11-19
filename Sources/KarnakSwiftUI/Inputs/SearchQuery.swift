import KarnakCore
import SwiftUI

/// A search's query on screen (ADR 0043, D3 and D5), shared by the system's search field (``ScreenSearchable``) and
/// the field drawn in the node's place (``SearchFieldView``): the native text is kept in step with the engine's value
/// as a `text_field`'s is (``TextSync``), and a submit asks the engine what it sends (`ResolvedSearch.payload`). There
/// is no second state for the query: the engine's value is the truth, and its 300 ms debounce applies to the requests
/// that read it.
@MainActor
final class SearchQuery {
  private var sync: TextSync

  init(_ search: ResolvedSearch) {
    sync = TextSync(search.value, edits: Int(search.edits))
  }

  /// The native text became `typed`: sends the edit once (a submit may have sent it already) and returns the text
  /// the field should show instead, if any (an edit while the search takes none is undone).
  func edited(_ typed: String, search: ResolvedSearch, inputs: InputSink) -> String? {
    outcome(
      sync.edited(typed, tree: search.value, accepts: search.acceptsEdits, maxLength: nil),
      search: search, inputs: inputs)
  }

  /// A new tree while the field shows `shown`: the text to write into the field when the engine's value is news (a
  /// `reset_value`, a `set_value`, a restored query).
  func treeChanged(_ search: ResolvedSearch, shown: String) -> String? {
    outcome(
      sync.treeValue(
        TextSync.Tree(value: search.value, edits: Int(search.edits)),
        readOnly: !search.acceptsEdits,
        shown: shown),
      search: search, inputs: nil)
  }

  /// The search stopped taking edits while the field shows `shown`: the engine's value, if the field must show it.
  func locked(_ search: ResolvedSearch, shown: String) -> String? {
    outcome(
      sync.locked(tree: TextSync.Tree(value: search.value, edits: Int(search.edits)), shown: shown),
      search: search, inputs: nil)
  }

  /// Submits `query`, the native text: sends an edit the engine has not seen yet first, so an action that reads the
  /// form reads `query`, then the `submit` event with the engine's payload. Returns false when nothing was sent (the
  /// search is disabled, or the query is shorter than `minLength`).
  @discardableResult
  func submit(
    _ query: String, search: ResolvedSearch, inputs: InputSink, actions: ActionSink
  ) -> Bool {
    guard search.enabled else { return false }
    _ = edited(query, search: search, inputs: inputs)
    guard let payload = search.payload(query: query) else { return false }
    if let handle = search.events[ResolvedSearch.companion.SUBMIT] {
      actions.event(handle, payload: payload, byUser: true)
    }
    return true
  }

  private func outcome(
    _ outcome: TextSync.Outcome, search: ResolvedSearch, inputs: InputSink?
  ) -> String? {
    switch outcome {
    case .keep: return nil
    case .send(let value):
      inputs?.send(.valueChange(search.key, value))
      return nil
    case .replace(let value): return value
    }
  }
}

extension View {
  /// Keeps `text`, a search's native text, in step with `search` through `query`: each edit is sent, and the engine's
  /// own value is written back.
  func syncsSearchQuery(
    _ search: ResolvedSearch, text: Binding<String>, query: SearchQuery, inputs: InputSink
  ) -> some View {
    onChange(of: text.wrappedValue) { _, typed in
      if let shown = query.edited(typed, search: search, inputs: inputs) {
        text.wrappedValue = shown
      }
    }
    .onChange(of: SearchTree(search)) { _, _ in
      if let shown = query.treeChanged(search, shown: text.wrappedValue) {
        text.wrappedValue = shown
      }
    }
    .onChange(of: search.acceptsEdits) { _, accepts in
      if !accepts, let shown = query.locked(search, shown: text.wrappedValue) {
        text.wrappedValue = shown
      }
    }
  }
}

/// What of a search's tree the native text follows: its value and the engine's count of its edits.
private struct SearchTree: Equatable {
  let value: String
  let edits: Int32

  init(_ search: ResolvedSearch) {
    value = search.value
    edits = search.edits
  }
}

extension ResolvedSearch {
  /// What the field shows while the query is empty: the placeholder, else the accessible name.
  var prompt: String { placeholder?.words ?? accessibleName }
}
