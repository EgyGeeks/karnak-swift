import KarnakSwiftUI
import SwiftUI

/// The path a tab's app owns (``SwiftUI/View/karnakTab(_:of:path:)``): what the tab rules read and pop in place of the
/// store's host stack of that tab, so the app's path stays the one truth of where the tab is.
@MainActor
struct TabPath {
  /// How many values the path holds above the tab's root view, the app's own and Karnak's.
  let depth: () -> Int
  /// Performs `request` on the path (``Swift/Array/performKarnakNavigation(_:navigator:rootScreen:)``) and reports the
  /// Karnak entries it removes.
  let perform: (_ request: KarnakNavigation) -> Void

  /// The tab rules and the tab's requests on `path`: an `open` appends `.karnak(entry)`, a pop removes values, and the
  /// Karnak entries a pop removes are reported to `opener`, so their openers hear `cancelled`.
  init<Element: KarnakPathElement>(_ path: Binding<[Element]>, opener: (any HostStackOpener)?) {
    depth = { path.wrappedValue.count }
    perform = { [weak opener] request in
      var values = path.wrappedValue
      _ = values.performKarnakNavigation(
        request, entryRemoved: { opener?.entryRemoved($0) }, report: { opener?.report($0) })
      path.wrappedValue = values
    }
  }
}

/// What one tab's ``SwiftUI/View/karnakTab(_:of:)`` appeared under: the hooks of the `.karnakHost` around that tab's
/// `NavigationStack`, and the app's path when it owns one.
struct TabHost {
  weak var opener: (any HostStackOpener)?
  let callbacks: KarnakHostCallbacks
  let path: TabPath?
}

/// What waits for a tab that has not appeared yet (`TabView` builds its tabs lazily): a link that popped it to
/// its root, then the requests a link sent it, delivered in order through its own hooks when it appears.
struct PendingTab {
  /// The tab was popped to its root: a path the app restored for it is emptied when it appears.
  var poppedToRoot = false
  var requests: [KarnakNavigation] = []

  /// The entry ids of the screens the waiting requests open, which never showed.
  var openedEntries: [String] {
    requests.compactMap { request in
      if case .open(let entryId, _, _, _) = request { entryId } else { nil }
    }
  }
}
