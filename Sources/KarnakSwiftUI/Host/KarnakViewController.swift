import SwiftUI
import UIKit

/// A full Karnak screen for UIKit hosts (`docs/integration.md`, Placing Karnak): a
/// `UIHostingController` around a ``KarnakScreen`` with the client and hooks already applied.
/// Push it, present it or embed it as a child like any view controller.
///
/// ```swift
/// let home = KarnakViewController(client: karnak, screenId: "home", params: ["city": "cairo"]) { screenId, params in
///   navigationController?.pushViewController(KarnakViewController(client: karnak, screenId: screenId, params: params), animated: true)
/// }
/// ```
public final class KarnakViewController: UIHostingController<AnyView> {
  /// Creates a controller showing `screenId` with `params`, loaded through `client`, with the
  /// default loading and error views. Images load through `imageLoader`, or through the built-in
  /// loader when it is nil (``SwiftUI/View/karnakImageLoader(_:)``). `entryId` binds the screen to
  /// the entry of a ``KarnakNavigation/open(entryId:target:params:presentation:)`` request and
  /// `onFinish` hears how it ended, as in ``KarnakScreen``. A ``KarnakNavigationCoordinator`` makes
  /// these controllers for you. The hooks are those of
  /// ``SwiftUI/View/karnakHost(_:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``.
  public init(
    client: KarnakSwiftClient,
    screenId: String,
    params: [String: Any] = [:],
    imageLoader: (any KarnakImageLoader)? = nil,
    onNavigate: ((_ route: String, _ params: [String: Any]) -> Void)? = nil,
    onOpenUrl: ((_ url: URL) -> Void)? = nil,
    onCustom: ((_ type: String, _ params: [String: Any]) -> Void)? = nil,
    onTrack: ((_ event: String, _ properties: [String: Any]) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    onOpenScreen: ((_ screenId: String, _ params: [String: Any]) -> Void)? = nil,
    onNavigation: ((_ request: KarnakNavigation) -> Void)? = nil,
    entryId: String? = nil,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil
  ) {
    let screen = KarnakScreen(screenId, params: params, entryId: entryId, onFinish: onFinish)
      .karnakHost(
        client, onNavigate: onNavigate, onOpenUrl: onOpenUrl, onCustom: onCustom, onTrack: onTrack,
        onDismiss: onDismiss, onOpenScreen: onOpenScreen, onNavigation: onNavigation)
    // Without a loader the environment default stays lazy: the shared built-in loader is only
    // created when an image first renders.
    super.init(
      rootView: imageLoader.map { AnyView(screen.karnakImageLoader($0)) } ?? AnyView(screen))
  }

  /// Storyboards can't create this controller; use ``init(client:screenId:params:imageLoader:onNavigate:onOpenUrl:onCustom:onTrack:onDismiss:onOpenScreen:onNavigation:)``.
  @available(*, unavailable)
  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    nil
  }
}
