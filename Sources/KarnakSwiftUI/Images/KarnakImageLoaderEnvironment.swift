import SwiftUI

extension EnvironmentValues {
  /// The loader image nodes use. The renderer's shared built-in loader unless the host sets one
  /// with ``SwiftUI/View/karnakImageLoader(_:)``.
  @Entry var karnakImageLoader: any KarnakImageLoader = URLSessionImageLoader.shared
}

extension View {
  /// Makes every image the Karnak content below this view renders load through `loader`, such as a
  /// configured ``URLSessionImageLoader`` or an adapter over the app's own image stack.
  ///
  /// Without it, images load through the renderer's shared built-in ``URLSessionImageLoader``.
  /// It applies to ``KarnakScreen``, ``KarnakSection`` and level-1 ``KarnakContent``. Apply it once
  /// near the root, next to ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:overlays:)``, and again
  /// on a sheet or cover that SwiftUI doesn't connect to the same hierarchy. A closer
  /// `karnakImageLoader` overrides a farther one. ``KarnakViewController`` takes the loader as an
  /// `init` parameter.
  ///
  /// - Parameter loader: The loader for rendered images; the view keeps it alive.
  public func karnakImageLoader(_ loader: any KarnakImageLoader) -> some View {
    environment(\.karnakImageLoader, loader)
  }
}
