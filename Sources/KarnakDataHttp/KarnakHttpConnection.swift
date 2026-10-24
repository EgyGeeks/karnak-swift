import Foundation
import KarnakCore
import KarnakSwiftUI

/// A request as an interceptor sees it: the connection's `GET`, with the headers it is about to send.
public struct KarnakHttpRequest: Sendable {
  public var url: String
  public var method: String
  public var headers: [String: String]

  public init(url: String, method: String = "GET", headers: [String: String] = [:]) {
    self.url = url
    self.method = method
    self.headers = headers
  }
}

/// An API the app lets HTTP sources call (ADR 0018, D12): the only place a request's host comes
/// from, and the boundary it must stay inside. Source documents only name a connection; its URL,
/// credentials and kill switch stay in app code.
///
/// ```swift
/// var shop = KarnakHttpConnection(
///   name: "shop_api", baseUrl: "https://api.shop.example/v2", allowedPrefixes: ["/v2/products"])
/// shop.headerProvider = { ["Authorization": "Bearer \(tokens.current)"] }
/// ```
public struct KarnakHttpConnection: Sendable {
  /// What source documents refer to: letters, digits, `_` and `-`, up to 64.
  public var name: String
  /// `https://host[:port][/base/path]`. The host comes only from here; `http` is for
  /// ``isInternal`` connections only.
  public var baseUrl: String
  /// The full paths, base path included, a request may start with, on a segment boundary. With
  /// none, nothing is allowed.
  public var allowedPrefixes: [String]
  /// Whether the API is on a private network, so private addresses and `http` are allowed.
  public var isInternal = false
  /// Marks an app-wide key rather than the user's token: a secret connection is never executed on
  /// the device and its sources are skipped.
  public var isSecret = false
  /// Whether sources may run now, read for every request: switch the connection off from your own
  /// remote config. Default: always on.
  public var isEnabled: @Sendable () -> Bool = { true }
  /// The request headers, such as the user's token, computed for every request off the main thread
  /// and only after the destination was validated. It must return quickly. `X-Karnak-*`,
  /// `Accept-Language` and the framing headers are the SDK's and are ignored.
  public var headerProvider: (@Sendable () -> [String: String])?
  /// Signs or logs requests, run in order after ``headerProvider``. The destination is checked again
  /// on what an interceptor returns, so it cannot move a request to another host or path, or
  /// change its method.
  public var interceptors: [@Sendable (KarnakHttpRequest) -> KarnakHttpRequest] = []
  /// The most requests in flight at once, between 1 and 32. `nil` keeps the default, 4.
  public var maxInFlight: Int?
  /// The deadline of one request in milliseconds. `nil` keeps the default, 4000.
  public var timeoutMillis: Int64?
  /// How long past its freshness a stored response may answer when the API cannot (offline, a
  /// timeout or a `5xx`), in milliseconds, at most 30 days. `nil` keeps `0`: never serve a stale
  /// response.
  public var offlineStaleMillis: Int64?

  public init(name: String, baseUrl: String, allowedPrefixes: [String] = []) {
    self.name = name
    self.baseUrl = baseUrl
    self.allowedPrefixes = allowedPrefixes
  }
}
