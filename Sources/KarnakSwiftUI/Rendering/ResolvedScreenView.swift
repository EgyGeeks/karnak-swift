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

  /// What the window shows of this view: the viewport of its nodes' appearances.
  @State private var viewport: CGRect?

  var body: some View {
    actions.handler = onAction
    actions.appearHandler = onAppear
    return ZStack(alignment: .topLeading) {
      if let root = screen.root.flatMap(drawnNode) {
        NodeView(
          node: root, placement: fillsSpace && NodeKind(root).isContainer ? .root : .standalone
        ).equatable()
      }
    }
    .frame(
      maxWidth: fillsSpace ? .infinity : nil, maxHeight: fillsSpace ? .infinity : nil,
      alignment: .topLeading
    )
    .background {
      if measuresViewport { ViewportProbe { viewport = $0 } }
    }
    .environment(\.karnakActions, actions)
    .environment(\.karnakViewport, viewport)
    .environment(\.layoutDirection, layoutDirection(screen.layoutDirection))
    .task(id: ObjectIdentifier(screen)) {
      RendererDiagnostics.reportUnsupported(in: screen, to: diagnostics)
    }
  }
}
