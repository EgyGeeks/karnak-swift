import KarnakCore
import SwiftUI

/// The rule of `layout.onNear` (`docs/renderer-contract.md`, Near the viewport): a node is near when its frame
/// overlaps the viewport grown by the viewport's own height above and below, and overlaps it horizontally, with no
/// horizontal margin. So a section one screen below the fold is near while the person reads the screen above it, and
/// a page of a pager off to the side is not.
enum NearArea {
  /// Whether `frame` is near `viewport`, both in the same coordinates. A viewport with no area shows nothing, so
  /// nothing is near it; a frame with no area counts when it lies inside the grown viewport, edges included. In a
  /// pager only the part of `frame` inside the pager's `clip` counts (``EnvironmentValues/karnakNearClip``), and
  /// none when they don't overlap by an area: a page laid out beside the one shown, or below a vertical pager, is not
  /// near (ADR 0040, D7). Global frames run left to right, so `rightToLeft` says which edge of the clip a page starts
  /// at.
  static func isNear(
    frame: CGRect, viewport: CGRect, clip: CGRect? = nil, rightToLeft: Bool = false
  ) -> Bool {
    guard viewport.width > 0, viewport.height > 0 else { return false }
    // A frame with no area lies inside the clip once it counts, so it is its own seen part.
    let hasArea = frame.width > 0 && frame.height > 0
    let seen = hasArea ? (clip.map { frame.intersection($0) } ?? frame) : frame
    if let clip, !isInside(frame, clip: clip, rightToLeft: rightToLeft) { return false }
    let grown = viewport.insetBy(dx: 0, dy: -viewport.height)
    return overlaps(seen.minX, seen.maxX, grown.minX, grown.maxX)
      && overlaps(seen.minY, seen.maxY, grown.minY, grown.maxY)
  }

  /// Whether `frame` is some of `clip`: it overlaps along each axis it has a length on, and lies in it on the others,
  /// from the clip's start edge up to, not on, its end edge in reading order. The shown page and the next one share
  /// that edge when they have no spacing, so a placeholder of no size at the start of the next page is not near.
  private static func isInside(_ frame: CGRect, clip: CGRect, rightToLeft: Bool) -> Bool {
    guard !clip.isNull else { return false }
    let across: Bool
    if frame.width > 0 {
      across = frame.minX < clip.maxX && frame.maxX > clip.minX
    } else if rightToLeft {
      across = frame.minX > clip.minX && frame.minX <= clip.maxX
    } else {
      across = frame.minX >= clip.minX && frame.minX < clip.maxX
    }
    let along =
      frame.height > 0
      ? frame.minY < clip.maxY && frame.maxY > clip.minY
      : frame.minY >= clip.minY && frame.minY < clip.maxY
    return across && along
  }

  /// Whether the span from `lower` to `upper` overlaps the one from `start` to `end`: by a positive length, or, for a
  /// span of no length, by lying inside it. Spans that only touch don't overlap, so the next page of a pager, whose
  /// edge is the viewport's, isn't near.
  private static func overlaps(
    _ lower: CGFloat, _ upper: CGFloat, _ start: CGFloat, _ end: CGFloat
  ) -> Bool {
    lower == upper ? lower >= start && lower <= end : lower < end && upper > start
  }
}

extension EnvironmentValues {
  /// The area, in global coordinates, of the pager a node is in: only the part of the node inside it can be near
  /// (``NearArea``). `nil` outside a pager; `.null` while the pager is not measured, so nothing in it is near yet.
  @Entry var karnakNearClip: CGRect?
}

/// Sends `near(handle)` once a node whose `layout.onNear` is set comes near the viewport (``NearArea``), while the
/// screen is not covered. The engine sets the handle on the root of a `data` boundary's `loading` slot while one of
/// its `start: "visible"` sources waits, and ignores a report it already acted on.
struct NodeNear: ViewModifier {
  /// The node's `layout.onNear` handle; nil when it has none.
  let handle: ActionHandle?

  func body(content: Content) -> some View {
    if let handle {
      content.modifier(NearWatcher(handle: handle))
    } else {
      content
    }
  }
}

/// The part of ``NodeNear`` that reads the viewport, so the many nodes without `layout.onNear` don't depend on it
/// and don't update while the screen scrolls. The viewport is the screen's (``karnakScreenViewport``), not the one a
/// list, pager or carousel around the node sets for `actions.appear`: a pager or carousel clears that one, which would
/// leave a section in it waiting for ever.
private struct NearWatcher: ViewModifier {
  let handle: ActionHandle
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakScreenViewport) private var viewport
  @Environment(\.karnakCovered) private var covered
  @Environment(\.karnakNearClip) private var clip
  @Environment(\.layoutDirection) private var direction
  @State private var frame: CGRect = .zero
  /// The handle this view already sent: each handle is sent once while the view lives.
  @State private var sent: ActionHandle?

  private var isNear: Bool {
    guard !covered, let viewport, frame != .zero else { return false }
    return NearArea.isNear(
      frame: frame, viewport: viewport, clip: clip, rightToLeft: direction == .rightToLeft)
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        frame = $0
      }
      .onChange(of: isNear ? handle : nil, initial: true) { _, near in
        guard let near, near != sent else { return }
        sent = near
        actions.near(near)
      }
  }
}
