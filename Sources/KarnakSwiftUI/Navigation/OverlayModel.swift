import Foundation

/// One entry of a contained stack: the model that follows a Karnak screen's instance, or the
/// native route the app draws.
struct OverlayEntry: Identifiable {
  let id: String
  /// The model of a Karnak screen; nil for a native route.
  let model: ScreenModel?
  /// The native route of a flow step; nil for a Karnak screen.
  let route: KarnakRouteTarget?
}

/// Follows the contained stack of one overlay (`docs/renderer-contract.md`, Contained stacks): the
/// entries to draw, bottom first, and the user's ways out. The engine owns the stack and closes
/// every entry's screen, so this model only listens, draws and reports dismissals.
@MainActor
final class OverlayModel: ObservableObject, Identifiable {
  let id: String
  /// ``KarnakPresentation/sheet`` or ``KarnakPresentation/modal``.
  let presentation: KarnakPresentation
  @Published private(set) var entries: [OverlayEntry] = []
  /// Called when the stack has no entry left: the overlay is over, however it ended.
  var onEnded: () -> Void = {}

  private let stack: any StackSession
  private let makeModel: @MainActor (any ScreenSession) -> ScreenModel
  private var models: [String: ScreenModel] = [:]
  private var stopObserving: (() -> Void)?

  init(
    _ request: OverlayRequest, makeModel: @escaping @MainActor (any ScreenSession) -> ScreenModel
  ) {
    id = request.id
    presentation = request.presentation
    stack = request.stack
    self.makeModel = makeModel
  }

  /// Starts listening to the stack. The entries are there before this returns on the main thread.
  func start() {
    stopObserving = stack.observe { [weak self] sessions in
      self?.receive(sessions)
    }
  }

  /// Stops listening and following the screens; the engine closes them.
  func stop() {
    stopObserving?()
    stopObserving = nil
    for model in models.values { model.stop() }
    models = [:]
  }

  /// The user swiped the sheet down: the whole overlay goes.
  func dismissedByUser() {
    entries.first.map { stack.entryRemoved($0.id) }
  }

  /// The user popped to `count` entries (the system back, a swipe from the edge).
  func popped(toCount count: Int) {
    guard count >= 1, entries.count > count else { return }
    stack.entryRemoved(entries[count].id)
  }

  private func receive(_ sessions: [StackEntrySession]) {
    let ids = Set(sessions.map(\.id))
    for (id, model) in models where !ids.contains(id) {
      model.stop()
      models[id] = nil
    }
    entries = sessions.map { session in
      guard let screen = session.screen else {
        return OverlayEntry(id: session.id, model: nil, route: session.route)
      }
      let model = models[session.id] ?? makeModel(screen)
      models[session.id] = model
      return OverlayEntry(id: session.id, model: model, route: nil)
    }
    if sessions.isEmpty { onEnded() }
  }
}
