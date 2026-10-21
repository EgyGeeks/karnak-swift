import Foundation
import KarnakCore

/// What to open: a screen id, the host's params as it wrote them and where it is drawn.
struct ScreenRequest {
  let screenId: String
  let params: [String: Any]
  let environment: ScreenEnvironment
  /// The host-stack entry the screen is, when it has one: its `back` and `finish` act on it.
  var entry: ScreenEntry?
}

/// A screen that is an entry of a stack, for the engine to tell `back` and `finish` apart from
/// the screens of the host's own.
struct ScreenEntry {
  let id: String
  /// Who hears how the entry ended, once; nil when nobody waits.
  var receiver: ((_ outcome: String, _ result: [String: Any]) -> Void)?

  init(id: String, receiver: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil) {
    self.id = id
    self.receiver = receiver
  }
}

/// One open screen as the views use it: the part of the engine's `ScreenController` they need,
/// so tests drive the views with a fake instead of a server.
@MainActor
protocol ScreenSession: AnyObject {
  /// Calls `listener` with the current state now and with every new one, on the main thread,
  /// until the returned function is called.
  func observe(_ listener: @escaping (ScreenState) -> Void) -> () -> Void
  /// Loads the screen again, as a retry does.
  func refresh()
  /// Resolves the current content again for `environment`.
  func setEnvironment(_ environment: ScreenEnvironment)
  /// Reports that the node or link run with `handle` was activated.
  func click(_ handle: ActionHandle)
  /// Reports that the node whose `actions.appear` is `handle` is at least half visible.
  func appear(_ handle: ActionHandle)
  /// Sets the hooks that answer the screen's host actions.
  func setHostActions(_ actions: HostActions)
  /// Calls `listener` with each of the instance's effects, on the main thread, until the
  /// returned function is called. Effects are one-shot and wait while nothing listens.
  func observeEffects(_ listener: @escaping (EffectRequest) -> Void) -> () -> Void
  /// A button of the dialog `effectId` was activated.
  func dialogButton(_ effectId: String, _ choice: DialogChoice)
  /// The toast, dialog or sheet `effectId` is off screen for any reason: sent once, after a
  /// dialog's ``dialogButton(_:_:)``.
  func effectDismissed(_ effectId: String)
  /// Tells the instance whether its screen is in the foreground: with `false` it stops its data
  /// streams and keeps their values, with `true` they start again (`ScreenController.setForeground`).
  func setForeground(_ foreground: Bool)
  /// Stops the instance's work.
  func close()
  /// The id of the screen the instance shows, when it is one; it picks the instance's loading and
  /// error views.
  var screenId: String? { get }
}

/// Opens screens: the client, or a fake in tests.
@MainActor
protocol ScreenOpening: AnyObject {
  /// Starts loading the requested screen. Throws for developer misuse in debug, such as params
  /// that aren't JSON values.
  func openScreen(_ request: ScreenRequest) throws -> ScreenSession
  /// Logs a diagnostic where the host configured its logs.
  func report(_ message: String)
  /// The host dropped the entry `id`: its receiver hears `cancelled` unless it had its delivery.
  func entryRemoved(_ id: String)
  /// The host stacks screens of this opener are on.
  var stackRegistry: HostStackRegistry { get }
  /// Places a flow in a container the app draws (``KarnakFlow``). Nil, logged, when the client has
  /// no flows module.
  func openFlow(_ request: FlowRequest) throws -> (any FlowSession)?
  /// Whether the entry `entryId` belongs to a flow that is not running: the host restored it
  /// with its back stack after process death, and the flow instance died (ADR 0017, D13).
  func isOrphanedFlowEntry(_ entryId: String) -> Bool
}

extension ScreenOpening {
  func openFlow(_ request: FlowRequest) throws -> (any FlowSession)? { nil }
  func isOrphanedFlowEntry(_ entryId: String) -> Bool { false }
}

/// An overlay's stack as the views use it: the entries to draw, and the report of a dismissal.
@MainActor
protocol StackSession: AnyObject {
  /// Calls `listener` with the entries, bottom first, now and with every change, on the main
  /// thread, until the returned function is called. The list is empty once the overlay closed.
  func observe(_ listener: @escaping ([StackEntrySession]) -> Void) -> () -> Void
  /// The user dismissed the entry `id` (back, a swipe down): it and the entries above it end.
  func entryRemoved(_ id: String)
}

/// One entry of a contained stack: its id and what it shows, either the screen instance the
/// engine opened for it or a native route a flow runs (drawn by the app).
struct StackEntrySession {
  let id: String
  /// The screen instance of a Karnak entry; nil for a native route.
  let screen: (any ScreenSession)?
  /// The native route the entry shows, with the handle that ends it; nil for a screen.
  let route: KarnakRouteTarget?

  init(id: String, screen: any ScreenSession) {
    self.id = id
    self.screen = screen
    route = nil
  }

  init(id: String, route: KarnakRouteTarget) {
    self.id = id
    screen = nil
    self.route = route
  }
}

/// A `ContainedStack` as a ``StackSession``.
@MainActor
final class ControllerStack: StackSession {
  // Set once by a nonisolated initializer; the engine's types are safe to hold from any thread.
  nonisolated(unsafe) private let stack: ContainedStack
  nonisolated(unsafe) private let session: (ScreenController) -> any ScreenSession

  nonisolated init(
    _ stack: ContainedStack, session: @escaping (ScreenController) -> any ScreenSession
  ) {
    self.stack = stack
    self.session = session
  }

  func observe(_ listener: @escaping ([StackEntrySession]) -> Void) -> () -> Void {
    let session = session
    let subscription = stack.observeEntries { entries in
      MainActor.assumeIsolated {
        listener(entries.map { entry in Self.session(entry, makeSession: session) })
      }
    }
    return { subscription.cancel() }
  }

  func entryRemoved(_ id: String) {
    stack.entryRemoved(entryId: id)
  }

  /// A route entry has no screen to follow (the engine's is inert); its native screen is the app's.
  private nonisolated static func session(
    _ entry: StackEntry, makeSession: (ScreenController) -> any ScreenSession
  ) -> StackEntrySession {
    guard let route = entry.route else {
      return StackEntrySession(id: entry.entryId, screen: makeSession(entry.screen))
    }
    let target = KarnakRouteTarget(
      id: route, params: entry.params,
      handle: entry.handle.map(KarnakFlowHandle.init))
    return StackEntrySession(id: entry.entryId, route: target)
  }
}

/// A `ScreenController` as a ``ScreenSession``.
@MainActor
final class ControllerSession: ScreenSession {
  private let controller: ScreenController

  init(_ controller: ScreenController) {
    self.controller = controller
  }

  var screenId: String? { controller.screenId }

  func observe(_ listener: @escaping (ScreenState) -> Void) -> () -> Void {
    let subscription = ScreenObservationKt.observe(controller, listener: listener)
    return { subscription.cancel() }
  }

  func refresh() {
    controller.refresh()
  }

  func setEnvironment(_ environment: ScreenEnvironment) {
    controller.setEnvironment(environment: environment)
  }

  func click(_ handle: ActionHandle) {
    controller.click(handle: handle)
  }

  func appear(_ handle: ActionHandle) {
    controller.appear(handle: handle)
  }

  func setHostActions(_ actions: HostActions) {
    controller.setHostActions(actions: actions)
  }

  func observeEffects(_ listener: @escaping (EffectRequest) -> Void) -> () -> Void {
    let subscription = ScreenObservationKt.observeEffects(controller) { effect in
      if let request = EffectRequest(effect, session: { ControllerSession($0) }) {
        listener(request)
      }
    }
    return { subscription.cancel() }
  }

  func dialogButton(_ effectId: String, _ choice: DialogChoice) {
    controller.dialogButton(effectId: effectId, choice: choice)
  }

  func effectDismissed(_ effectId: String) {
    controller.effectDismissed(effectId: effectId)
  }

  func setForeground(_ foreground: Bool) {
    controller.setForeground(foreground: foreground)
  }

  func close() {
    controller.close()
  }
}
