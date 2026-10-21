import Foundation
import KarnakCore

/// Follows one flow the app placed (``KarnakFlow``): starts it when the view has what it needs,
/// publishes the contained stack to draw, and closes the flow when the view is released. It is
/// the view's `@StateObject`, so it outlives the view's updates.
@MainActor
final class FlowModel: ObservableObject {
  /// Where the flow is, for the view.
  enum Phase {
    /// Not started, or loading: the flow has no entry yet.
    case loading
    /// The flow shows its entries.
    case running(OverlayModel)
    /// The flow ended, or could not start; the app removes the view.
    case ended
  }

  @Published private(set) var phase = Phase.loading

  /// The factory of the models that follow each entry's screen: it carries the host's hooks and
  /// the environment, as the screen that shows an overlay does.
  private let screens = ScreenModel()
  private let closer = DeinitCloser()
  private var flow: (any FlowSession)?
  private var started: FlowKey?
  private var deliver: ((_ outcome: String, _ result: [String: Any]) -> Void)?
  /// Counts the flows this model started, so the end of an earlier one is not taken for the
  /// current one's.
  private var run = 0

  /// The models of the screens the flow shows now, bottom first.
  var screenModels: [ScreenModel] {
    if case .running(let overlay) = phase { overlay.entries.compactMap(\.model) } else { [] }
  }

  /// Starts the flow `key` names, unless it is running. Another flow replaces the running one.
  func start(
    _ key: FlowKey, request: FlowRequest, opener: ScreenOpening?,
    callbacks: KarnakHostCallbacks, environment: ScreenEnvironment
  ) {
    guard started != key else { return }
    stop()
    run += 1
    started = key
    screens.updateHostCallbacks(callbacks)
    screens.setEnvironment(environment)
    guard let opener else {
      return end(
        "Karnak: KarnakFlow('\(key.flowId)') has no client; apply .karnakHost(client) above it.")
    }
    do {
      guard let placed = try opener.openFlow(wrapped(request)) else {
        return end(nil)
      }
      flow = placed
      closer.action = { placed.close() }
      show(placed)
    } catch {
      end("Karnak: KarnakFlow('\(key.flowId)') was rejected: \(error)")
    }
  }

  /// Answers the screens of the flow with the latest hooks and environment.
  func update(callbacks: KarnakHostCallbacks, environment: ScreenEnvironment) {
    screens.updateHostCallbacks(callbacks)
    screens.setEnvironment(environment)
  }

  /// Closes the flow, if one runs: it is cancelled, and nobody is told (the view is gone).
  func stop() {
    run += 1
    deliver = nil
    closer.action = nil
    if case .running(let overlay) = phase { overlay.stop() }
    flow?.close()
    flow = nil
    started = nil
    phase = .loading
  }

  deinit {
    // The view is gone for good: close what it left running. A model's `deinit` can't touch its
    // main-actor state, so it runs the closer instead.
    let closer = closer
    Task { @MainActor in closer.action?() }
  }

  // MARK: - Private

  /// The request with this model between the flow and the app: the flow's end is published as
  /// the phase before the app hears it, and never after the view stopped.
  private func wrapped(_ request: FlowRequest) -> FlowRequest {
    deliver = request.receiver
    let current = run
    let hear: (String, [String: Any]) -> Void = { [weak self] outcome, result in
      MainActor.assumeIsolated {
        if self?.run == current { self?.finished(outcome, result) }
      }
    }
    return FlowRequest(flowId: request.flowId, params: request.params, receiver: hear)
  }

  private func show(_ placed: any FlowSession) {
    let request = OverlayRequest(
      id: "karnak-flow-\(UUID().uuidString)", generation: 0, presentation: .push,
      stack: placed.stack)
    let overlay = OverlayModel(request, makeModel: screens.effects.openOverlayEntry)
    overlay.start()
    phase = .running(overlay)
  }

  private func finished(_ outcome: String, _ result: [String: Any]) {
    let hear = deliver
    deliver = nil
    if case .running(let overlay) = phase { overlay.stop() }
    phase = .ended
    hear?(outcome, result)
  }

  /// Ends the view's flow without a delivery from the engine: the app hears `cancelled`.
  private func end(_ problem: String?) {
    if let problem { NSLog("%@", problem) }
    finished("cancelled", [:])
  }
}

/// Which flow a view places, for telling when it must start another.
struct FlowKey: Equatable {
  let flowId: String
  /// The params in the client's canonical text form, without what isn't a JSON value.
  let params: String
  let opener: ObjectIdentifier?

  init(flowId: String, params: [String: Any], opener: ScreenOpening?) {
    self.flowId = flowId
    self.opener = opener.map(ObjectIdentifier.init)
    let converter = KarnakParamsConverter(debug: false, log: { _ in })
    self.params = (try? converter.convert(params)).map(CanonicalParamsKt.canonicalJson) ?? ""
  }
}

/// What closes the flow when its model is released.
private final class DeinitCloser: @unchecked Sendable {
  var action: (@MainActor () -> Void)?
}
