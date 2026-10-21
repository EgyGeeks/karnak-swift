import SwiftUI

/// A piece of server-driven UI inside a native screen (`docs/integration.md`, Placing Karnak):
/// like ``KarnakScreen`` but content-sized, so it takes the height its content needs, and its
/// content keeps the leading edge. The section is as wide as the space it is offered, because it
/// measures that width to pick its size class (`adaptive` branches), and a `fill` width takes it.
///
/// ```swift
/// VStack {
///   NativeHeader()
///   KarnakSection("home_promos")
/// }
/// ```
///
/// By default a section shows nothing while it loads and when it fails, so a promo strip never
/// disturbs the native screen around it. Pass `loading` or `error` to show something, or register
/// views for its id with ``KarnakConfiguration/screenStates(_:)``: its entry, else the registered
/// default, wins over the nothing, and a call's own arguments win over both.
public struct KarnakSection<Loading: View, Failure: View>: View {
  private let id: String
  private let params: [String: Any]
  private let loading: (() -> Loading)?
  private let error: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?

  /// Shows section `id` opened with `params`, drawing `loading` before the first content and
  /// `error` when there is nothing to show and loading failed. Calling `retry` loads again.
  public init(
    _ id: String,
    params: [String: Any] = [:],
    @ViewBuilder loading: @escaping () -> Loading,
    @ViewBuilder error:
      @escaping (_ error: KarnakScreenError, _ retry: @escaping () -> Void) -> Failure
  ) {
    self.init(id, params: params, loading: Optional(loading), error: Optional(error))
  }

  fileprivate init(
    _ id: String, params: [String: Any], loading: (() -> Loading)?,
    error: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Failure)?
  ) {
    self.id = id
    self.params = params
    self.loading = loading
    self.error = error
  }

  /// The section in its current state.
  public var body: some View {
    ScreenPresenter(
      screenId: id, params: params, fillsSpace: false, closesWhenHidden: true, loading: loading,
      failure: error, sdkViews: .section)
  }
}

extension KarnakSection where Loading == EmptyView, Failure == EmptyView {
  /// Shows section `id` opened with `params`: the views registered for it, else nothing while it
  /// loads or when it fails.
  public init(_ id: String, params: [String: Any] = [:]) {
    self.init(id, params: params, loading: nil, error: nil)
  }
}
