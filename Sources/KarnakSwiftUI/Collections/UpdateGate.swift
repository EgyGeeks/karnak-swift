import KarnakCore

/// Decides when a new tree reaches the screen while the user is scrolling (ADR 0015, D7, kept by
/// ADR 0018, D8): a tree that keeps the structure applies at once, so bound scalars are live; a
/// tree that adds, removes or reorders nodes waits for the gesture to end. Only the newest waiting
/// tree is kept: it holds everything the older ones did.
struct UpdateGate {
  /// The tree that waits for the gesture to end, if any.
  private(set) var pending: ResolvedScreen?

  /// The tree to show now for `new`, or nil when it waits.
  /// - Parameters:
  ///   - new: The tree the engine just emitted.
  ///   - shown: The tree on screen; nil when none is, which never waits.
  ///   - gestureActive: Whether the user is scrolling.
  mutating func offer(
    _ new: ResolvedScreen, shown: ResolvedScreen?, gestureActive: Bool
  ) -> ResolvedScreen? {
    guard let shown, gestureActive, !TreeStructure.isSame(shown, new) else {
      pending = nil
      return new
    }
    pending = new
    return nil
  }

  /// The waiting tree, when the gesture ended: show it.
  mutating func release() -> ResolvedScreen? {
    defer { pending = nil }
    return pending
  }

  /// Forgets the waiting tree, as a load or a failure replaces what the screen shows.
  mutating func reset() {
    pending = nil
  }
}
