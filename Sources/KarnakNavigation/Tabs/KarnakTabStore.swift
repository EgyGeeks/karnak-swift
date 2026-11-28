import Foundation
import KarnakCore
import KarnakSwiftUI
import SwiftUI

/// Tabs with a back stack each (ADR 0045; `docs/integration.md`, Bottom navigation): one Karnak host
/// stack per tab, kept here, above the `TabView`, because `TabView` builds its tabs lazily, and the
/// tab rules of the engine's `KarnakTabs` for selecting, reselecting, back and links.
///
/// ``KarnakTabView`` draws it. An app with its own `TabView` binds its selection to ``selection``
/// and puts ``SwiftUI/View/karnakTab(_:of:)`` on each tab's root view, inside that tab's
/// `NavigationStack`; one that owns a path per tab gives it with ``SwiftUI/View/karnakTab(_:of:path:)``, and the
/// tab rules read and pop that path instead of the tab's host stack.
///
/// The store keeps the hooks each tab appeared under: a link that names a tab, and an action item's `open_screen`,
/// run on that tab's own `.karnakHost` hooks (its `onNavigation` when it has one). A link to a tab that has not
/// appeared yet selects it, and its requests wait until it appears.
///
/// Back never changes the tab on iOS (`KarnakTabBack.stayInTab`): the back button and the edge
/// swipe pop within the tab.
///
/// Made from a ``KarnakTabList`` (`karnak.tabs(fallback:)`, ADR 0047), it shows the server's tab list: an action item
/// (`KarnakTab.isAction`) is drawn like a tab and has no stack, and a tap on it asks ``shouldSelect``, then runs its
/// `open_screen` on the selected tab's hooks; the selection stays.
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
  /// Asked on each tap on a tab (``selection``), before the tab rules: `false` leaves the bar as it was, for an item
  /// that acts instead of showing a tab, such as a "+" that presents the app's sheet. The default lets every tap
  /// through. ``select(_:)`` and links don't ask it.
  public var shouldSelect: (String) -> Bool = { _ in true }

  /// What links need of the tabs: give it to `KarnakLinkOptions(tabs:)`, so a link whose pattern
  /// names a tab shows that tab popped to its root and opens its target on that tab's stack.
  public private(set) lazy var links: any LinkTabs = TabLinks(store: self)

  private let stacks: [String: KarnakHostStack]
  private let model: KarnakTabs
  /// What each tab appeared under, by tab: a link or an action item runs on the hooks of the tab it opens on.
  private var hosts: [String: TabHost] = [:]
  /// The tab that appeared last: its opener reports, and its hooks stand in for those of a tab not yet appeared.
  private var lastTab: String?
  /// What waits for the tabs that have not appeared yet, by tab.
  private var waiting: [String: PendingTab] = [:]
  private var bridges: [String: HostActionBridge] = [:]
  private var restored = false
  /// The opener of the tab that appeared last.
  private var opener: (any HostStackOpener)? { lastTab.flatMap { hosts[$0]?.opener } }
  /// The navigation module of the client the tabs appeared under: it runs an action item's `open_screen`.
  private var module: KarnakNavigationModule?
  /// The `modal` or `sheet` an action item opened over the shell, which ``KarnakTabView`` presents.
  let shell = ShellOverlays()

  /// - Parameters:
  ///   - tabs: The tabs, in the bar's order: at least one, with unique ids.
  ///   - startTab: The tab shown first, the first one when nil; it must not be an action item. Every tab opens for
  ///     everyone: a root screen marked `auth: "required"` shows its sign-in placeholder to someone signed out.
  public convenience init(tabs: [KarnakTab], startTab: String? = nil) {
    self.init(tabs: tabs, startTab: startTab, makeStack: { KarnakHostStack() })
  }

  /// The tabs of `list`, the tab list `karnak.tabs(fallback:)` picked at the cold start (ADR 0047): the server's, with
  /// its action items and its revision, or the app's own.
  ///
  /// - Parameters:
  /// - Parameter list: The tabs, the one shown first and the revision.
  public convenience init(list: KarnakTabList) {
    self.init(
      tabs: list.tabs, startTab: list.startTab, revision: list.revision,
      makeStack: { KarnakHostStack() })
  }

  /// Tabs whose stacks `makeStack` makes: tests settle pushes at once.
  init(
    tabs: [KarnakTab], startTab: String?, revision: String? = nil,
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
    model = KarnakTabs(tabs: tabs, stacks: port, startTab: start, backAtRoot: .stayInTab)
    port.store = self
  }

  /// The selection a `TabView` binds to: a tap on the selected tab reaches it too, which pops that
  /// tab to its root, or asks for a scroll to its top at the root (``onScrollToTop``).
  public var selection: Binding<String> {
    Binding(get: { self.selected }, set: { self.tapped($0) })
  }

  /// The user selected `tab`. Returns what changed; the store calls ``onScrollToTop`` itself. An action item runs its `open_screen` on the selected tab and changes nothing.
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
    }
    return change
  }

  /// A link whose pattern names `tab` is about to open: the tab shows popped to its root
  /// (`KarnakTabs.openLink`), the app's path of it included (``SwiftUI/View/karnakTab(_:of:path:)``).
  @discardableResult
  public func openLink(_ tab: String) -> KarnakTabChange {
    let change = model.openLink(tab: tab)
    popUnseen(tab)
    return change
  }

  /// Pops `tab` to its root when it has not appeared, whatever its depth: the store can't see a path the app restored
  /// for it, so that path is emptied when the tab appears.
  private func popUnseen(_ tab: String) {
    if hosts[tab] == nil, stacks[tab] != nil { pop(tab, toRoot: true) }
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

  /// The tab's view appeared under a host: its stack reports to that host's opener, and what opens on that tab (a
  /// link, an action item while it is selected) runs on that host's hooks, with `path` as the tab's place when the app
  /// owns it. Requests that waited for the tab are delivered now.
  func attach(
    _ opener: (any HostStackOpener)?, callbacks: KarnakHostCallbacks, path: TabPath? = nil,
    to tab: String
  ) {
    guard let opener, let stack = stacks[tab] else { return }
    hosts[tab] = TabHost(opener: opener, callbacks: callbacks, path: path)
    lastTab = tab
    module = (opener as? KarnakSwiftClient)?.flowModule
    shell.surface = { [weak client = opener as? KarnakSwiftClient] in
      client?.overlaySurface(dark: $0)
    }
    stack.entryRemoved = { [weak opener] in opener?.entryRemoved($0) }
    stack.report = { [weak opener] in opener?.report($0) }
    // At a tab's root there is nowhere to go back to.
    stack.leave = {}
    if tab == selected { opener.stackRegistry.register(stack) }
    deliverWaiting(tab)
  }

  /// The view of ``KarnakTabView`` appeared under a host whose hooks every tab shares: the tabs that have not appeared
  /// take them now, so what opens on such a tab goes on its host stack at once. The selected tab's comes last.
  func attachShared(_ opener: (any HostStackOpener)?, callbacks: KarnakHostCallbacks) {
    let unseen = tabs.filter { !$0.isAction && hosts[$0.id] == nil }.map(\.id)
    for tab in unseen.filter({ $0 != selected }) + unseen.filter({ $0 == selected }) {
      attach(opener, callbacks: callbacks, to: tab)
    }
  }

  /// The hooks for a link that opens on `tab`, with that tab's place as the navigation; nil for a tab the app does not
  /// have, or before any tab appeared under a host.
  func hostActions(forLink tab: String) -> HostActions? {
    guard stacks[tab] != nil, lastTab != nil else { return nil }
    openLink(tab)
    return bridge(of: tab)
  }

  /// How many entries are above `tab`'s root: the tab's host stack's, plus the app's path's when it owns one (a
  /// `karnak.open(_:params:)` still pushes on the host stack, above the path), plus the screens waiting to open on a
  /// tab that has not appeared, so a second link pops them as it pops a shown tab.
  func depth(_ tab: String) -> Int {
    (stacks[tab]?.entries.count ?? 0) + (hosts[tab]?.path?.depth() ?? 0)
      + (waiting[tab]?.openedEntries.count ?? 0)
  }

  /// Pops `tab` by one, or to its root: the host stack's top entry first, then the app's path when it owns one. A tab
  /// that has not appeared drops what waits for it, and a path the app gives it when it appears is emptied.
  func pop(_ tab: String, toRoot: Bool) {
    let request: KarnakSwiftUI.KarnakNavigation = .back(screen: nil, root: toRoot, before: nil)
    if hosts[tab] == nil, toRoot {
      for entry in waiting[tab]?.openedEntries ?? [] { opener?.entryRemoved(entry) }
      waiting[tab] = PendingTab(poppedToRoot: true)
    }
    let stacked = stacks[tab]?.entries.isEmpty == false
    if stacked { stacks[tab]?.perform(request) }
    guard let path = hosts[tab]?.path, toRoot || !stacked else { return }
    path.perform(request)
  }

  /// The hooks with `tab`'s place as the navigation, nil before any tab appeared under a host.
  private func bridge(of tab: String) -> HostActions? {
    guard stacks[tab] != nil, let callbacks = callbacks(of: tab) else { return nil }
    let bridge =
      bridges[tab]
      ?? HostActionBridge { [weak self] in self?.opener?.report($0) }
    bridges[tab] = bridge
    bridge.update(callbacks)
    return bridge.hostActions
  }

  /// The hooks of the host `tab` appeared under, its own navigation winning over the tab's place (the app's path when
  /// it gave one, else the tab's host stack). Until it appears, those of the tab that appeared last, whose navigation
  /// waits for `tab` instead.
  private func callbacks(of tab: String) -> KarnakHostCallbacks? {
    if let host = hosts[tab] {
      if let path = host.path { return host.callbacks.withDefault(navigation: path.perform) }
      let stack = stacks[tab]
      return host.callbacks.withDefault(navigation: { [weak stack] in stack?.perform($0) })
    }
    guard let last = lastTab.flatMap({ hosts[$0] }) else { return nil }
    var held = last.callbacks
    held.onOpenScreen = nil
    held.onNavigation = { [weak self] in
      self?.waiting[tab, default: PendingTab()].requests.append($0)
    }
    return held
  }

  /// Delivers what waited for `tab`, which just appeared: the pop to its root first, then the requests in order.
  private func deliverWaiting(_ tab: String) {
    let held = waiting.removeValue(forKey: tab)
    if held?.poppedToRoot == true {
      hosts[tab]?.path?.perform(.back(screen: nil, root: true, before: nil))
    }
    guard let bridge = bridges[tab], let callbacks = callbacks(of: tab) else { return }
    bridge.update(callbacks)
    held?.requests.forEach(bridge.perform)
  }

  fileprivate func show(_ tab: String) {
    selected = tab
    if let stack = stacks[tab] { (hosts[tab]?.opener ?? opener)?.stackRegistry.register(stack) }
  }
}

/// The store as the links' `LinkTabs`. The links module may call it from its own dispatcher: the
/// tab work hops to the main thread, which never waits on a link (`handleLink` is async).
/// Unchecked Sendable: its state is set when it is made, and the store it reaches is read on the main thread.
private final class TabLinks: NSObject, LinkTabs, @unchecked Sendable {
  private weak var store: KarnakTabStore?

  @MainActor init(store: KarnakTabStore) {
    self.store = store
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
    MainActor.assumeIsolated { Int32(store?.depth(tab) ?? 0) }
  }

  func show(tab: String) {
    MainActor.assumeIsolated { store?.show(tab) }
  }

  func popToRoot(tab: String) {
    MainActor.assumeIsolated { store?.pop(tab, toRoot: true) }
  }

  func pop(tab: String) {
    MainActor.assumeIsolated { store?.pop(tab, toRoot: false) }
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
