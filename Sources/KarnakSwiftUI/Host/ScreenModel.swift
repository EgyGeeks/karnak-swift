import Combine
import Foundation
import KarnakCore

/// What a screen view shows now.
enum ScreenPhase {
  case loading
  case content(ResolvedScreen)
  case failed(KarnakScreenError)
}

/// Follows one open screen for its view: opens it when the view appears and publishes its states.
/// It is the view's `@StateObject`, which SwiftUI keeps for the life of the view's identity, so
/// the screen it follows does too: a hidden screen (covered, in another tab) keeps its content
/// and effects. ``ViewLifetime`` stops it when the view is gone for good, a section stops it when
/// it disappears, and a model that is released closes what is still open
/// (iOS 16 has no `@Observable`; `docs/integration.md`, State ownership).
@MainActor
final class ScreenModel: ObservableObject {
  /// What to draw. It keeps the last content while the same screen loads again.
  @Published private(set) var phase = ScreenPhase.loading

  /// The effects the open screen asks to present.
  let effects: EffectModel

  /// Holds structural updates while the user scrolls and anchors the row they read.
  let gate = ContentGate()

  /// The id of the screen it follows, once known: the key it opened, or the instance it follows.
  private(set) var screenId: String?
  private var session: ScreenSession?
  private let closer = DeinitCloser()
  /// Whether the model closes the session it follows: not for a sheet's, which the engine owns.
  private var ownsSession = true
  private var stopObserving: (() -> Void)?
  private var stopObservingEffects: (() -> Void)?
  private var startedKey: SessionKey?
  private var opener: ScreenOpening?
  private var params: [String: Any] = [:]
  private var environment = ScreenModel.initialEnvironment
  private var callbacks = KarnakHostCallbacks()
  /// What keeps the screen in the foreground; a change that flips the answer reaches the engine.
  private var presence = ForegroundPresence() {
    didSet {
      if presence.isForeground != oldValue.isForeground { reportForeground() }
      effects.setVisible(presence.shown && !presence.covered)
    }
  }
  /// The entry the screen is, when it has one, and the id the model reports as removed when the
  /// screen is gone (its own entries only).
  private var entry: ScreenEntry?
  /// The id of the entry the screen makes of itself when its caller waits for an outcome.
  let ownEntryId = "karnak-screen-\(UUID().uuidString)"
  /// Who hears the outcome of a screen that is an entry of its own: the latest hook.
  var finishHandler: ((_ outcome: String, _ result: [String: Any]) -> Void)?
  private var reportsRemoval = false
  private lazy var bridge = HostActionBridge { [weak self] message in
    self?.report(message)
  }

  init(effects: EffectModel = EffectModel()) {
    self.effects = effects
    effects.openChild = { [weak self] request in
      self?.followChild(request.screen) ?? ScreenModel()
    }
    effects.openOverlayEntry = { [weak self] screen in
      self?.followChild(screen) ?? ScreenModel()
    }
  }

  /// A model for a child instance the engine opened (a sheet's, an overlay entry's), with this
  /// screen's hooks and environment.
  private func followChild(_ session: any ScreenSession) -> ScreenModel {
    let child = ScreenModel()
    child.updateHostCallbacks(callbacks)
    child.follow(session, environment: environment)
    return child
  }

  private static let initialEnvironment = ScreenEnvironment.make(
    colorMode: .light, layoutDirection: .ltr)

  /// Opens the screen `key` names, unless it is already open. A different screen replaces the
  /// open one.
  func start(
    _ key: SessionKey, opener: ScreenOpening?, params: [String: Any],
    environment: ScreenEnvironment, entry: ScreenEntry? = nil, reportsRemoval: Bool = false
  ) {
    guard session == nil || startedKey != key else { return }
    let sameScreen = startedKey == key
    stop()
    startedKey = key
    screenId = key.screenId
    self.opener = opener
    self.params = params
    self.environment = environment
    self.entry = entry
    self.reportsRemoval = reportsRemoval
    bridge.ownEntryId = reportsRemoval ? entry?.id : nil
    if !sameScreen { phase = .loading }
    if let id = entry?.id, opener?.isOrphanedFlowEntry(id) == true {
      return removeOrphan(id)
    }
    guard let opener else {
      fail("Karnak: screen \(key.screenId) has no client; apply .karnakHost(client) above it.")
      return
    }
    do {
      let opened = try opener.openScreen(
        ScreenRequest(
          screenId: key.screenId, params: params, environment: environment, entry: entry))
      attach(opened)
    } catch {
      fail("Karnak: screen \(key.screenId) was rejected: \(error)")
    }
  }

  /// Follows `session`, a sheet's child that the engine opened and will close. It is drawn like
  /// a screen; stopping only stops listening.
  func follow(_ session: ScreenSession, environment: ScreenEnvironment) {
    guard self.session == nil else { return }
    ownsSession = false
    screenId = session.screenId
    self.environment = environment
    attach(session)
  }

  private func attach(_ opened: ScreenSession) {
    session = opened
    // A new instance is in the foreground until told otherwise.
    if ownsSession, !presence.isForeground { opened.setForeground(false) }
    if ownsSession { closer.action = closingAction(opened) }
    effects.bind(opened)
    opened.setHostActions(bridge.hostActions)
    stopObserving = opened.observe { [weak self] state in
      MainActor.assumeIsolated { self?.receive(state) }
    }
    stopObservingEffects = opened.observeEffects { [weak self] effect in
      MainActor.assumeIsolated { self?.effects.offer(effect) }
    }
  }

  /// What closes `opened` and reports its removal, if it reports one, for a model that is released.
  private func closingAction(_ opened: ScreenSession) -> @MainActor () -> Void {
    let removed = reportsRemoval ? entry?.id : nil
    let owner = opener
    return {
      opened.close()
      if let removed { owner?.entryRemoved(removed) }
    }
  }

  /// The entry belongs to a flow that died with the process: the host restored the step but not
  /// the flow (ADR 0017, D13). Nothing opens; the screen asks the host to pop it, which leaves the
  /// screen that started the flow, and the user starts the flow again.
  private func removeOrphan(_ id: String) {
    report(
      "Karnak: removed the restored flow step \(id): its flow did not survive the process. "
        + "Start the flow again.")
    callbacks.onNavigation?(.back(screen: nil, root: false, before: id))
  }

  /// Fails the screen as rejected and logs why: to the client's `log`, or `NSLog` without one.
  /// Misuse doesn't crash the host, in debug or release; the log is where a developer sees it.
  private func fail(_ message: String) {
    phase = .failed(KarnakScreenError(kind: .rejected, message: message))
    report(message)
    // Nothing opened, so nothing will ever finish: whoever waits hears `cancelled`.
    entry?.receiver?("cancelled", [:])
  }

  /// Logs `message` to the client's `log`, or `NSLog` without a client.
  private func report(_ message: String) {
    if let opener { opener.report(message) } else { NSLog("%@", message) }
  }

  /// The screen's view appeared (`true`) or disappeared while the screen stays open (`false`).
  func setShown(_ shown: Bool) { presence.shown = shown }

  /// The app left the background (`true`) or entered it (`false`).
  func setAppActive(_ active: Bool) { presence.appActive = active }

  /// An entry of the host stack was pushed above the screen (`true`) or removed (`false`).
  func setCovered(_ covered: Bool) { presence.covered = covered }

  /// Tells the engine where the screen is. A sheet's or overlay entry's instance is the engine's:
  /// it covers the entries below the top by itself, so nothing is reported for it.
  private func reportForeground() {
    guard ownsSession else { return }
    session?.setForeground(presence.isForeground)
  }

  /// Sends the activation of `handle` to the open screen; nothing happens without one.
  func click(_ handle: ActionHandle) {
    session?.click(handle)
  }

  /// Sends the appearance of `handle`, a node at least half visible, to the open screen; nothing
  /// happens without one.
  func appear(_ handle: ActionHandle) {
    session?.appear(handle)
  }

  /// Answers the screen's host actions with `callbacks` from now on.
  func updateHostCallbacks(
    _ callbacks: KarnakHostCallbacks,
    onFinish: ((_ outcome: String, _ result: [String: Any]) -> Void)? = nil
  ) {
    finishHandler = onFinish
    self.callbacks = callbacks
    if bridge.update(callbacks) { session?.setHostActions(bridge.hostActions) }
    effects.sheet?.model.updateHostCallbacks(callbacks)
  }

  /// Closes the open screen, if any. The last phase stays for a view that appears again. A
  /// screen that reports its removal tells the SDK it is gone, so a receiver hears `cancelled`.
  func stop() {
    stopObserving?()
    stopObservingEffects?()
    if ownsSession { session?.close() }
    effects.reset()
    gate.reset()
    stopObserving = nil
    stopObservingEffects = nil
    session = nil
    closer.action = nil
    if reportsRemoval, let id = entry?.id { opener?.entryRemoved(id) }
  }

  deinit {
    // The view is gone for good, covered or not: close what a disappearing view left open.
    let closer = closer
    Task { @MainActor in closer.action?() }
  }

  /// Loads the screen again, from the error UI's retry.
  func retry() {
    if case .failed = phase { phase = .loading }
    if let session {
      session.refresh()
    } else if let startedKey {
      start(startedKey, opener: opener, params: params, environment: environment)
    }
  }

  /// Resolves the content again when the color scheme or layout direction changed.
  func setEnvironment(_ environment: ScreenEnvironment) {
    guard !environment.isEqual(self.environment) else { return }
    self.environment = environment
    session?.setEnvironment(environment)
    effects.sheet?.model.setEnvironment(environment)
  }

  private func receive(_ state: ScreenState) {
    switch state {
    case let content as ScreenStateContent:
      var shown: ResolvedScreen?
      if case .content(let screen) = phase { shown = screen }
      gate.offer(content.screen, shown: shown) { [weak self] in self?.show($0) }
    case let failed as ScreenStateFailed:
      gate.reset()
      phase = .failed(KarnakScreenError(failed.error))
    case is ScreenStateLoading:
      if case .content = phase { return }
      phase = .loading
    default: break
    }
  }

  private func show(_ screen: ResolvedScreen) {
    phase = .content(screen)
    effects.setGeneration(screen.generation)
  }
}

/// Which screen a view shows, for telling when it must open another.
struct SessionKey: Equatable {
  let screenId: String
  /// The params in the client's canonical text form, without what isn't a JSON value.
  let params: String
  let opener: ObjectIdentifier?
  let entryId: String?

  init(screenId: String, params: [String: Any], opener: ScreenOpening?, entryId: String? = nil) {
    self.screenId = screenId
    self.entryId = entryId
    self.opener = opener.map(ObjectIdentifier.init)
    // The client's own canonical form, so equal params in any order are one screen. Release
    // mode drops what isn't a JSON value, as the client does, and never throws.
    let converter = KarnakParamsConverter(debug: false, log: { _ in })
    self.params = (try? converter.convert(params)).map(CanonicalParamsKt.canonicalJson) ?? ""
  }
}

/// What closes a screen when its model is released: set while a screen is open, cleared by
/// `stop()`. A model's `deinit` can't touch its main-actor state, so it runs this instead.
private final class DeinitCloser: @unchecked Sendable {
  var action: (@MainActor () -> Void)?
}
