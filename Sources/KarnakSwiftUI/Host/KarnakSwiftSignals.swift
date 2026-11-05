import KarnakCore

/// A signal as ``KarnakSwiftSignals/observe(_:)`` delivers it: its name and, when the change is about one record, the
/// record's key. It carries no data.
public struct KarnakSignal: Sendable, Equatable {
  /// The signal's name, such as `cart.changed`.
  public let name: String
  /// The record the change is about, or `nil` when it is not about one record.
  public let key: String?
}

/// Signals on this device (`docs/integration.md`, Signals), ``KarnakSwiftClient/signals``: a way for the app's code to
/// say that something changed, such as `cart.changed`, and to hear it. A signal carries no data and never leaves the
/// app's process. The sources of the screens that subscribe with `refreshOn` refresh when a matching signal is raised,
/// here or by a `signal` action, and a screen that opens later still refreshes what a signal made old.
///
/// ```swift
/// try karnak.signals.raise("cart.changed")  // after a native purchase
/// for await _ in karnak.signals.observe("cart.changed") { badge.reload() }
/// ```
///
/// Getting it builds the client's parts, as the first screen does, so keep it off construction. The value is safe to
/// use from any thread.
public struct KarnakSwiftSignals: @unchecked Sendable {
  private let signals: Signals

  init(_ signals: Signals) {
    self.signals = signals
  }

  /// Raises the signal `name`, about the record `key` when given. `name` is 1 to 4 lower-case segments joined by dots
  /// (`cart.changed`); `key` is 1 to 128 characters. A subscription without a key matches every signal of the name; one
  /// with a key matches that key and a signal raised without one.
  ///
  /// A `name` or `key` that breaks that is developer misuse: it throws in debug and is logged and ignored in release.
  public func raise(_ name: String, key: String? = nil) throws {
    try signals.raiseSignal(name: name, key: key)
  }

  /// The signals named `name` as they are raised, from the app's code and from `signal` actions: the stream yields the
  /// signals raised after this returns. It never finishes by itself; cancelling the task that iterates it, or releasing
  /// both the stream and its iterator, stops the collection.
  public func observe(_ name: String) -> AsyncStream<KarnakSignal> {
    AsyncStream { continuation in
      let subscription = SignalSubscription(
        signals.observe(name: name) { signal in
          continuation.yield(KarnakSignal(name: signal.name, key: signal.key))
        })
      continuation.onTermination = { _ in subscription.cancel() }
    }
  }
}

private final class SignalSubscription: @unchecked Sendable {
  private let subscription: KarnakCancellable
  init(_ subscription: KarnakCancellable) { self.subscription = subscription }
  func cancel() { subscription.cancel() }
}
