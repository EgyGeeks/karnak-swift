import Foundation
import KarnakCore
import KarnakSwiftUI

/// The credentials a delivered connection may carry, and where they may go (ADR 0015 D12.2). A connection the
/// project adds in the dashboard names a profile by its `name` in its `auth`; the credentials themselves stay in app
/// code, and go only to ``hosts`` and only on ``allowedPrefixes``.
public struct KarnakAuthProfile: Sendable {
  /// The name a delivered connection names in its `auth`: letters, digits, `_` and `-`, up to 64.
  public var name: String
  /// The hosts these credentials may go to: exact names (`api.example.com`) or `*.` and a suffix, 1 to 64.
  public var hosts: [String]
  /// The full paths, base path included, they may be sent on, on a segment boundary. Every prefix of a delivered
  /// connection that names this profile must lie inside one of them.
  public var allowedPrefixes: [String]
  /// The request headers, such as the person's token, computed for every request off the main thread and only after
  /// the destination was validated.
  public var headerProvider: (@Sendable () -> [String: String])?
  /// What a `401` does, as ``KarnakHttpConnection/onUnauthorized``: one run at a time for this profile.
  public var onUnauthorized: (@Sendable () async -> Bool)?

  public init(name: String, hosts: [String], allowedPrefixes: [String]) {
    self.name = name
    self.hosts = hosts
    self.allowedPrefixes = allowedPrefixes
  }
}

/// The app's opt-in to remote connections (ADR 0015 D12.1): connections the project adds in the dashboard reach the
/// app with the screens whose `http` sources name them, so a new backend needs no app release. The app decides what
/// they may call.
///
/// ```swift
/// var remote = KarnakRemoteConnections(hosts: ["api.open-meteo.com"])
/// var shop = KarnakAuthProfile(name: "shopper", hosts: ["api.shop.example.com"], allowedPrefixes: ["/v1"])
/// shop.headerProvider = { ["Authorization": "Bearer \(session.token)"] }
/// shop.onUnauthorized = { await session.refresh() }
/// remote.authProfiles = [shop]
/// configuration.modules = [KarnakHttpConnections([], remote: remote)]
/// ```
///
/// A delivered connection runs only when it passes every check (`https`, a public host, the host in ``hosts`` or in
/// its profile's hosts, its prefixes inside the profile's); otherwise its sources fail under their `error` policy and
/// the client reports `source.connection_refused`. The app's own connection of the same name always wins. Delivered
/// connections are read-only: posts never run on them.
public struct KarnakRemoteConnections: Sendable {
  /// The hosts a delivered connection with no auth profile may reach: exact names or `*.suffix`, at most 64.
  public var hosts: [String]
  /// Whether a delivered connection with no auth profile may reach any public host. Such a host takes literal
  /// request inputs only: a source there that binds a value is refused (`source.request_refused`). Default `false`.
  public var anyPublicHost = false
  /// The auth profiles, at most 16; a name given twice is developer misuse.
  public var authProfiles: [KarnakAuthProfile] = []
  /// Whether delivered connections may run now, read for every request: the app's kill switch. Default: always on.
  public var isEnabled: @Sendable () -> Bool = { true }
  /// Signs or logs delivered connections' requests; the destination is checked again on what it returns.
  public var interceptors: [@Sendable (KarnakHttpRequest) -> KarnakHttpRequest] = []
  /// The most requests one delivered connection has in flight at once, between 1 and 32. `nil` keeps 4.
  public var maxInFlight: Int?
  /// The deadline of one request in milliseconds. `nil` keeps 4000.
  public var timeoutMillis: Int64?
  /// How long past its freshness a stored response may answer when the API cannot, in milliseconds. `nil` keeps `0`.
  public var offlineStaleMillis: Int64?

  public init(hosts: [String] = []) {
    self.hosts = hosts
  }

  func kotlin() -> RemoteConnectionsSwift {
    let kotlin = RemoteConnectionsSwift()
    kotlin.hosts = hosts
    kotlin.anyPublicHost = anyPublicHost
    let enabled = isEnabled
    kotlin.isEnabled = { KotlinBoolean(bool: enabled()) }
    maxInFlight.map { kotlin.maxInFlight = Int32($0) }
    timeoutMillis.map { kotlin.timeoutMillis = $0 }
    offlineStaleMillis.map { kotlin.offlineStaleMillis = $0 }
    for profile in authProfiles {
      kotlin.addAuthProfile(profile: profile.kotlin())
    }
    for sign in interceptors {
      kotlin.addInterceptor(interceptor: KarnakHttpRequest.bridge(sign))
    }
    return kotlin
  }
}

extension KarnakAuthProfile {
  func kotlin() -> AuthProfileSwift {
    let kotlin = AuthProfileSwift(name: name)
    kotlin.hosts = hosts
    kotlin.allowedPrefixes = allowedPrefixes
    headerProvider.map { provider in kotlin.addHeaderProvider(provider: provider) }
    onUnauthorized.map { hook in kotlin.setOnUnauthorized(hook: unauthorizedHook(hook)) }
    return kotlin
  }
}

/// `hook` as the Kotlin face takes it: run in a task, its answer passed to the completion once.
func unauthorizedHook(
  _ hook: @escaping @Sendable () async -> Bool
) -> (@escaping (KotlinBoolean) -> KotlinUnit) -> Void {
  { completion in
    // The Kotlin completion is safe to call from any thread, once.
    nonisolated(unsafe) let completion = completion
    Task {
      let renewed = await hook()
      _ = completion(KotlinBoolean(bool: renewed))
    }
  }
}

extension KarnakHttpRequest {
  /// `sign` as the Kotlin face takes an interceptor.
  static func bridge(
    _ sign: @escaping @Sendable (KarnakHttpRequest) -> KarnakHttpRequest
  ) -> (HttpRequestSwift) -> HttpRequestSwift {
    { request in
      let signed = sign(
        KarnakHttpRequest(url: request.url, method: request.method, headers: request.headers))
      return HttpRequestSwift(url: signed.url, method: signed.method, headers: signed.headers)
    }
  }
}
