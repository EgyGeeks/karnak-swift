import KarnakCore

/// Why a screen couldn't be loaded, for the host's error UI.
public struct KarnakScreenError: Error, Equatable, Sendable {
  /// What went wrong.
  public enum Kind: Sendable {
    /// The server couldn't be reached.
    case network
    /// The request took too long.
    case timeout
    /// The screen doesn't exist.
    case notFound
    /// The server, or the SDK before sending, refused the request: a bad client key, params or
    /// preview token, or a screen opened outside `.karnakHost`.
    case rejected
    /// The server failed.
    case server
    /// The response isn't a screen this SDK can read: malformed, over a limit or in a newer schema.
    case invalidResponse
    /// The screen loaded, but a data source of a section that holds the whole screen (a `data`
    /// boundary with `onError: "screen"`, ADR 0026) failed with nothing to show. Retrying reloads
    /// only the sources that failed.
    case data
    /// The screen source failed without saying why, or the error is of a kind this SDK doesn't know.
    case source
  }

  /// What went wrong.
  public let kind: Kind
  /// Diagnostic text for logs, never for display.
  public let message: String

  /// Creates an error of `kind` with the diagnostic `message`.
  public init(kind: Kind, message: String) {
    self.kind = kind
    self.message = message
  }

  init(_ error: ScreenError) {
    self.init(kind: Kind(error.kind), message: error.message)
  }
}

extension KarnakScreenError.Kind {
  fileprivate init(_ kind: ScreenErrorKind) {
    switch kind {
    case .network: self = .network
    case .timeout: self = .timeout
    case .notfound: self = .notFound
    case .rejected: self = .rejected
    case .server: self = .server
    case .invalidresponse: self = .invalidResponse
    case .data: self = .data
    default: self = .source
    }
  }
}
