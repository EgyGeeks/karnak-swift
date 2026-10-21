import Combine
import SwiftUI

/// Gives the views below `.karnakHost` the client's resources through `\.karnakResources`, and
/// draws them again when the content changes. It also starts the first load, off the main thread.
struct KarnakResourcesHost: ViewModifier {
  @StateObject private var model: KarnakResourcesModel

  init(core: ResourcesCore) {
    _model = StateObject(wrappedValue: KarnakResourcesModel(core: core))
  }

  func body(content: Content) -> some View {
    content.environment(\.karnakResources, model.resources)
  }
}

/// The resources value the host publishes: a new generation for each update the Kotlin side
/// reports, so a view that reads `\.karnakResources` draws again.
@MainActor
final class KarnakResourcesModel: ObservableObject {
  @Published private(set) var resources: KarnakSwiftResources

  private var observing = false

  init(core: ResourcesCore) {
    resources = KarnakSwiftResources(core: core)
    // Pay for what you use: nothing is read until a view or the app asks for a string or a color.
    core.whenFirstUsed { [weak self] in
      Task { @MainActor in self?.startObserving(core) }
    }
  }

  private func startObserving(_ core: ResourcesCore) {
    guard !observing else { return }
    observing = true
    let updates = core.updates(sinceFirstUse: true)
    Task { [weak self] in
      for await _ in updates {
        guard let self else { return }
        self.resources = KarnakSwiftResources(core: core, generation: self.resources.generation + 1)
      }
    }
  }
}
