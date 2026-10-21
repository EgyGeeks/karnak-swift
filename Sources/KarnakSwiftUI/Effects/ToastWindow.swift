import SwiftUI
import UIKit

/// Shows a toast in a window of its own, above the app and below nothing it needs: touches pass
/// through to the app, so a toast never takes a tap or focus from the screen. Without a
/// foreground scene there is no window, and ``isPresenting`` stays false.
@MainActor
final class ToastWindow: ObservableObject {
  private var window: UIWindow?

  /// Whether a window shows the toast now.
  @Published private(set) var isPresenting = false

  /// Shows `toast` (replacing the one shown), or hides the window for nil.
  func show(_ toast: ToastRequest?, fonts: ThemeFontRegistry?, dynamicTypeSize: DynamicTypeSize) {
    guard let toast, let scene = Self.foregroundScene() else {
      window?.isHidden = true
      window = nil
      isPresenting = false
      return
    }
    let root = ToastView(toast: toast)
      .id(toast.id)
      .environment(\.karnakFonts, fonts)
      .environment(\.dynamicTypeSize, dynamicTypeSize)
      .padding(.bottom, 24)
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    if let controller = window?.rootViewController as? UIHostingController<AnyView> {
      controller.rootView = AnyView(root)
    } else {
      let controller = UIHostingController(rootView: AnyView(root))
      controller.view.backgroundColor = .clear
      let toastWindow = PassThroughWindow(windowScene: scene)
      toastWindow.rootViewController = controller
      toastWindow.windowLevel = .alert
      toastWindow.backgroundColor = .clear
      toastWindow.isHidden = false
      window = toastWindow
    }
    isPresenting = true
  }

  private static func foregroundScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }
}

/// A window that never handles a touch: they reach the windows below.
private final class PassThroughWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
