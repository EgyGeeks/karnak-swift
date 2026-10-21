import Foundation
import KarnakCore

/// The SDK's navigation bookkeeping, for hosts that implement `onNavigation` (`docs/integration.md`,
/// Navigation): get it from ``KarnakSwiftClient/navigator``. The default integrations
/// (`.karnakDestinations()`, ``KarnakNavigationCoordinator``) use it for you.
///
/// Every call is safe from any thread and never throws on a stale or unknown id.
public final class KarnakSwiftNavigator: @unchecked Sendable {
  private let navigator: KarnakNavigator
  private let converter: KarnakParamsConverter

  init(_ navigator: KarnakNavigator, converter: KarnakParamsConverter) {
    self.navigator = navigator
    self.converter = converter
  }

  /// The host's router dropped the entry `entryId`, however it did: system back, a swipe, its
  /// own pop. The entry's receiver (an `onFinish`, ``KarnakSwiftClient/open(_:params:)``) gets
  /// `cancelled` unless it already had its delivery. An unknown id, or one reported twice, does
  /// nothing.
  public func entryRemoved(_ entryId: String) {
    navigator.entryRemoved(entryId: entryId)
  }

  /// Opens `screenId` as the entry `entryId` of the host's stack (or as a screen of its own when
  /// nil), for the view that draws it.
  @MainActor
  func open(
    _ request: ScreenRequest, entry: ScreenEntry
  ) throws -> any ScreenSession {
    let receiver = entry.receiver.map { ClosureReceiver($0) }
    let controller = try navigator.open(
      screenId: request.screenId, paramValues: converter.convert(request.params),
      environment: request.environment, entryId: entry.id, receiver: receiver)
    return ControllerSession(controller)
  }
}

/// A Kotlin ``KarnakFinishReceiver`` that calls a closure, once.
final class ClosureReceiver: NSObject, KarnakFinishReceiver, @unchecked Sendable {
  private let deliver: (String, [String: Any]) -> Void

  init(_ deliver: @escaping (String, [String: Any]) -> Void) {
    self.deliver = deliver
  }

  /// Delivers on the main thread, where the screens and the host's callbacks live.
  func onFinish(outcome: String, result: [String: Any]) {
    if Thread.isMainThread {
      deliver(outcome, result)
    } else {
      nonisolated(unsafe) let result = result
      DispatchQueue.main.async { [deliver] in deliver(outcome, result) }
    }
  }
}
