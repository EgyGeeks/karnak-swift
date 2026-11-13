import Foundation
import KarnakCore

/// The app's bridge to one analytics vendor (`docs/integration.md`, Analytics destinations): it hands each event the
/// project's tracking plan sends to the destination to the vendor's SDK. Karnak sends nothing to a vendor itself; the
/// bridge is the app's code, so it may filter or enrich the event, and the user's identity stays with the app.
///
/// `send` is called on the thread the screen's `track` runs on (the main thread for a tap), in event order, and must
/// not block. An error it throws loses that event for its destination, is logged and reported once as
/// `analytics.destination_failed`, and the next destination still runs.
public protocol KarnakAnalyticsDestination {
  /// Sends `event` to the vendor.
  func send(_ event: KarnakDestinationEvent) throws
}

/// One event as a destination receives it: named, selected, converted and cut by the tracking plan's rules for that
/// destination. It never holds a value read from a member the data marks `personal`.
public struct KarnakDestinationEvent: @unchecked Sendable {
  /// The key the bridge is registered under, such as `firebase`.
  public let destination: String
  /// The vendor's event name, such as `view_item`: the plan's name for the destination, else ``canonical``.
  public let name: String
  /// The properties under the vendor's names: each value is a `String`, a `Double` or a `Bool`, of a kind the
  /// destination takes, and text is at most the destination's longest value.
  public let properties: [String: Any]
  /// The event's name in the project, as the screen's `track` names it (`listing_viewed`).
  public let canonical: String
}

/// The receiver of ``KarnakConfiguration/analytics(_:)``: the app's analytics destinations by the key the project's
/// tracking plan names them with, and the consent that gates them.
public final class KarnakAnalytics {
  var destinations: [(key: String, destination: any KarnakAnalyticsDestination)] = []
  var consent: ((String) -> Bool)?

  init() {}

  /// Registers `destination` as the bridge of the plan's destination `key`. A key is lowercase letters, digits and
  /// `_`, starting with a letter, at most 64 characters, and registered once: anything else is misuse, which throws
  /// when the client is created in debug and is logged and ignored in release.
  public func destination(_ key: String, _ destination: any KarnakAnalyticsDestination) {
    destinations.append((key, destination))
  }

  /// Registers `send` as the bridge of the plan's destination `key`, as ``destination(_:_:)`` does.
  public func destination(_ key: String, send: @escaping (KarnakDestinationEvent) throws -> Void) {
    destination(key, ClosureDestination(body: send))
  }

  /// Sets the consent check: called before each event is sent to a destination, with its key, on the thread the
  /// `track` runs on; `false` skips the destination for that event, so withdrawing consent stops the next one. Without
  /// it every registered destination is allowed: registering a bridge is the app's yes.
  public func consent(_ allows: @escaping (String) -> Bool) {
    consent = allows
  }
}

extension KarnakConfiguration {
  /// Registers the app's analytics destinations and their consent (``KarnakAnalytics``): each event a screen tracks
  /// goes, besides `onTrack`, to the destinations the project's tracking plan names, through the bridges registered
  /// here. Without a destination the client asks for no plan.
  ///
  /// ```swift
  /// configuration.analytics {
  ///   $0.destination("firebase", FirebaseDestination())
  ///   $0.consent { destination in consentStore.allows(destination) }
  /// }
  /// ```
  public mutating func analytics(_ register: (KarnakAnalytics) -> Void) {
    let analytics = KarnakAnalytics()
    register(analytics)
    analyticsDestinations += analytics.destinations
    analytics.consent.map { analyticsConsent = $0 }
  }
}

extension KarnakClientConfig {
  /// Hands the registrations to the Kotlin config: a bridge's error becomes the failure Kotlin reports. A key registered
  /// twice keeps its first bridge and is `log`ged.
  func register(
    analytics destinations: [(key: String, destination: any KarnakAnalyticsDestination)],
    consent: ((String) -> Bool)?,
    log: (String) -> Void
  ) {
    var bridges: [String: (KarnakCore.KarnakDestinationEvent) -> String?] = [:]
    for (key, destination) in destinations {
      guard bridges[key] == nil else {
        log("Karnak: the analytics destination '\(key)' is registered twice; the first is used.")
        continue
      }
      bridges[key] = { event in Self.send(event, to: destination) }
    }
    guard !bridges.isEmpty || consent != nil else { return }
    analytics(
      destinations: bridges, consent: consent.map { allows in { KotlinBoolean(bool: allows($0)) } })
  }
}

extension KarnakClientConfig {
  /// Sends the Kotlin `event` to `destination` with Swift values; `nil`, or the type of the error it threw.
  fileprivate static func send(
    _ event: KarnakCore.KarnakDestinationEvent, to destination: any KarnakAnalyticsDestination
  ) -> String? {
    let plain = KarnakDestinationEvent(
      destination: event.destination, name: event.name,
      properties: event.properties.mapValues(swiftValue), canonical: event.canonical)
    do {
      try destination.send(plain)
      return nil
    } catch {
      // Only the type: the app's own message may hold a value.
      return "\(type(of: error))"
    }
  }

  /// A Kotlin boolean or number as Swift's own `Bool` or `Double`, which vendors' JSON writes as `true` or a number.
  private static func swiftValue(_ value: Any) -> Any {
    switch value {
    case let flag as KotlinBoolean: flag.boolValue
    case let number as KotlinDouble: number.doubleValue
    default: value
    }
  }
}

private struct ClosureDestination: KarnakAnalyticsDestination {
  let body: (KarnakDestinationEvent) throws -> Void

  func send(_ event: KarnakDestinationEvent) throws {
    try body(event)
  }
}
