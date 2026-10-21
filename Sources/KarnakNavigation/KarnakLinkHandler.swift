import Foundation
import KarnakCore
import KarnakSwiftUI
import SwiftUI

/// Opens the links of the app (`docs/links.md`; ADR 0017, D7): resolves a URI against the link
/// table on the device, so a link works online and offline and on a cold start, and opens what it
/// matches through the hooks of the enclosing ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``,
/// the way the same action from a screen would.
///
/// Get it from the environment, below ``SwiftUI/View/karnakLinks()`` (or
/// ``SwiftUI/View/karnakOnOpenURL(onNotKarnak:onRejected:)``, which also calls it from
/// `.onOpenURL`):
///
/// ```swift
/// @Environment(\.karnakLinkHandler) private var links
///
/// func open(_ url: URL) async {
///   switch await links?(url) {
///   case .opened, nil: break
///   case .notKarnak: myRouter.open(url)         // not one of ours: your own router
///   case .rejected: break                     // ours but unsafe or malformed: neither open nor pass on
///   }
/// }
/// ```
///
/// A screen is pushed on the stack of the `.karnakDestinations()` that appeared last, a flow joins
/// that stack, a native route goes to `onNavigate` (checked against the route manifest) and a static URL to
/// `onOpenUrl`, which stays your policy point. Nothing but the open is dispatched, and a link's
/// params reach the target as typed data only. The client needs the navigation module
/// (``KarnakFlows``); without it every call is logged and answers ``KarnakLinkResult/notKarnak``.
@MainActor
public struct KarnakLinkHandler {
  private let host: KarnakLinkHost

  init(_ host: KarnakLinkHost) {
    self.host = host
  }

  /// Resolves `url` and opens what it matches. Waits for the first table at most 1.5 s, and only
  /// when the app bundled none and none was fetched yet. Never throws.
  public func callAsFunction(_ url: URL) async -> KarnakLinkResult {
    await callAsFunction(url.absoluteString)
  }

  /// Resolves the URI `uri` (a path, a URL or a custom scheme link) and opens what it matches.
  public func callAsFunction(_ uri: String) async -> KarnakLinkResult {
    guard let context = host.context else { return .notKarnak }
    return await KarnakLinkHandler.handle(uri, in: context)
  }

  static func handle(_ uri: String, in context: KarnakLinkContext) async -> KarnakLinkResult {
    // The engine takes the hooks and calls them on the thread it resumes on; the bridge hops to
    // the main thread for them.
    nonisolated(unsafe) let actions = context.actions
    nonisolated(unsafe) let links = context.links
    do {
      return KarnakLinkResult(try await links.handleLink(uri: uri, host: actions))
    } catch {
      // Only a cancelled task gets here: nothing was opened.
      context.report("Karnak: handleLink was cancelled before it opened the link.")
      return .notKarnak
    }
  }
}

extension EnvironmentValues {
  /// The link handler ``SwiftUI/View/karnakLinks()`` provides; nil outside it.
  @Entry public var karnakLinkHandler: KarnakLinkHandler?
}

extension View {
  /// Gives the views below the link handler (`@Environment(\.karnakLinkHandler)`), bound to the
  /// hooks of the enclosing `.karnakHost`. Apply it inside `.karnakHost`, on the content that has
  /// `.karnakDestinations()`, or on any view that calls the handler, such as the one that handles
  /// a push notification's tap.
  public func karnakLinks() -> some View {
    KarnakLinkHostReader { host in
      environment(\.karnakLinkHandler, KarnakLinkHandler(host))
    }
  }

  /// Opens the links the system gives the app: `.onOpenURL` of a custom scheme (`zest://dishes/ramen`)
  /// and of a universal link, through ``KarnakLinkHandler``. Apply it once, inside `.karnakHost`:
  ///
  /// ```swift
  /// ContentView()
  ///   .karnakOnOpenURL(onNotKarnak: { url in router.open(url) })
  ///   .karnakHost(karnak)
  /// ```
  ///
  /// - Parameters:
  ///   - onNotKarnak: Called, on the main thread, with a URL the link table does not own: your own
  ///     router opens it.
  ///   - onRejected: Called with a URL that is ours but unsafe or malformed, with the reason and
  ///     the name of the param (never its value). It is neither opened nor passed on; use it to
  ///     tell the user or to log.
  public func karnakOnOpenURL(
    onNotKarnak: ((_ url: URL) -> Void)? = nil,
    onRejected: ((_ url: URL, _ reason: String, _ param: String?) -> Void)? = nil
  ) -> some View {
    KarnakLinkHostReader { host in
      let handler = KarnakLinkHandler(host)
      onOpenURL { url in
        Task { @MainActor in
          switch await handler(url) {
          case .opened: break
          case .notKarnak: onNotKarnak?(url)
          case .rejected(let reason, let param): onRejected?(url, reason, param)
          }
        }
      }
      .environment(\.karnakLinkHandler, handler)
    }
  }
}

#if canImport(UIKit)
  import UIKit

  extension KarnakNavigationCoordinator {
    /// Resolves `url` and opens what it matches on this coordinator's navigation controller, for
    /// UIKit apps: call it from `scene(_:openURLContexts:)` and
    /// `scene(_:continue:)` (a universal link is `userActivity.webpageURL`). The coordinator's
    /// hooks open the targets, with its `perform` as the router. Answers
    /// ``KarnakLinkResult/notKarnak`` and logs when the coordinator was made without a client.
    public func handleLink(_ url: URL) async -> KarnakLinkResult {
      guard let context = linkContext() else { return .notKarnak }
      return await KarnakLinkHandler.handle(url.absoluteString, in: context)
    }
  }
#endif
