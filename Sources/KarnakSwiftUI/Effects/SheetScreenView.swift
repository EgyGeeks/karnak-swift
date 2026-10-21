import KarnakCore
import SwiftUI

/// The child screen of a sheet, drawn like a top-level screen: its own states and effects, and
/// the host's hooks. The sheet's ``ScreenModel`` follows an instance the engine owns and closes,
/// so this view never closes it.
struct SheetScreenView: View {
  @ObservedObject var model: ScreenModel
  @Environment(\.karnakScreenStates) private var screenStates

  var body: some View {
    phaseView.presentingEffects(model.effects)
  }

  @ViewBuilder private var phaseView: some View {
    switch model.phase {
    case .loading:
      views.loading(of: model.screenId, callSite: nil as (() -> EmptyView)?)
        .onAppear { model.screenId.map(screenStates.reportFallback) }
    case .content(let screen):
      ScrollView {
        ResolvedScreenView(
          screen: screen, onAction: { model.click($0) }, onAppear: { model.appear($0) },
          measuresViewport: true, fillsSpace: false)
      }
    case .failed(let error):
      views.error(
        of: model.screenId, error, retry: { model.retry() },
        callSite: nil as ((KarnakScreenError, () -> Void) -> EmptyView)?)
    }
  }

  private var views: ScreenStateViews { ScreenStateViews(registry: screenStates, sdk: .contained) }
}
