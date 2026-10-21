import KarnakCore
import SwiftUI

extension EnvironmentValues {
  /// The area of the window a node must be inside to count as visible, in global coordinates: the
  /// window clipped by the scroll views around the screen (``ViewportProbe``). Nil outside a screen.
  @Entry var karnakViewport: CGRect?
}

/// The share of a node that must be visible for its `actions.appear`
/// (`docs/protocol.md`, Action lists).
let appearThreshold: CGFloat = 0.5

extension CGRect {
  /// Whether at least ``appearThreshold`` of this frame's area is inside `viewport`. A frame
  /// with no area counts as visible when it lies inside the viewport.
  func isMostlyVisible(in viewport: CGRect) -> Bool {
    let shown = intersection(viewport)
    if shown.isNull { return false }
    let area = width * height
    return area <= 0 ? true : (shown.width * shown.height) / area >= appearThreshold
  }
}

/// Sends `appear(handle)` each time at least half of a node's frame is inside the viewport.
/// The engine runs the actions once per node key, so a node that leaves and returns, or a lazy
/// item that is recycled, sends it again and runs nothing twice.
struct NodeAppear: ViewModifier {
  /// The node's `actions.appear` handle; nil when it has none.
  let handle: ActionHandle?

  func body(content: Content) -> some View {
    if let handle {
      content.modifier(AppearWatcher(handle: handle))
    } else {
      content
    }
  }
}

/// The part of ``NodeAppear`` that reads the viewport, so the many nodes without `actions.appear`
/// don't depend on it and don't update while the screen scrolls.
private struct AppearWatcher: ViewModifier {
  let handle: ActionHandle
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakViewport) private var viewport
  @State private var frame: CGRect = .zero

  private var isVisible: Bool {
    guard let viewport, frame != .zero else { return false }
    return frame.isMostlyVisible(in: viewport)
  }

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .global)
      } action: {
        frame = $0
      }
      .task(id: isVisible) { if isVisible { actions.appear(handle) } }
  }
}
