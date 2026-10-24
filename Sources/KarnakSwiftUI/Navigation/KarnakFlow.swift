import KarnakCore
import SwiftUI

/// A flow the app places itself (`docs/integration.md`, Flows on iOS): runs the flow `flowId` in a
/// contained stack of its own, drawn in the space the view is offered with a `NavigationStack`,
/// so the app can put a checkout or an onboarding in a tab, a sheet or a full-screen cover.
///
/// ```swift
/// .fullScreenCover(isPresented: $checkingOut) {
///   KarnakFlow("checkout", params: ["cartId": cart.id]) { outcome, result in
///     checkingOut = false
///     if outcome == "placed" { show(result["orderId"] as? String) }
///   }
/// }
/// ```
///
/// `onFinish` runs once, on the main thread, with the outcome of the flow's `finish` step and its
/// result, or `cancelled` with an empty result when the flow is left: a `back` at its first step
/// or a `dismiss` in a step (the first step has no back button of its own, so give it one in the
/// screen or close the container yourself), or a flow that fails to load or start. The flow's
/// entries are gone when `onFinish` runs; the view then draws nothing, and the app removes it. A
/// view that goes away while the flow runs cancels the flow without calling `onFinish`.
///
/// While the flow loads the view shows the `loading` view, else the `default` of
/// ``KarnakConfiguration/screenStates(_:)``, else ``KarnakLoadingView``; its steps draw the views registered for their
/// screens. The flow needs the flows module
/// (`KarnakFlows()` of `KarnakNavigation` in ``KarnakConfiguration/modules``) and the client that
/// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``
/// provides; without them it calls `onFinish` with `cancelled` and logs why. A `route` step shows
/// the screen registered with ``SwiftUI/View/karnakRoute(_:content:)``.
///
/// Place it where no `NavigationStack` of your own surrounds it (a tab, a sheet, a cover): SwiftUI
/// cannot nest a stack in a pushed destination, and the flow's steps are pushed on the stack the
/// view draws. To run a flow on your own stack, let a screen's `open_flow` action push it (joined
/// mode).
public struct KarnakFlow<Loading: View>: View {
  private let flowId: String
  private let params: [String: Any]
  private let onFinish: (_ outcome: String, _ result: [String: Any]) -> Void
  private let loading: (() -> Loading)?

  @StateObject private var model = FlowModel()
  @Environment(\.karnakOpener) private var opener
  @Environment(\.karnakScreenStates) private var screenStates
  @Environment(\.karnakHostCallbacks) private var hostCallbacks
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.karnakDeviceSizes) private var injectedDevice
  @Environment(\.karnakContainerWidth) private var forcedWidth
  @Environment(\.karnakFlowObserver) private var flowObserver
  @State private var measuredWidth: CGFloat?

  /// Places the flow `flowId` with `params` (JSON values), drawing `loading` while it loads.
  /// `onFinish` hears how it ended.
  public init(
    _ flowId: String,
    params: [String: Any] = [:],
    onFinish: @escaping (_ outcome: String, _ result: [String: Any]) -> Void,
    @ViewBuilder loading: @escaping () -> Loading
  ) {
    self.init(flowId, params: params, onFinish: onFinish, loadingOrNil: loading)
  }

  fileprivate init(
    _ flowId: String, params: [String: Any],
    onFinish: @escaping (_ outcome: String, _ result: [String: Any]) -> Void,
    loadingOrNil loading: (() -> Loading)?
  ) {
    self.flowId = flowId
    self.params = params
    self.onFinish = onFinish
    self.loading = loading
  }

  /// The flow in its current state.
  public var body: some View {
    let width = forcedWidth ?? measuredWidth.map(Double.init)
    let environment = screenEnvironment(width: width ?? 0)
    let callbacks = hostCallbacks
    // The model keeps the latest hooks and environment (no published state changes), like the
    // screens do. A result builder allows a declaration here, not a bare call.
    // swiftlint:disable:next redundant_discardable_let
    let _ = model.update(callbacks: callbacks, environment: environment)
    ZStack {
      phaseView
      Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
        // The flow starts once its container is measured, so its first screen carries the right
        // size classes.
        .task(id: StartKey(key: key, measured: width != nil)) {
          guard width != nil else { return }
          flowObserver?(model)
          model.start(
            key, request: FlowRequest(flowId: flowId, params: params, receiver: onFinish),
            opener: opener, callbacks: callbacks, environment: environment)
        }
    }
    .measuringContainerWidth($measuredWidth)
  }

  private var key: FlowKey {
    FlowKey(flowId: flowId, params: params, opener: opener)
  }

  @ViewBuilder private var phaseView: some View {
    switch model.phase {
    case .loading:
      ScreenStateViews(registry: screenStates, sdk: .screen).loading(of: nil, callSite: loading)
    case .running(let overlay):
      ContainedStackView(overlay: overlay, fillsSpace: true, reportsTheme: true)
    case .ended: Color.clear
    }
  }

  private func screenEnvironment(width: Double) -> ScreenEnvironment {
    (injectedDevice ?? DeviceSizes.current).environment(
      colorScheme: colorScheme, layoutDirection: layoutDirection, width: width)
  }
}

extension KarnakFlow where Loading == KarnakLoadingView {
  /// Places the flow `flowId` with `params`, with the `default` loading view of
  /// ``KarnakConfiguration/screenStates(_:)``, else the SDK's ``KarnakLoadingView``.
  public init(
    _ flowId: String,
    params: [String: Any] = [:],
    onFinish: @escaping (_ outcome: String, _ result: [String: Any]) -> Void
  ) {
    self.init(flowId, params: params, onFinish: onFinish, loadingOrNil: nil)
  }
}

private struct StartKey: Equatable {
  let key: FlowKey
  let measured: Bool
}
