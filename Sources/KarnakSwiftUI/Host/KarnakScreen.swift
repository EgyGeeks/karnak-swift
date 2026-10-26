import SwiftUI

/// A full screen of server-driven UI (`docs/integration.md`, Placing Karnak): opens `id` through
/// the client that ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:overlays:)`` provides, and
/// shows a loading view, then the content, or an error view with a retry.
///
/// ```swift
/// KarnakScreen("home", params: ["city": "cairo"])
/// KarnakScreen("home", loading: { Skeleton() }, error: { error, retry in ErrorView(error.kind, retry) })
/// ```
///
/// Without `loading` or `error`, the screen draws the views the app registered for its id with
/// ``KarnakConfiguration/screenStates(_:)``, else the registered default, else the SDK's
/// ``KarnakLoadingView`` and ``KarnakErrorView``. A call's own arguments win.
///
/// The content fills the space it is offered. The screen opens when the view appears and is
/// closed when it disappears (not while a screen pushed above it covers it, and not when it is
/// a host-stack entry: then when its view is gone); a new `id` or different `params` opens another one. Screens
/// outside `.karnakHost` show the error view with kind ``KarnakScreenError/Kind/rejected``. Color
/// scheme and layout direction changes resolve the content again without loading it.
///
/// With `onFinish`, the screen is an entry of its own and the callback hears how it ended: the
/// outcome of its `finish` action and the result, or `cancelled` with an empty result when the
/// view goes away without finishing (`docs/integration.md`, Navigation). The screen stays; remove
/// it in the callback. Without it, a `finish` acts as `back`. A host that implements
/// `onNavigation` passes the `entryId` of the request it opens the screen for.
public struct KarnakScreen<Loading: View, Failure: View>: View {
  private let id: String
  private let params: [String: Any]
  private let entry: ScreenEntry?
  private let onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)?
  private let loading: (() -> Loading)?
  private let error: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?

  /// Shows screen `id` opened with `params`, drawing `loading` before the first content and
  /// `error` when there is nothing to show and loading failed. Calling `retry` loads again.
  /// `entryId` binds the screen to the host-stack entry of a ``KarnakNavigation/open(entryId:target:params:presentation:)``
  /// request; `onFinish` hears how the screen ended.
  public init(
    _ id: String,
    params: [String: Any] = [:],
    entryId: String? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil,
    @ViewBuilder loading: @escaping () -> Loading,
    @ViewBuilder error:
      @escaping (_ error: KarnakScreenError, _ retry: @escaping () -> Void) -> Failure
  ) {
    self.init(
      id, params: params, entry: entryId.map { ScreenEntry(id: $0) }, onFinish: onFinish,
      loading: loading, error: error)
  }

  /// The designated initializer: a `nil` `loading` or `error` uses the views registered with
  /// ``KarnakConfiguration/screenStates(_:)`` for this screen id, else the SDK's.
  init(
    _ id: String,
    params: [String: Any],
    entry: ScreenEntry?,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil,
    loading: (() -> Loading)?,
    error: ((_ error: KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?
  ) {
    self.id = id
    self.params = params
    self.entry = entry
    self.onFinish = onFinish
    self.loading = loading
    self.error = error
  }

  /// The screen in its current state.
  public var body: some View {
    ScreenPresenter(
      screenId: id, params: params, fillsSpace: true, entry: entry, onFinish: onFinish,
      loading: loading, failure: error, sdkViews: .screen)
  }
}

extension KarnakScreen where Loading == KarnakLoadingView, Failure == KarnakErrorView {
  /// Shows screen `id` opened with `params`, with the views registered for it with
  /// ``KarnakConfiguration/screenStates(_:)``: its entry, else the default, else the SDK's
  /// ``KarnakLoadingView`` and ``KarnakErrorView``. `entryId` and `onFinish` are as in
  /// ``init(_:params:entryId:onFinish:loading:error:)``.
  public init(
    _ id: String, params: [String: Any] = [:], entryId: String? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil
  ) {
    self.init(
      id, params: params, entry: entryId.map { ScreenEntry(id: $0) }, onFinish: onFinish,
      loading: nil, error: nil)
  }

  /// The screen of a host-stack entry that shows a screen.
  init(entry: KarnakStackEntry, screenId: String) {
    self.init(
      screenId, params: entry.params,
      entry: ScreenEntry(id: entry.id, receiver: entry.receiver), loading: nil, error: nil)
  }
}

extension KarnakScreen where Failure == KarnakErrorView {
  /// Shows screen `id` with your `loading` view and the error view registered for it, else the
  /// default ``KarnakErrorView``.
  public init(
    _ id: String, params: [String: Any] = [:], entryId: String? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil,
    @ViewBuilder loading: @escaping () -> Loading
  ) {
    self.init(
      id, params: params, entry: entryId.map { ScreenEntry(id: $0) }, onFinish: onFinish,
      loading: loading, error: nil)
  }
}

extension KarnakScreen where Loading == KarnakLoadingView {
  /// Shows screen `id` with the loading view registered for it, else the default
  /// ``KarnakLoadingView``, and your `error` view.
  public init(
    _ id: String, params: [String: Any] = [:], entryId: String? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil,
    @ViewBuilder error:
      @escaping (_ error: KarnakScreenError, _ retry: @escaping () -> Void) -> Failure
  ) {
    self.init(
      id, params: params, entry: entryId.map { ScreenEntry(id: $0) }, onFinish: onFinish,
      loading: nil, error: error)
  }
}
