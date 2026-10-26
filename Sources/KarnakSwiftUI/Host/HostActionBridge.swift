import Foundation
import KarnakCore

/// Answers the engine's host actions with the hooks of the enclosing `.karnakHost`, read when the
/// action arrives, so a hook that changed since the screen opened is the one that runs.
///
/// The engine is given the hooks the host provides and nothing else, so an action whose hook is missing
/// reaches the engine as it does on every platform: it is dropped, logged with the name to pass and reported
/// as the client event `action.unhandled` (`track` and `dismiss` stay silent because they are optional by
/// design). The bridge tells the screen when a hook appears or goes away. Hooks run on the main thread: where
/// the tap that led to them ran, or, for what a flow does by itself (its next step, the `onFinish` of its end),
/// hopped to it.
@MainActor
final class HostActionBridge {
  private var callbacks = KarnakHostCallbacks()
  private let report: (String) -> Void

  /// Creates a bridge that sends diagnostics to `report`.
  init(report: @escaping (String) -> Void) {
    self.report = report
  }

  /// The entry id of a screen whose caller waits for its outcome (`KarnakScreen(onFinish:)`): the
  /// `back` that follows its `finish` is the caller's to perform, in its callback.
  var ownEntryId: String?

  /// Whether the engine is given an `onNavigation` hook: the host or `.karnakDestinations()` has
  /// one, or the screen is an entry of its own and must answer its `back`.
  private var navigationWired: Bool { callbacks.onNavigation != nil || ownEntryId != nil }

  /// Which hooks the engine is given: `onNavigation` and the three whose absence it reports, and whether the host
  /// draws the overlays. It reads at once whether each is there.
  private var wiring: [Bool] {
    [
      navigationWired, callbacks.onNavigate != nil, callbacks.onOpenUrl != nil,
      callbacks.onCustom != nil, callbacks.overlays == .host,
    ]
  }

  /// Uses `callbacks` for the actions that arrive from now on. Returns whether the engine must
  /// be given ``hostActions`` again: a hook it was given is gone, or one it lacked is there.
  @discardableResult
  func update(_ callbacks: KarnakHostCallbacks) -> Bool {
    let before = wiring
    self.callbacks = callbacks
    return before != wiring
  }

  /// The hooks to give the engine instance (`ScreenController.setHostActions`).
  var hostActions: HostActions {
    let actions = engineActions.withOverlays(choice: callbacks.overlays.core)
    guard navigationWired else { return actions }
    return actions.withNavigation { @Sendable [weak self] request in
      nonisolated(unsafe) let request = request
      Self.onMain { self?.navigation(request) }
    }
  }

  /// The hook for `navigate`, or nil when the host has none, so the engine reports the action.
  private var navigateHook: (@Sendable (String, [String: Any]) -> Void)? {
    guard callbacks.onNavigate != nil else { return nil }
    return { @Sendable [weak self] route, params in
      nonisolated(unsafe) let params = params
      Self.onMain { self?.navigate(route, params) }
    }
  }

  /// The hook for `open_url`, or nil when the host has none.
  private var openUrlHook: (@Sendable (String) -> Void)? {
    guard callbacks.onOpenUrl != nil else { return nil }
    return { @Sendable [weak self] url in
      Self.onMain { self?.openUrl(url) }
    }
  }

  /// The hook for custom actions, or nil when the host has none.
  private var customHook: (@Sendable (HostCustomAction) -> Void)? {
    guard callbacks.onCustom != nil else { return nil }
    return { @Sendable [weak self] action in
      nonisolated(unsafe) let action = action
      Self.onMain { self?.custom(action) }
    }
  }

  private var engineActions: HostActions {
    HostActions(
      onNavigate: navigateHook, onOpenUrl: openUrlHook, onCustom: customHook,
      onTrack: { @Sendable [weak self] event, properties in
        nonisolated(unsafe) let properties = properties
        Self.onMain { self?.callbacks.onTrack?(event, properties) }
      },
      onDismiss: { @Sendable [weak self] in
        Self.onMain { self?.callbacks.onDismiss?() }
      },
      onOpenScreen: { @Sendable [weak self] screenId, params in
        nonisolated(unsafe) let params = params
        Self.onMain { self?.openScreen(screenId, params) }
      })
  }

  /// Runs `work` on the main thread: at once when the engine called from there (a tap), later
  /// when it called from its own dispatcher (a flow moving to its next step, the end of a flow
  /// running an `onFinish`). The order of the calls is kept.
  private nonisolated static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(work)
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  /// Answers a navigation request with the host's `onNavigation`, or with the older hooks.
  private func navigation(_ request: any KarnakCore.KarnakNavigation) {
    guard let request = KarnakNavigation(request) else {
      return report("Karnak: ignored a navigation request of a kind this SDK does not know.")
    }
    if case .back(nil, false, let before?) = request, before == ownEntryId { return }
    if let hook = callbacks.onNavigation {
      hook(request)
      return
    }
    switch request {
    case .open(_, .screen(let screenId), let params, _):
      openScreen(screenId, params)
    case .open(_, .route(let id, _), _, _):
      report(
        "Karnak: dropped the native route '\(id)' of a flow step: the host has no onNavigation hook "
          + "(docs/integration.md, Flows on iOS).")
    case .back(nil, false, nil):
      callbacks.onDismiss?()
    case .back:
      report(
        "Karnak: dropped a back with 'to', 'root' or 'before': the host has no onNavigation hook "
          + "(docs/integration.md, Navigation).")
    }
  }

  // The hooks the host removed after the engine was given them are reported here, until it is given ``hostActions`` again.
  private func navigate(_ route: String, _ params: [String: Any]) {
    if let hook = callbacks.onNavigate {
      hook(route, params)
    } else {
      missing("navigate", hook: "onNavigate")
    }
  }

  private func openScreen(_ screenId: String, _ params: [String: Any]) {
    if let hook = callbacks.onOpenScreen {
      hook(screenId, params)
    } else {
      missing("open_screen", hook: "onOpenScreen")
    }
  }

  private func openUrl(_ text: String) {
    guard let hook = callbacks.onOpenUrl else { return missing("open_url", hook: "onOpenUrl") }
    guard let url = URL(string: text) else {
      return report("Karnak: dropped an open_url action: '\(text)' is not a URL.")
    }
    hook(url)
  }

  private func custom(_ action: HostCustomAction) {
    if let hook = callbacks.onCustom {
      hook(action.type, action.payload)
    } else {
      missing(action.type, hook: "onCustom")
    }
  }

  private func missing(_ type: String, hook: String) {
    report(
      "Karnak: ignored the '\(type)' action: the host has no \(hook) hook (docs/integration.md, Setup)."
    )
  }
}
