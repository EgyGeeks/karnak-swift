import Foundation

/// One screen of a detail pane as it is saved with the screen that opened it: its id, its params as JSON text, and
/// the form state the person typed in it.
struct SavedPaneScreen: Codable, Equatable {
  let screenId: String
  let params: String
  var forms: String?

  /// The params as JSON host values; none when the text isn't a JSON object.
  var paramValues: [String: Any] {
    let object = params.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    return object as? [String: Any] ?? [:]
  }
}

/// The detail pane a screen keeps for a process that replaces this one (`docs/renderer-contract.md`, Detail panes):
/// kept in the store of the screen's form state, under a name of its own, at the same moments (the app leaves the
/// foreground; dropped when it comes back or the screen closes), and reopened by the screen's next instance as a new
/// stack with fresh instances (`KarnakNavigator.restoreOverlay`), as Compose does with its saved state. A pane that
/// shows a flow's native route is not kept: the flow died with the process.
@MainActor
enum SavedDetail {
  /// Where the detail of the screen whose form state is kept in `forms` is kept.
  static func slot(beside forms: SavedFormsSlot) -> SavedFormsSlot {
    SavedFormsSlot(store: forms.store, name: "karnak.detail." + forms.name)
  }

  /// The text that reopens `entries`, bottom first, with `forms` of each; nil when one of them can't be kept.
  static func text(of entries: [OverlayEntry], forms: (OverlayEntry) -> String?) -> String? {
    var screens: [SavedPaneScreen] = []
    for entry in entries {
      guard let screenId = entry.model?.screenId, let params = json(entry.params) else {
        return nil
      }
      screens.append(SavedPaneScreen(screenId: screenId, params: params, forms: forms(entry)))
    }
    guard !screens.isEmpty, let data = try? JSONEncoder().encode(screens) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// The screens `text` holds; none when it can't be read.
  static func screens(from text: String) -> [SavedPaneScreen] {
    text.data(using: .utf8).flatMap { try? JSONDecoder().decode([SavedPaneScreen].self, from: $0) }
      ?? []
  }

  private static func json(_ params: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(params),
      let data = try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
