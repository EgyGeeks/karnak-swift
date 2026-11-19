import KarnakSwiftUI
import SwiftUI

extension View {
  /// Registers the native screen for the route `id` (`karnak.routes.json`), so a `route` step of a
  /// flow shows it (`docs/integration.md`, Flows on iOS). Apply it once near the root, next to
  /// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:onScreen:overlays:)``,
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
