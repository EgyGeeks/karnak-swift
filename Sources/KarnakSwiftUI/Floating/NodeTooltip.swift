import KarnakCore
import SwiftUI

/// The one tooltip a screen shows (`docs/renderer-contract.md`, Tooltips and cursors): the key of the node whose
/// tooltip is up. A node shows its own, which replaces any other, and hides only its own.
@MainActor @Observable
final class TooltipState {
  /// The key of the node whose tooltip shows; nil for none.
  private(set) var owner: String?

  func show(_ key: String) { owner = key }

  func hide(_ key: String) {
    if owner == key { owner = nil }
  }
}

extension EnvironmentValues {
  /// The screen's tooltips; nil outside a screen, where none shows.
  @Entry var karnakTooltips: TooltipState?
}

/// A tooltip that shows, with its node's bounds, for the screen's ``TooltipLayer``.
struct ShownTooltip {
  let tooltip: ResolvedTooltip
  let anchor: Anchor<CGRect>
}

/// Carries the shown tooltip up to the screen.
struct TooltipAnchorKey: PreferenceKey {
  static var defaultValue: ShownTooltip? { nil }

  static func reduce(value: inout ShownTooltip?, nextValue: () -> ShownTooltip?) {
    value = value ?? nextValue()
  }
}

/// How long a pointer rests on a node before its tooltip shows.
let tooltipHoverDelay: Duration = .milliseconds(500)

/// How long a tooltip a long press showed stays after the finger lifts.
let tooltipTouchLinger: Duration = .milliseconds(1500)

/// What shows and hides a node's tooltip: a pointer resting on it (iPadOS), keyboard focus on a button and a long press
/// show it, the pointer leaving and blur hide it, and one a long press showed hides after ``tooltipTouchLinger``. On
/// a node a long press is a gesture of its own, so it is never also the node's tap; a button's system tap fires when
/// the finger lifts whatever the press's length, so a long press on a button both shows its tooltip and clicks it. On
/// a node with a context menu (``longPressShows`` off) a long press opens the menu instead.
struct NodeTooltip: ViewModifier {
  let key: String
  let tooltip: ResolvedTooltip?
  /// Whether the node has keyboard focus; only a button tracks it.
  var focused = false
  /// Whether the node is a system button, whose tap the long press runs beside.
  var isButton = false
  /// Whether a long press shows the tooltip: not on a node with a context menu, which the long press opens.
  var longPressShows = true
  @Environment(\.karnakTooltips) private var tooltips
  @State private var timer: Task<Void, Never>?

  func body(content: Content) -> some View {
    if let tooltip, let tooltips {
      longPressing(content, tooltips)
        .onHover { inside in
          inside ? later(tooltipHoverDelay) { tooltips.show(key) } : hide(tooltips)
        }
        .onChange(of: focused) { _, now in now ? tooltips.show(key) : hide(tooltips) }
        .anchorPreference(key: TooltipAnchorKey.self, value: .bounds) { anchor in
          tooltips.owner == key ? ShownTooltip(tooltip: tooltip, anchor: anchor) : nil
        }
        .onDisappear { hide(tooltips) }
    } else {
      content
    }
  }

  /// A long press shows the tooltip; it lingers for ``tooltipTouchLinger`` from the lift.
  @ViewBuilder
  private func longPressing(_ content: Content, _ tooltips: TooltipState) -> some View {
    let linger = { later(tooltipTouchLinger) { tooltips.hide(key) } }
    if !longPressShows {
      content
    } else if isButton {
      content.simultaneousGesture(
        LongPressGesture()
          .onEnded { _ in tooltips.show(key) }
          .sequenced(before: DragGesture(minimumDistance: 0))
          .onEnded { _ in linger() })
    } else {
      content.onLongPressGesture {
        tooltips.show(key)
      } onPressingChanged: { pressing in
        if !pressing && tooltips.owner == key { linger() }
      }
    }
  }

  private func hide(_ tooltips: TooltipState) {
    timer?.cancel()
    tooltips.hide(key)
  }

  private func later(_ delay: Duration, _ action: @escaping @MainActor () -> Void) {
    timer?.cancel()
    timer = Task {
      try? await Task.sleep(for: delay)
      if !Task.isCancelled { action() }
    }
  }
}

/// The system's hover effect on iPadOS over a node a pointer can act on: one with an `onClick` or the `pointer`
/// cursor. iOS 17 has no pointer shapes, so the other cursors draw nothing.
struct NodeHover: ViewModifier {
  let isActive: Bool

  func body(content: Content) -> some View {
    if isActive { content.hoverEffect() } else { content }
  }
}
