import KarnakSwiftUI
import SwiftUI

/// One Karnak entry of a path your app owns (`NavigationStack(path:)`, `docs/integration.md`, Navigation on iOS): what
/// ``Swift/Array/performKarnakNavigation(_:navigator:rootScreen:)`` puts on the path for an `open`. Draw it with
/// ``KarnakPathScreen``. Two entries are equal when they have the same ``id``, the SDK's entry id, so the path's
/// `Hashable` stays cheap and its params need not be.
public struct KarnakPathEntry: Hashable, Identifiable {
  /// The SDK's id of the entry (the `entryId` of the request that opened it).
  public let id: String
  /// The Karnak screen, or the native route of a flow step, the entry shows.
  public let target: KarnakNavigationTarget
  /// The params it was opened with, as JSON values.
  public let params: [String: Any]

  init(id: String, target: KarnakNavigationTarget, params: [String: Any]) {
    self.id = id
    self.target = target
    self.params = params
  }

  /// The Karnak screen the entry shows; nil for a native route step.
  public var screenId: String? {
    if case .screen(let id) = target { id } else { nil }
  }

  public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

  public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A value of your app's typed path that can hold a Karnak entry, so
/// ``Swift/Array/performKarnakNavigation(_:navigator:rootScreen:)`` performs Karnak's requests on that path. An enum with a
/// `karnak` case conforms with one property:
///
/// ```swift
/// enum Route: KarnakPathElement {
///   case product(Int)
///   case karnak(KarnakPathEntry)
///
///   var karnakEntry: KarnakPathEntry? {
///     if case .karnak(let entry) = self { entry } else { nil }
///   }
/// }
/// ```
///
/// ``KarnakPathEntry`` conforms itself, for a path of Karnak entries only.
public protocol KarnakPathElement: Hashable {
  /// The path value that shows `entry`.
  static func karnak(_ entry: KarnakPathEntry) -> Self
  /// The Karnak entry this value shows; nil for one of your own destinations.
  var karnakEntry: KarnakPathEntry? { get }
}

extension KarnakPathEntry: KarnakPathElement {
  /// `entry` itself.
  public static func karnak(_ entry: KarnakPathEntry) -> KarnakPathEntry { entry }
  /// The entry itself.
  public var karnakEntry: KarnakPathEntry? { self }
}

extension Array where Element: KarnakPathElement {
  /// Performs `request`, what a Karnak screen asked of your router (`.karnakHost(client, onNavigation:)`), on this
  /// path: the SwiftUI twin of Android's `performKarnakNavigation`, for an app that owns its stack with
  /// `NavigationStack(path: $path)` and any number of paths (one per tab). The path holds the entries above the
  /// stack's root view.
  ///
  /// - `open` appends `.karnak(entry)`: `replace` swaps the last value (on an empty path it appends, as the root view
  ///   can't be replaced), `reset` empties the path and appends, and every other presentation (`modal`, `sheet` and
  ///   `detail`, which reach you only with `overlays: .host`) is a push, the documented downgrade of a router with no
  ///   overlay.
  /// - `back` removes the last value, the values above the last entry showing `screen`, every value (`root`), or
  ///   the entry `before` and every value above it. A `back` to `rootScreen`, the screen your stack's root view shows,
  ///   empties the path when no entry of it shows that screen. One that names a screen or an entry the path doesn't
  ///   have is logged and does nothing.
  ///
  /// Every Karnak entry it removes is reported to `navigator` (``KarnakSwiftNavigator/entryRemoved(_:)``), so its
  /// opener hears `cancelled`. The values the user removes (the swipe back, the back button) are yours to report:
  /// ``KarnakSwiftNavigator/pathChanged(from:to:)`` in an `onChange(of: path)` does it.
  ///
  /// ```swift
  /// .karnakHost(karnak, onNavigation: { request in
  ///   if !path.performKarnakNavigation(request, navigator: karnak.navigator) { dismiss() }
  /// })
  /// ```
  ///
  /// - Returns: `true` when the request was handled; `false` for a `back` on an empty path, which is yours to decide
  ///   (close the screen the stack is in, leave the tab).
  @discardableResult
  public mutating func performKarnakNavigation(
    _ request: KarnakNavigation, navigator: KarnakSwiftNavigator, rootScreen: String? = nil
  ) -> Bool {
    performKarnakNavigation(
      request, rootScreen: rootScreen, entryRemoved: navigator.entryRemoved,
      report: navigator.report)
  }

  /// ``performKarnakNavigation(_:navigator:rootScreen:)`` with the reports as closures, for tests.
  mutating func performKarnakNavigation(
    _ request: KarnakNavigation, rootScreen: String? = nil, entryRemoved: (String) -> Void,
    report: (String) -> Void
  ) -> Bool {
    switch request {
    case .open(let entryId, let target, let params, let presentation):
      let element = Element.karnak(KarnakPathEntry(id: entryId, target: target, params: params))
      switch presentation {
      case .replace where !isEmpty: truncate(to: count - 1, entryRemoved)
      case .reset: truncate(to: 0, entryRemoved)
      default: break
      }
      append(element)
      return true
    case .back(let screen, let root, let before):
      // The root view shows `rootScreen` and is no value of the path: a back to it is a back to the root.
      let toRoot = screen != nil && screen == rootScreen && !shows(screen)
      guard
        let kept = kept(
          screen: toRoot ? nil : screen, root: root || toRoot, before: before, report: report)
      else {
        return true
      }
      guard kept >= 0 else { return false }
      truncate(to: kept, entryRemoved)
      return true
    }
  }

  /// How many values a `back` keeps: nil when it names what the path doesn't have (logged), -1 when it would pop an
  /// empty path.
  private func kept(
    screen: String?, root: Bool, before: String?, report: (String) -> Void
  ) -> Int? {
    if let before {
      guard let index = firstIndex(where: { $0.karnakEntry?.id == before }) else {
        report("Karnak: ignored a back before '\(before)': no entry of the path has it.")
        return nil
      }
      return index
    }
    if let screen {
      guard let index = lastIndex(where: { $0.karnakEntry?.screenId == screen }) else {
        report("Karnak: ignored a back to '\(screen)': no entry of the path shows it.")
        return nil
      }
      return index + 1
    }
    if root { return 0 }
    return isEmpty ? -1 : count - 1
  }

  /// Whether an entry of the path shows `screen`.
  private func shows(_ screen: String?) -> Bool {
    contains { $0.karnakEntry?.screenId == screen }
  }

  /// Keeps the first `kept` values and reports the Karnak entries of the others, deepest first.
  private mutating func truncate(to kept: Int, _ entryRemoved: (String) -> Void) {
    let removed = self[kept...].reversed().compactMap(\.karnakEntry?.id)
    removeSubrange(kept...)
    removed.forEach(entryRemoved)
  }
}

extension KarnakSwiftNavigator {
  /// Reports the Karnak entries that `old` had and `new` hasn't: call it from `onChange(of: path)` so the entries the
  /// user pops (the swipe back, the back button) end, and their openers hear `cancelled`. Reporting an entry that
  /// ``Swift/Array/performKarnakNavigation(_:navigator:rootScreen:)`` already reported does nothing.
  ///
  /// ```swift
  /// NavigationStack(path: $path) { … }
  ///   .onChange(of: path) { old, new in karnak.navigator.pathChanged(from: old, to: new) }
  /// ```
  public func pathChanged<Element: KarnakPathElement>(from old: [Element], to new: [Element]) {
    for id in Self.removed(from: old, to: new) { entryRemoved(id) }
  }

  /// The ids of the Karnak entries of `old` that `new` hasn't, deepest first.
  static func removed<Element: KarnakPathElement>(
    from old: [Element], to new: [Element]
  ) -> [String] {
    let kept = Set(new.compactMap(\.karnakEntry?.id))
    return old.reversed().compactMap(\.karnakEntry?.id).filter { !kept.contains($0) }
  }
}

/// The view of a ``KarnakPathEntry``: the Karnak screen it shows, bound to its entry, or the native screen you
/// registered for its route with ``SwiftUI/View/karnakRoute(_:content:)``, with the flow handle in its environment.
/// Show it in your `navigationDestination`:
///
/// ```swift
/// .navigationDestination(for: Route.self) { route in
///   switch route {
///   case .product(let id): ProductView(id: id)
///   case .karnak(let entry): KarnakPathScreen(entry)
///   }
/// }
/// ```
public struct KarnakPathScreen: View {
  private let entry: KarnakPathEntry

  /// Draws `entry`.
  public init(_ entry: KarnakPathEntry) {
    self.entry = entry
  }

  public var body: some View {
    Group {
      switch entry.target {
      case .screen(let screenId):
        KarnakScreen(screenId, params: entry.params, entryId: entry.id)
      case .route(let routeId, let handle):
        KarnakRouteEntryView(
          route: KarnakRouteTarget(id: routeId, params: entry.params, handle: handle))
      }
    }
    // A destination of the app's stack: a covering detail pane is pushed on it.
    .environment(\.karnakInNavigationStack, true)
  }
}
