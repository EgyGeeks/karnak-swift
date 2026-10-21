import KarnakCore

/// The app's hook into what the SDK notices (ADR 0022): `configuration.listener = ClosureKarnakListener { event in … }`.
/// Today it hears the client events, so an app can forward them to Crashlytics, Sentry or Datadog; the load timings
/// and cache hits of the observability work join as further members with default bodies.
///
/// It is called **once per new event key**: the first occurrence of a code at a place with an outcome in the session,
/// which is exactly the stream that creates upload entries. An app that wants every occurrence reads the debug log. It
/// is called on the client's own queue, never the main thread, in order, whether or not events are uploaded
/// (``KarnakClientEventsConfiguration/enabled``) and in a build with no network. It must not block.
public protocol KarnakListener: AnyObject, Sendable {
  /// Hears `event`.
  func onEvent(_ event: KarnakEvent)
}

extension KarnakListener {
  /// Does nothing: a listener says which members it wants by implementing them.
  public func onEvent(_ event: KarnakEvent) {}
}

/// A ``KarnakListener`` made of a closure, for the common case of hearing the events only.
///
/// ```swift
/// configuration.listener = ClosureKarnakListener { event in
///   crashlytics.log("karnak \(event.code) \(event.subject)")
/// }
/// ```
public final class ClosureKarnakListener: KarnakListener {
  private let handler: @Sendable (KarnakEvent) -> Void

  /// A listener that calls `onEvent` for every new event.
  public init(onEvent: @escaping @Sendable (KarnakEvent) -> Void) {
    handler = onEvent
  }

  public func onEvent(_ event: KarnakEvent) {
    handler(event)
  }
}

/// A client event as the listener hears it (`docs/protocol.md#client-events`). It carries the fields the upload carries
/// and nothing more, so a listener that forwards it forwards no more than the SDK sends: catalogue constants, authored
/// identifiers (a screen key, a node type, a JSON Pointer), the normalised node key and numbers. Never a value read
/// from data, a URL, a header or a message.
///
/// Besides the catalogue's codes there is one local code, `events.dropped`: the SDK lost ``count`` occurrences because
/// the session held too many keys or the queue was full (at most once a minute). It is never uploaded.
public struct KarnakEvent: Sendable, Equatable {
  /// The catalogue code, such as `node.unknown_type`.
  public let code: String
  /// The screen key, or `""` for an event of the project (a theme).
  public let screen: String
  /// The screen's revision as served (a theme's for a `theme.*` event); `nil` when there is none.
  public let revision: String?
  /// The node's key with the row key of a `repeat` removed; `nil` when the event is not about a node.
  public let nodeKey: String?
  /// The wire type of the node; `nil` when the event is not about a node's type.
  public let nodeType: String?
  /// What identifies the problem within a screen; `""` when the code has none.
  public let subject: String
  /// The closed class of the code (`unknown`, `network/dns`); `nil` when the code has none.
  public let detailClass: String?
  /// An authored identifier that says more, such as the pointer of an invalid field; `nil` when none.
  public let detail: String?
  /// What the SDK did about it (`fallback_shown`, `removed`, `failed`, …).
  public let outcome: String
  /// How many times it happened: 1 for a new key, the number lost for `events.dropped`.
  public let count: Int
  /// The protocol platform: `ios` here.
  public let platform: String
  /// The host app's version.
  public let appVersion: String
  /// The SDK's version.
  public let sdkVersion: String
  /// Whether the event was queued for upload: `false` when events are off, the session is sampled out, the server
  /// turned them off, the SDK points at a preview, or the event never leaves the device.
  public let uploaded: Bool

  /// An event with the given fields, for an app's own tests of its listener.
  public init(
    code: String, screen: String = "", revision: String? = nil, nodeKey: String? = nil,
    nodeType: String? = nil, subject: String = "", detailClass: String? = nil,
    detail: String? = nil, outcome: String, count: Int = 1, platform: String = "ios",
    appVersion: String = "0.0.0", sdkVersion: String = "0.0.0", uploaded: Bool = true
  ) {
    self.code = code
    self.screen = screen
    self.revision = revision
    self.nodeKey = nodeKey
    self.nodeType = nodeType
    self.subject = subject
    self.detailClass = detailClass
    self.detail = detail
    self.outcome = outcome
    self.count = count
    self.platform = platform
    self.appVersion = appVersion
    self.sdkVersion = sdkVersion
    self.uploaded = uploaded
  }

  init(_ event: KarnakCore.KarnakEvent) {
    self.init(
      code: event.code, screen: event.screen, revision: event.revision, nodeKey: event.nodeKey,
      nodeType: event.nodeType, subject: event.subject, detailClass: event.detailClass,
      detail: event.detail, outcome: event.outcome, count: Int(event.count),
      platform: event.platform, appVersion: event.appVersion, sdkVersion: event.sdkVersion,
      uploaded: event.uploaded)
  }
}

/// The Kotlin client's listener, calling the app's.
final class ListenerBridge: NSObject, KarnakCore.KarnakListener, @unchecked Sendable {
  private let listener: any KarnakListener

  init(_ listener: any KarnakListener) {
    self.listener = listener
  }

  func onEvent(event: KarnakCore.KarnakEvent) {
    listener.onEvent(KarnakEvent(event))
  }
}
