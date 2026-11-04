import Foundation
import KarnakCore

/// One submission of a form, as a form handler gets it (`docs/integration.md`, Form handlers in the app). The values
/// are by input name, passwords included: never log them.
public struct KarnakFormSubmission: @unchecked Sendable {
  /// The screen the form is on.
  public let screenId: String
  /// The form's id.
  public let formId: String
  /// The screen's revision, empty when it has none.
  public let revision: String
  /// The screen's params, as JSON host values.
  public let params: [String: Any]
  /// The form's values by input name, as JSON host values.
  public let values: [String: Any]
  /// The submission's `Idempotency-Key`: the same for a retry of identical values after a failure.
  public let idempotencyKey: String
}

/// One action of a submit response: at most 5, the immediate ones (``toast(_:)``, ``track(_:properties:)``) first and at
/// most one final action last (`docs/protocol.md`, Submission). The engine drops and reports an action that breaks it.
public struct KarnakSubmitAction: @unchecked Sendable {
  let json: [String: Any]

  /// The action whose wire JSON is `json`, such as `["type": "open_screen", "screenId": "orders"]`.
  public init(json: [String: Any]) { self.json = json }

  /// An immediate action: shows `message` as a toast.
  public static func toast(_ message: String) -> Self {
    Self(json: ["type": "show_toast", "message": message])
  }

  /// An immediate action: sends `event` with `properties` to the app's analytics.
  public static func track(_ event: String, properties: [String: Any] = [:]) -> Self {
    Self(json: ["type": "track", "event": event, "properties": properties])
  }

  /// A final action: ends the screen with `outcome` and `result` for whoever opened it (a flow, a caller).
  public static func finish(_ outcome: String = "done", result: [String: Any] = [:]) -> Self {
    Self(json: ["type": "finish", "outcome": outcome, "result": result])
  }

  /// A final action: closes the sheet or dialog the form is in, or goes back from a full screen.
  public static let dismiss = Self(json: ["type": "dismiss"])

  /// A final action: opens the Karnak screen `screenId` with `params`.
  public static func openScreen(_ screenId: String, params: [String: Any] = [:]) -> Self {
    Self(json: ["type": "open_screen", "screenId": screenId, "params": params])
  }
}

/// A form handler's answer: the same submit response a server sends (`docs/protocol.md`, Submission).
public struct KarnakSubmitResponse: @unchecked Sendable {
  let json: [String: Any]

  /// The form was accepted: `reset` clears it first, then `actions` run in order.
  public static func ok(_ actions: [KarnakSubmitAction] = [], reset: Bool = false) -> Self {
    Self(json: ["status": "ok", "actions": actions.map(\.json), "reset": reset])
  }

  /// The form was refused: `fieldErrors` by input name show on the inputs, `formError` as a toast.
  public static func invalid(
    fieldErrors: [String: String] = [:], formError: String? = nil
  ) -> Self {
    var json: [String: Any] = ["status": "invalid", "fieldErrors": fieldErrors]
    if let formError { json["formError"] = formError }
    return Self(json: json)
  }

  /// The response as JSON text, or `nil` when a value in it is no JSON value.
  var text: String? {
    guard JSONSerialization.isValidJSONObject(json),
      let data = try? JSONSerialization.data(withJSONObject: json)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// Answers the submissions of one form id in the app instead of the server: sign-in, whose password stays in the app.
/// It runs off the main thread and owns its timeouts. When the screen closes first it runs to its end, and its answer
/// is dropped. What it throws, or an answer that is no submit response, fails
/// the submission: the button's `failureMessage`, else the host's `onSubmitError`.
public typealias KarnakFormHandler =
  @Sendable (_ submission: KarnakFormSubmission) async throws -> KarnakSubmitResponse

/// A form handler as registered: for one screen, or for every screen when `screenId` is `nil`.
struct FormHandlerRegistration: Sendable {
  let screenId: String?
  let formId: String
  let handler: KarnakFormHandler
}

extension KarnakConfiguration {
  /// Registers `handler` for the form `formId` on every screen (`docs/integration.md`, Form handlers in the app; ADR
  /// 0034 D2): its submissions go to `handler` and no request is sent. Form ids are unique only within a screen, so
  /// pick a distinctive one or use ``screenFormHandlers(_:_:)``. A repeat is developer misuse, which throws when the
  /// client is created in debug and is logged in release, the last one winning.
  ///
  /// ```swift
  /// configuration.formHandler("sign_in") { submission in
  ///   try await auth.signIn(submission.values["email"] as? String, submission.values["password"] as? String)
  ///     ? .ok([.finish("signed_in")]) : .invalid(formError: strings.wrongPassword)
  /// }
  /// ```
  public mutating func formHandler(_ formId: String, _ handler: @escaping KarnakFormHandler) {
    formHandlers.append(FormHandlerRegistration(screenId: nil, formId: formId, handler: handler))
  }

  /// Registers the form handlers of the screen `screenId`, which win over ``formHandler(_:_:)`` on that screen.
  ///
  /// ```swift
  /// configuration.screenFormHandlers("login") { screen in
  ///   screen.formHandler("sign_in") { submission in try await auth.answer(submission) }
  /// }
  /// ```
  public mutating func screenFormHandlers(
    _ screenId: String, _ register: (KarnakScreenFormHandlers) -> Void
  ) {
    let screen = KarnakScreenFormHandlers(screenId)
    register(screen)
    formHandlers += screen.registrations
  }
}

/// The form handlers of one screen id: the receiver of ``KarnakConfiguration/screenFormHandlers(_:_:)``.
public final class KarnakScreenFormHandlers {
  let screenId: String
  var registrations: [FormHandlerRegistration] = []

  init(_ screenId: String) { self.screenId = screenId }

  /// Registers `handler` for the form `formId` on this screen.
  public func formHandler(_ formId: String, _ handler: @escaping KarnakFormHandler) {
    registrations.append(
      FormHandlerRegistration(screenId: screenId, formId: formId, handler: handler))
  }
}

extension KarnakClientConfig {
  /// Hands the form handlers to the Kotlin config: each runs in a task and answers with its response's JSON.
  func register(formHandlers: [FormHandlerRegistration]) {
    for registration in formHandlers {
      formHandler(
        formId: registration.formId, screenId: registration.screenId,
        handler: bridgeForm(registration.handler))
    }
  }
}

/// The Kotlin handler for `handler`: it calls `done` exactly once, with the response's JSON or why it failed.
private func bridgeForm(
  _ handler: @escaping KarnakFormHandler
) -> (FormSubmission, @escaping (String?, String?) -> KotlinUnit) -> Void {
  { submission, done in
    let plain = KarnakFormSubmission(
      screenId: submission.screenId, formId: submission.formId, revision: submission.revision,
      params: submission.params, values: submission.values,
      idempotencyKey: submission.idempotencyKey)
    nonisolated(unsafe) let done = done
    Task {
      do {
        let response = try await handler(plain)
        // An answer that is no JSON is passed as empty text: no submit response, an invalid response.
        _ = done(response.text ?? "", nil)
      } catch {
        // Only the type: the app's own message may hold a value.
        _ = done(nil, "the form handler threw \(type(of: error))")
      }
    }
  }
}
