import Foundation
import KarnakCore
import KarnakSwiftUI

/// The HTTP data module (ADR 0018, D12): registers connections on the client, so screens can have
/// `http` sources. Add it to ``KarnakConfiguration/modules`` where the client is built.
///
/// ```swift
/// var configuration = KarnakConfiguration(clientKey: "pk_live_…", baseUrl: "https://karnak.example.com")
/// configuration.modules = [KarnakHttpConnections([shop])]
/// let karnak = try KarnakSwiftClient(configuration)
/// ```
///
/// An invalid connection, or a name registered twice, is developer misuse: the client's
/// initializer throws in debug, and in release it is logged and ignored. An app that doesn't add
/// the module runs no `http` source: a source that names a connection fails on the device under its policy.
public struct KarnakHttpConnections: KarnakClientModule {
  public let connections: [KarnakHttpConnection]

  public init(_ connections: [KarnakHttpConnection]) {
    self.connections = connections
  }

  public func install(into config: KarnakClientConfig) {
    config.setHttpConnections(connections: connections.map(Self.kotlin))
  }

  private static func kotlin(_ connection: KarnakHttpConnection) -> HttpConnectionSwift {
    let kotlin = HttpConnectionSwift(name: connection.name, baseUrl: connection.baseUrl)
    kotlin.allowedPrefixes = connection.allowedPrefixes
    kotlin.isInternal = connection.isInternal
    kotlin.isSecret = connection.isSecret
    let enabled = connection.isEnabled
    kotlin.isEnabled = { KotlinBoolean(bool: enabled()) }
    connection.maxInFlight.map { kotlin.maxInFlight = Int32($0) }
    connection.timeoutMillis.map { kotlin.timeoutMillis = $0 }
    connection.offlineStaleMillis.map { kotlin.offlineStaleMillis = $0 }
    connection.headerProvider.map { provider in kotlin.addHeaderProvider(provider: provider) }
    for sign in connection.interceptors {
      kotlin.addInterceptor { request in
        let signed = sign(
          KarnakHttpRequest(url: request.url, method: request.method, headers: request.headers))
        return HttpRequestSwift(url: signed.url, method: signed.method, headers: signed.headers)
      }
    }
    return kotlin
  }
}
