import Foundation
import KarnakCore

/// The Karnak client for Swift: one per app, built from a ``KarnakConfiguration``. It wraps the
/// shared Kotlin client with Swift's own shapes: `async` calls that stop with their task, and
/// params as `[String: Any]`.
///
/// Construction only stores the configuration: no I/O, no threads and no calls to the header
/// provider. The first ``warmUp(prefetch:)``, ``prefetch(_:params:)``, ``setUser(id:attributes:)``,
/// ``clearUser()`` or screen builds the rest, and each part does its I/O off the main thread.
///
/// ```swift
/// let karnak = try KarnakSwiftClient(configuration)
/// Task { try await karnak.warmUp(prefetch: ["home"]) }
/// ContentView().karnakHost(karnak, onNavigate: { screenId, params in … })
/// ```
///
/// The type is `Sendable`: the Kotlin client it holds is safe to call from any thread.
public final class KarnakSwiftClient: @unchecked Sendable {
  private let client: KarnakClient
  private let debug: Bool
  private let log: @Sendable (String) -> Void
  let resourcesCore: ResourcesCore
  let stacks = HostStackRegistry()
  private let signedInState = SignedInState()
  /// The loading and error views the app registered with ``KarnakConfiguration/screenStates(_:)``.
  let screenStates: ScreenStatesRegistry
  /// The installed flows module (`KarnakFlows`), or nil when the app didn't add one.
  let flowModule: KarnakNavigationModule?

  private let navigatorLock = NSLock()
  private var cachedNavigator: KarnakSwiftNavigator?

  /// The SDK's navigation bookkeeping, for a host that implements `onNavigation` and reports the
  /// entries its router drops (`docs/integration.md`, Navigation). The first call builds the
  /// Kotlin client's graph, as the first screen does, so keep it off construction.
  public var navigator: KarnakSwiftNavigator {
    navigatorLock.withLock {
      if let cachedNavigator { return cachedNavigator }
      let made = KarnakSwiftNavigator(
        client.navigator, converter: KarnakParamsConverter(debug: debug, log: log))
      cachedNavigator = made
      return made
    }
  }

  /// The client-event pipeline's switch and flush (``KarnakClientEvents``): the SDK reports what goes wrong on a device to
  /// the platform, and an app with a consent screen turns it off at runtime. Getting it builds the Kotlin client's
  /// graph, as the first screen does, so keep it off construction.
  public var clientEvents: KarnakClientEvents { KarnakClientEvents(client.clientEvents) }

  /// The project's strings and theme colors for your own screens, with the bundled offline copy
  /// (``KarnakConfiguration/bundledResources``). Getting it does no I/O. See
  /// ``KarnakSwiftResources``.
  public var resources: KarnakSwiftResources { KarnakSwiftResources(core: resourcesCore) }

  /// The theme fonts of this client's screens: downloaded and cached by the Kotlin client,
  /// registered with Core Text on first use.
  @MainActor
  lazy var fonts = ThemeFontRegistry(source: ClientFontSource(client))

  /// Creates the client. Throws when the client key is blank, the base URL isn't an absolute
  /// `http(s)` URL, or ``KarnakClientEventsConfiguration/sampleRate`` is outside 0 to 1. It flushes
  /// the client events when the app resigns active.
  public init(_ configuration: KarnakConfiguration) throws {
    let config = KarnakClientConfig(
      clientKey: configuration.clientKey, baseUrl: configuration.baseUrl)
    config.appVersion = configuration.appVersion
    config.debug = configuration.debug
    config.acceptLanguage = configuration.acceptLanguage
    config.liveUpdates = configuration.liveUpdates
    config.bundledResources = configuration.bundledResources
    config.routeManifest = configuration.routeManifest
    config.routeManifestJson = configuration.routeManifestJson
    configuration.diskSize.map { config.diskSize = $0 }
    configuration.memorySize.map { config.memorySize = $0 }
    let log = configuration.log ?? { NSLog("%@", $0) }
    config.log = log
    for registered in configuration.dataAdapters {
      config.dataAdapter(name: registered.name, adapter: DataAdapterBridge(registered.adapter))
    }
    for (name, value) in configuration.headers { config.setHeader(name: name, value: value) }
    configuration.headerProvider.map { provider in config.addHeaderProvider(provider: provider) }
    config.clientEventsEnabled = configuration.clientEvents.enabled
    config.clientEventsSampleRate = configuration.clientEvents.sampleRate
    config.listener = configuration.listener.map(ListenerBridge.init)
    config.contextProvider = signedInState
    for module in configuration.modules { module.install(into: config) }
    flowModule =
      configuration.modules.lazy.compactMap { ($0 as? KarnakFlowModule)?.navigationModule }
      .first
    client = try KarnakClientIosKt.KarnakClient(config: config)
    debug = configuration.debug
    self.log = log
    resourcesCore = ResourcesCore(client: client, debug: configuration.debug, log: log)
    screenStates = ScreenStatesRegistry(
      configuration.screenStatesFactories, debug: configuration.debug, log: log)
  }

  /// Gets the client ready for the first screen, after the first frame: opens the cache,
  /// resolves the current theme and prefetches each of `prefetch`, once. Returns when that ends.
  /// Cancelling the task stops it. Misuse, such as an id of `.` or `..`, throws in debug;
  /// failures are logged.
  public func warmUp(prefetch: [String] = []) async throws {
    try await untilCompleted { completion in
      try self.client.warmUp(prefetch: prefetch, completion: completion)
    }
  }

  /// Loads a screen into the cache the way opening it would, so it opens with current content
  /// at once. Returns when the load ends; cancelling the task stops it. A prefetch and an
  /// open of the same screen and params share one request. Misuse, such as params over 4 KiB
  /// or a value that isn't JSON, throws in debug; failures are logged.
  public func prefetch(_ screenId: String, params: [String: Any] = [:]) async throws {
    let values = try converter.convert(params)
    try await untilCompleted { completion in
      try self.client.prefetch(screenId: screenId, paramValues: values, completion: completion)
    }
  }

  /// Sets the signed-in user, sent with every request for targeting. Another id clears the
  /// previous user's cached screens. Misuse, such as a blank id, throws in debug.
  public func setUser(id: String, attributes: [String: Any] = [:]) throws {
    try client.setUser(id: id, attributeValues: converter.convert(attributes))
  }

  /// Says whether the user is signed in, for the `context.signedIn` binding (`docs/protocol.md`,
  /// Context): `true`, `false`, or `nil` when the app does not say. A change reloads the sources
  /// of the open screens that read it. It carries no credential, and is separate from ``setUser(id:attributes:)``.
  public func setSignedIn(_ signedIn: Bool?) {
    signedInState.set(value: signedIn.map { KotlinBoolean(bool: $0) })
  }

  /// Signs the user out: clears their cached screens and stops sending them.
  public func clearUser() {
    client.clearUser()
  }

  private var converter: KarnakParamsConverter {
    KarnakParamsConverter(debug: debug, log: log)
  }

  /// Runs `start`, which begins background work and returns its cancel handle, and returns when
  /// the work calls its completion. Cancelling the task cancels the handle.
  private func untilCompleted(
    _ start: (@escaping @Sendable () -> Void) throws -> KarnakCancellable
  ) async throws {
    let handle = CancelHandle()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: Continuation) in
        do {
          handle.set(try start { continuation.resume() })
        } catch {
          continuation.resume(throwing: error)
        }
      }
    } onCancel: {
      handle.cancel()
    }
  }
}

extension KarnakSwiftClient: ScreenOpening {
  @MainActor
  func report(_ message: String) {
    log(message)
  }

  @MainActor
  func entryRemoved(_ id: String) {
    navigator.entryRemoved(id)
  }

  @MainActor
  var stackRegistry: HostStackRegistry { stacks }

  @MainActor
  func isOrphanedFlowEntry(_ entryId: String) -> Bool {
    flowModule?.isOrphan(entryId: entryId) ?? false
  }

  @MainActor
  func openFlow(_ request: FlowRequest) throws -> (any FlowSession)? {
    guard let flowModule else {
      report(
        "Karnak: KarnakFlow('\(request.flowId)') needs the flows module: add KarnakFlows() "
          + "(KarnakNavigation) to KarnakConfiguration.modules.")
      return nil
    }
    // The module attaches to the engine when the client builds its graph.
    _ = navigator
    let flow = try flowModule.openRoot(
      flowId: request.flowId, paramValues: converter.convert(request.params),
      receiver: ClosureReceiver(request.receiver))
    return ControllerFlow(flow, session: { ControllerSession($0) })
  }

  @MainActor
  func openScreen(_ request: ScreenRequest) throws -> ScreenSession {
    if let entry = request.entry { return try navigator.open(request, entry: entry) }
    let controller = try client.open(
      screenId: request.screenId, paramValues: converter.convert(request.params),
      environment: request.environment)
    return ControllerSession(controller)
  }
}

/// Holds a Kotlin cancel handle that may arrive after the task was cancelled.
private typealias Continuation = CheckedContinuation<Void, Error>

final class CancelHandle: @unchecked Sendable {
  private let lock = NSLock()
  private var handle: KarnakCancellable?
  private var cancelled = false

  func set(_ handle: KarnakCancellable) {
    lock.lock()
    let alreadyCancelled = cancelled
    self.handle = handle
    lock.unlock()
    if alreadyCancelled { handle.cancel() }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let handle = self.handle
    lock.unlock()
    handle?.cancel()
  }
}

/// The Kotlin client's font cache as a ``FontFileSource``.
private struct ClientFontSource: FontFileSource, @unchecked Sendable {
  private let client: KarnakClient

  init(_ client: KarnakClient) {
    self.client = client
  }

  func fontFile(for face: FontFaceHandle) async -> String? {
    try? await client.fonts.load(face: face.face)?.path
  }
}
