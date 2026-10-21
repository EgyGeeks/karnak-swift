import SwiftUI

/// What a screen shows while it has no content: its loading view, and its error view with a retry. The
/// app implements it once per screen, or once as the default for every screen without its own, and
/// registers the type with ``KarnakConfiguration/screenStates(_:)`` (`docs/integration.md`, Loading and
/// error views).
///
/// ```swift
/// struct ProductStates: KarnakScreenStates {
///   func loading() -> some View { ProductSkeleton() }
///   func error(kind: KarnakScreenError.Kind, retry: @escaping () -> Void) -> some View {
///     ProductError(retry: retry)
///   }
/// }
/// ```
///
/// The views are drawn in the space the screen is given: all of it for a full screen, and only what they
/// need in a section. One instance serves every visit to its screen for the client's lifetime, so keep
/// it free of state that outlives a screen.
@MainActor
public protocol KarnakScreenStates {
  /// The view shown until the screen has content.
  associatedtype LoadingContent: View
  /// The view shown when the screen couldn't be loaded.
  associatedtype ErrorContent: View

  /// The loading view, shown until the screen has content.
  @ViewBuilder func loading() -> LoadingContent

  /// The error view, shown when the screen couldn't be loaded and has nothing to show.
  ///
  /// - Parameters:
  ///   - kind: Why it couldn't be loaded.
  ///   - retry: Loads the screen again, showing ``loading()`` until it loads or fails again.
  @ViewBuilder func error(kind: KarnakScreenError.Kind, retry: @escaping () -> Void) -> ErrorContent
}

/// Registers the ``KarnakScreenStates`` of the screens, inside ``KarnakConfiguration/screenStates(_:)``.
public final class KarnakScreenStatesBuilder {
  private(set) var factories: [String: @MainActor () -> AnyScreenStates] = [:]
  private(set) var defaultFactory: (@MainActor () -> AnyScreenStates)?

  init(_ existing: ScreenStatesFactories) {
    factories = existing.screens
    defaultFactory = existing.defaultFactory
  }

  /// Registers `states` for every screen without an entry of its own. The closure runs the first time
  /// such a screen needs a loading or error view, and the instance is kept for the client's lifetime.
  public func `default`<States: KarnakScreenStates>(_ states: @escaping @MainActor () -> States) {
    defaultFactory = { AnyScreenStates(states()) }
  }

  /// Registers `states` for the screen `id`. The closure runs the first time that screen needs a
  /// loading or error view, and the instance is kept for the client's lifetime. A later registration
  /// of the same id replaces the earlier one.
  public func screen<States: KarnakScreenStates>(
    _ id: String, _ states: @escaping @MainActor () -> States
  ) {
    precondition(
      !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A screen id is not blank.")
    factories[id] = { AnyScreenStates(states()) }
  }

  var built: ScreenStatesFactories {
    ScreenStatesFactories(screens: factories, defaultFactory: defaultFactory)
  }
}

extension KarnakConfiguration {
  /// Registers the app's loading and error views per screen (`docs/integration.md`, Loading and error
  /// views):
  ///
  /// ```swift
  /// configuration.screenStates { states in
  ///   states.default { AppStates() }               // any id without its own entry
  ///   states.screen("product") { ProductStates() } // built the first time "product" loads, then kept
  /// }
  /// ```
  ///
  /// Only the closures are stored: the ``KarnakScreenStates`` of a screen is created the first time that
  /// screen shows a loading or error view, then kept for the client's lifetime. Every surface uses the
  /// registry (`karnakDestinations`, ``KarnakScreen``, ``KarnakSection``, sheets and flows),
  /// choosing per screen id, in this order:
  /// 1. the `loading` and `error` arguments of a ``KarnakScreen`` or ``KarnakSection`` call;
  /// 2. the entry registered for the screen id;
  /// 3. `default`;
  /// 4. the SDK's own: a spinner and a retry button (a section shows nothing).
  ///
  /// Registering is optional: a screen without an entry falls back, which matters for screens added
  /// on the server after an app release. A debug client (``debug``) logs once per such screen, and
  /// `karnak lint screen-states` warns at build time (`docs/integration.md`, Lint: forgotten screens). Blocks add up: a
  /// later one adds its entries, and an id registered again is replaced.
  public mutating func screenStates(_ configure: (KarnakScreenStatesBuilder) -> Void) {
    let builder = KarnakScreenStatesBuilder(screenStatesFactories)
    configure(builder)
    screenStatesFactories = builder.built
  }
}
