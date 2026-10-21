import SwiftUI

/// A ``KarnakScreenStates`` with its types erased, so the registry can hold one per screen.
@MainActor
struct AnyScreenStates {
  private let makeLoading: () -> AnyView
  private let makeError: (KarnakScreenError.Kind, @escaping () -> Void) -> AnyView

  init<States: KarnakScreenStates>(_ states: States) {
    makeLoading = { AnyView(states.loading()) }
    makeError = { kind, retry in AnyView(states.error(kind: kind, retry: retry)) }
  }

  func loading() -> AnyView { makeLoading() }

  func error(kind: KarnakScreenError.Kind, retry: @escaping () -> Void) -> AnyView {
    makeError(kind, retry)
  }
}

/// What `screenStates` registered, before any instance exists: a value the configuration keeps.
struct ScreenStatesFactories {
  var screens: [String: @MainActor () -> AnyScreenStates] = [:]
  var defaultFactory: (@MainActor () -> AnyScreenStates)?
}

/// The factories of a client with the instances they made. An instance is created the first time its
/// screen needs a loading or error view, then reused for as long as the client lives. Everything but the
/// initializer runs on the main actor.
final class ScreenStatesRegistry: @unchecked Sendable {
  /// Nothing registered: every screen draws the SDK's views.
  static let empty = ScreenStatesRegistry(ScreenStatesFactories(), debug: false, log: { _ in })

  private let factories: ScreenStatesFactories
  private let debug: Bool
  private let log: @Sendable (String) -> Void
  private var screens: [String: AnyScreenStates] = [:]
  private var fallback: AnyScreenStates?
  private var reported: Set<String> = []

  init(_ factories: ScreenStatesFactories, debug: Bool, log: @escaping @Sendable (String) -> Void) {
    self.factories = factories
    self.debug = debug
    self.log = log
  }

  /// Whether nothing is registered, so no screen is expected to have an entry.
  var isEmpty: Bool { factories.screens.isEmpty && factories.defaultFactory == nil }

  /// The states of `screenId`: its entry, else the default, else `nil`. A flow's first step has no
  /// screen id yet and passes `nil`, which skips the entry.
  @MainActor
  func states(for screenId: String?) -> AnyScreenStates? {
    if let screenId, let made = screens[screenId] { return made }
    if let screenId, let make = factories.screens[screenId] {
      let made = make()
      screens[screenId] = made
      return made
    }
    if let fallback { return fallback }
    fallback = factories.defaultFactory?()
    return fallback
  }

  /// In a debug client, logs once per id that `screenId` has no entry of its own and falls back, when
  /// the app registered any entry.
  @MainActor
  func reportFallback(_ screenId: String) {
    guard debug, !isEmpty, factories.screens[screenId] == nil, reported.insert(screenId).inserted
    else { return }
    log(
      "Karnak: screen \"\(screenId)\" has no screenStates entry, so it uses the default (or the SDK's) "
        + "loading and error views. Register states.screen(\"\(screenId)\") { … } in screenStates, or leave it "
        + "on the default.")
  }
}
