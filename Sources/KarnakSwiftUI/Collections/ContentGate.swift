import Foundation
import KarnakCore

/// Between the engine's trees and the screen view: holds a structural change while the user
/// scrolls, and keeps the row they read in place when it is shown (ADR 0018, D8; ADR 0015, D7).
///
/// - A tree that keeps the structure applies at once: bound scalars are live.
/// - A tree that adds, removes or reorders nodes waits until the scroll gesture ends, then shows
///   the newest one. A hold ends after ``maxHold`` even if the finger stays down, so the screen
///   cannot go stale.
/// - A tree that changes the structure while the user is not scrolling applies at once, with the
///   topmost visible row anchored: ``RowAnchors`` moves the scroll view by what the rows above it
///   grew or shrank.
@MainActor
final class ContentGate {
  /// How long a structural change may wait for a gesture.
  static let maxHold: TimeInterval = 10
  private static let pollInterval: TimeInterval = 0.05

  /// The row anchors of the screen: its row roots report their frames here.
  let anchors = RowAnchors()
  /// The scroll view around the screen; nil when there is none.
  weak var scroll: ScrollContext? {
    didSet { anchors.scroll = scroll }
  }

  private var gate = UpdateGate()
  private var poll: Timer?
  private var heldSince: Date?
  /// Shows the waiting tree: the caller of the offer that made it wait.
  private var showWaiting: ((ResolvedScreen) -> Void)?
  private let now: () -> Date

  /// - Parameter now: The clock; tests replace it.
  init(now: @escaping () -> Date = Date.init) {
    self.now = now
  }

  /// Shows `screen` through `show` now, or when the gesture ends. `shown` is the tree on screen.
  func offer(
    _ screen: ResolvedScreen, shown: ResolvedScreen?, show: @escaping (ResolvedScreen) -> Void
  ) {
    let active = scroll?.isGestureActive ?? false
    guard let ready = gate.offer(screen, shown: shown, gestureActive: active) else {
      showWaiting = show
      holdUntilGestureEnds()
      return
    }
    stopPolling()
    present(ready, replacing: shown, show: show)
  }

  /// A load or failure replaced what the screen shows: drop what waited.
  func reset() {
    gate.reset()
    stopPolling()
  }

  private func present(
    _ screen: ResolvedScreen, replacing shown: ResolvedScreen?,
    show: (ResolvedScreen) -> Void
  ) {
    if let shown, !TreeStructure.isSame(shown, screen), let scroll {
      anchors.capture(in: scroll.visibleRect)
    }
    show(screen)
    anchors.prune(toKeys: TreeStructure.rowRootKeys(screen))
  }

  private func holdUntilGestureEnds() {
    if heldSince == nil { heldSince = now() }
    guard poll == nil else { return }
    let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.checkGesture() }
    }
    RunLoop.main.add(timer, forMode: .common)
    poll = timer
  }

  private func checkGesture() {
    let expired = heldSince.map { now().timeIntervalSince($0) >= Self.maxHold } ?? true
    guard expired || !(scroll?.isGestureActive ?? false) else { return }
    let show = showWaiting
    stopPolling()
    // A held tree always moved the structure, so the shown tree is not needed to tell.
    guard let waiting = gate.release(), let show else { return }
    if let scroll { anchors.capture(in: scroll.visibleRect) }
    show(waiting)
    anchors.prune(toKeys: TreeStructure.rowRootKeys(waiting))
  }

  private func stopPolling() {
    poll?.invalidate()
    poll = nil
    heldSince = nil
    showWaiting = nil
  }
}
