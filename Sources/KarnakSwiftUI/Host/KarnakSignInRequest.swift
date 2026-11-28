import Foundation
import KarnakCore

/// The app's sign-in is needed before something the screen's author declared runs: an action marked as needing
/// sign-in was tapped by someone signed out, or a signed-in request got a final `401`. Show the app's sign-in, then
/// call ``resume()`` or ``cancel()`` (`docs/integration.md`, Sign-in gate).
///
/// The first of ``resume()`` and ``cancel()`` decides; later calls do nothing. Both are safe from any thread.
public struct KarnakSignInRequest: Sendable {
  /// What was gated.
  public enum Kind: Sendable, Equatable {
    /// A custom action; ``KarnakSignInRequest/key`` is its type, such as `acme.cart.add`.
    case customAction
    /// A screen that needs sign-in was shown to someone signed out, or its placeholder's button was pressed; the key
    /// is the screen id. It only notifies: the screen stays locked until ``KarnakSwiftClient/setSession(signedIn:)``
    /// says signed in, then it loads in place.
    case screen
    /// A `post`; the key is the post's key.
    case post
    /// A source whose request got a final `401`; the key is the source's name.
    case data
  }

  /// What was gated.
  public let kind: Kind
  /// The custom action type, screen id, post key or source name.
  public let key: String
  /// The author's reason code, such as `cart`, which the app maps to its own sign-in copy; `nil` for none.
  public let reason: String?

  private let request: SignInRequestBox

  init(_ request: any SignInRequest) {
    kind = Kind(request.kind)
    key = request.key
    reason = request.reason
    self.request = SignInRequestBox(request)
  }

  /// The person signed in: runs the gated action once, as it was tapped. Call
  /// ``KarnakSwiftClient/setSession(signedIn:)`` first: it runs only when the client then says signed in, and after
  /// a `401` only for the same account.
  public func resume() { request.value.resume() }

  /// The person gave up: the action does not run, and what it does when cancelled runs instead.
  public func cancel() { request.value.cancel() }
}

/// The Kotlin request, which is thread-safe, carried across actors.
private final class SignInRequestBox: @unchecked Sendable {
  let value: any SignInRequest

  init(_ value: any SignInRequest) { self.value = value }
}

extension KarnakSignInRequest.Kind {
  fileprivate init(_ kind: SignInKind) {
    switch kind {
    case .customaction: self = .customAction
    case .screen: self = .screen
    case .post: self = .post
    default: self = .data
    }
  }
}
