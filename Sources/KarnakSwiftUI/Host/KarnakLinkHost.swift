import KarnakCore
import SwiftUI

/// What a link that opens the app needs of the host (`KarnakNavigation`'s `handleLink`): the
/// client's Kotlin links, and the host's hooks as the engine's ``HostActions``, so the link takes
/// the same path as the same action from a screen. `package` access: the public API is in the
/// `KarnakNavigation` product, which the app adds only when it uses links.
package struct KarnakLinkContext {
  /// The links of the client.
  package let links: KarnakLinks
  /// The hooks the target is opened through. They stay valid as long as ``KarnakLinkHost`` lives.
  package let actions: HostActions
  /// Logs a diagnostic where the host configured its logs.
  package let report: @MainActor (String) -> Void
}

/// Owns the bridge from the hooks of one host to the engine's ``HostActions``, for as long as the
/// link handler that uses it lives: a joined flow a link started keeps asking the hooks for its
/// next steps, so the bridge must outlive the call.
@MainActor
package final class KarnakLinkHost: ObservableObject {
  private lazy var bridge = HostActionBridge { [weak self] message in
    self?.client?.report(message)
  }
  private weak var client: KarnakSwiftClient?

  package init() {}

  /// Uses `callbacks` and `opener` from now on. The screens' default for `onNavigation` is the
  /// stack of their level; a link has no level, so it opens on the stack that appeared last
  /// (``KarnakSwiftClient/open(_:params:)`` does the same). The explicit hooks win over it.
  func update(opener: (any ScreenOpening)?, callbacks: KarnakHostCallbacks) {
    let client = opener as? KarnakSwiftClient
    self.client = client
    bridge.update(
      callbacks.withDefault(navigation: { [weak client] request in
        MainActor.assumeIsolated { client?.performOnActiveStack(request) }
      }))
  }

  /// What a link needs, or nil outside `.karnakHost` and for a client with no links module.
  package var context: KarnakLinkContext? {
    guard let client, let links = client.linksOrReport() else { return nil }
    return KarnakLinkContext(
      links: links, actions: bridge.hostActions, report: { [weak client] in client?.report($0) })
  }

  /// A host for hooks that are not a view's: the coordinator's.
  func update(client: KarnakSwiftClient, callbacks: KarnakHostCallbacks) {
    update(opener: client, callbacks: callbacks)
  }
}

/// Reads the host a view sits in and hands it to `content`, so a modifier of the `KarnakNavigation`
/// product can use the hooks of the enclosing `.karnakHost`. Apply it inside `.karnakHost`.
package struct KarnakLinkHostReader<Content: View>: View {
  @Environment(\.karnakOpener) private var opener
  @Environment(\.karnakHostCallbacks) private var callbacks
  @StateObject private var host = KarnakLinkHost()
  private let content: (KarnakLinkHost) -> Content

  package init(@ViewBuilder content: @escaping (KarnakLinkHost) -> Content) {
    self.content = content
  }

  package var body: some View {
    // The host keeps the latest hooks (no published state changes), like the screens do. A
    // result builder allows a declaration here, not a bare call.
    // swiftlint:disable:next redundant_discardable_let
    let _ = host.update(opener: opener, callbacks: callbacks)
    content(host)
  }
}

extension KarnakSwiftClient {
  /// The Kotlin links, or nil, logged, when the client has no navigation module.
  @MainActor
  func linksOrReport() -> KarnakLinks? {
    guard let flowModule else {
      report(
        "Karnak: handleLink needs the navigation module: add KarnakFlows() (KarnakNavigation) to "
          + "KarnakConfiguration.modules.")
      return nil
    }
    // The module attaches to the engine when the client builds its graph.
    _ = navigator
    guard let links = flowModule.linksOrNull() else {
      report(
        "Karnak: handleLink could not start: the navigation module is not attached to a client.")
      return nil
    }
    return links
  }

  /// Performs `request` on the stack native code opens screens on, or logs that there is none.
  @MainActor
  func performOnActiveStack(_ request: KarnakNavigation) {
    guard let active = stacks.active else {
      return report(
        "Karnak: a link could not open its screen: no .karnakDestinations() or "
          + "KarnakNavigationCoordinator is on screen, and the host has no onNavigation hook.")
    }
    active.perform(request)
  }
}
