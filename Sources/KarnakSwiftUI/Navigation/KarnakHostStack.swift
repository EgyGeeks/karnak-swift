import Foundation
import SwiftUI

/// One entry of the host stack that `.karnakDestinations()` draws: the screen to show and the id
/// the SDK gave the entry.
struct KarnakStackEntry: Identifiable {
  let id: String
  /// A screen of the SDK, or a native route a flow runs.
  let target: KarnakNavigationTarget
  let params: [String: Any]
  /// Who hears how the entry ended, when native code opened it (``KarnakSwiftClient/open(_:params:)``).
  let receiver: ((_ outcome: String, _ result: [String: Any]) -> Void)?

  /// The id of the screen the entry shows; nil for a native route.
  var screenId: String? {
    if case .screen(let id) = target { id } else { nil }
  }

  /// The native route the entry shows; nil for a screen.
  var route: KarnakRouteTarget? {
    if case .route(let id, let handle) = target {
      KarnakRouteTarget(id: id, params: params, handle: handle)
    } else {
      nil
    }
  }
}

/// The entries `.karnakDestinations()` pushed on a `NavigationStack`, bottom first, and the
/// operations of ADR 0017's host column that change them (`docs/integration.md`, Navigation).
/// The stack's views follow ``entries``: a pop is a shorter list, a swipe back reports the
/// entries it dropped.
///
/// A push while another is on its way in waits: operations run one at a time, each once the
/// previous push has appeared (or after a short timeout), so none is dropped. An `open` identical
/// to one on its way in or waiting (a double tap) is the exception: it is dropped, and its entry
/// reported removed, so a second tap never pushes the same screen twice.
@MainActor
final class KarnakHostStack: ObservableObject, KarnakEntryHost {
  @Published private(set) var entries: [KarnakStackEntry] = []

  /// Tells the SDK the host dropped an entry (``KarnakSwiftNavigator/entryRemoved(_:)``).
  var entryRemoved: (String) -> Void = { _ in }
  /// Goes back out of the stack: `back` with nothing left to pop.
  var leave: () -> Void = {}
  /// Logs a diagnostic.
  var report: (String) -> Void = { NSLog("%@", $0) }

  private var shown: [Int: KarnakStackEntry] = [:]
  private var nativeReceivers: [String: OnceReceiver] = [:]
  private var inFlight: String?
  /// What the push on its way in opens, to tell a second identical request.
  private var inFlightKey: OpenKey?
  private var draining = false
  private var waiting: [Waiting] = []
  private let settleAfter: Duration
  private let transition: Duration

  /// - Parameters:
  ///   - settleAfter: How long a push may take to appear before the next operation runs anyway.
  ///   - transition: How long the push animation takes after the view appeared: the next
  ///     operation waits for it, as a push over a screen that is still sliding in is lost.
  init(settleAfter: Duration = .milliseconds(1500), transition: Duration = .milliseconds(450)) {
    self.settleAfter = settleAfter
    self.transition = transition
  }

  /// Runs the host-stack part of `request`. Overlays are not the host's: a `modal` or `sheet`
  /// that reaches it opens as a push.
  func perform(_ request: KarnakNavigation) {
    let key = OpenKey(request)
    if let key, key == inFlightKey || waiting.contains(where: { $0.key == key }) {
      if case .open(let entryId, _, _, _) = request {
        report("Karnak: dropped an open identical to one on its way in (a double tap).")
        entryRemoved(entryId)
      }
      return
    }
    schedule(key) { [self] in
      switch request {
      case .open(let entryId, let target, let params, let presentation):
        open(
          KarnakStackEntry(id: entryId, target: target, params: params, receiver: nil),
          presentation, key: key)
      case .back(let screen, let toRoot, let before):
        back(to: screen, root: toRoot, before: before)
      }
    }
  }

  /// Pushes a screen native code asked for; `receiver` hears how it ended, once.
  func push(
    _ screenId: String, params: [String: Any], entryId: String,
    receiver: @escaping (String, [String: Any]) -> Void
  ) {
    let once = OnceReceiver(receiver)
    nativeReceivers[entryId] = once
    let entry = KarnakStackEntry(
      id: entryId, target: .screen(screenId), params: params,
      receiver: { outcome, result in
        MainActor.assumeIsolated { once.deliver(outcome, result) }
      })
    schedule { [self] in open(entry, .push) }
  }

  /// Removes `entryId` and everything above it, as native code asked (`karnak.open`'s task was
  /// cancelled).
  func remove(_ entryId: String) {
    schedule { [self] in back(to: nil, root: false, before: entryId) }
  }

  /// The user swiped back, or SwiftUI popped: the entries from `depth` up are gone.
  func popped(toDepth depth: Int) {
    guard entries.count > depth else { return }
    truncate(to: depth)
    drain()
  }

  /// The entry at `depth`, or the one that was there until it left, so its screen doesn't
  /// vanish before the pop animation ends.
  func entry(at depth: Int) -> KarnakStackEntry? {
    if entries.indices.contains(depth) { shown[depth] = entries[depth] }
    return shown[depth]
  }

  /// Whether a screen drawn at `depth` has an entry above it.
  func isCovered(at depth: Int) -> Bool {
    entries.count > depth
  }

  /// The view of entry `id` is on screen: once its transition ends, the next waiting operation
  /// may run.
  func appeared(_ id: String) {
    guard inFlight == id else { return }
    if transition == .zero {
      settled(id)
    } else {
      Task { [weak self, transition] in
        try? await Task.sleep(for: transition)
        self?.settled(id)
      }
    }
  }

  private func settled(_ id: String) {
    guard inFlight == id else { return }
    inFlight = nil
    inFlightKey = nil
    drain()
  }

  // MARK: - Operations

  private func open(
    _ entry: KarnakStackEntry, _ presentation: KarnakPresentation, key: OpenKey? = nil
  ) {
    switch presentation {
    case .replace where !entries.isEmpty:
      truncate(to: entries.count - 1)
      push(entry, key: key)
    case .reset:
      truncate(to: 0)
      push(entry, key: key)
    default:
      if presentation == .modal || presentation == .sheet {
        report("Karnak: opened a \(presentation) screen as a push: this stack has no overlay.")
      } else if presentation == .replace {
        report("Karnak: opened a replace as a push: the root of the stack cannot be replaced.")
      }
      push(entry, key: key)
    }
  }

  private func push(_ entry: KarnakStackEntry, key: OpenKey? = nil) {
    entries.append(entry)
    inFlight = entry.id
    inFlightKey = key
    Task { [weak self, settleAfter, id = entry.id] in
      try? await Task.sleep(for: settleAfter)
      self?.settled(id)
    }
  }

  private func back(to screenId: String?, root: Bool, before: String?) {
    if let before {
      guard let index = entries.firstIndex(where: { $0.id == before }) else {
        return report("Karnak: ignored a back before '\(before)': no entry of this stack has it.")
      }
      truncate(to: index)
    } else if let screenId {
      guard let index = entries.lastIndex(where: { $0.screenId == screenId }) else {
        return report("Karnak: ignored a back to '\(screenId)': no entry of this stack shows it.")
      }
      truncate(to: index + 1)
    } else if root {
      truncate(to: 0)
    } else if entries.isEmpty {
      leave()
    } else {
      truncate(to: entries.count - 1)
    }
  }

  /// Keeps the first `count` entries and reports the others, deepest first.
  private func truncate(to count: Int) {
    let removed = entries[count...]
    entries.removeSubrange(count...)
    if let flying = inFlight, !entries.contains(where: { $0.id == flying }) {
      inFlight = nil
      inFlightKey = nil
    }
    for entry in removed.reversed() {
      entryRemoved(entry.id)
      // The engine delivered if the entry's screen had opened; if not, nobody else will.
      nativeReceivers.removeValue(forKey: entry.id)?.deliver("cancelled", [:])
    }
  }

  // MARK: - Queue

  private func schedule(_ key: OpenKey? = nil, _ operation: @escaping () -> Void) {
    waiting.append(Waiting(key: key, run: operation))
    drain()
  }

  private func drain() {
    // An operation that makes a request of its own (a receiver's handler) waits for its turn.
    guard !draining else { return }
    draining = true
    defer { draining = false }
    while inFlight == nil, !waiting.isEmpty {
      waiting.removeFirst().run()
    }
  }
}

/// An operation of the stack's queue, and what it opens when it is an `open`.
private struct Waiting {
  let key: OpenKey?
  let run: () -> Void
}

/// What an `open` request shows and how, to tell a second identical one: the target, the params in
/// the client's canonical form, and the presentation. `nil` for a `back`.
struct OpenKey: Equatable {
  let target: String
  let params: String
  let presentation: String

  init?(_ request: KarnakNavigation) {
    guard case .open(_, let target, let params, let presentation) = request else { return nil }
    switch target {
    case .screen(let id): self.target = "screen:\(id)"
    case .route(let id, _): self.target = "route:\(id)"
    }
    self.params = SessionKey(screenId: "", params: params, opener: nil).params
    self.presentation = "\(presentation)"
  }
}

/// Delivers to its receiver once, whoever asks first: the engine, or the stack for an entry whose
/// screen never opened.
@MainActor
final class OnceReceiver {
  private var receiver: ((String, [String: Any]) -> Void)?

  init(_ receiver: @escaping (String, [String: Any]) -> Void) {
    self.receiver = receiver
  }

  func deliver(_ outcome: String, _ result: [String: Any]) {
    let target = receiver
    receiver = nil
    target?(outcome, result)
  }
}

/// A stack native code can open screens on: the `.karnakDestinations()` stack, or a
/// ``KarnakNavigationCoordinator``.
@MainActor
protocol KarnakEntryHost: AnyObject {
  /// Pushes `screenId` as the entry `entryId`; `receiver` hears how it ended, once.
  func push(
    _ screenId: String, params: [String: Any], entryId: String,
    receiver: @escaping (String, [String: Any]) -> Void)
  /// Removes `entryId` and the entries above it.
  func remove(_ entryId: String)
  /// Performs a navigation request, such as the screen a link opens.
  func perform(_ request: KarnakNavigation)
}
