import KarnakCore
import SwiftUI

/// The child screen of a sheet, drawn like a top-level screen: its own states and effects, and
/// the host's hooks. The sheet's ``ScreenModel`` follows an instance the engine owns and closes,
/// so this view never closes it.
struct SheetScreenView: View {
  let model: ScreenModel
  @Environment(\.karnakScreenStates) private var screenStates

  var body: some View {
    // Every phase is measured: a loading or failed sheet is as tall as its state view.
    phaseView.fitsSheet().presentingEffects(model.effects)
  }

  @ViewBuilder private var phaseView: some View {
    switch model.phase {
    case .loading:
      views.loading(of: model.screenId, callSite: nil as (() -> EmptyView)?)
        .compactStateFrame()
        .onAppear { model.screenId.map(screenStates.reportFallback) }
    case .content(let screen):
      // Bounded by the sheet, not scrolled: a weighted child takes the height left, and scrolling is
      // the screen's own `list`.
      ResolvedScreenView(
        screen: screen, onAction: { model.click($0) }, onAppear: { model.appear($0) },
        onNear: { model.near($0) },
        onEvent: { model.event($0, payload: $1, byUser: $2, generation: $3) },
        onInput: { model.input($0) }, onFloatingDismiss: { model.floatingDismissed($0, $1) },
        focus: model.effects.focus, measuresViewport: true,
        fillsSpace: false
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    case .failed(let error):
      views.error(
        of: model.screenId, error, retry: { model.retry() },
        callSite: nil as ((KarnakScreenError, () -> Void) -> EmptyView)?
      ).compactStateFrame()
    }
  }

  private var views: ScreenStateViews { ScreenStateViews(registry: screenStates, sdk: .screen) }
}
