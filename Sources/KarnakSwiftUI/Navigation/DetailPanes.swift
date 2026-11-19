import KarnakCore
import SwiftUI
import UIKit

/// Draws a screen with the detail pane it opened (`open_screen` with `presentation: "detail"`;
/// `docs/renderer-contract.md`, Detail panes). In a container of the `expanded` size class the
/// screen keeps a start pane as wide as `startPane` asks (`StartPane.widthIn`: 360 points
/// without one) and the pane's stack takes the rest, with a divider between them. In a narrower
/// container the pane covers the screen: pushed on the `NavigationStack` the screen is in, as a
/// screen is (``PanePushLevel``), or, in no stack, drawn over it with a back button of its own.
/// The screen keeps its place in the view tree in every drawing, so resizing changes neither its
/// state nor the pane's stack, and a resize that moves the pane between beside and over moves it
/// without an animation. Under an app's split view (`.karnakSplitDetail(_:)` of the `KarnakNavigation` product) the
/// pane goes to the split view's detail column instead (``DetailColumnHost``).
struct DetailPanes<Content: View>: View {
  @ObservedObject var effects: EffectModel
  /// The width the screen asks for as its start pane; `nil` for the default.
  let startPane: StartPane?
  /// The environment of a container this many points wide on this device.
  let environment: (Double) -> ScreenEnvironment
  @ViewBuilder let content: () -> Content

  @Environment(\.karnakDetailColumn) private var column

  var body: some View {
    if let column {
      content().modifier(
        SendsDetailToColumn(effects: effects, column: column, environment: environment))
    } else {
      OwnDetailPanes(
        effects: effects, startPane: startPane, environment: environment, content: content)
    }
  }
}

/// The pane drawn by the screen itself: beside it, pushed over it, or drawn over it.
private struct OwnDetailPanes<Content: View>: View {
  @ObservedObject var effects: EffectModel
  let startPane: StartPane?
  let environment: (Double) -> ScreenEnvironment
  @ViewBuilder let content: () -> Content

  @Environment(\.karnakContainerWidth) private var forcedWidth
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.karnakInNavigationStack) private var inStack
  @Environment(\.karnakPushedAbove) private var pushedAbove
  /// The container's width: measured by the screen, or, while the pane is pushed and the covered screen is out of the
  /// window, by the pane (the stack's width, which is the screen's).
  @State private var measuredWidth: CGFloat?
  /// Whether a navigation controller shows the screen (``NavigationControllerProbe``).
  @State private var inNavigationController = false
  /// Whether a covering pane is pushed; it changes without an animation, after the width.
  @State private var pushes = false
  /// The pane on the push chain, kept while it is popped so it doesn't vanish mid-animation.
  @State private var pushed: OverlayModel?

  var body: some View {
    let width = forcedWidth ?? measuredWidth.map(Double.init) ?? 0
    let beside = environment(width).sizeClass.wire == DetailPaneMetrics.splitClass
    let start = DetailPaneMetrics.startWidth(of: startPane, in: width)
    let drawn = pushes ? nil : effects.detail
    DetailPaneLayout(split: beside && drawn != nil, startWidth: start) {
      // Covered, the screen is still there for its state; a screen reader sees only the pane. The screen is a
      // container of its own, so `accessibilityHidden(false)` lands on that container: without one it lands on
      // every element of the screen, and shows the ones the screen hides (decorations, zero-size anchors).
      content().accessibilityElement(children: .contain).accessibilityHidden(
        drawn != nil && !beside)
      if let drawn {
        if beside { DetailDivider() }
        DetailPane(
          overlay: drawn, beside: beside,
          environment: environment(
            beside ? DetailPaneMetrics.detailWidth(of: width, startWidth: start) : width),
          onClose: { effects.detailClosedByUser() }
        )
        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
      }
    }
    .animation(.easeInOut(duration: DetailPaneMetrics.transitionSeconds), value: drawn?.id)
    .measuringContainerWidth($measuredWidth)
    .navigationDestination(isPresented: pushBinding) {
      if let pushed {
        PanePushLevel(
          overlay: pushed, depth: 0, environment: environment(width),
          onWidth: paneMeasured)
      }
    }
    .background {
      if inStack {
        NavigationControllerProbe { inNavigationController = $0 }.accessibilityHidden(true)
      }
    }
    .onChange(of: !beside && inStack && inNavigationController, initial: true) { _, push in
      setPushes(push)
    }
    .onChange(of: effects.detail?.id, initial: true) {
      if let detail = effects.detail { pushed = detail }
    }
  }

  /// The stack's width, measured by the pushed pane. The covered screen is out of the window, where SwiftUI runs no
  /// `onChange`, so the pane moves beside it from here when the stack grows to `expanded`.
  private func paneMeasured(_ width: CGFloat) {
    if measuredWidth != width { measuredWidth = width }
    let beside = environment(Double(width)).sizeClass.wire == DetailPaneMetrics.splitClass
    if beside { setPushes(false) }
  }

  /// A resize across the classes moves the pane, it doesn't push or pop it: no animation.
  private func setPushes(_ push: Bool) {
    guard pushes != push else { return }
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { pushes = push }
  }

  /// Whether the pane is pushed; the system's back or swipe from its first screen closes it. An entry the stack pushes
  /// above the screen takes the pane's place without closing it: the screen is out of the window then, where SwiftUI
  /// runs no `onChange`, so the binding reads it itself.
  private var pushBinding: Binding<Bool> {
    let covered = pushedAbove
    return Binding(
      get: { pushes && !covered && effects.detail != nil },
      set: { if !$0, pushes, !covered { effects.detailClosedByUser() } })
  }
}

/// The sizes of the two panes, the same on every platform: their widths are `StartPane`'s.
enum DetailPaneMetrics {
  /// The width of the start pane of a screen that asks for none, in points.
  static let defaultStartWidth: Double = StartPane.companion.DEFAULT_WIDTH
  /// The width of the divider between the panes, in points.
  static let dividerWidth: Double = StartPane.companion.DIVIDER_WIDTH
  /// The size class in which the panes sit side by side.
  static let splitClass = "expanded"
  /// How long the pane takes to slide in, in seconds.
  static let transitionSeconds: Double = 0.25

  /// The width of the start pane `pane` asks for in an expanded container `width` points wide.
  static func startWidth(of pane: StartPane?, in width: Double) -> Double {
    StartPane.companion.widthIn(pane: pane, containerWidth: width)
  }

  /// The width left for the detail pane in a container `width` points wide beside a start pane
  /// `startWidth` points wide.
  static func detailWidth(of width: Double, startWidth: Double) -> Double {
    max(0, width - startWidth - dividerWidth)
  }
}

/// Places the screen, and its detail pane when it has one: side by side when `split`, else each
/// in the whole space with the pane on top.
private struct DetailPaneLayout: Layout {
  let split: Bool
  /// The start pane's width, in points.
  let startWidth: Double

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
      let start = min(startWidth, bounds.width)
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
struct DetailPane: View {
  @ObservedObject var overlay: OverlayModel
  /// Whether the pane sits beside its screen, where its first entry has no way back.
  let beside: Bool
  let environment: ScreenEnvironment
  let onClose: () -> Void

  var body: some View {
    PaneStackView(overlay: overlay, onRootBack: beside ? nil : onClose)
      .background(Color(uiColor: .systemBackground))
      .task(id: PaneEnvironmentKey(environment, entries: overlay.entries.map(\.id))) {
        // The pane's screens take the size class of the pane, not of the screen that opened it.
        for entry in overlay.entries { entry.model?.setEnvironment(environment) }
      }
  }
}
