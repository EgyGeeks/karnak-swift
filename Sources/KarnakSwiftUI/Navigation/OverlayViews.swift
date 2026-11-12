import KarnakCore
import SwiftUI

/// Draws the overlay of an ``EffectModel``: a bottom sheet or a full-screen cover, each holding a
/// `NavigationStack` over the overlay's contained stack, so a push inside stays inside and the
/// system back and swipe work. It sits on a view of its own: SwiftUI allows one sheet modifier
/// per view, and the screen's `show_sheet` sheet uses the screen's.
struct OverlayPresentation: View {
  @ObservedObject var model: EffectModel
  /// Whether the screen draws its detail pane itself (``DetailPanes``).
  var hasPanes = false

  var body: some View {
    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      .sheet(item: overlay(.sheet)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: false)
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(item: overlay(.modal)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: true)
      }
      .background(detailCover)
  }

  /// A screen with no panes of its own (a section) shows its detail as a full-screen cover. It
  /// sits on a view of its own, since a view takes one cover.
  @ViewBuilder private var detailCover: some View {
    if !hasPanes {
      Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        .fullScreenCover(
          item: Binding(
            get: { model.detail },
            set: { if $0 == nil { model.detailClosedByUser() } })
        ) { presented in
          ContainedStackView(overlay: presented, fillsSpace: true)
        }
    }
  }

  private func overlay(_ presentation: KarnakPresentation) -> Binding<OverlayModel?> {
    Binding(
      get: { model.overlay.flatMap { $0.presentation == presentation ? $0 : nil } },
      set: { if $0 == nil, let open = model.overlay { model.overlayClosedByUser(id: open.id) } })
  }
}

/// The `NavigationStack` of a contained stack, an overlay's or a placed flow's (a detail pane
/// has ``PaneStackView``): its first entry is the root, the others are pushed, and a pop is
/// reported to the engine.
struct ContainedStackView: View {
  @ObservedObject var overlay: OverlayModel
  /// Whether the screens fill the space they are offered (a full-screen cover, a placed flow)
  /// or are bounded by the sheet without scrolling it (a sheet).
  let fillsSpace: Bool
  /// What the entries of a sheet measured: the sheet is as tall as the top one.
  @State private var heights = SheetHeights()

  var body: some View {
    if fillsSpace {
      stack
    } else {
      stack.presentationDetents([heights.detent(top: overlay.entries.last)])
    }
  }

  private var stack: some View {
    NavigationStack(
      path: Binding(
        get: { overlay.entries.dropFirst().map(\.id) },
        set: { overlay.popped(toCount: $0.count + 1) })
    ) {
      Group {
        if let root = overlay.entries.first {
          ContainedEntryView(entry: root, fillsSpace: fillsSpace, onHeight: report(root.id))
            .toolbar(.hidden, for: .navigationBar)
        }
      }
      .navigationDestination(for: String.self) { id in
        if let entry = overlay.entries.first(where: { $0.id == id }) {
          ContainedEntryView(entry: entry, fillsSpace: fillsSpace, onHeight: report(id))
        }
      }
    }
  }

  private func report(_ id: String) -> (CGFloat) -> Void { { heights.record($0, for: id) } }
}

/// One entry of a contained stack: the SDK's screen, or the app's native screen of a route step.
struct ContainedEntryView: View {
  let entry: OverlayEntry
  let fillsSpace: Bool
  let onHeight: (CGFloat) -> Void

  var body: some View {
    if fillsSpace || entry.route != nil {
      content
    } else {
      // As tall as the screen needs up to the sheet's cap: weighted children take the height left.
      content.measuredForSheet(onHeight)
    }
  }

  @ViewBuilder private var content: some View {
    if let model = entry.model {
      OverlayScreenView(model: model, fillsSpace: fillsSpace)
    } else if let route = entry.route {
      KarnakRouteEntryView(route: route)
    }
  }
}

/// The screen of one overlay entry, drawn like a top-level screen: its own states and effects.
struct OverlayScreenView: View {
  let model: ScreenModel
  let fillsSpace: Bool
  @Environment(\.karnakScreenStates) private var screenStates

  var body: some View {
    phaseView.presentingEffects(model.effects)
  }

  @ViewBuilder private var phaseView: some View {
    switch model.phase {
    case .loading:
      views.loading(of: model.screenId, callSite: nil as (() -> EmptyView)?)
        .compactStateFrame(if: !fillsSpace)
        .onAppear { model.screenId.map(screenStates.reportFallback) }
    case .content(let screen):
      if fillsSpace {
        content(screen)
      } else {
        // Bounded by the sheet, not scrolled: weighted children take the height left.
        content(screen).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      }
    case .failed(let error):
      views.error(
        of: model.screenId, error, retry: { model.retry() },
        callSite: nil as ((KarnakScreenError, () -> Void) -> EmptyView)?
      ).compactStateFrame(if: !fillsSpace)
    }
  }

  private var views: ScreenStateViews { ScreenStateViews(registry: screenStates, sdk: .screen) }

  private func content(_ screen: ResolvedScreen) -> some View {
    ResolvedScreenView(
      screen: screen, onAction: { model.click($0) }, onAppear: { model.appear($0) },
      onNear: { model.near($0) },
      onEvent: { model.event($0, payload: $1, byUser: $2, generation: $3) },
      onInput: { model.input($0) }, onFloatingDismiss: { model.floatingDismissed($0, $1) },
      focus: model.effects.focus, measuresViewport: true, fillsSpace: fillsSpace)
  }
}
