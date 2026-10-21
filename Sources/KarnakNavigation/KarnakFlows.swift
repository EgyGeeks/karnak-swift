import KarnakCore
import KarnakSwiftUI

/// The flows module (ADR 0017, D15): installs `karnak-navigation` on the client, so the client
/// announces the `open_flow` action (`X-Karnak-Actions`) and runs flows. Add it to
/// ``KarnakConfiguration/modules`` where the client is built:
///
/// ```swift
/// import KarnakNavigation
///
/// var configuration = KarnakConfiguration(clientKey: "pk_live_…", baseUrl: "https://karnak.example.com")
/// configuration.modules = [KarnakFlows()]
/// let karnak = try KarnakSwiftClient(configuration)
/// ```
///
/// An app that doesn't add it announces no `open_flow`, so the server never sends one, and
/// carries none of the module's Swift code. (The Kotlin part is in the one static `KarnakCore`
/// framework, as ADR 0017 D15 accepts.) Install it once: a second flows module on one client is
/// developer misuse, which throws in debug and is logged and ignored in release.
///
/// A flow is started by a screen's `open_flow` action, or placed by the app with `KarnakFlow`
/// (`KarnakSwiftUI`). See `docs/integration.md`, Flows on iOS.
///
/// The module also runs links (`docs/integration.md`, Links on iOS): the client then announces
/// `open_link` too, and ``SwiftUI/View/karnakOnOpenURL(onNotKarnak:onRejected:)`` opens the links
/// the system gives the app. A table with patterns that need a signed-in user needs
/// `KarnakFlows(links: KarnakLinkOptions(signedIn: …, onSignInRequired: …))`.
public final class KarnakFlows: KarnakFlowModule, @unchecked Sendable {
  /// The Kotlin module this installs: its snapshot, restore and ownership calls are the module's
  /// (`docs/integration.md`, Process death).
  public let navigationModule: KarnakNavigationModule

  /// Installs flows and links. `links` says who is signed in, for the patterns with
  /// `auth: "required"`: by default nobody, so such a link is rejected as `sign_in_required`.
  public init(links: KarnakLinkOptions = KarnakLinkOptions()) {
    navigationModule = KarnakNavigationModule(linkOptions: links.kotlin)
  }

  public func install(into config: KarnakClientConfig) {
    let module = navigationModule
    config.install { builder in builder.install(extension: module) }
  }
}
