import KarnakCore
import SwiftUI

/// Reports the current item of a carousel to its `pageChange` trigger (`docs/renderer-contract.md`, Input events):
/// once, with `initial: true`, when it first has a current item, then each time a scroll settles on another item,
/// never per frame. A scroll has settled when nothing has moved for ``settleDelay``. A report is a person's when a drag
/// started the scroll that settled on it; a drag that settles back on the same item is not carried to the next settle.
@MainActor
final class PageChangeReporter {
  /// How long nothing moves before a scroll has settled.
  var settleDelay: Duration = .milliseconds(150)
  /// Receives a report: the carousel's `pageChange` trigger, its payload, and whether a person caused it.
  var send: (_ handle: ActionHandle, _ payload: KarnakValue, _ byUser: Bool) -> Void = { _, _, _ in
  }
  /// The carousel's `pageChange` trigger; a carousel without one reports nothing.
  var handle: ActionHandle?
  /// The keys of the carousel's items, in order.
  var keys: [String] = []
  private var current = 0
  private var reported: Int?
  private var dragged = false
  private var touching = false
  private var timer: Task<Void, Never>?

  /// What the carousel has now: its trigger and its items' keys.
  func update(handle: ActionHandle?, keys: [String]) {
    self.handle = handle
    self.keys = keys
  }

  /// The current item changed or the scroll moved: the report waits until it stops.
  func moved(to index: Int) {
    current = index
    restart()
  }

  /// The scroll moved without changing the current item.
  func scrolling() { restart() }

  /// A finger went down: the scroll that follows is a person's, and it hasn't settled while the finger stays.
  func dragStarted() {
    dragged = true
    touching = true
  }

  /// The finger lifted: the scroll settles once it stops.
  func dragEnded() {
    touching = false
    restart()
  }

  /// Drops a settle that is waiting, for a carousel that has left the screen.
  func cancel() {
    timer?.cancel()
  }

  /// The scroll has settled: reports the current item unless it is the one last reported. A finger still down
  /// is not a settle.
  func settle() {
    timer?.cancel()
    guard !touching else { return }
    defer { dragged = false }
    guard current != reported else { return }
    guard let handle, keys.indices.contains(current) else { return }
    let initial = reported == nil
    send(
      handle, Self.payload(index: current, key: keys[current], initial: initial),
      dragged && !initial)
    reported = current
  }

  private func restart() {
    timer?.cancel()
    timer = Task { [weak self, settleDelay] in
      try? await Task.sleep(for: settleDelay)
      guard !Task.isCancelled else { return }
      self?.settle()
    }
  }

  /// The payload of a `pageChange`: `index`, `id` when the item's key has one, and `initial`.
  static func payload(index: Int, key: String, initial: Bool) -> KarnakValue {
    var fields: [String: KarnakValue] = [
      "index": KarnakValueNumber.make(value: Double(index)),
      "initial": KarnakValueBool.make(value: initial),
    ]
    if key.hasPrefix(idPrefix) {
      fields["id"] = KarnakValueText.make(value: String(key.dropFirst(idPrefix.count)))
    }
    return KarnakValueObject.make(fields: fields)
  }

  private static let idPrefix = "i:"
}
