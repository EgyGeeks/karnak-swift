import KarnakCore
import SwiftUI

/// An anchored view (ADR 0038, D5): placed next to its anchor's bounds on its side and alignment, flipped to the other
/// side when it doesn't fit and shifted to stay inside the screen. Its anchor's bounds come from the layer's overlay
/// preference, so it follows scrolling in the layout phase and nothing animates the follow. When the anchor is gone, or
/// scrolled fully out of the screen, the view ends with `AnchorLost`, which only the renderer sees.
struct FloatingAnchoredView: View {
  let view: ResolvedFloating
  let anchored: ResolvedFloatingPlacementAnchored
  /// The anchor's bounds in the layer's coordinates; nil when no marked node of that key is drawn.
  let anchor: CGRect?
  let bounds: CGRect
  let host: FloatingHost

  @State private var size: CGSize?

  /// How long an anchor may be missing or out of sight before the view ends: a lazy row is built a moment after the
  /// tap that showed its popover.
  static let graceMillis = 200

  private var isLost: Bool {
    guard let anchor else { return true }
    return !anchor.intersects(bounds)
  }

  var body: some View {
    let placed = placement
    ZStack(alignment: .topLeading) {
      if view.behavior.tapOutside && (view.isModal || view.holdsAction) {
        // A view that took focus consumes the outside tap, as a focusable popup does.
        Color.clear.contentShape(Rectangle()).onTapGesture { host.dismiss(view.key, .tapoutside) }
      }
      FloatingEntryView(view: view, host: host)
        .fixedSize(horizontal: false, vertical: true)
        // Measured inside the screen-wide cap, which takes the whole width it is offered: the placement needs the
        // view's own size, or it shifts every narrower view to the screen's start.
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: {
          size = $0
        }
        .frame(maxWidth: bounds.width, alignment: .topLeading)
        .offset(x: placed?.frame.minX ?? 0, y: placed?.frame.minY ?? 0)
        .opacity(placed == nil ? 0 : 1)
    }
    .task(id: isLost) {
      guard isLost else { return }
      try? await Task.sleep(for: .milliseconds(Self.graceMillis))
      guard !Task.isCancelled else { return }
      host.dismiss(view.key, .anchorlost)
    }
  }

  private var placement: (frame: CGRect, side: FloatingGeometry.Side)? {
    guard let anchor, let size else { return nil }
    return FloatingGeometry.anchoredFrame(
      anchor: anchor, size: size, bounds: bounds,
      placement: .init(
        side: anchored.side.geometry, align: anchored.align.alongAnchor,
        gap: points(dp: anchored.gap)))
  }
}
