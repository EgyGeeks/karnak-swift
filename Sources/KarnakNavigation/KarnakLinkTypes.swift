import KarnakCore

/// What ``KarnakLinkHandler`` did with a URI (`docs/links.md`, Matching; ADR 0017, D7). The app
/// acts on ``notKarnak`` and ``rejected(reason:param:)`` itself; ``opened`` needs nothing more.
public enum KarnakLinkResult: Equatable, Sendable {
  /// The URI matched a pattern with valid params and its target was handed to the host's hooks
  /// (a screen or a flow on the host's stack, a native route, or a static URL through
  /// `onOpenUrl`), or, for an `auth: "required"` pattern with nobody signed in, to the app's
  /// sign-in: it opens when ``KarnakLinkContinuation/resume()`` is called. `opened` means the
  /// target was handed over, not that something is on screen.
  case opened
  /// The URI is not one the link table owns, or no pattern has its shape: pass it to your own
  /// router.
  case notKarnak
  /// The URI must not be opened and must not be passed on: it is ours but unsafe or malformed,
  /// it matched a pattern's shape and failed its params, or it needs a signed-in user and the
  /// app gave no way to sign in (`reason` is `sign_in_required`).
  ///
  /// - Parameters:
  ///   - reason: The wire name of the reason, such as `encoded_slash` or `param_invalid`.
  ///   - param: The name of the param for a param reason, never its value; nil otherwise.
  case rejected(reason: String, param: String?)
}

extension KarnakLinkResult {
  init(_ result: LinkResult) {
    switch result {
    case let rejected as LinkResultRejected:
      self = .rejected(reason: rejected.reason, param: rejected.param)
    case is LinkResultNotKarnak:
      self = .notKarnak
    default:
      self = .opened
    }
  }
}

/// The app's side of the links auth gate (`docs/links.md`, Gates). The gate is user experience,
/// not authorisation: the target screen's own requests still carry the user's credentials to
/// your backend.
public struct KarnakLinkOptions: Sendable {
  /// Whether a user is signed in now. A pattern with `auth: "required"` opens only when this is
  /// true. Read each time a link needs it, on any thread; nobody is signed in by default.
  public var signedIn: @Sendable () -> Bool
  /// Called, on the main thread, when a link needs a signed-in user and ``signedIn`` is false.
  /// Show your sign-in and call ``KarnakLinkContinuation/resume()`` once the user is signed in, or
  /// ``KarnakLinkContinuation/cancel()`` when they gave up. Nil, the default, rejects such a link
  /// as `sign_in_required`.
  public var onSignInRequired: (@MainActor @Sendable (KarnakLinkContinuation) -> Void)?

  /// Creates the options.
  public init(
    signedIn: @escaping @Sendable () -> Bool = { false },
    onSignInRequired: (@MainActor @Sendable (KarnakLinkContinuation) -> Void)? = nil
  ) {
    self.signedIn = signedIn
    self.onSignInRequired = onSignInRequired
  }

  /// The Kotlin options these are.
  var kotlin: LinkOptions {
    let signedIn = signedIn
    guard let onSignInRequired else {
      return LinkOptions(signedIn: { KotlinBoolean(bool: signedIn()) }, onSignInRequired: nil)
    }
    return LinkOptions(
      signedIn: { KotlinBoolean(bool: signedIn()) },
      onSignInRequired: { continuation in
        // The engine may call from its own dispatcher: the app's sign-in is main-thread work.
        nonisolated(unsafe) let waiting = continuation
        Task { @MainActor in onSignInRequired(KarnakLinkContinuation(waiting)) }
      })
  }
}

/// A link that waits for the user to sign in. ``resume()`` opens it once, if
/// ``KarnakLinkOptions/signedIn`` is true by then; ``cancel()`` drops it. Whichever comes first
/// decides and later calls do nothing, so a sign-in screen may call either without tracking it.
@MainActor
public final class KarnakLinkContinuation {
  private let continuation: LinkContinuation

  init(_ continuation: LinkContinuation) {
    self.continuation = continuation
  }

  /// The user signed in: opens the link, unless it was resumed or cancelled already or nobody is
  /// signed in.
  public func resume() { continuation.resume() }

  /// The user did not sign in: the link is dropped.
  public func cancel() { continuation.cancel() }
}
