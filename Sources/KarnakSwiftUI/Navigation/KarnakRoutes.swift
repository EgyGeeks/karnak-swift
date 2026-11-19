import SwiftUI

/// The native screens of the routes the app registered, by route id: `.karnakRoute` of the `KarnakNavigation`
/// product fills it, and the route steps the core draws (a flow's overlay, ``KarnakFlow``) read it.
package struct KarnakRouteRegistry {
  private var screens: [String: ([String: Any]) -> AnyView] = [:]

  package mutating func register(_ id: String, screen: @escaping ([String: Any]) -> AnyView) {
    screens[id] = screen
  }

  func screen(for id: String, params: [String: Any]) -> AnyView? {
    screens[id]?(params)
  }
}

extension EnvironmentValues {
  /// The routes registered above the views below.
  @Entry package var karnakRoutes = KarnakRouteRegistry()
}

/// A native route a stack shows as an entry: which route, its params and the handle that ends it.
package struct KarnakRouteTarget {
  package let id: String
  package let params: [String: Any]
  package let handle: KarnakFlowHandle?

  package init(id: String, params: [String: Any], handle: KarnakFlowHandle?) {
    self.id = id
    self.params = params
    self.handle = handle
  }
}

/// The screen of a native route entry: the app's view for the route with the flow handle in its
/// environment, or a plain message when the app registered none.
package struct KarnakRouteEntryView: View {
  let route: KarnakRouteTarget
  @Environment(\.karnakRoutes) private var routes
  @Environment(\.karnakOpener) private var opener

  package init(route: KarnakRouteTarget) {
    self.route = route
  }

  package var body: some View {
    if let screen = routes.screen(for: route.id, params: route.params) {
      screen.environment(\.karnakFlow, route.handle)
    } else {
      KarnakMissingRouteView()
        .task { opener?.report(Self.missing(route.id)) }
    }
  }

  package static func missing(_ id: String) -> String {
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
package struct KarnakMissingRouteView: View {
  @Environment(\.karnakScreenStates) private var screenStates

  package init() {}

  package var body: some View {
    if let states = screenStates.states(for: nil) {
      states.error(kind: .notFound, retry: {})
    } else {
      KarnakErrorView()
    }
  }
}
