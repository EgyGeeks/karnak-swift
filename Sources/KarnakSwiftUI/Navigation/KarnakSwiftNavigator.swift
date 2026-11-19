import Foundation
import KarnakCore

/// The SDK's navigation bookkeeping, for hosts that implement `onNavigation` (`docs/integration.md`,
/// Navigation): get it from ``KarnakSwiftClient/navigator``. The default integrations
/// (`.karnakDestinations()`, `KarnakNavigationCoordinator`) use it for you.
///
/// Every call is safe from any thread and never throws on a stale or unknown id.
public final class KarnakSwiftNavigator: @unchecked Sendable {
  private let navigator: KarnakNavigator
  private let converter: KarnakParamsConverter
  /// The client's logger, for a request a helper of the SDK ignored.
  package let report: @Sendable (String) -> Void

  init(
    _ navigator: KarnakNavigator, converter: KarnakParamsConverter,
    report: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }
  ) {
    self.navigator = navigator
    self.converter = converter
    self.report = report
  }

  /// The host's router dropped the entry `entryId`, however it did: system back, a swipe, its
  /// own pop. The entry's receiver (an `onFinish`, `karnak.open(_:params:)` (`KarnakNavigation` product)) gets
  /// `cancelled` unless it already had its delivery. An unknown id, or one reported twice, does
  /// nothing.
  public func entryRemoved(_ entryId: String) {
    navigator.entryRemoved(entryId: entryId)
  }

  /// The Kotlin navigator's screen events for `observer`, on the thread that made them.
  func observing(_ observer: KarnakCore.KarnakScreenObserver) -> any KotlinAutoCloseable {
    navigator.observeScreens(dispatcher: nil, observer: observer)
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

  /// Reopens the screens of a saved detail pane as a new stack, or nil, logged, when there is none to reopen.
  func restoreDetail(_ screens: [SavedPaneScreen]) -> ContainedStack? {
    let saved = screens.map { SavedStackEntry(screenId: $0.screenId, params: $0.paramValues) }
    return navigator.restoreOverlay(presentation: .detail, saved: saved)
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
