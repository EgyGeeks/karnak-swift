import KarnakCore
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
  private let cachedLoadingScreen: @MainActor () -> CachedLoadingScreen?
  private let debug: Bool
  private let log: @Sendable (String) -> Void
  private var screens: [String: AnyScreenStates] = [:]
  private var fallback: AnyScreenStates?
  private var reported: Set<String> = []
  private var checkedLoadingScreen: (json: String, resolves: Bool)?

  /// `loadingScreen` reads the app's loading screen (``KarnakConfiguration/loadingScreen``) while the
  /// client holds it cached, else `nil`.
  init(
    _ factories: ScreenStatesFactories, debug: Bool, log: @escaping @Sendable (String) -> Void,
    loadingScreen: @escaping @MainActor () -> CachedLoadingScreen? = { nil }
  ) {
    self.factories = factories
    self.cachedLoadingScreen = loadingScreen
    self.debug = debug
    self.log = log
  }

  /// Whether nothing is registered, so no screen is expected to have an entry.
  var isEmpty: Bool { factories.screens.isEmpty && factories.defaultFactory == nil }

  /// The states of `screenId`: its entry, else the default, else `nil`. A flow's first step has no
  /// screen id yet and passes `nil`, which skips the entry.
  @MainActor
  func states(for screenId: String?) -> AnyScreenStates? {
    entry(for: screenId) ?? defaultStates()
  }

  /// The entry registered for `screenId`, made the first time it is asked for; `nil` for none.
  @MainActor
  func entry(for screenId: String?) -> AnyScreenStates? {
    guard let screenId else { return nil }
    if let made = screens[screenId] { return made }
    guard let make = factories.screens[screenId] else { return nil }
    let made = make()
    screens[screenId] = made
    return made
  }

  /// The registered default, made the first time it is asked for; `nil` for none.
  @MainActor
  func defaultStates() -> AnyScreenStates? {
    if let fallback { return fallback }
    fallback = factories.defaultFactory?()
    return fallback
  }

  /// The app's loading screen while the client holds it cached and its body resolves, else `nil`, so a
  /// body that can't be drawn falls to the next view instead of leaving the screen blank. Each body is
  /// resolved once to check it.
  @MainActor
  func loadingScreen() -> CachedLoadingScreen? {
    guard let screen = cachedLoadingScreen() else { return nil }
    if checkedLoadingScreen?.json != screen.screenJson {
      checkedLoadingScreen = (screen.screenJson, Self.resolves(screen))
    }
    return checkedLoadingScreen?.resolves == true ? screen : nil
  }

  @MainActor
  private static func resolves(_ screen: CachedLoadingScreen) -> Bool {
    let environment = DeviceSizes.current.environment(
      colorScheme: .light, layoutDirection: .leftToRight, width: 0)
    let state = ScreenResolversKt.screenResolver(debug: false, log: { _ in })
      .resolve(screenJson: screen.screenJson, themeJson: screen.themeJson, environment: environment)
    return state is ScreenStateContent
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
