import Foundation
import KarnakCore

/// What happened to a screen of the SDK's navigation: see ``KarnakScreenEvent``.
public enum KarnakScreenEventKind: String, Sendable {
  /// The screen became the top visible screen: it opened, or what covered it went away.
  case shown
  /// The screen's entry ended: it went back, was swiped away, finished, was replaced or its flow
  /// moved on.
  case closed
}

/// A screen the SDK navigated to became visible or went away, for the host's analytics
/// (`docs/integration.md`, Screen events). Ids only: no param, result or text ever travels in it,
/// because screen params can carry personal data.
///
/// It covers every screen that has an entry in the SDK's navigation: an `open_screen` on the
/// host's stack, in a `modal`, a `sheet` or a `detail` pane, the screens of a `show_sheet` and the
/// steps of a flow. A screen the host places itself, with no entry id (its start screen), is the
/// host's to report.
public struct KarnakScreenEvent: Equatable, Sendable {
  /// ``KarnakScreenEventKind/shown`` or ``KarnakScreenEventKind/closed``.
  public let kind: KarnakScreenEventKind
  /// The screen's id; for a native `route` step of a flow, the route's name.
  public let screenId: String
  /// How the screen joins the navigation: ``KarnakPresentation/push`` for the host's stack,
  /// whatever the request was, ``KarnakPresentation/modal``, ``KarnakPresentation/sheet`` or
  /// ``KarnakPresentation/detail``.
  public let presentation: KarnakPresentation
  /// The id of the entry the screen shows; nil for the child of a `show_sheet`. It pairs a shown
  /// with its closed.
  public let entryId: String?
  /// The id of the flow the screen is a step of, or nil.
  public let flow: String?
  /// The revision of that flow, or nil.
  public let flowRevision: String?
  /// The id of the flow step, or nil.
  public let step: String?
  /// For a shown: the id of the screen the user was on (the one reported shown before this one, or the one under it
  /// when that one has closed since), or nil for the first.
  public let previous: String?
  /// For a closed: the outcome the screen's own `finish` delivered; nil when it closed without
  /// finishing (back, a swipe, the host's router, a flow ending). A flow step its edge replaces closes with
  /// the outcome it ended with.
  public let outcome: String?
}

extension KarnakScreenEvent {
  init(_ event: KarnakCore.KarnakScreenEvent) {
    self.init(
      kind: event.kind == .closed ? .closed : .shown, screenId: event.screenId,
      presentation: KarnakPresentation(event.presentation), entryId: event.entryId,
      flow: event.flow, flowRevision: event.flowRevision, step: event.step,
      previous: event.previous, outcome: event.outcome)
  }
}

/// A Kotlin ``KarnakScreenObserver`` that calls a closure on the main thread, where the host's
/// callbacks live, in the order the events happened.
final class ClosureScreenObserver: NSObject, KarnakCore.KarnakScreenObserver, @unchecked Sendable {
  private let deliver: @MainActor (KarnakScreenEvent) -> Void

  init(_ deliver: @escaping @MainActor (KarnakScreenEvent) -> Void) {
    self.deliver = deliver
  }

  func onScreen(event: KarnakCore.KarnakScreenEvent) {
    let seen = KarnakScreenEvent(event)
    if Thread.isMainThread {
      MainActor.assumeIsolated { deliver(seen) }
    } else {
      DispatchQueue.main.async { [deliver] in
        MainActor.assumeIsolated { deliver(seen) }
      }
    }
  }
}

extension KarnakSwiftNavigator {
  /// Hears every ``KarnakScreenEvent`` from now on, on the main thread, until the returned handle
  /// is cancelled or released. `.karnakHost(onScreen:)` does it for you.
  @MainActor
  public func observeScreens(
    _ onScreen: @escaping @MainActor (KarnakScreenEvent) -> Void
  ) -> KarnakScreenWatch {
    KarnakScreenWatch(observing(ClosureScreenObserver(onScreen)))
  }
}

/// The subscription ``KarnakSwiftNavigator/observeScreens(_:)`` made; it stops when cancelled or
/// released.
public final class KarnakScreenWatch: @unchecked Sendable {
  private let handle: any KotlinAutoCloseable

  init(_ handle: any KotlinAutoCloseable) {
    self.handle = handle
  }

  deinit { cancel() }

  /// Stops the events. Calling it again does nothing.
  public func cancel() {
    try? handle.close()
  }
}
