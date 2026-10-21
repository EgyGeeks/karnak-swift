import SwiftUI

/// Keeps the row the user is reading where it is when rows are inserted or removed above it
/// (ADR 0015, D7: "collection changes apply live, with the scroll anchored to the item key").
///
/// Row roots report their frames here as they lay out. Before a structural tree is shown,
/// ``capture(in:)`` picks the topmost visible row; when that row reports a new frame after the
/// update, the scroll view moves by the difference, so the row stays at the same place on screen.
@MainActor
final class RowAnchors {
  /// The row chosen before an update and where it was, in window coordinates.
  private struct Captured {
    let key: String
    let top: CGFloat
  }

  /// How long a capture waits for its row to move before it is dropped: layout follows the tree
  /// at once, and a later move is the user's scrolling.
  private static let captureLife: Duration = .milliseconds(300)

  private var frames: [String: CGRect] = [:]
  private var captured: Captured?
  private var captures = 0
  /// The scroll view around the screen, set by its ``ScrollProbe``.
  weak var scroll: ScrollContext?

  /// A row root's frame in window coordinates, from its layout.
  func record(_ key: String, frame: CGRect) {
    frames[key] = frame
    guard let captured, captured.key == key, !(scroll?.isGestureActive ?? false) else { return }
    self.captured = nil
    if let delta = Self.shift(from: captured.top, to: frame.minY) { scroll?.shift(by: delta) }
  }

  /// Keeps only the frames of the rows of the tree just shown: rows that left it are not anchors.
  func prune(toKeys keys: Set<String>) {
    frames = frames.filter { keys.contains($0.key) }
  }

  /// Chooses the row to hold in place: the topmost one that shows in `viewport`. Nothing is held
  /// when no row shows, as the screen has no rows or they are scrolled out.
  func capture(in viewport: CGRect) {
    captured = Self.anchor(frames, in: viewport).map { Captured(key: $0.key, top: $0.value.minY) }
    captures += 1
    guard captured != nil else { return }
    let current = captures
    Task { [weak self] in
      try? await Task.sleep(for: Self.captureLife)
      // A capture the update never moved is dropped, so a later layout does not shift the scroll.
      if self?.captures == current { self?.captured = nil }
    }
  }

  /// The topmost frame that shows in `viewport`.
  static func anchor(
    _ frames: [String: CGRect], in viewport: CGRect
  ) -> (key: String, value: CGRect)? {
    frames.filter { $0.value.maxY > viewport.minY && $0.value.minY < viewport.maxY }
      .min { ($0.value.minY, $0.key) < ($1.value.minY, $1.key) }
      .map { (key: $0.key, value: $0.value) }
  }

  /// How far to move the scroll view when the anchor row went from `top` to `newTop`; nil for a
  /// move too small to see.
  static func shift(from top: CGFloat, to newTop: CGFloat) -> CGFloat? {
    let delta = newTop - top
    return abs(delta) > 0.5 ? delta : nil
  }
}

extension EnvironmentValues {
  /// The anchors of the screen being drawn; nil outside a screen view.
  @Entry var karnakRowAnchors: RowAnchors?
}

/// Reports a row root's frame to the screen's ``RowAnchors``.
struct RowAnchorModifier: ViewModifier {
  let key: String
  @Environment(\.karnakRowAnchors) private var anchors

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        anchors?.record(key, frame: $0)
      }
  }
}
