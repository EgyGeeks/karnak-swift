import KarnakCore

/// What ``KarnakLinkHandler`` did with a URI (`docs/links.md`, Matching; ADR 0017, D7). The app
/// acts on ``notKarnak`` and ``rejected(reason:param:)`` itself; ``opened`` needs nothing more.
public enum KarnakLinkResult: Equatable, Sendable {
  /// The URI matched a pattern with valid params and its target was handed to the host's hooks
  /// (a screen or a flow on the host's stack, a native route, or a static URL through
  /// `onOpenUrl`). `opened` means the target was handed over, not that something is on screen: a
  /// screen marked `auth: "required"` shows its sign-in placeholder to someone signed out.
  case opened
  /// The URI is not one the link table owns, or no pattern has its shape: pass it to your own
  /// router.
  case notKarnak
  /// The URI must not be opened and must not be passed on: it is ours but unsafe or malformed,
  /// or it matched a pattern's shape and failed its params.
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

/// The app's options for links (`docs/links.md`). A link opens for everyone: a screen that needs a
/// signed-in user is marked `auth: "required"` and gates itself, whichever way it was opened.
public struct KarnakLinkOptions: Sendable {
  /// The app's tabs, when it has bottom navigation (`docs/integration.md`, Bottom navigation): a
  /// link whose pattern names a tab shows that tab popped to its root and opens there. Give it
  /// `KarnakTabStore.links`. Nil, the default, opens every link where it came from.
  public nonisolated(unsafe) var tabs: (any LinkTabs)?

  /// Creates the options.
  public init(tabs: (any LinkTabs)? = nil) {
    self.tabs = tabs
  }

  /// The Kotlin options these are.
  var kotlin: LinkOptions { LinkOptions(tabs: tabs) }
}
