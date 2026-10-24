import KarnakCore
import SwiftUI

/// Draws the overlay of an ``EffectModel``: a bottom sheet or a full-screen cover, each holding a
/// `NavigationStack` over the overlay's contained stack, so a push inside stays inside and the
/// system back and swipe work. It sits on a view of its own: SwiftUI allows one sheet modifier
/// per view, and the screen's `show_sheet` sheet uses the screen's.
struct OverlayPresentation: View {
  @ObservedObject var model: EffectModel

  var body: some View {
    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
      .sheet(item: overlay(.sheet)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: false, reportsTheme: false)
          .presentationDetents([.medium, .large])
          .presentationDragIndicator(.visible)
      }
      .fullScreenCover(item: overlay(.modal)) { presented in
        ContainedStackView(overlay: presented, fillsSpace: true, reportsTheme: false)
      }
  }

  private func overlay(_ presentation: KarnakPresentation) -> Binding<OverlayModel?> {
    Binding(
      get: { model.overlay.flatMap { $0.presentation == presentation ? $0 : nil } },
      set: { if $0 == nil, let open = model.overlay { model.overlayClosedByUser(id: open.id) } })
  }
}

/// The `NavigationStack` of a contained stack, an overlay's or a placed flow's: its first entry
/// is the root, the others are pushed, and a pop is reported to the engine.
struct ContainedStackView: View {
  @ObservedObject var overlay: OverlayModel
  /// Whether the screens fill the space they are offered (a full-screen cover, a placed flow)
  /// or scroll in their own height (a sheet).
  let fillsSpace: Bool
  /// Whether its screens are the host's shown screen (a placed flow's steps), whose theme a view
  /// around the screens reads; an overlay's (a sheet's, a modal's) never are
  /// (`docs/renderer-contract.md`, Theme of the shown screen).
  let reportsTheme: Bool

  var body: some View {
    NavigationStack(
      path: Binding(
        get: { overlay.entries.dropFirst().map(\.id) },
        set: { overlay.popped(toCount: $0.count + 1) })
    ) {
      Group {
        if let root = overlay.entries.first {
          ContainedEntryView(entry: root, fillsSpace: fillsSpace, reportsTheme: reportsTheme)
            .toolbar(.hidden, for: .navigationBar)
        }
      }
      .navigationDestination(for: String.self) { id in
        if let entry = overlay.entries.first(where: { $0.id == id }) {
          ContainedEntryView(entry: entry, fillsSpace: fillsSpace, reportsTheme: reportsTheme)
        }
      }
    }
  }
}

/// One entry of a contained stack: the SDK's screen, or the app's native screen of a route step.
private struct ContainedEntryView: View {
  let entry: OverlayEntry
  let fillsSpace: Bool
  let reportsTheme: Bool

  var body: some View {
    if let model = entry.model {
      OverlayScreenView(model: model, fillsSpace: fillsSpace, reportsTheme: reportsTheme)
    } else if let route = entry.route {
      KarnakRouteEntryView(route: route)
    }
  }
}

/// The screen of one overlay entry, drawn like a top-level screen: its own states and effects.
/// While it is on screen, a flow step reports its theme to the host (``KarnakShownThemes``); an
/// overlay's entry does not.
struct OverlayScreenView: View {
  @ObservedObject var model: ScreenModel
  let fillsSpace: Bool
  var reportsTheme = false
  @Environment(\.karnakScreenStates) private var screenStates
  @Environment(\.karnakShownThemes) private var shownThemes

  var body: some View {
    phaseView.presentingEffects(model.effects)
      .onAppear { model.reportsTheme(into: reportsTheme ? shownThemes : nil) }
      // A step a push covers, or one that is gone, is no longer the shown screen.
      .onDisappear { model.reportsTheme(into: nil) }
  }

  @ViewBuilder private var phaseView: some View {
    switch model.phase {
    case .loading:
      views.loading(of: model.screenId, callSite: nil as (() -> EmptyView)?)
        .onAppear { model.screenId.map(screenStates.reportFallback) }
    case .content(let screen):
      if fillsSpace {
        content(screen)
      } else {
        ScrollView { content(screen) }
      }
    case .failed(let error):
      views.error(
        of: model.screenId, error, retry: { model.retry() },
        callSite: nil as ((KarnakScreenError, () -> Void) -> EmptyView)?)
    }
  }

  private var views: ScreenStateViews { ScreenStateViews(registry: screenStates, sdk: .contained) }

  private func content(_ screen: ResolvedScreen) -> some View {
    ResolvedScreenView(
      screen: screen, onAction: { model.click($0) }, onAppear: { model.appear($0) },
      measuresViewport: true, fillsSpace: fillsSpace)
  }
}
