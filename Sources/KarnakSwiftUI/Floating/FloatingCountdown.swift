import Foundation

/// How long a transient view has left (ADR 0038, D7): a pause keeps what is left, and it runs again from there. The
/// engine never ticks; the layer asks this when its timer starts and reports `Timeout` when the time is up.
@MainActor
final class FloatingCountdown {
  /// What is left.
  private(set) var left: Duration
  private var startedAt: ContinuousClock.Instant?

  init(milliseconds: Int) { left = .milliseconds(milliseconds) }

  /// The time is running now.
  func start(now: ContinuousClock.Instant = .now) { startedAt = now }

  /// The time stopped, by a pause or because the view went away: what ran is taken off.
  func pause(now: ContinuousClock.Instant = .now) {
    guard let startedAt else { return }
    left = max(.zero, left - (now - startedAt))
    self.startedAt = nil
  }
}

/// Whether a view's timer runs now (ADR 0038, D7 and D10): a view with no duration is sticky, and so is one with
/// controls while a screen reader runs; a press, or a dialog the SDK shows over the screen, pauses it.
struct FloatingTimerRule: Equatable {
  let hasDuration: Bool
  let interactive: Bool
  let screenReaderRunning: Bool
  let pressed: Bool
  let coveredByDialog: Bool

  /// Whether the timer runs.
  var runs: Bool {
    hasDuration && !(interactive && screenReaderRunning) && !pressed && !coveredByDialog
  }
}
