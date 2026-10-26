import Foundation
import KarnakCore

/// Runs one custom action type on the main thread; the payload is the action's resolved JSON values. A
/// ``KarnakPayloadError`` it throws drops the action and logs the field; any other error is logged.
public typealias KarnakCustomActionHandler = @MainActor (_ payload: KarnakPayload) throws -> Void

/// How a custom action that reports back ended (ADR 0031 D5): the outcome `name` its definition declares, or
/// `"cancelled"` when the person backed out, and the `fields` it hands back as JSON host values. The action's
/// `onFinish` handler for `name` runs with the fields as `result.<field>`. An outcome the definition does not declare,
/// or fields that do not fit it, read as `cancelled` and are reported (`custom_action.outcome_invalid`).
public struct KarnakActionOutcome: @unchecked Sendable {
  /// The outcome's name.
  public let name: String
  /// The fields it hands back.
  public let fields: [String: Any]

  /// Creates the outcome `name` with `fields`.
  public init(_ name: String, fields: [String: Any] = [:]) {
    self.name = name
    self.fields = fields
  }

  /// The person backed out of what the handler opened; runs `onFinish.cancelled` when the action has one.
  public static let cancelled = KarnakActionOutcome("cancelled")
}

/// Runs one custom action type that reports back, on the main actor: the node that started the action is busy until
/// it returns, and a second tap is ignored. A ``KarnakPayloadError`` it throws ends the action as `cancelled` and
/// logs the field; any other error ends it as `cancelled` and is logged.
public typealias KarnakOutcomeCustomActionHandler =
  @MainActor (_ payload: KarnakPayload) async throws -> KarnakActionOutcome

/// The handlers of one screen id: the receiver of ``KarnakConfiguration/screenCustomActions(_:_:)``.
public final class KarnakScreenCustomActions {
  var registrations: [CustomActionRegistration] = []

  /// Registers `handler` for the custom action `type` on this screen, where it wins over the app-wide one.
  public func customAction(_ type: String, _ handler: @escaping KarnakCustomActionHandler) {
    registrations.append(CustomActionRegistration(type: type, handler: .runs(handler)))
  }

  /// Registers `handler`, which reports back (ADR 0031 D5), for `type` on this screen.
  public func customActionWithOutcome(
    _ type: String, _ handler: @escaping KarnakOutcomeCustomActionHandler
  ) {
    registrations.append(CustomActionRegistration(type: type, handler: .reports(handler)))
  }

  /// Registers `handler` for `type` with the payload read by `decoder` first: a payload the decoder cannot read ends
  /// the action as `cancelled` and `handler` never runs.
  public func customActionWithOutcome<T>(
    _ type: String, decoder: @escaping @Sendable (KarnakPayload) throws -> T,
    _ handler: @escaping @MainActor (T) async throws -> KarnakActionOutcome
  ) {
    customActionWithOutcome(type) { payload in try await handler(try decoder(payload)) }
  }

  /// Registers `handler` for `type` with the payload read by `decoder` first, as generated code does: a payload the
  /// decoder cannot read drops the action and `handler` never runs.
  public func customAction<T>(
    _ type: String, decoder: @escaping @Sendable (KarnakPayload) throws -> T,
    _ handler: @escaping @MainActor (T) -> Void
  ) {
    customAction(type) { payload in handler(try decoder(payload)) }
  }
}

extension KarnakConfiguration {
  /// Registers `handler` for the custom action `type` app-wide (`docs/integration.md`, Custom actions), such as
  /// `nia.bookmark`. It runs after a screen's own handler for the type (``screenCustomActions(_:_:)``) and before
  /// `onCustom`. Registering announces nothing: the client's `X-Karnak-Actions` lists built-in types whatever is
  /// registered, and the platform judges a custom action by its definition and the app's version.
  ///
  /// A type needs a dot and is registered once: a repeat is developer misuse, which throws when the client is
  /// created in debug and is logged and ignored in release.
  public mutating func customAction(
    _ type: String, _ handler: @escaping KarnakCustomActionHandler
  ) {
    customActions.append(CustomActionRegistration(type: type, handler: .runs(handler)))
  }

  /// Registers `handler`, which reports back (ADR 0031 D5), for the custom action `type` app-wide. Use it for a
  /// definition that declares outcomes: the node that started the action is busy until `handler` returns, an outcome
  /// that does not fit the definition reads as `cancelled`, and the action's `onFinish` handler for the outcome runs.
  public mutating func customActionWithOutcome(
    _ type: String, _ handler: @escaping KarnakOutcomeCustomActionHandler
  ) {
    customActions.append(CustomActionRegistration(type: type, handler: .reports(handler)))
  }

  /// Registers `handler` for `type` app-wide with the payload read by `decoder` first, as generated code does.
  public mutating func customActionWithOutcome<T>(
    _ type: String, decoder: @escaping @Sendable (KarnakPayload) throws -> T,
    _ handler: @escaping @MainActor (T) async throws -> KarnakActionOutcome
  ) {
    customActionWithOutcome(type) { payload in try await handler(try decoder(payload)) }
  }

  /// Registers `handler` for `type` app-wide with the payload read by `decoder` first, as generated code does.
  public mutating func customAction<T>(
    _ type: String, decoder: @escaping @Sendable (KarnakPayload) throws -> T,
    _ handler: @escaping @MainActor (T) -> Void
  ) {
    customAction(type) { payload in handler(try decoder(payload)) }
  }

  /// Registers the handlers of the screen `screenId` (ADR 0021 D21), which win over the app-wide ones on that screen.
  /// A handler is registered per type, so a type the screen does not register falls through to the app-wide one.
  public mutating func screenCustomActions(
    _ screenId: String, _ register: (KarnakScreenCustomActions) -> Void
  ) {
    let screen = KarnakScreenCustomActions()
    register(screen)
    screenCustomActions.append((screenId, screen.registrations))
  }
}

/// One handler registered for a type: one that runs and returns, or one that reports back.
struct CustomActionRegistration: Sendable {
  enum Handler: Sendable {
    case runs(KarnakCustomActionHandler)
    case reports(KarnakOutcomeCustomActionHandler)
  }

  let type: String
  let handler: Handler
}

extension KarnakClientConfig {
  /// Hands the registrations to the Kotlin config; each handler runs on the main thread.
  func register(
    customActions: [CustomActionRegistration],
    screens: [(String, [CustomActionRegistration])], log: @escaping @Sendable (String) -> Void
  ) {
    for registration in customActions {
      switch registration.handler {
      case .runs(let handler):
        customAction(type: registration.type, handler: bridge(registration.type, handler, log))
      case .reports(let handler):
        customActionAsync(
          type: registration.type, handler: bridgeReporting(registration.type, handler, log))
      }
    }
    for (screenId, registrations) in screens {
      for registration in registrations {
        switch registration.handler {
        case .runs(let handler):
          screenCustomAction(
            screenId: screenId, type: registration.type,
            handler: bridge(registration.type, handler, log))
        case .reports(let handler):
          screenCustomActionAsync(
            screenId: screenId, type: registration.type,
            handler: bridgeReporting(registration.type, handler, log))
        }
      }
    }
  }
}

/// The Kotlin handler for the `handler` registered for `type`. On the main thread (a tap) it runs at once and returns the problem the
/// payload had; elsewhere (a flow running an `onFinish`) it hops to the main thread, in order, and a problem is logged.
private func bridge(
  _ type: String, _ handler: @escaping KarnakCustomActionHandler,
  _ log: @escaping @Sendable (String) -> Void
) -> ([String: Any]) -> PayloadProblem? {
  { values in
    nonisolated(unsafe) let values = values
    let run: @MainActor @Sendable () -> KarnakPayloadError? = {
      do {
        try handler(KarnakPayload(values))
        return nil
      } catch let problem as KarnakPayloadError {
        return problem
      } catch {
        log("Karnak: the handler of the '\(type)' action threw: \(error)")
        return nil
      }
    }
    if Thread.isMainThread {
      return MainActor.assumeIsolated(run).map {
        PayloadProblem(pointer: $0.pointer, kind: $0.kind.core)
      }
    }
    DispatchQueue.main.async {
      if let problem = run() {
        log("Karnak: dropped the '\(type)' action: its payload field \(problem).")
      }
    }
    return nil
  }
}

/// The Kotlin handler for a handler that reports back: it runs on the main actor, and tells the engine how it ended
/// exactly once, whatever it throws.
private func bridgeReporting(
  _ type: String, _ handler: @escaping KarnakOutcomeCustomActionHandler,
  _ log: @escaping @Sendable (String) -> Void
) -> ([String: Any], @escaping (CustomActionResult) -> KotlinUnit) -> Void {
  { values, done in
    nonisolated(unsafe) let values = values
    nonisolated(unsafe) let done = done
    Task { @MainActor in
      do {
        let outcome = try await handler(KarnakPayload(values))
        _ = done(CustomOutcome(name: outcome.name, fields: outcome.fields))
      } catch let problem as KarnakPayloadError {
        _ = done(
          PayloadUnreadable(
            problem: PayloadProblem(pointer: problem.pointer, kind: problem.kind.core)))
      } catch {
        log("Karnak: the handler of the '\(type)' action threw: \(error)")
        _ = done(CustomActionFailed(reason: "\(error)"))
      }
    }
  }
}

extension KarnakPayloadProblemKind {
  fileprivate var core: PayloadProblemKind {
    switch self {
    case .required: .required
    case .wrongType: .wrongtype
    case .notInEnum: .notinenum
    }
  }
}
