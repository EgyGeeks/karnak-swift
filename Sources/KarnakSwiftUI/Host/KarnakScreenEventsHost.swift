import SwiftUI

/// Hears the client's ``KarnakScreenEvent``s for the host's `onScreen` hook. The subscription is
/// made when the host is created, not when it appears: a child screen appears (and opens) before
/// its parents, and its first event must not be missed. Nothing is subscribed, and the client's
/// graph is not built, when the host gave no hook.
struct KarnakScreenEventsHost: ViewModifier {
  @StateObject private var model: KarnakScreenEventsModel
  private let client: KarnakSwiftClient
  private let onScreen: (@MainActor (KarnakScreenEvent) -> Void)?

  init(client: KarnakSwiftClient, onScreen: (@MainActor (KarnakScreenEvent) -> Void)?) {
    _model = StateObject(
      wrappedValue: KarnakScreenEventsModel(client: client, first: onScreen))
    self.client = client
    self.onScreen = onScreen
  }

  func body(content: Content) -> some View {
    // The latest closure is the one called: a view that draws again hands over its newer hook.
    model.follow(client, hook: onScreen)
    return content
  }
}

/// The subscription and the latest hook of a ``KarnakScreenEventsHost``.
@MainActor
final class KarnakScreenEventsModel: ObservableObject {
  private var hook: (@MainActor (KarnakScreenEvent) -> Void)?
  private var client: KarnakSwiftClient
  private var watch: KarnakScreenWatch?

  init(client: KarnakSwiftClient, first: (@MainActor (KarnakScreenEvent) -> Void)?) {
    self.client = client
    hook = first
    subscribe()
  }

  /// The latest closure is the one called, and a host handed another client hears that one.
  func follow(_ client: KarnakSwiftClient, hook: (@MainActor (KarnakScreenEvent) -> Void)?) {
    self.hook = hook
    guard client !== self.client else { return }
    watch?.cancel()
    watch = nil
    self.client = client
    subscribe()
  }

  private func subscribe() {
    guard hook != nil else { return }
    watch = client.navigator.observeScreens { [weak self] event in
      self?.hook?(event)
    }
  }
}
