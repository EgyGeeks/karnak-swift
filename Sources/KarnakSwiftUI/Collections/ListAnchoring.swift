import SwiftUI

/// Keeps the row a user reads where it is when the rows of a lazy list change above it (ADR 0015, D7): the list is
/// its own scroll view, so it has its own ``RowAnchors`` and finds that scroll view with a ``ScrollProbe``.
///
/// Its rows report their frames to ``anchors``; when the keys of the rows change, the topmost visible row is chosen
/// before the new rows are laid out, and its move afterwards moves the scroll by the same distance, as the
/// screen's ``ContentGate`` does for the host's scroll view.
@MainActor
final class ListAnchoring {
  /// Where the rows of the list report their frames.
  let anchors = RowAnchors()
  private var keys: [String] = []

  /// The list's scroll view, found by its probe; nil while there is none.
  func attach(_ context: ScrollContext?) {
    anchors.scroll = context
  }

  /// The keys of the rows the list is about to draw. A change of the rows' structure remembers the row at the top
  /// of what shows, so its move is followed; the first rows, and a change that keeps the keys, remember nothing.
  func rowsChanged(to newKeys: [String]) {
    defer { keys = newKeys }
    guard !keys.isEmpty, keys != newKeys, let scroll = anchors.scroll else { return }
    anchors.capture(in: scroll.visibleRect)
    anchors.prune(toKeys: Set(newKeys))
  }
}
