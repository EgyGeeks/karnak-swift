import KarnakCore

/// The setup of the client-event pipeline, ``KarnakConfiguration/clientEvents`` (ADR 0022; `docs/integration.md`, Client
/// events): the SDK reports what goes wrong on a device (a component it cannot draw, a binding that reads nothing, a
/// screen that does not load) to the platform the app already talks to, batched, best effort, and with no value, URL or
/// user data in it. Nothing goes to anyone else.
public struct KarnakClientEventsConfiguration: Sendable {
  /// Whether events are uploaded. On by default: they are the SDK's own errors about the app's own content, sent to
  /// its own platform. Off, nothing is sent and nothing is kept on the device; the ``KarnakListener`` still hears them.
  /// ``KarnakClientEvents/setEnabled(_:)`` changes it at runtime, for an app with a consent screen.
  public var enabled: Bool = true
  /// The share of sessions that upload, 0 to 1; the default 1 uploads them all, as de-duplication already bounds the
  /// volume. The platform can ask for less in a response but never for more than this. One draw at the start of a
  /// session decides all of it, so a session's events stay together. A value outside 0 to 1 makes
  /// ``KarnakSwiftClient/init(_:)`` throw.
  public var sampleRate: Double = 1.0

  /// The defaults: on, every session.
  public init() {}
}

/// The running client-event pipeline of a client, ``KarnakSwiftClient/clientEvents``: switch it at runtime and flush it.
/// The SDK flushes by itself when the app resigns active (`UIApplication.willResignActiveNotification`); an app has no
/// need to.
///
/// Getting it builds the client's parts, as the first screen does, so keep it off construction.
public struct KarnakClientEvents: @unchecked Sendable {
  private let control: ClientEventsControl

  init(_ control: ClientEventsControl) {
    self.control = control
  }

  /// Whether events are uploaded now.
  public var enabled: Bool { control.enabled }

  /// Turns the upload on or off, for example from a consent screen. Off drops the queue, deletes what the SDK kept on
  /// the device and stops sending; the ``KarnakListener`` keeps hearing events. Safe from any thread; never blocks.
  public func setEnabled(_ enabled: Bool) {
    control.setEnabled(enabled: enabled)
  }

  /// Writes the queue to the device and sends what waits at once, without waiting for the batch to fill. Safe from any
  /// thread; never blocks, and the request runs in the background. Does nothing while events are off.
  public func flush() {
    control.flush()
  }
}
