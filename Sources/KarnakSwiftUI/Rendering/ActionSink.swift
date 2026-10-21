import KarnakCore
import SwiftUI

/// Where clicks and appearances go: the root view's `onAction` and `onAppear`. Clickable nodes,
/// link runs and nodes with `actions.appear` read it from the environment, so no node view takes
/// it as a parameter.
final class ActionSink {
  /// The latest click handler; the root view replaces it on every update.
  var handler: (ActionHandle) -> Void

  /// The latest appearance handler; the root view replaces it on every update.
  var appearHandler: (ActionHandle) -> Void

  /// Creates a sink that sends clicks to `handler` and appearances to `appearHandler`; the
  /// defaults drop them.
  init(
    handler: @escaping (ActionHandle) -> Void = { _ in },
    appearHandler: @escaping (ActionHandle) -> Void = { _ in }
  ) {
    self.handler = handler
    self.appearHandler = appearHandler
  }

  /// Sends `click(handle)` for an activated node or link run.
  func click(_ handle: ActionHandle) {
    handler(handle)
  }

  /// Sends `appear(handle)` for a node that is at least half visible.
  func appear(_ handle: ActionHandle) {
    appearHandler(handle)
  }
}

extension EnvironmentValues {
  /// The sink for the clicks of the screen being drawn; outside a screen, clicks are dropped.
  @Entry var karnakActions = ActionSink()
}
