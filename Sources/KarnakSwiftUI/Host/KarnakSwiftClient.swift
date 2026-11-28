import Foundation
import KarnakCore

/// The Karnak client for Swift: one per app, built from a ``KarnakConfiguration``. It wraps the
/// shared Kotlin client with Swift's own shapes: `async` calls that stop with their task, and
/// params as `[String: Any]`.
///
/// Construction only stores the configuration: no I/O, no threads and no calls to the header
/// provider. The first ``warmUp(prefetch:sources:)``, ``prefetch(_:params:sources:)``, ``setSession(signedIn:)``,
/// ``setUser(id:attributes:)`` or screen builds the rest, and each part does its I/O off the main thread.
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
  package let stacks = HostStackRegistry()
  /// The loading and error views the app registered with ``KarnakConfiguration/screenStates(_:)``.
  let screenStates: ScreenStatesRegistry
  /// The custom components the app registered with ``KarnakConfiguration/components(_:)``.
  let components: ComponentRegistry
  /// The installed flows module (`KarnakFlows`), or nil when the app didn't add one.
  package let flowModule: KarnakNavigationModule?

  /// What tells this client's saved state from another client's in the same app: its server and client key.
  let savedStateScope: String

  private let navigatorLock = NSLock()
  private var cachedNavigator: KarnakSwiftNavigator?

  /// The SDK's navigation bookkeeping, for a host that implements `onNavigation` and reports the
  /// entries its router drops (`docs/integration.md`, Navigation). The first call builds the
  /// Kotlin client's graph, as the first screen does, so keep it off construction.
  public var navigator: KarnakSwiftNavigator {
    navigatorLock.withLock {
      if let cachedNavigator { return cachedNavigator }
      let made = KarnakSwiftNavigator(
        client.navigator, converter: KarnakParamsConverter(debug: debug, log: log), report: log)
      cachedNavigator = made
      return made
    }
  }

  /// The client-event pipeline's switch and flush (``KarnakClientEvents``): the SDK reports what goes wrong on a device to
  /// the platform, and an app with a consent screen turns it off at runtime. Getting it builds the Kotlin client's
  /// graph, as the first screen does, so keep it off construction.
  public var clientEvents: KarnakClientEvents { KarnakClientEvents(client.clientEvents) }

  /// Signals on this device: raise `cart.changed` after a change the app made, and hear the signals raised
  /// (``KarnakSwiftSignals``). Screens whose sources subscribe with `refreshOn` refresh on them. Getting it builds the
  /// Kotlin client's graph, as the first screen does, so keep it off construction.
  public var signals: KarnakSwiftSignals { KarnakSwiftSignals(client.signals) }

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
    components = ComponentRegistry(configuration.componentRenderers)
    config.renderer = SwiftRendererProfile.make(
      loadingLabel: config.renderer.loadingLabel, custom: components.types)
    config.appVersion = configuration.appVersion
    config.debug = configuration.debug
    config.acceptLanguage = configuration.acceptLanguage
    config.acceptLanguageProvider = configuration.acceptLanguageProvider
    config.liveUpdates = configuration.liveUpdates
    config.syncWait = Self.milliseconds(of: configuration.syncWait)
    config.bundledResources = configuration.bundledResources
    config.routeManifest = configuration.routeManifest
    config.routeManifestJson = configuration.routeManifestJson
    config.loadingScreen = configuration.loadingScreen
    configuration.diskSize.map { config.diskSize = $0 }
    configuration.memorySize.map { config.memorySize = $0 }
    let log = configuration.log ?? { NSLog("%@", $0) }
    config.log = log
    for registered in configuration.dataAdapters {
      config.dataAdapter(name: registered.name, adapter: DataAdapterBridge(registered.adapter))
    }
    config.register(
      customActions: configuration.customActions, screens: configuration.screenCustomActions,
      log: log)
    config.register(formHandlers: configuration.formHandlers)
    config.register(
      analytics: configuration.analyticsDestinations, consent: configuration.analyticsConsent,
      log: log)
    for (name, value) in configuration.headers { config.setHeader(name: name, value: value) }
    configuration.headerProvider.map { provider in config.addHeaderProvider(provider: provider) }
    config.register(signIn: configuration.onSignInRequired)
    config.refreshToken = configuration.refreshToken.map(refreshTokenBridge)
    config.clientEventsEnabled = configuration.clientEvents.enabled
    config.clientEventsSampleRate = configuration.clientEvents.sampleRate
    config.listener = configuration.listener.map(ListenerBridge.init)
    for module in configuration.modules { module.install(into: config) }
    flowModule =
      configuration.modules.lazy.compactMap { ($0 as? KarnakFlowModule)?.navigationModule }
      .first
    client = try KarnakClientIosKt.KarnakClient(config: config)
    debug = configuration.debug
    self.log = log
    savedStateScope = "\(configuration.baseUrl) \(configuration.clientKey)"
    resourcesCore = ResourcesCore(client: client, debug: configuration.debug, log: log)
    screenStates = ScreenStatesRegistry(
      configuration.screenStatesFactories, debug: configuration.debug, log: log,
      loadingScreen: { [client] in client.currentLoadingScreen })
  }

  /// Gets the client ready for the first screen, after the first frame: opens the cache,
  /// resolves the current theme and prefetches each of `prefetch`, once. Returns when that ends.
  /// Cancelling the task stops it. Misuse, such as an id of `.` or `..`, throws in debug;
  /// failures are logged.
  ///
  /// With `sources`, `true` by default, each prefetched screen's data sources that cache (the `http` sources) are
  /// fetched too, once each under their own cache rules, so the screen draws their answers in its first frame instead
  /// of its section skeletons: they are the screens the app shows first, whose sources load a moment later anyway.
  public func warmUp(prefetch: [String] = [], sources: Bool = true) async throws {
    try await untilCompleted { completion in
      try self.client.warmUp(prefetch: prefetch, sources: sources, completion: completion)
    }
  }

  /// Loads a screen into the cache the way opening it would, so it opens with current content
  /// at once. Returns when the load ends; cancelling the task stops it. A prefetch and an
  /// open of the same screen and params share one request. Misuse, such as params over 4 KiB
  /// or a value that isn't JSON, throws in debug; failures are logged.
  ///
  /// With `sources` the screen's data sources that cache are fetched too, as ``warmUp(prefetch:sources:)`` does;
  /// `false` by default, since a screen prefetched on a guess may never open.
  public func prefetch(
    _ screenId: String, params: [String: Any] = [:], sources: Bool = false
  ) async throws {
    let values = try converter.convert(params)
    try await untilCompleted { completion in
      try self.client.prefetch(
        screenId: screenId, paramValues: values, sources: sources, completion: completion)
    }
  }

  /// Says whether the person is signed in, the one write of the session (`docs/integration.md`,
  /// Sign-in gate): `true` for a real account and `false` for a guest or nobody. Call it at start,
  /// then `true` on every sign-in and `false` on every sign-out; an account switch is a sign-out and
  /// then a sign-in. Until the first call the sign-in gate treats the person as signed out. A
  /// sign-out clears everything personal, a sign-in clears nothing, and each screen that needs
  /// sign-in loads again from the network on every change; a locked screen loads in place once this
  /// says signed in.
  public func setSession(signedIn: Bool) {
    client.setSession(signedIn: signedIn)
  }

  /// Sets the user the server targets (`X-Karnak-User`): `id` or `nil`, and its targeting
  /// `attributes`. It clears nothing and says nothing about the session: call it just before
  /// each ``setSession(signedIn:)`` with `true`, so the screens the sign-in loads ask as that
  /// user, since a sign-out forgets it.
  /// Misuse, such as a blank id, throws in debug.
  public func setUser(id: String?, attributes: [String: Any] = [:]) throws {
    try client.setUser(id: id, attributeValues: converter.convert(attributes))
  }

  /// Tells the client the language its ``KarnakConfiguration/acceptLanguageProvider`` answers changed: every open
  /// screen loads again in it, and the app's resources reload their strings. Content stays until the new copy
  /// arrives. Cached screens are kept per language, so a screen of the old language never shows for the new one;
  /// this call only makes open screens fetch now. Call it from the app's language setter.
  public func languageChanged() {
    client.languageChanged()
  }

  /// The keys of the analytics destinations this session's tracking plan delivers `event` to
  /// (`docs/integration.md`, Moving from onTrack to destinations): each destination whose plan
  /// rules send the event and that ``KarnakConfiguration/analytics(_:)`` registers. Empty without
  /// a destination, before the session holds a plan, or when no rule sends the event. The consent
  /// check doesn't change it, so a forwarder that skips these keys never sends a vendor what the
  /// person refused it. Call it from `onTrack`:
  ///
  /// ```swift
  /// onTrack: { event, properties in
  ///   guard !karnak.plannedDestinations(event).contains("firebase") else { return }
  ///   Analytics.logEvent(event, parameters: properties)
  /// }
  /// ```
  ///
  /// It reads memory only, on any thread. Calling it builds the Kotlin client's graph, as the
  /// first screen does.
  public func plannedDestinations(_ event: String) -> Set<String> {
    client.plannedDestinations(event: event)
  }

  /// `seconds` as the whole milliseconds the Kotlin client takes. A wait that is not a finite number
  /// passes as one the client refuses, so it throws like a negative one instead of trapping here.
  private static func milliseconds(of seconds: TimeInterval) -> Int64 {
    let milliseconds = (seconds * 1000).rounded()
    return Int64(exactly: milliseconds) ?? (milliseconds > 0 ? Int64.max : -1)
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
  package func report(_ message: String) {
    log(message)
  }

  @MainActor
  package func entryRemoved(_ id: String) {
    navigator.entryRemoved(id)
  }

  @MainActor
  package var stackRegistry: HostStackRegistry { stacks }

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
  func restoreDetail(_ screens: [SavedPaneScreen]) -> (any StackSession)? {
    navigator.restoreDetail(screens).map { ControllerStack($0, session: { ControllerSession($0) }) }
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

extension KarnakSwiftClient {
  /// The tab bar of `form` as the project's theme styles it (ADR 0045, D12), from the theme the
  /// client holds or the SDK's baseline, with no I/O.
  package func tabBarStyle(
    _ form: KarnakTabBarForm, dark: Bool, rtl: Bool, icons: [String]
  ) -> ResolvedTabBarStyle {
    client.tabBarStyle(form: form, mode: dark ? .dark : .light, rtl: rtl, icons: icons)
  }

  /// The background of a sheet the SDK presents outside any screen, such as a tab bar action item's (ADR 0047, D10):
  /// the theme's surface as the engine's ARGB, from the theme the client holds or the SDK's baseline, with no I/O.
  package func overlaySurface(dark: Bool) -> Int32 {
    client.overlayStyle(mode: dark ? .dark : .light).surface.value
  }

  /// The project's theme the client holds (`nil` while it holds none): the one now, then each time it holds another
  /// (from ``loadTheme()`` or any screen's load), on the main thread.
  package func themes() -> AsyncStream<ScreenTheme?> {
    AsyncStream { continuation in
      let handle = CancelHandle()
      handle.set(
        client.observeTheme { held in
          // A Kotlin ScreenTheme is immutable once made: handing it to the stream's reader shares nothing mutable.
          nonisolated(unsafe) let theme = held
          continuation.yield(theme)
        })
      continuation.onTermination = { _ in handle.cancel() }
    }
  }

  /// Loads the app's theme in the background; returns whether one decoded.
  package func loadTheme() async -> Bool {
    let handle = CancelHandle()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        handle.set(client.loadTheme { continuation.resume(returning: $0.boolValue) })
      }
    } onCancel: {
      handle.cancel()
    }
  }
}

extension KarnakClientConfig {
  /// Calls the app's `onSignInRequired`, `hook`, on the main actor with each request wrapped; `nil` sets none.
  fileprivate func register(signIn hook: (@MainActor @Sendable (KarnakSignInRequest) -> Void)?) {
    guard let hook else { return }
    onSignInRequired = { request in
      let wrapped = KarnakSignInRequest(request)
      Task { @MainActor in hook(wrapped) }
    }
  }
}
