import Combine
import SwiftUI

/// What a screen model shows now: the loading view, the content or the error view, shared by
/// ``KarnakScreen`` and ``KarnakSection`` however their model is owned.
struct ScreenPhaseView<Loading: View, Failure: View>: View {
  @ObservedObject var model: ScreenModel
  let screenId: String
  /// Whether the content fills the space it is offered (a screen) or takes only its own size
  /// (a section).
  let fillsSpace: Bool
  /// The call's own loading and error views, which win over the registered ones.
  let loading: (() -> Loading)?
  let failure: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?
  /// The SDK's own views, the last choice.
  let sdkViews: SdkScreenViews
  @Environment(\.karnakScreenStates) private var screenStates

  var body: some View {
    let views = ScreenStateViews(registry: screenStates, sdk: sdkViews)
    switch model.phase {
    case .loading: views.loading(of: screenId, callSite: loading)
    case .content(let screen):
      ResolvedScreenView(
        screen: screen, onAction: { model.click($0) }, onAppear: { model.appear($0) },
        measuresViewport: true, fillsSpace: fillsSpace
      )
      .environment(\.karnakRowAnchors, model.gate.anchors)
      .background { ScrollProbe { model.gate.scroll = $0 } }
    case .failed(let error):
      views.error(of: screenId, error, retry: { model.retry() }, callSite: failure)
    }
  }
}

/// Whether an entry of the host stack lies above the level, as the stack changes; never for a view
/// outside a stack.
@MainActor func stackCoverage(_ level: KarnakStackLevel?) -> AnyPublisher<Bool, Never> {
  guard let level else { return Empty().eraseToAnyPublisher() }
  return level.stack.$entries.map { $0.count > level.depth }.removeDuplicates()
    .eraseToAnyPublisher()
}

/// Where a screen's default navigation goes: the stack level it sits in.
@MainActor func karnakNavigationTarget(_ level: KarnakStackLevel) -> (KarnakNavigation) -> Void {
  { request in MainActor.assumeIsolated { level.stack.perform(request) } }
}
