import KarnakCore
import SwiftUI

/// Draws one `ResolvedScreen` (`docs/renderer-contract.md`): the renderer alone, which the
/// level-1 `KarnakContent` (#190) and the screen views build on.
///
/// The view fills the space it is offered and the root fills it (`docs/renderer-contract.md`,
/// The root fills the screen): a root container lays its content out in it from the top start
/// corner, with its own alignment, so give the view a bounded size. The screen's layout direction applies to everything
/// inside. When node recovery removed the root, nothing is drawn and no accessibility
/// elements are added: an empty screen is still a successful load.
///
/// A new tree redraws only what changed: node views are `Equatable` on their node, and the
/// engine shares unchanged subtrees between trees.
struct ResolvedScreenView: View {
  /// The tree to draw.
  let screen: ResolvedScreen
  /// Called with a clickable node's or link run's handle when the user activates it. The
  /// handle is only meaningful to the engine instance that resolved ``screen``.
  let onAction: (ActionHandle) -> Void
  /// Called with the handle of a node with `actions.appear` each time at least half of it is
  /// inside the viewport. The engine runs the actions once per node.
  var onAppear: (ActionHandle) -> Void = { _ in }
  /// Called with a node's settled event (a carousel's `pageChange`): its handle, the payload, whether a person caused
  /// it, and the generation of the tree it was raised on.
  var onEvent: (ActionHandle, KarnakValue, Bool, Int64) -> Void = { _, _, _, _ in }
  /// Called with each input's edits, toggles, picks, focus changes and keyboard actions (`InputEvent`).
  var onInput: (InputEvent) -> Void = { _ in }
  /// Called when a floating view ends for a reason the renderer decides (its timer, a swipe, a tap outside, its anchor
  /// gone): the view's key and why. Without it the screen draws no floating layer.
  var onFloatingDismiss: ((String, FloatingDismissReason) -> Void)?
  /// The engine's focus requests for this screen's inputs; without one the view keeps its own, which hears none.
  var focus: InputFocus?
  /// Receives renderer diagnostics, such as a node type this renderer can't draw.
  var diagnostics: (String) -> Void = RendererDiagnostics.systemLog
  /// Whether the view reads what the window shows of it (``ViewportProbe``), which `actions.appear`
  /// needs. On for the screens a host presents in a window; off where there is none to read, such as
  /// the image renderer of the snapshot tests, which can't draw the probe's UIKit view.
  var measuresViewport = false
  /// Whether the view fills the space it is offered (a screen) or takes only the size its
  /// content needs (a section).
  var fillsSpace = true

  /// Keeps its identity across updates, so node views reading it don't redraw when the host
  /// passes a new closure (Compose's `rememberUpdatedState`).
  @State private var actions = ActionSink()

  /// Keeps its identity across updates, as ``actions`` does, for the inputs.
  @State private var inputs = InputSink()

  /// The focus of a view given none: kept across updates, so the inputs' environment doesn't change identity.
  @State private var ownFocus = InputFocus()

  /// What the window shows of this view: the viewport of its nodes' appearances.
  @State private var viewport: CGRect?

  /// The tooltip a node of this screen shows.
  @State private var tooltips = TooltipState()

  var body: some View {
    actions.handler = onAction
    actions.appearHandler = onAppear
    actions.eventHandler = onEvent
    actions.generation = screen.generation
    inputs.handler = onInput
    return ZStack(alignment: .topLeading) {
      if let root = screen.root.flatMap(drawnNode) {
        let fills = fillsSpace && NodeRenderers.registration(for: root).isContainer
        NodeView(node: root, placement: fills ? .root : .standalone).equatable()
      }
    }
    .frame(
      maxWidth: fillsSpace ? .infinity : nil, maxHeight: fillsSpace ? .infinity : nil,
      alignment: .topLeading
    )
    .background {
      if measuresViewport { ViewportProbe { viewport = $0 } }
    }
    // Inside the environment below, so a floating view reads the same actions, inputs and direction as the content.
    .floatingLayer(screen.floating, dismiss: onFloatingDismiss)
    // Over the floating layer, so a floating view's node shows its tooltip above it too.
    .tooltipLayer()
    .environment(\.karnakTooltips, tooltips)
    .environment(\.karnakActions, actions)
    .environment(\.karnakInputs, inputs)
    .environment(\.karnakInputFocus, focus ?? ownFocus)
    .environment(\.karnakViewport, viewport)
    .environment(\.layoutDirection, layoutDirection(screen.layoutDirection))
    .task(id: ObjectIdentifier(screen)) {
      RendererDiagnostics.reportUnsupported(in: screen, to: diagnostics)
    }
  }
}
