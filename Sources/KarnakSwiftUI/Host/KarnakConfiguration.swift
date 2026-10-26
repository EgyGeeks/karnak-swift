import Foundation

/// The static setup of a ``KarnakSwiftClient`` (`docs/integration.md`, Setup): a plain value the
/// host fills in and passes to the client. Creating or changing it does no work.
///
/// ```swift
/// var configuration = KarnakConfiguration(clientKey: "pk_live_…", baseUrl: "https://karnak.example.com")
/// configuration.debug = isDebugBuild
/// configuration.headers["X-App-Build"] = build
/// let karnak = try KarnakSwiftClient(configuration)
/// ```
public struct KarnakConfiguration {
  /// The project environment's public key, sent as `X-Karnak-Client-Key`. Not a secret.
  public var clientKey: String
  /// Where the Karnak server is mounted: an absolute `http(s)` URL with any path prefix.
  public var baseUrl: String
  /// The host app's version, sent as `X-Karnak-App-Version`. `nil` reads `CFBundleShortVersionString`.
  public var appVersion: String?
  /// The host's build mode, not the SDK's: developer misuse, such as a reserved header or params
  /// that can't be sent, throws in debug and is logged in release. `false` by default, since a
  /// library can't see the host's build settings; pass your own `DEBUG` flag.
  public var debug: Bool
  /// Receives diagnostics: every recovery, and misuse in release. `nil` logs with `NSLog`.
  /// It must not throw.
  public var log: (@Sendable (String) -> Void)?
  /// The `Accept-Language` value. `nil` sends the user's preferred languages.
  public var acceptLanguage: String?
  /// Whether newer content replaces what an open screen shows as soon as it arrives.
  public var liveUpdates: Bool
  /// The most a screen's first draw waits for the release sync, in seconds: the first Karnak request of a cold start
  /// carries `X-Karnak-Sync`, and a cached screen waits for its answer, which says which cached screens are out of
  /// date, before it draws. A screen the answer marked stale also waits at most this long for its network answer
  /// before it draws from the cache. `1` by default; `0` turns waiting off. Not negative.
  public var syncWait: TimeInterval
  /// Static headers every request carries. `X-Karnak-*` names belong to the SDK.
  public var headers: [String: String]
  /// Headers computed for every request, for a token that changes. It is called off the main
  /// thread, must return quickly and must not throw: refresh a token beforehand.
  public var headerProvider: (@Sendable () -> [String: String])?
  /// The folder in the app bundle that holds the bundled resources snapshot `karnak resources pull`
  /// wrote (`manifest.json`, `strings/<locale>.json`, `theme.json`): the offline copy of the
  /// strings and colors that ``KarnakSwiftClient/resources`` reads on first launch and without a
  /// network. Add the folder to the app as a blue folder reference. `nil` ships none.
  public var bundledResources: String?
  /// The path in the app bundle of the route manifest `karnak.routes.json`, such as
  /// `"karnak.routes.json"` for a file in the bundle's root (add it to the app target). With a
  /// manifest, a `navigate` to a route it does not declare, or with params of the wrong type, is
  /// dropped and logged and never reaches `onNavigate`. `nil` ships none: routes stay opaque ids.
  public var routeManifest: String?
  /// The route manifest as JSON text, for an app that has it in memory instead of in the bundle.
  /// It wins over ``routeManifest``.
  public var routeManifestJson: String?
  /// The most bytes of screens and themes kept on disk. `nil` keeps the default, 50 MiB.
  public var diskSize: Int64?
  /// About the most bytes of screens kept in memory. `nil` keeps the default, 4 MiB.
  public var memorySize: Int64?
  /// The client-event pipeline (ADR 0022): on by default, every session. See ``KarnakClientEventsConfiguration``.
  public var clientEvents: KarnakClientEventsConfiguration
  /// Hears every new client event, off the main thread (``KarnakListener``). `nil` hears none.
  public var listener: (any KarnakListener)?
  /// Opt-in modules plugged in at the composition root, such as `KarnakDataHttp`'s
  /// `KarnakHttpConnections`. An app that adds none carries none of their Swift code.
  public var modules: [any KarnakClientModule]

  /// The data adapters registered with `dataAdapter(_:_:)`, in order.
  var dataAdapters: [(name: String, adapter: KarnakDataAdapter)] = []

  /// The custom action handlers registered with ``customAction(_:_:)``, in order.
  var customActions: [CustomActionRegistration] = []

  /// The per-screen custom action handlers registered with ``screenCustomActions(_:_:)``, in order.
  var screenCustomActions: [(String, [CustomActionRegistration])] = []

  /// The loading and error views registered with ``screenStates(_:)``.
  var screenStatesFactories = ScreenStatesFactories()

  /// Creates a configuration with the required settings; every other one has its default.
  public init(clientKey: String, baseUrl: String) {
    self.clientKey = clientKey
    self.baseUrl = baseUrl
    debug = false
    liveUpdates = false
    syncWait = 1
    headers = [:]
    clientEvents = KarnakClientEventsConfiguration()
    modules = []
  }
}
