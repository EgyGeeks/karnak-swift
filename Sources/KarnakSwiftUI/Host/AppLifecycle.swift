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

  /// `false` each time the app stops being the one the person uses (it resigns: the app switcher, a system alert,
  /// the way to the background) and `true` each time it is again. Nothing until the first change. A process is
  /// ended only while it is not frontmost, so the first is the moment to save what must outlive it.
  @MainActor
  static var isFrontmost: AnyPublisher<Bool, Never> {
    let center = NotificationCenter.default
    let resigned = center.publisher(for: UIApplication.willResignActiveNotification).map { _ in
      false
    }
    let returned = center.publisher(for: UIApplication.didBecomeActiveNotification).map { _ in
      true
    }
    return resigned.merge(with: returned).eraseToAnyPublisher()
  }
}
