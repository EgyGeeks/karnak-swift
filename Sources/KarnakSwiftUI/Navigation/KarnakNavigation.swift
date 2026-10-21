import Foundation
import KarnakCore

/// How an `open_screen` joins the navigation (`docs/protocol.md`, Presentation).
public enum KarnakPresentation: String, Sendable {
  /// Adds the screen on top of the stack.
  case push
  /// Swaps the screen it came from for the new one.
  case replace
  /// Makes the new screen the only entry above the stack's root.
  case reset
  /// A full-screen overlay with a stack of its own.
  case modal
  /// A bottom sheet with a stack of its own.
  case sheet
}

/// What a ``KarnakNavigation/open(entryId:target:params:presentation:)`` shows.
public enum KarnakNavigationTarget: Equatable, Sendable {
  /// A Karnak screen, by id.
  case screen(String)
  /// A native route of the app's route manifest (`karnak.routes.json`), shown by native code: the
  /// `route` step of a flow (`docs/integration.md`, Flows on iOS). Draw the screen the app has
  /// for `id` and give it `handle`, which ends the step. `.karnakDestinations()` and
  /// ``KarnakNavigationCoordinator`` do it for the routes you register with
  /// ``SwiftUI/View/karnakRoute(_:content:)`` and ``KarnakNavigationCoordinator/routes``.
  case route(String, handle: KarnakFlowHandle?)
}

/// What the SDK asks the host's navigation to do (`docs/integration.md`, Navigation): the
/// request ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``
/// hands to `onNavigation`. Perform it on the stack you own, and report every entry that stack
/// drops with ``KarnakSwiftNavigator/entryRemoved(_:)``.
public enum KarnakNavigation {
  /// Shows `target` as the entry `entryId`: open a screen with `KarnakScreen(_:params:entryId:)` or
  /// `KarnakViewController(client:screenId:params:entryId:)`, which pass the id on, and a native
  /// route with your own view. A host with no overlay may open ``KarnakPresentation/modal`` and
  /// ``KarnakPresentation/sheet`` as a push.
  case open(
    entryId: String, target: KarnakNavigationTarget, params: [String: Any],
    presentation: KarnakPresentation)
  /// Pops. At most one of the three is set; none pops one entry. `screen` pops down to the nearest
  /// entry showing that screen id and keeps it, `root` pops to the stack's root and `before` is
  /// an entry id: pop that entry and every entry above it.
  case back(screen: String?, root: Bool, before: String?)
}

extension KarnakNavigation {
  /// The request the engine made, as the Swift type; nil for a kind this SDK doesn't know.
  init?(_ request: any KarnakCore.KarnakNavigation) {
    switch request {
    case let open as KarnakNavigationOpen:
      guard let target = KarnakNavigationTarget(open.target, handle: open.handle) else {
        return nil
      }
      self = .open(
        entryId: open.entryId, target: target, params: open.params,
        presentation: KarnakPresentation(open.presentation))
    case let back as KarnakNavigationBack:
      self = .back(screen: back.to, root: back.root, before: back.before)
    default:
      return nil
    }
  }
}

extension KarnakNavigationTarget {
  /// The target the engine asked for, with the flow handle of the request that carries it.
  init?(_ target: any KarnakCore.KarnakNavigationTarget, handle: EntryHandle?) {
    switch target {
    case let screen as KarnakNavigationTargetScreen:
      self = .screen(screen.screenId)
    case let route as KarnakNavigationTargetRoute:
      self = .route(route.routeId, handle: handle.map(KarnakFlowHandle.init))
    default:
      return nil
    }
  }
}

extension KarnakPresentation {
  init(_ presentation: Presentation) {
    switch presentation {
    case .replace: self = .replace
    case .reset: self = .reset
    case .modal: self = .modal
    case .sheet: self = .sheet
    default: self = .push
    }
  }
}
