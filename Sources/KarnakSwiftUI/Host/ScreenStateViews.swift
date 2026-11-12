import KarnakCore
import SwiftUI

/// Where a screen is drawn, which decides the SDK's own loading and error views, the last in the order
/// ``KarnakConfiguration/screenStates(_:)`` describes.
@MainActor
enum SdkScreenViews {
  /// A full screen: a spinner, and a message with a retry button.
  case screen
  /// A section among native content: nothing, so a promo strip never disturbs the screen around it.
  case section

  @ViewBuilder func loading() -> some View {
    switch self {
    case .screen: KarnakLoadingView()
    case .section: EmptyView()
    }
  }

  /// The app's cached loading screen, drawn statically: no instance, so its sources never load and its
  /// actions go nowhere. A sheet bounds it like any loading view (``compactStateFrame()``).
  func loadingScreen(_ screen: CachedLoadingScreen) -> some View {
    KarnakContent(screenJson: screen.screenJson, themeJson: screen.themeJson)
  }

  @ViewBuilder func error(retry: @escaping () -> Void) -> some View {
    switch self {
    case .screen: KarnakErrorView(retry: retry)
    case .section: EmptyView()
    }
  }
}

/// The height of a sheet while its screen has no content, whatever the app's loading or error view asks for.
let compactStateHeight: CGFloat = 160

extension View {
  /// Draws a loading or error view of a sheet in exactly ``compactStateHeight``, so a view that fills its
  /// space, as a full-screen skeleton does, cannot hold the sheet at its maximum height.
  func compactStateFrame() -> some View {
    frame(height: compactStateHeight).clipped().environment(\.karnakScreenPlacement, .contained)
  }

  /// ``compactStateFrame()`` when `applies`, else the view as it is (a full-screen overlay fills its window).
  @ViewBuilder func compactStateFrame(if applies: Bool) -> some View {
    if applies { compactStateFrame() } else { self }
  }
}

/// Picks the loading and error view of a screen id: the call site's own, the screen's entry, the
/// registered default, then the SDK's. A loading view has one more step, after the entry: the app's
/// loading screen (``KarnakConfiguration/loadingScreen``) while it is cached, outside sections.
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
    } else if let entry = registry.entry(for: screenId) {
      entry.loading()
    } else if sdk != .section, let screen = registry.loadingScreen() {
      sdk.loadingScreen(screen)
    } else if let fallback = registry.defaultStates() {
      fallback.loading()
    } else {
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
