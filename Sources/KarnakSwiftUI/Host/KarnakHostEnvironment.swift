import Foundation
import SwiftUI

/// The host's hooks for what a screen asks the app to do (`docs/integration.md`, Setup). A
/// ``HostActionBridge`` answers the engine's host actions with them.
struct KarnakHostCallbacks {
  var onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)?
  var onOpenUrl: ((_ url: URL) -> Void)?
  var onCustom: ((_ type: String, _ params: [String: Any]) -> Void)?
  var onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)?
  var onDismiss: (() -> Void)?
  var onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)?
  var onNavigation: ((_ request: KarnakNavigation) -> Void)?

  /// These hooks with `defaultNavigation` as `onNavigation` unless the host gave `onNavigation`
  /// or `onOpenScreen`: the explicit hooks win over `.karnakDestinations()`.
  func withDefault(
    navigation defaultNavigation: ((_ request: KarnakNavigation) -> Void)?
  ) -> KarnakHostCallbacks {
    var resolved = self
    if onNavigation == nil && onOpenScreen == nil { resolved.onNavigation = defaultNavigation }
    return resolved
  }
}

extension EnvironmentValues {
  /// Opens the screens below. `nil` outside `.karnakHost`, where screens fail as rejected.
  @Entry var karnakOpener: (any ScreenOpening)?
  /// The host's action hooks.
  @Entry var karnakHostCallbacks = KarnakHostCallbacks()
  /// Called with the model of each ``KarnakScreen`` as it opens, so tests can read what the screen
  /// presents and answer it as its alerts and sheets do.
  @Entry var karnakScreenObserver: (@MainActor (ScreenModel) -> Void)?
  /// Called with the model of each ``KarnakFlow`` as it starts, so tests can read the screens the
  /// flow presents.
  @Entry var karnakFlowObserver: (@MainActor (FlowModel) -> Void)?
  /// Where a screen sits in the stack ``SwiftUI/View/karnakDestinations()`` drives; nil outside it.
  @Entry var karnakStack: KarnakStackLevel?
}

extension View {
  /// Gives every Karnak screen and section below this view the `client` and the host's hooks.
  /// Apply it once near the root, and again on a sheet or cover that SwiftUI doesn't connect
  /// to the same hierarchy.
  ///
  /// Server actions reach the app through the hooks. Every hook is optional: an action whose
  /// hook is missing is ignored and logged, never thrown on. The hooks run on the main thread
  /// when the user taps, and the latest closures are used, so changing one needs no reopening.
  /// The SDK owns no allowlist: `onNavigate` and `onOpenUrl` are your policy points.
  ///
  /// - Parameters:
  ///   - client: The client screens load through.
  ///   - onNavigate: Called with the route and params of a `navigate` action. The route is an
  ///     opaque id for your router.
  ///   - onOpenUrl: Called with the URL of an `open_url` action. It is absolute and neither
  ///     script-like nor a local file; you still decide which schemes and hosts to open.
  ///   - onCustom: Called with the type (such as `acme.add_to_cart`) and params of a custom
  ///     action.
  ///   - onTrack: Called with the event and properties of a `track` action.
  ///   - onDismiss: Called when a full screen's `dismiss` action asks to go back.
  ///   - onOpenScreen: Called with the id and params of an `open_screen` action, which asks for
  ///     another Karnak screen. Without it, ``SwiftUI/View/karnakDestinations()`` on the
  ///     `NavigationStack` pushes the screen; this hook wins over it. It covers pushes only.
  ///   - onNavigation: Called with every navigation a screen asks for: an `open_screen` of any
  ///     presentation and a `back` of any form (``KarnakNavigation``). Perform it on your router,
  ///     open the screen with `KarnakScreen(_:params:entryId:)`, and report each entry your router
  ///     drops with ``KarnakSwiftNavigator/entryRemoved(_:)``. It wins over `onOpenScreen` and
  ///     over `.karnakDestinations()`.
  public func karnakHost(
    _ client: KarnakSwiftClient,
    onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)? = nil,
    onOpenUrl: ((_ url: URL) -> Void)? = nil,
    onCustom: ((_ type: String, _ params: [String: Any]) -> Void)? = nil,
    onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)? = nil,
    onNavigation: ((_ request: KarnakNavigation) -> Void)? = nil
  ) -> some View {
    karnakHost(
      opener: client,
      callbacks: KarnakHostCallbacks(
        onNavigate: onNavigate, onOpenUrl: onOpenUrl, onCustom: onCustom, onTrack: onTrack,
        onDismiss: onDismiss, onOpenScreen: onOpenScreen, onNavigation: onNavigation)
    )
    .environment(\.karnakFonts, client.fonts)
    .environment(\.karnakScreenStates, client.screenStates)
    .modifier(KarnakShownThemeHost())
    .modifier(KarnakResourcesHost(core: client.resourcesCore))
  }

  func karnakHost(
    opener: any ScreenOpening, callbacks: KarnakHostCallbacks = .init()
  ) -> some View {
    environment(\.karnakOpener, opener).environment(\.karnakHostCallbacks, callbacks)
  }
}
