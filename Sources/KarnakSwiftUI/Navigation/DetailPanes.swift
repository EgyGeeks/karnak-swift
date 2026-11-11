import KarnakCore
import SwiftUI
import UIKit

/// Draws a screen with the detail pane it opened (`open_screen` with `presentation: "detail"`;
/// `docs/renderer-contract.md`, Detail panes). In a container of the `expanded` size class the
/// screen keeps a start pane ``DetailPaneMetrics/startWidth`` points wide and the pane's stack
/// takes the rest, with a divider between them; in a narrower container the pane covers the
/// screen, which stays open beneath it. The screen keeps its place in the view tree in both
/// drawings, so resizing changes neither its state nor the pane's stack.
struct DetailPanes<Content: View>: View {
  @ObservedObject var effects: EffectModel
  /// The environment of a container this many points wide on this device.
  let environment: (Double) -> ScreenEnvironment
  @ViewBuilder let content: () -> Content

  @Environment(\.karnakContainerWidth) private var forcedWidth
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var measuredWidth: CGFloat?

  var body: some View {
    let detail = effects.detail
    let width = forcedWidth ?? measuredWidth.map(Double.init) ?? 0
    let split = environment(width).sizeClass.wire == DetailPaneMetrics.splitClass
    DetailPaneLayout(split: split && detail != nil) {
      // Covered, the screen is still there for its state; a screen reader sees only the pane. The screen is a
      // container of its own, so `accessibilityHidden(false)` lands on that container: without one it lands on
      // every element of the screen, and shows the ones the screen hides (decorations, zero-size anchors).
      content().accessibilityElement(children: .contain).accessibilityHidden(
        detail != nil && !split)
      if let detail {
        if split { DetailDivider() }
        DetailPane(
          overlay: detail, split: split,
          environment: environment(split ? DetailPaneMetrics.detailWidth(of: width) : width),
          onClose: { effects.detailClosedByUser() }
        )
        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
      }
    }
    .animation(.easeInOut(duration: DetailPaneMetrics.transitionSeconds), value: detail?.id)
    .measuringContainerWidth($measuredWidth)
  }
}

/// The sizes of the two panes, the same on every platform.
enum DetailPaneMetrics {
  /// The width of the start pane, in points.
  static let startWidth: Double = 360
  /// The width of the divider between the panes, in points.
  static let dividerWidth: Double = 1
  /// The size class in which the panes sit side by side.
  static let splitClass = "expanded"
  /// How long the pane takes to slide in, in seconds.
  static let transitionSeconds: Double = 0.25

  /// The width left for the detail pane in a container `width` points wide.
  static func detailWidth(of width: Double) -> Double {
    max(0, width - startWidth - dividerWidth)
  }
}

/// Places the screen, and its detail pane when it has one: side by side when `split`, else each
/// in the whole space with the pane on top.
private struct DetailPaneLayout: Layout {
  let split: Bool

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let fallback = subviews.first?.sizeThatFits(proposal) ?? .zero
    return CGSize(
      width: proposal.width ?? fallback.width, height: proposal.height ?? fallback.height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    // The screen, then a divider (side by side only), then the pane.
    let sideBySide = split && subviews.count == 3
    var widths = Array(repeating: bounds.width, count: subviews.count)
    if sideBySide {
      let start = min(DetailPaneMetrics.startWidth, bounds.width)
      let divider = min(DetailPaneMetrics.dividerWidth, bounds.width - start)
      widths = [start, divider, bounds.width - start - divider]
    }
    var x = bounds.minX
    for (subview, width) in zip(subviews, widths) {
      subview.place(
        at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: width, height: bounds.height))
      if sideBySide { x += width }
    }
  }
}

/// The line between the two panes: the system separator, as the overlays keep the system look.
private struct DetailDivider: View {
  var body: some View {
    Color(uiColor: .separator).accessibilityHidden(true)
  }
}

/// The detail pane: its contained stack (``PaneStackView``) on the system background. Covering
/// the screen, its first entry shows a back button that closes the pane, as a pushed screen's does.
private struct DetailPane: View {
  @ObservedObject var overlay: OverlayModel
  let split: Bool
  let environment: ScreenEnvironment
  let onClose: () -> Void

  var body: some View {
    PaneStackView(overlay: overlay, onRootBack: split ? nil : onClose)
      .background(Color(uiColor: .systemBackground))
      .task(id: PaneEnvironmentKey(environment, entries: overlay.entries.map(\.id))) {
        // The pane's screens take the size class of the pane, not of the screen that opened it.
        for entry in overlay.entries { entry.model?.setEnvironment(environment) }
      }
  }
}

private struct PaneEnvironmentKey: Equatable {
  let sizeClass: String
  let reach: String
  let entries: [String]

  init(_ environment: ScreenEnvironment, entries: [String]) {
    sizeClass = environment.sizeClass.wire
    reach = environment.sizeReach.reachableHeader
    self.entries = entries
  }
}
