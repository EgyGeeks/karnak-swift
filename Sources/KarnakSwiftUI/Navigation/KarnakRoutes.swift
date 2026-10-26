import SwiftUI

extension View {
  /// Registers the native screen for the route `id` (`karnak.routes.json`), so a `route` step of a
  /// flow shows it (`docs/integration.md`, Flows on iOS). Apply it once near the root, next to
  /// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:overlays:)``,
  /// and again on a sheet or cover that SwiftUI doesn't connect to the same hierarchy. It covers
  /// the entries that `.karnakDestinations()`, the overlay of a flow and ``KarnakFlow`` draw.
  ///
  /// ```swift
  /// ContentView()
  ///   .karnakHost(karnak)
  ///   .karnakRoute("wallet_pay") { params in WalletPay(cartId: params["cartId"] as? String) }
  /// ```
  ///
  /// `content` gets the route's params as JSON values. The view it builds reads the flow handle
  /// with `@Environment(\.karnakFlow)` and ends the step with
  /// ``KarnakFlowHandle/finish(_:result:)``. A route with no registered screen shows a plain
  /// message and is logged.
  public func karnakRoute<Content: View>(
    _ id: String, @ViewBuilder content: @escaping (_ params: [String: Any]) -> Content
  ) -> some View {
    transformEnvironment(\.karnakRoutes) { $0.register(id) { AnyView(content($0)) } }
  }
}

/// The native screens of the routes the app registered, by route id.
struct KarnakRouteRegistry {
  private var screens: [String: ([String: Any]) -> AnyView] = [:]

  mutating func register(_ id: String, screen: @escaping ([String: Any]) -> AnyView) {
    screens[id] = screen
  }

  func screen(for id: String, params: [String: Any]) -> AnyView? {
    screens[id]?(params)
  }
}

extension EnvironmentValues {
  @Entry var karnakRoutes = KarnakRouteRegistry()
}

/// A native route a stack shows as an entry: which route, its params and the handle that ends it.
struct KarnakRouteTarget {
  let id: String
  let params: [String: Any]
  let handle: KarnakFlowHandle?
}

/// The screen of a native route entry: the app's view for the route with the flow handle in its
/// environment, or a plain message when the app registered none.
struct KarnakRouteEntryView: View {
  let route: KarnakRouteTarget
  @Environment(\.karnakRoutes) private var routes
  @Environment(\.karnakOpener) private var opener

  var body: some View {
    if let screen = routes.screen(for: route.id, params: route.params) {
      screen.environment(\.karnakFlow, route.handle)
    } else {
      KarnakMissingRouteView()
        .task { opener?.report(Self.missing(route.id)) }
    }
  }

  static func missing(_ id: String) -> String {
    "Karnak: the flow step shows the native route '\(id)', and the app registered no screen for it "
      + "(.karnakRoute(\"\(id)\") { … }): the step stays until the user goes back."
  }
}

/// What a route step shows when the app registered no screen for its route: the error view
/// registered as the default with ``KarnakConfiguration/screenStates(_:)`` (kind
/// ``KarnakScreenError/Kind/notFound``), else the SDK's message.
///
/// It has no retry on purpose. A route's screen is registered in code (`.karnakRoute`), so loading
/// again finds the same nothing: the SDK's message shows no button, and the `retry` a registered view
/// gets does nothing. The step is developer misuse, logged when it shows.
struct KarnakMissingRouteView: View {
  @Environment(\.karnakScreenStates) private var screenStates

  var body: some View {
    if let states = screenStates.states(for: nil) {
      states.error(kind: .notFound, retry: {})
    } else {
      KarnakErrorView()
    }
  }
}
