import KarnakCore

/// An opt-in module that plugs into the client at the composition root, such as `KarnakDataHttp`'s
/// ``KarnakHttpConnections`` (ADR 0018, D12). Add it to ``KarnakConfiguration/modules``; an app
/// that adds none carries none of the module's Swift code.
public protocol KarnakClientModule: Sendable {
  /// Registers the module on [config], once, while ``KarnakSwiftClient`` is created: after every
  /// other setting is applied, so the module sees the host's `debug` and `log`.
  func install(into config: KarnakClientConfig)
}
