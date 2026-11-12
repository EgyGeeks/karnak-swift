import KarnakCore
import SwiftUI

/// Where clicks, appearances and near reports go: the root view's `onAction`, `onAppear` and `onNear`. Clickable
/// nodes, link runs and nodes with `actions.appear` or `layout.onNear` read it from the environment, so no node view
/// takes it as a parameter.
final class ActionSink {
  /// The latest click handler; the root view replaces it on every update.
  var handler: (ActionHandle) -> Void

  /// The latest appearance handler; the root view replaces it on every update.
  var appearHandler: (ActionHandle) -> Void

  /// The latest near handler; the root view replaces it on every update.
  var nearHandler: (ActionHandle) -> Void

  /// The latest event handler; the root view replaces it on every update.
  var eventHandler: (ActionHandle, KarnakValue, Bool, Int64) -> Void

  /// The generation of the tree being drawn, which an event says it was raised on.
  var generation: Int64 = 0

  /// Creates a sink that sends clicks to `handler`, appearances to `appearHandler` and near reports to
  /// `nearHandler`; the defaults drop them.
  init(
    handler: @escaping (ActionHandle) -> Void = { _ in },
    appearHandler: @escaping (ActionHandle) -> Void = { _ in },
    nearHandler: @escaping (ActionHandle) -> Void = { _ in },
    eventHandler: @escaping (ActionHandle, KarnakValue, Bool, Int64) -> Void = { _, _, _, _ in }
  ) {
    self.eventHandler = eventHandler
    self.handler = handler
    self.appearHandler = appearHandler
    self.nearHandler = nearHandler
  }

  /// Sends `click(handle)` for an activated node or link run.
  func click(_ handle: ActionHandle) {
    handler(handle)
  }

  /// Sends a node's settled event, such as a carousel's `pageChange`, with the `payload` its type declares
  /// (`docs/protocol.md`, Component events and node values) and whether a person caused it.
  func event(_ handle: ActionHandle, payload: KarnakValue, byUser: Bool) {
    eventHandler(handle, payload, byUser, generation)
  }

  /// Sends `appear(handle)` for a node that is at least half visible.
  func appear(_ handle: ActionHandle) {
    appearHandler(handle)
  }

  /// Sends `near(handle)` for a node whose `layout.onNear` is near the viewport (``NearArea``).
  func near(_ handle: ActionHandle) {
    nearHandler(handle)
  }
}

extension EnvironmentValues {
  /// The sink for the clicks of the screen being drawn; outside a screen, clicks are dropped.
  @Entry var karnakActions = ActionSink()
}
