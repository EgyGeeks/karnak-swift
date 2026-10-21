import Foundation
import KarnakCore

/// A code adapter written in Swift (`docs/integration.md`, Data adapters): app code that fills
/// the model of a screen. It turns the request params of the screen's `adapter` source into a
/// stream of values **in the app's own shape**; the screen's mapper projects each one onto the
/// model, so the adapter never knows the model.
///
/// Register one by name on the configuration, before the client is created:
///
/// ```swift
/// var configuration = KarnakConfiguration(clientKey: "pk_live_…", baseUrl: "https://karnak.example.com")
/// configuration.dataAdapter("cart") { params in
///   cartStore.updates(user: params["user"]?.string).map { cart in
///     KarnakJSON.object(["itemCount": .number(Double(cart.items.count))])
///   }
/// }
/// ```
///
/// The SDK starts the stream when a bound field the adapter fills is first read, and cancels the
/// task that iterates it when the last reader leaves, when the screen is covered by another
/// (``KarnakScreen`` below a pushed destination, or the app leaving the foreground), and when it
/// closes. The stream should stop its work when its task is cancelled; `AsyncStream`'s
/// `onTermination` and `Task.isCancelled` both work. Each element replaces the previous one, so a
/// slow screen may skip to the latest. A stream that throws is started again once and then fails
/// the fields it fills; no message or value of the error is logged.
public struct KarnakDataAdapter: Sendable {
  typealias Emit = @Sendable (KarnakJSON) throws -> Void
  let run: @Sendable ([String: KarnakJSON], Emit) async throws -> Void

  /// An adapter over the stream `make` builds for each start, with the request params.
  public init<S: AsyncSequence>(
    _ make: @escaping @Sendable ([String: KarnakJSON]) -> S
  ) where S.Element == KarnakJSON {
    run = { params, emit in
      for try await value in make(params) { try emit(value) }
    }
  }

  /// An adapter that emits `Encodable` models, encoded as JSON in the adapter's own shape. Dates
  /// and keys use `JSONEncoder`'s defaults: emit a `KarnakJSON` when the shape must be exact.
  public init<S: AsyncSequence>(
    encoding make: @escaping @Sendable ([String: KarnakJSON]) -> S
  ) where S.Element: Encodable {
    run = { params, emit in
      let encoder = JSONEncoder()
      for try await model in make(params) {
        let json = try JSONDecoder().decode(KarnakJSON.self, from: encoder.encode(model))
        try emit(json)
      }
    }
  }
}

extension KarnakConfiguration {
  /// Registers the data adapter `name` (nonblank, without `,` or whitespace): the name the
  /// server's `adapter` source uses, announced to the server so it only sends sources this app
  /// can run. A bad or repeated name throws when the client is created in debug and is logged and
  /// ignored in release. `make` builds the stream for each start of the adapter, given the
  /// request params the source names.
  public mutating func dataAdapter<S: AsyncSequence>(
    _ name: String, _ make: @escaping @Sendable ([String: KarnakJSON]) -> S
  ) where S.Element == KarnakJSON {
    dataAdapters.append((name, KarnakDataAdapter(make)))
  }

  /// Registers the data adapter `name` over a stream of `Encodable` models; see
  /// ``KarnakDataAdapter/init(encoding:)``.
  public mutating func dataAdapter<S: AsyncSequence>(
    _ name: String, encoding make: @escaping @Sendable ([String: KarnakJSON]) -> S
  ) where S.Element: Encodable {
    dataAdapters.append((name, KarnakDataAdapter(encoding: make)))
  }
}

/// The Kotlin ``SwiftDataAdapter`` that runs a ``KarnakDataAdapter`` in a task per start.
final class DataAdapterBridge: NSObject, SwiftDataAdapter, @unchecked Sendable {
  private let adapter: KarnakDataAdapter

  init(_ adapter: KarnakDataAdapter) {
    self.adapter = adapter
  }

  func start(params: KarnakValueObject, sink: SwiftDataSink) -> KarnakCancellable {
    let request = params.fields.mapValues(KarnakJSON.init)
    nonisolated(unsafe) let sink = sink
    let adapter = adapter
    let task = Task {
      do {
        try await adapter.run(request) { value in
          try Task.checkCancellation()
          // A value JSON cannot hold (a NaN) fails the stream, as a throw does.
          guard let converted = value.karnakValue() else { throw InvalidEmission() }
          sink.value(value: converted)
        }
        if !Task.isCancelled { sink.finish() }
      } catch {
        if !Task.isCancelled { sink.fail() }
      }
    }
    return TaskHandle(task)
  }
}

/// What ends a stream that emitted something JSON cannot express.
private struct InvalidEmission: Error {}

/// Cancels a task through a Kotlin ``KarnakCancellable``.
private final class TaskHandle: NSObject, KarnakCancellable, @unchecked Sendable {
  private let task: Task<Void, Never>

  init(_ task: Task<Void, Never>) {
    self.task = task
  }

  func cancel() {
    task.cancel()
  }
}
