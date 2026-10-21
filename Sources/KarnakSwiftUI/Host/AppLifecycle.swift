import Combine
import UIKit

/// Whether the app is out of the background, from the lifecycle notifications of `UIApplication`.
///
/// Not `@Environment(\.scenePhase)`: it follows a SwiftUI `Scene`, and a screen hosted in a
/// `UIHostingController` of a UIKit app, or in a window without one, would read `background` for
/// good and stop its streams for ever. The notifications report the app itself, whoever hosts the
/// view.
enum AppLifecycle {
  /// The current answer now, then `false` each time the app enters the background and `true`
  /// each time it comes back.
  @MainActor
  static var isActive: AnyPublisher<Bool, Never> {
    let center = NotificationCenter.default
    let stopped = center.publisher(for: UIApplication.didEnterBackgroundNotification).map { _ in
      false
    }
    let started = center.publisher(for: UIApplication.willEnterForegroundNotification).map { _ in
      true
    }
    return Just(UIApplication.shared.applicationState != .background)
      .merge(with: stopped, started)
      .eraseToAnyPublisher()
  }
}
