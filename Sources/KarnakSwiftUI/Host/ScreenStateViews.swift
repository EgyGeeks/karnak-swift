import SwiftUI

/// Where a screen is drawn, which decides the SDK's own loading and error views, the last in the order
/// ``KarnakConfiguration/screenStates(_:)`` describes.
@MainActor
enum SdkScreenViews {
  /// A full screen: a spinner, and a message with a retry button.
  case screen
  /// A section among native content: nothing, so a promo strip never disturbs the screen around it.
  case section
  /// A sheet's child or a step of a contained stack: like a screen, with a minimum height.
  case contained

  @ViewBuilder func loading() -> some View {
    switch self {
    case .screen: KarnakLoadingView()
    case .section: EmptyView()
    case .contained: KarnakLoadingView().frame(minHeight: 160)
    }
  }

  @ViewBuilder func error(retry: @escaping () -> Void) -> some View {
    switch self {
    case .screen: KarnakErrorView(retry: retry)
    case .section: EmptyView()
    case .contained: KarnakErrorView(retry: retry).frame(minHeight: 160)
    }
  }
}

/// Picks the loading and error view of a screen id: the call site's own, the screen's entry, the
/// registered default, then the SDK's.
@MainActor
struct ScreenStateViews {
  let registry: ScreenStatesRegistry
  let sdk: SdkScreenViews

  /// The loading view of `screenId`; `callSite` is the `loading` argument of the call, if it gave one.
  @ViewBuilder func loading<Content: View>(
    of screenId: String?, callSite: (() -> Content)?
  ) -> some View {
    if let callSite {
      callSite()
    } else if let states = registry.states(for: screenId) {
      states.loading()
    } else {
      // Part B (#1296) puts the screen's cached server skeleton here, between the registered views
      // and the SDK's.
      sdk.loading()
    }
  }

  /// The error view of `screenId`; `callSite` is the `error` argument of the call, if it gave one.
  @ViewBuilder func error<Content: View>(
    of screenId: String?, _ error: KarnakScreenError, retry: @escaping () -> Void,
    callSite: ((KarnakScreenError, _ retry: @escaping () -> Void) -> Content)?
  ) -> some View {
    if let callSite {
      callSite(error, retry)
    } else if let states = registry.states(for: screenId) {
      states.error(kind: error.kind, retry: retry)
    } else {
      sdk.error(retry: retry)
    }
  }
}

extension EnvironmentValues {
  /// The loading and error views the client's configuration registered.
  @Entry var karnakScreenStates = ScreenStatesRegistry.empty
}
