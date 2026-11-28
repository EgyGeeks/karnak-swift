import SwiftUI

/// What a screen shows while it has no content: its loading view, its error view with a retry, and, optionally,
/// its sign-in view while it needs a signed-in person. The app implements it once per screen, or once as the
/// default for every screen without its own, and registers the type with ``KarnakConfiguration/screenStates(_:)``
/// (`docs/integration.md`, Loading and error views).
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
/// need in a section. In a sheet they are held to a compact, fixed height, and ``EnvironmentValues/karnakScreenPlacement``
/// says where they are drawn. One instance serves every visit to its screen for the client's lifetime, so keep
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

  /// The view shown while the screen needs a signed-in person.
  associatedtype SignInRequiredContent: View = KarnakNoSignInView

  /// The sign-in view, shown while the screen needs a signed-in person and the app has said nobody is
  /// (``KarnakSwiftClient/setSession(signedIn:)``).
  ///
  /// Optional: the default answers ``KarnakNoSignInView``, which passes to the next in the order: a screen's
  /// entry without one uses the default's, and without either the SDK's placeholder shows. Answering
  /// ``KarnakSignInRequiredView`` yourself draws it for this entry, with your `signIn`. Never show
  /// `reason` itself to the person: it is a code, for choosing a text of your own.
  ///
  /// - Parameters:
  ///   - reason: The screen's reason code (`authReason`), or `nil` when it has none.
  ///   - signIn: Asks the app to sign in (``KarnakConfiguration/onSignInRequired``), once per call. The screen
  ///     loads in place once the app says signed in.
  @ViewBuilder func signInRequired(reason: String?, signIn: @escaping () -> Void)
    -> SignInRequiredContent
}

extension KarnakScreenStates {
  /// No sign-in view of its own, so the next in the order draws it.
  public func signInRequired(
    reason: String?, signIn: @escaping () -> Void
  ) -> KarnakNoSignInView {
    KarnakNoSignInView(reason: reason, signIn: signIn)
  }
}

/// What ``KarnakScreenStates/signInRequired(reason:signIn:)`` answers when the states have no sign-in view of
/// their own: the next in the order draws instead. Only the SDK makes one; drawn, it is the SDK's placeholder.
public struct KarnakNoSignInView: View {
  private let reason: String?
  private let signIn: () -> Void

  init(reason: String?, signIn: @escaping () -> Void) {
    self.reason = reason
    self.signIn = signIn
  }

  /// The SDK's placeholder, ``KarnakSignInRequiredView``.
  public var body: some View { KarnakSignInRequiredView(reason: reason, signIn: signIn) }
}

/// Where the loading or error view of a screen is drawn.
public enum KarnakScreenPlacement: Sendable {
  /// A full screen or a section: the space the host gives.
  case screen
  /// A sheet or another contained overlay, held to a compact height while the screen has no content.
  case contained
}

extension EnvironmentValues {
  /// Where the ``KarnakScreenStates`` view being drawn is placed, so an app can draw a compact skeleton in a
  /// sheet and a full one on a screen. It is ``KarnakScreenPlacement/screen`` outside a state view.
  @Entry public var karnakScreenPlacement = KarnakScreenPlacement.screen
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
  /// The sign-in view has no call-site argument: it is the entry's
  /// ``KarnakScreenStates/signInRequired(reason:signIn:)`` when it has its own, else the default's, else the
  /// SDK's placeholder (``KarnakSignInRequiredView``), on a section too.
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
