import Foundation
import SwiftUI

/// The host's hooks for what a screen asks the app to do (`docs/integration.md`, Setup). A
/// ``HostActionBridge`` answers the engine's host actions with them.
package struct KarnakHostCallbacks {
  package var onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)?
  package var onOpenUrl: ((_ url: URL) -> Void)?
  package var onCustom: ((_ type: String, _ params: [String: Any]) -> Void)?
  package var onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)?
  package var onDismiss: (() -> Void)?
  package var onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)?
  package var onNavigation: ((_ request: KarnakNavigation) -> Void)?
  package var onScreen: (@MainActor (_ event: KarnakScreenEvent) -> Void)?
  package var overlays: KarnakOverlays = .sdk

  /// Hooks from the host's closures; every one is optional.
  package init(
    onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)? = nil,
    onOpenUrl: ((_ url: URL) -> Void)? = nil,
    onCustom: ((_ type: String, _ params: [String: Any]) -> Void)? = nil,
    onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)? = nil,
    onNavigation: ((_ request: KarnakNavigation) -> Void)? = nil,
    onScreen: (@MainActor (_ event: KarnakScreenEvent) -> Void)? = nil,
    overlays: KarnakOverlays = .sdk
  ) {
    self.onNavigate = onNavigate
    self.onOpenUrl = onOpenUrl
    self.onCustom = onCustom
    self.onTrack = onTrack
    self.onDismiss = onDismiss
    self.onOpenScreen = onOpenScreen
    self.onNavigation = onNavigation
    self.onScreen = onScreen
    self.overlays = overlays
  }

  /// These hooks with `defaultNavigation` as `onNavigation` unless the host gave `onNavigation`
  /// or `onOpenScreen`: the explicit hooks win over `.karnakDestinations()`.
  package func withDefault(
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
  @Entry package var karnakHostCallbacks = KarnakHostCallbacks()
  /// Called with the model of each ``KarnakScreen`` as it opens, so tests can read what the screen
  /// presents and answer it as its alerts and sheets do.
  @Entry var karnakScreenObserver: (@MainActor (ScreenModel) -> Void)?
  /// Called with the model of each ``KarnakFlow`` as it starts, so tests can read the screens the
  /// flow presents.
  @Entry var karnakFlowObserver: (@MainActor (FlowModel) -> Void)?
  /// Where a screen sits in a host stack of the `KarnakNavigation` product (`.karnakDestinations()`, a tab's
  /// stack); nil outside one.
  @Entry package var karnakStack: (any HostStackPosition)?
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
  ///     another Karnak screen. Without it, `.karnakDestinations()` (`KarnakNavigation` product) on the
  ///     `NavigationStack` pushes the screen; this hook wins over it. It covers pushes only.
  ///   - onNavigation: Called with every navigation a screen asks for: an `open_screen` of any
  ///     presentation and a `back` of any form (``KarnakNavigation``). Perform it on your router,
  ///     open the screen with `KarnakScreen(_:params:entryId:)`, and report each entry your router
  ///     drops with ``KarnakSwiftNavigator/entryRemoved(_:)``. It wins over `onOpenScreen` and
  ///     over `.karnakDestinations()`.
  ///   - onScreen: Called with every screen the SDK shows or ends, for analytics
  ///     (``KarnakScreenEvent``): the screens of your stack, of a `modal`, a `sheet` or a `detail`
  ///     pane, the screens of a `show_sheet` and the steps of a flow, with the flow's id, revision
  ///     and step. Ids only, never a param. Your own start screen has no entry and is yours to
  ///     report. It runs on the main thread.
  ///   - overlays: Who draws the screens that open as a `modal` or a `sheet`.
  ///     ``KarnakOverlays/sdk``, the default, draws them in the SDK's contained stack, also for a
  ///     screen your own router drew, so `onNavigation` hears only requests for your stack.
  ///     ``KarnakOverlays/host`` sends them to `onNavigation` with their presentation, for an app
  ///     that draws its own sheets.
  public func karnakHost(
    _ client: KarnakSwiftClient,
    onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)? = nil,
    onOpenUrl: ((_ url: URL) -> Void)? = nil,
    onCustom: ((_ type: String, _ params: [String: Any]) -> Void)? = nil,
    onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)? = nil,
    onNavigation: ((_ request: KarnakNavigation) -> Void)? = nil,
    onScreen: (@MainActor (_ event: KarnakScreenEvent) -> Void)? = nil,
    overlays: KarnakOverlays = .sdk
  ) -> some View {
    karnakHost(
      opener: client,
      callbacks: KarnakHostCallbacks(
        onNavigate: onNavigate, onOpenUrl: onOpenUrl, onCustom: onCustom, onTrack: onTrack,
        onDismiss: onDismiss, onOpenScreen: onOpenScreen, onNavigation: onNavigation,
        onScreen: onScreen, overlays: overlays)
    )
    .environment(\.karnakFonts, client.fonts)
    .environment(\.karnakScreenStates, client.screenStates)
    .environment(\.karnakComponents, client.components)
    .modifier(KarnakResourcesHost(core: client.resourcesCore))
    .modifier(KarnakThemeHost(client: client))
    .modifier(KarnakScreenEventsHost(client: client, onScreen: onScreen))
  }

  func karnakHost(
    opener: any ScreenOpening, callbacks: KarnakHostCallbacks = .init()
  ) -> some View {
    environment(\.karnakOpener, opener).environment(\.karnakHostCallbacks, callbacks)
  }
}
