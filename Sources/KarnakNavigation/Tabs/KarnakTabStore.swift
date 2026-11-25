import Foundation
import KarnakCore
import KarnakSwiftUI
import SwiftUI

/// Tabs with a back stack each (ADR 0045; `docs/integration.md`, Bottom navigation): one Karnak host
/// stack per tab, kept here, above the `TabView`, because `TabView` builds its tabs lazily, and the
/// tab rules of the engine's `KarnakTabs` for selecting, reselecting, back and sign-out.
///
/// ``KarnakTabView`` draws it. An app with its own `TabView` binds its selection to ``selection``
/// and puts ``SwiftUI/View/karnakTab(_:of:)`` on each tab's root view, inside that tab's
/// `NavigationStack`.
///
/// Back never changes the tab on iOS (`KarnakTabBack.stayInTab`): the back button and the edge
/// swipe pop within the tab.
///
/// Made from a ``KarnakTabList`` (`karnak.tabs(fallback:)`, ADR 0047), it shows the server's tab list: an action item
/// (`KarnakTab.isAction`) is drawn like a tab and has no stack, and a tap on it asks ``shouldSelect``, then runs its
/// `open_screen` on the selected tab's stack; the selection stays.
@MainActor
public final class KarnakTabStore: ObservableObject {
  /// The tabs, in the bar's order, action items among them.
  public let tabs: [KarnakTab]
  /// The revision of the server's tab list, or nil for the app's own tabs: a selection saved under another revision
  /// is not restored (``restore(_:savedUnder:)``).
  public let revision: String?
  /// The selected tab's id.
  @Published public private(set) var selected: String
  /// The search tab's id (`KarnakTabRole.search`), or nil: ``KarnakTabView`` makes it a `Tab(role: .search)` on
  /// iOS 18. At most one tab has the role: more stops a debug build, and in release only the first is the search tab.
  public let searchTab: String?
  /// Called when the selected tab was selected again at its root: scroll its root screen to the top.
  public var onScrollToTop: (String) -> Void = { _ in }
  /// Called when the user selected a tab that needs a signed-in user and nobody is signed in: show
  /// the sign-in, then call ``select(_:)`` again.
  public var onSignInNeeded: (String) -> Void = { _ in }
  /// Asked on each tap on a tab (``selection``), before the tab rules: `false` leaves the bar as it was, for an item
  /// that acts instead of showing a tab, such as a "+" that presents the app's sheet. The default lets every tap
  /// through. ``select(_:)`` and links don't ask it.
  public var shouldSelect: (String) -> Bool = { _ in true }

  /// What links need of the tabs: give it to `KarnakLinkOptions(tabs:)`, so a link whose pattern
  /// names a tab shows that tab popped to its root and opens its target on that tab's stack.
  public private(set) lazy var links: any LinkTabs = TabLinks(store: self)

  private let stacks: [String: KarnakHostStack]
  private let model: KarnakTabs
  private weak var opener: (any HostStackOpener)?
  private var callbacks: KarnakHostCallbacks?
  private var bridges: [String: HostActionBridge] = [:]
  private var restored = false
  /// The navigation module of the client the tabs appeared under: it runs an action item's `open_screen`.
  private var module: KarnakNavigationModule?
  /// The `modal` or `sheet` an action item opened over the shell, which ``KarnakTabView`` presents.
  let shell = ShellOverlays()

  /// - Parameters:
  ///   - tabs: The tabs, in the bar's order: at least one, with unique ids.
  ///   - startTab: The tab shown first, the first one when nil; it must not need a sign-in.
  ///   - signedIn: Whether a user is signed in now: the same function as the links' `signedIn`.
  public convenience init(
    tabs: [KarnakTab], startTab: String? = nil, signedIn: @escaping () -> Bool = { true }
  ) {
    self.init(tabs: tabs, startTab: startTab, signedIn: signedIn, makeStack: { KarnakHostStack() })
  }

  /// The tabs of `list`, the tab list `karnak.tabs(fallback:)` picked at the cold start (ADR 0047): the server's, with
  /// its action items and its revision, or the app's own.
  ///
  /// - Parameters:
  ///   - list: The tabs, the one shown first and the revision.
  ///   - signedIn: Whether a user is signed in now: the same function as the links' `signedIn`.
  public convenience init(list: KarnakTabList, signedIn: @escaping () -> Bool = { true }) {
    self.init(
      tabs: list.tabs, startTab: list.startTab, revision: list.revision, signedIn: signedIn,
      makeStack: { KarnakHostStack() })
  }

  /// Tabs whose stacks `makeStack` makes: tests settle pushes at once.
  init(
    tabs: [KarnakTab], startTab: String?, revision: String? = nil, signedIn: @escaping () -> Bool,
    makeStack: () -> KarnakHostStack
  ) {
    self.tabs = tabs
    self.revision = revision
    searchTab = KarnakTabs.companion.searchTab(tabs: tabs, debug: isDebugBuild)
    let start = startTab ?? tabs.first?.id ?? ""
    selected = start
    stacks = Dictionary(
      uniqueKeysWithValues: tabs.filter { !$0.isAction }.map { ($0.id, makeStack()) })
    let port = StackPort()
    model = KarnakTabs(
      tabs: tabs, stacks: port, startTab: start, backAtRoot: .stayInTab,
      signedIn: { KotlinBoolean(bool: signedIn()) })
    port.store = self
  }

  /// The selection a `TabView` binds to: a tap on the selected tab reaches it too, which pops that
  /// tab to its root, or asks for a scroll to its top at the root (``onScrollToTop``).
  public var selection: Binding<String> {
    Binding(get: { self.selected }, set: { self.tapped($0) })
  }

  /// The user selected `tab`. Returns what changed; the store calls ``onScrollToTop`` and
  /// ``onSignInNeeded`` itself. An action item runs its `open_screen` on the selected tab and changes nothing.
  @discardableResult
  public func select(_ tab: String) -> KarnakTabChange {
    if let item = tabs.first(where: { $0.id == tab }), item.isAction {
      runAction(of: item)
    }
    let change = model.select(tab: tab)
    if change == KarnakTabChange.none, selected != tab {
      // A `TabView` that already shows the tapped item reads the selection again and goes back to the selected tab.
      objectWillChange.send()
    } else if change == .scrollToTop {
      onScrollToTop(tab)
    } else if change == .signInNeeded {
      // `selected` did not change, so nothing was published: a `TabView` that already shows the
      // tapped tab is told to read the selection again and go back to the selected one.
      objectWillChange.send()
      onSignInNeeded(tab)
    }
    return change
  }

  /// A link whose pattern names `tab` is about to open: the tab shows popped to its root
  /// (`KarnakTabs.openLink`).
  @discardableResult
  public func openLink(_ tab: String) -> KarnakTabChange {
    model.openLink(tab: tab)
  }

  /// The user signed out: every sign-in tab pops to its root and a selected one leaves for the
  /// start tab.
  public func signedOut() {
    model.signedOut()
  }

  /// Shows the first tab: `saved`, a ``selected`` of an earlier scene, when the app has it and may
  /// show it now, else the start tab. ``KarnakTabView`` calls it with its `@SceneStorage`; an app
  /// with its own `TabView` calls it once, when it knows whether someone is signed in.
  public func restore(_ saved: String?) {
    guard !restored else { return }
    restored = true
    model.restore(saved: saved)
  }

  /// ``restore(_:)`` for a selection saved with the tab list's ``revision``: one saved under another revision (or
  /// under the app's own tabs, nil) restores nothing and shows the start tab (ADR 0047, D8). Save ``revision`` beside
  /// ``selected``.
  public func restore(_ saved: String?, savedUnder revision: String?) {
    restore(revision == self.revision ? saved : nil)
  }

  private func tapped(_ tab: String) {
    guard shouldSelect(tab) else {
      objectWillChange.send()
      return
    }
    select(tab)
  }

  private func runAction(of item: KarnakTab) {
    guard let module, let actions = bridge(of: selected) else { return }
    shell.show(module.runTabAction(tab: item, actions: actions))
  }

  /// The host stack of `tab`.
  func stack(_ tab: String) -> KarnakHostStack? {
    stacks[tab]
  }

  /// The tab's view appeared under a host: its stack reports to that host's opener, and links
  /// opened on any tab use that host's hooks.
  func attach(_ opener: (any HostStackOpener)?, callbacks: KarnakHostCallbacks, to tab: String) {
    guard let opener, let stack = stacks[tab] else { return }
    self.opener = opener
    self.callbacks = callbacks
    module = (opener as? KarnakSwiftClient)?.flowModule
    for (id, bridge) in bridges { bridge.update(navigation(of: id, callbacks)) }
    stack.entryRemoved = { [weak opener] in opener?.entryRemoved($0) }
    stack.report = { [weak opener] in opener?.report($0) }
    // At a tab's root there is nowhere to go back to.
    stack.leave = {}
    if tab == selected { opener.stackRegistry.register(stack) }
  }

  /// The host's hooks for a link that opens on `tab`, with that tab's stack as the navigation;
  /// nil for a tab the app does not have, one a signed-out user may not see, or before any tab
  /// appeared under a host.
  func hostActions(forLink tab: String) -> HostActions? {
    guard stacks[tab] != nil, callbacks != nil, openLink(tab) != .signInNeeded else { return nil }
    return bridge(of: tab)
  }

  /// The host's hooks with `tab`'s stack as the navigation, nil before any tab appeared under a host.
  private func bridge(of tab: String) -> HostActions? {
    guard stacks[tab] != nil, let callbacks else { return nil }
    let bridge =
      bridges[tab]
      ?? HostActionBridge { [weak self] in self?.opener?.report($0) }
    bridges[tab] = bridge
    bridge.update(navigation(of: tab, callbacks))
    return bridge.hostActions
  }

  private func navigation(of tab: String, _ callbacks: KarnakHostCallbacks) -> KarnakHostCallbacks {
    callbacks.withDefault(navigation: { [weak self] in self?.stacks[tab]?.perform($0) })
  }

  fileprivate func show(_ tab: String) {
    selected = tab
    if let stack = stacks[tab] { opener?.stackRegistry.register(stack) }
  }
}

/// The store as the links' `LinkTabs`. The links module may call it from its own dispatcher: the
/// tab work hops to the main thread, which never waits on a link (`handleLink` is async).
/// Unchecked Sendable: its state is set when it is made, and the store it reaches is read on the main thread.
private final class TabLinks: NSObject, LinkTabs, @unchecked Sendable {
  private let signInTabs: Set<String>
  private weak var store: KarnakTabStore?

  @MainActor init(store: KarnakTabStore) {
    signInTabs = Set(store.tabs.filter(\.requiresSignIn).map(\.id))
    self.store = store
  }

  func requiresSignIn(tab: String) -> Bool {
    signInTabs.contains(tab)
  }

  func open(tab: String) -> HostActions? {
    // HostActions is a Kotlin class, not Sendable: it is handed over once, after the work ran.
    nonisolated(unsafe) var actions: HostActions?
    let work = { MainActor.assumeIsolated { actions = self.opened(tab) } }
    if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    return actions
  }

  @MainActor private func opened(_ tab: String) -> HostActions? {
    store?.hostActions(forLink: tab)
  }
}

/// The engine's port on the host stacks: what `KarnakTabs` asks of them.
/// Unchecked Sendable: the store is set once, before the engine's first call, and read on the main thread.
private final class StackPort: NSObject, KarnakTabStacks, @unchecked Sendable {
  /// Set once the store is made: the engine's model is made first, with this port.
  weak var store: KarnakTabStore?

  func depth(tab: String) -> Int32 {
    MainActor.assumeIsolated { Int32(store?.stack(tab)?.entries.count ?? 0) }
  }

  func show(tab: String) {
    MainActor.assumeIsolated { store?.show(tab) }
  }

  func popToRoot(tab: String) {
    MainActor.assumeIsolated {
      store?.stack(tab)?.perform(.back(screen: nil, root: true, before: nil))
    }
  }

  func pop(tab: String) {
    MainActor.assumeIsolated {
      store?.stack(tab)?.perform(.back(screen: nil, root: false, before: nil))
    }
  }
}

/// Whether this is a debug build of the app, which builds the package with it: developer misuse stops it.
private var isDebugBuild: Bool {
  #if DEBUG
    true
  #else
    false
  #endif
}
