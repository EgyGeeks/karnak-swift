import Foundation

/// Where full screens' form state waits for a process that replaces this one (`docs/protocol.md`, Forms: State): one
/// small file the SDK owns in the app's caches, as the web renderer has `sessionStorage`. Not the scene's saved
/// state (`@SceneStorage`): the system decides when that is written and whether a new process gets it back, and a
/// process ended in the background did not.
///
/// A store reads what the last process left when it is made and removes the file, so that text is handed out once
/// (``take(_:)``) and what nobody takes ends with this process. From then on the file holds only what this process
/// keeps (``keep(_:_:)``), and a file older than ``lifetime`` is of no use to anyone. A file that can't be read or
/// written saves nothing and never throws. The texts are the engine's (`ScreenSavedState`): it never puts a
/// password or a `personal` value in one.
@MainActor
final class SavedFormsStore {
  /// The app's store, in its caches: not backed up, and the system may empty it, which only loses a restore.
  static let shared = SavedFormsStore(
    file: URL.cachesDirectory.appending(
      path: "karnak/saved-forms.json", directoryHint: .notDirectory))

  /// How long what a process kept is of use to the next one: a form left for longer starts clean.
  static let lifetime: TimeInterval = 24 * 60 * 60

  /// What the file holds: the texts by name and when the process that kept them wrote them.
  private struct Kept: Codable {
    var savedAt: Date
    var forms: [String: String]
  }

  private let file: URL
  private let now: @MainActor () -> Date
  private var left: [String: String]
  private var kept: [String: String] = [:]

  init(file: URL, now: @escaping @MainActor () -> Date = { Date() }) {
    self.file = file
    self.now = now
    let last = (try? Data(contentsOf: file)).flatMap {
      try? JSONDecoder().decode(Kept.self, from: $0)
    }
    let age = last.map { now().timeIntervalSince($0.savedAt) }
    // A time from the future is a clock that moved: as old as it gets.
    let fresh = age.map { $0 >= 0 && $0 <= Self.lifetime } ?? false
    left = fresh ? last?.forms ?? [:] : [:]
    try? FileManager.default.removeItem(at: file)
  }

  /// What the last process kept under `name`, once.
  func take(_ name: String) -> String? { left.removeValue(forKey: name) }

  /// Keeps `text` under `name` for the next process; nil keeps nothing under it.
  func keep(_ name: String, _ text: String?) {
    guard kept[name] != text else { return }
    kept[name] = text
    write()
  }

  private func write() {
    let files = FileManager.default
    guard !kept.isEmpty, let data = try? JSONEncoder().encode(Kept(savedAt: now(), forms: kept))
    else {
      try? files.removeItem(at: file)
      return
    }
    try? files.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(
      to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

/// The place of one screen in a ``SavedFormsStore``: the store and the screen's name in it (``SavedFormsKey``).
@MainActor
struct SavedFormsSlot {
  let store: SavedFormsStore
  let name: String

  func take() -> String? { store.take(name) }
  func keep(_ text: String?) { store.keep(name, text) }
}
