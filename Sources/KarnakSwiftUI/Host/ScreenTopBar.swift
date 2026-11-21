import KarnakCore
import SwiftUI

/// Whether the navigation bar shows above the Karnak screens of a navigation stack when a screen doesn't say
/// (`screen.chrome.topBar`, `docs/integration.md`, Screens that draw their own top bar). A screen that says wins.
public enum KarnakNavigationBar: Sendable {
  /// The bar shows, with the screen's title and the back button, unless the screen draws its own top bar.
  case automatic
  /// The bar is hidden, unless the screen asks for it (`topBar: "system"`): every screen draws its own top bar and
  /// goes back with its own `back` action or the system's swipe from the edge.
  case hidden
}

extension EnvironmentValues {
  /// The host's default for the navigation bar above the Karnak screens below, set by
  /// `karnakDestinations(navigationBar:)`.
  @Entry package var karnakNavigationBar = KarnakNavigationBar.automatic
  /// The host's default for the screens pushed inside the `sheet`s and `modal`s the screens below present, the host's
  /// root included, so a sheet follows it as the host's stack does. Set by `karnakDestinations(navigationBar:)`.
  @Entry package var karnakOverlayNavigationBar = KarnakNavigationBar.automatic
}

extension ScreenModel {
  /// Whether the screen hides the navigation bar of its stack entry: it says `none`, or says nothing while `host` is
  /// ``KarnakNavigationBar/hidden``. Before content the screen says nothing, so the host's default holds.
  func hidesNavigationBar(host: KarnakNavigationBar) -> Bool {
    guard case .content(let screen) = phase else { return host == .hidden }
    let topBar = screen.chrome?.topBar
    if topBar == TopBar.none { return true }
    if topBar == TopBar.system { return false }
    return host == .hidden
  }
}

extension View {
  /// Hides the navigation bar of the stack entry the view is in when `hidden`, and leaves it as the app set it
  /// otherwise. Put it on an empty view of its own, as ``screenNavigationTitle(_:)`` is, so the branch it takes never
  /// changes the identity of the screen's content. The swipe back from the edge keeps working (``SwipeBackKeeper``).
  @ViewBuilder
  func screenNavigationBar(hidden: Bool) -> some View {
    if hidden {
      hiddenNavigationBar.background(SwipeBackKeeper())
    } else {
      self
    }
  }

  @ViewBuilder private var hiddenNavigationBar: some View {
    if #available(iOS 18, *) {
      toolbarVisibility(.hidden, for: .navigationBar)
    } else {
      toolbar(.hidden, for: .navigationBar)
    }
  }
}
