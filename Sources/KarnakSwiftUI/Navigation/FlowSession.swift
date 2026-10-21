import Foundation
import KarnakCore

/// A flow the app placed with ``KarnakFlow``, as the views use it, so tests drive the views with a
/// fake instead of a server.
@MainActor
protocol FlowSession: AnyObject {
  /// The flow's contained stack: empty while the flow loads and again once it ended.
  var stack: any StackSession { get }
  /// The container is gone: a flow that runs is cancelled and a flow that loads is dropped.
  func close()
}

/// What ``KarnakFlow`` asks of the client: start `flowId` with `params` and hear how it ended.
struct FlowRequest {
  let flowId: String
  let params: [String: Any]
  /// Called once, on the main thread, with the outcome of the flow's `finish` step or
  /// `cancelled`.
  let receiver: (_ outcome: String, _ result: [String: Any]) -> Void
}

/// A Kotlin ``RootFlow`` as a ``FlowSession``.
@MainActor
final class ControllerFlow: FlowSession {
  // Set once by a nonisolated initializer; the module's types are safe to hold from any thread.
  nonisolated(unsafe) private let flow: RootFlow
  let stack: any StackSession

  init(_ flow: RootFlow, session: @escaping (ScreenController) -> any ScreenSession) {
    self.flow = flow
    stack = ControllerStack(flow.stack, session: session)
  }

  func close() {
    flow.close()
  }
}
