import Foundation
import KarnakCore
import SwiftUI

/// The Kotlin resources behind ``KarnakSwiftResources``, with Swift's shapes: `[String: Any]` args,
/// dynamic colors and an `AsyncStream`. `resources` is `nil` for the value outside `.karnakHost`.
final class ResourcesCore: @unchecked Sendable {
  private let make: () -> KarnakCore.KarnakResources?
  private let converter: KarnakParamsConverter
  private let log: @Sendable (String) -> Void
  private let lock = NSLock()
  private var made: KarnakCore.KarnakResources?
  private var used = false
  private var onFirstUse: [@Sendable () -> Void] = []
  private var firstSnapshot: KarnakResourceSnapshot?

  /// Resources over a client. Pay for what you use: the Kotlin resources are read from the client
  /// (which turns them on) the first time something asks for a string, a color or an update.
  convenience init(
    client: KarnakClient, debug: Bool, log: @escaping @Sendable (String) -> Void
  ) {
    self.init(make: { client.resources }, debug: debug, log: log)
  }

  /// Fixed resources, or `nil` for the value outside `.karnakHost`.
  convenience init(
    resources: KarnakCore.KarnakResources?, debug: Bool, log: @escaping @Sendable (String) -> Void
  ) {
    self.init(make: { resources }, debug: debug, log: log)
  }

  private init(
    make: @escaping () -> KarnakCore.KarnakResources?, debug: Bool,
    log: @escaping @Sendable (String) -> Void
  ) {
    self.make = make
    self.log = log
    converter = KarnakParamsConverter(debug: debug, log: log)
  }

  /// Calls `action` once, the first time anything reads the resources (at once if that happened).
  func whenFirstUsed(_ action: @escaping @Sendable () -> Void) {
    lock.lock()
    let alreadyUsed = used
    if !alreadyUsed { onFirstUse.append(action) }
    lock.unlock()
    if alreadyUsed { action() }
  }

  /// The Kotlin resources; reading them for the first time turns them on.
  private var resources: KarnakCore.KarnakResources? {
    lock.lock()
    if made == nil { made = make() }
    let resources = made
    let first = !used
    used = true
    if first { firstSnapshot = resources?.current }
    let callbacks = first ? onFirstUse : []
    if first { onFirstUse = [] }
    lock.unlock()
    // The first use starts the first load, off the main thread.
    if first { _ = resources?.whenReady(completion: {}) }
    for callback in callbacks { callback() }
    return resources
  }

  /// The content now.
  var current: ResourceContent { ResourceContent(resources?.current) }

  func string(_ key: String, args: [String: Any]) -> String {
    guard let resources else { return key }
    do {
      return try resources.string(key: key, argValues: converter.convert(args))
    } catch {
      log("Karnak resources: the args of \"\(key)\" were left out: \(error)")
      return (try? resources.string(key: key, argValues: KarnakValueObject.make(fields: [:])))
        ?? key
    }
  }

  /// The updates after the content there is now, or, with `sinceFirstUse`, after the content the
  /// first reader saw, so a load that ends before the observer starts is not missed.
  func updates(sinceFirstUse: Bool = false) -> AsyncStream<KarnakResourcesUpdate> {
    guard let resources else { return AsyncStream { $0.finish() } }
    let baseline = lock.withLock { firstSnapshot }
    return AsyncStream { continuation in
      let initial = (sinceFirstUse ? baseline : nil) ?? resources.current
      let subscription = SubscriptionBox(
        resources.observe { snapshot in
          if snapshot !== initial { continuation.yield(ResourceContent(snapshot).update) }
        })
      continuation.onTermination = { _ in subscription.cancel() }
    }
  }

  func whenReady(_ completion: @escaping @Sendable () -> Void) -> KarnakCancellable? {
    resources.map { $0.whenReady(completion: completion) }
  }

  func whenRefreshed(_ completion: @escaping @Sendable () -> Void) -> KarnakCancellable? {
    resources.map { $0.whenRefreshed(completion: completion) }
  }

  /// Runs `start`, which begins background work and returns its cancel handle, and returns when the
  /// work calls its completion. Cancelling the task cancels the handle.
  func untilCompleted(
    _ start: (@escaping @Sendable () -> Void) -> KarnakCancellable?
  ) async {
    let handle = CancelHandle()
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        guard let cancellable = start({ continuation.resume() }) else {
          continuation.resume()
          return
        }
        handle.set(cancellable)
      }
    } onCancel: {
      handle.cancel()
    }
  }
}

/// A snapshot of the Kotlin content as Swift values.
struct ResourceContent {
  let locale: String?
  let layoutDirection: SwiftUI.LayoutDirection
  let stringsRevision: String?

  init(_ snapshot: KarnakResourceSnapshot?) {
    locale = snapshot?.locale
    layoutDirection = snapshot?.layoutDirection == .rtl ? .rightToLeft : .leftToRight
    stringsRevision = snapshot?.stringsRevision
  }

  var update: KarnakResourcesUpdate {
    KarnakResourcesUpdate(
      locale: locale, layoutDirection: layoutDirection, stringsRevision: stringsRevision)
  }
}

private final class SubscriptionBox: @unchecked Sendable {
  private let subscription: KarnakCancellable
  init(_ subscription: KarnakCancellable) { self.subscription = subscription }
  func cancel() { subscription.cancel() }
}
