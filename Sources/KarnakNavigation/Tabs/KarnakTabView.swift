import KarnakCore
import KarnakSwiftUI
import SwiftUI

/// A `TabView` with a `NavigationStack` and a Karnak host stack per tab (ADR 0045;
/// `docs/integration.md`, Bottom navigation): Karnak's requests land on the stack of the tab the
/// screen is in, a tap on the selected tab pops it to its root, and the selected tab comes back
/// with the scene (`@SceneStorage`). On iOS 18 the tabs adapt to a sidebar on iPad
/// (`.sidebarAdaptable`), and the search tab (`KarnakTabRole.search`) is a `Tab(role: .search)`: the system draws it
/// apart at the bar's trailing end (a round glass button on iOS 26), and the `search` node of its root screen goes into
/// the system's search field, which iOS 26 puts in the bar. On iOS 17 it is a normal tab.
///
/// ```swift
/// @StateObject var tabs = KarnakTabStore(tabs: [KarnakTab(id: "home"), KarnakTab(id: "cart")])
///
/// KarnakTabView(tabs) { tab in
///   TabRoot(tab.id)
/// } label: { tab in
///   Label(title(tab.id), systemImage: icon(tab.id))
/// }
/// .karnakHost(karnak)
/// ```
///
/// The label and icon are the app's: draw them in `label`. Without a `label`, each tab shows its
/// server label and theme icon (``KarnakTabLabel``), the bar takes the theme's tint, and on iOS 26 it shrinks as the
/// content scrolls as the theme's `minimize` says. A tab's badge is the app's state: return it from `badge`.
///
/// With a store made from a server's tab list (``KarnakTabStore/init(list:)``), each tab's root is the app's
/// view: draw the tab's Karnak screen, `KarnakScreen(tab.start ?? tab.id)`, for the tabs the app has no view of its
/// own for, or leave `root` out (the themed initializer) for Karnak screens everywhere. The selection is saved with the
/// list's revision, and a scene restored under another revision shows the start tab.
public struct KarnakTabView<Root: View, TabLabel: View>: View {
  @ObservedObject private var store: KarnakTabStore
  private let root: (KarnakTab) -> Root
  private let label: (KarnakTab, Bool, KarnakTabIcons) -> TabLabel
  private let badge: (KarnakTab) -> KarnakTabBadge
  @SceneStorage("karnak.tabs.selected") private var saved = ""
  /// The revision of the server's tab list `saved` was saved under: empty for the app's own tabs.
  @SceneStorage("karnak.tabs.revision") private var savedRevision = ""
  @Environment(\.karnakStackOpener) private var opener
  @Environment(\.karnakHostCallbacks) private var callbacks
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.layoutDirection) private var layoutDirection
  /// Whether the tabs show their server label and theme icon, and the bar takes the theme's tint.
  private let themed: Bool
  @State private var icons = KarnakTabIcons.none
  @State private var minimize = KarnakTabBarMinimize.never
  @State private var themeRevision = ""

  /// - Parameters:
  ///   - store: The tabs and their stacks; keep it in a `@StateObject` above this view.
  ///   - badge: The badge of a tab: the app's own state (an unread count, a cart's size).
  ///   - root: The root view of a tab's `NavigationStack`.
  ///   - label: The tab's label in the bar.
  public init(
    _ store: KarnakTabStore,
    badge: @escaping (KarnakTab) -> KarnakTabBadge = { _ in KarnakTabBadge.companion.none },
    @ViewBuilder root: @escaping (KarnakTab) -> Root,
    @ViewBuilder label: @escaping (KarnakTab) -> TabLabel
  ) {
    self.store = store
    self.root = root
    self.label = { tab, _, _ in label(tab) }
    self.badge = badge
    self.themed = false
  }

  public var body: some View {
    tabView
      .karnakShellOverlays(store.shell)
      .modifier(ThemeTint(themed: themed, color: icons.tint))
      .modifier(MinimizeOnScroll(minimize: minimize))
      .onAppear {
        store.restore(
          saved.isEmpty ? nil : saved, savedUnder: savedRevision.isEmpty ? nil : savedRevision)
        // Every tab is under the `.karnakHost` around this view: a link to a tab not shown yet opens on it at once.
        store.attachShared(opener, callbacks: callbacks)
      }
      .onChange(of: store.selected) { _, tab in
        saved = tab
        savedRevision = store.revision ?? ""
      }
      .task(id: themeKey) { drawIcons() }
      .task(id: themedClient) {
        guard themed, let client = opener as? KarnakSwiftClient else { return }
        _ = await client.loadTheme()
      }
      .task(id: themedClient) {
        guard themed, let client = opener as? KarnakSwiftClient else { return }
        for await theme in client.themes() { themeRevision = theme?.revision ?? "" }
      }
  }

  /// The client whose theme the bar follows, while the tabs are themed.
  private var themedClient: ObjectIdentifier? {
    themed ? opener.map(ObjectIdentifier.init) : nil
  }

  /// What the icons are drawn for: the appearance, the direction and the theme the client holds.
  private var themeKey: String {
    "\(colorScheme == .dark)-\(layoutDirection == .rightToLeft)-\(themeRevision)"
  }

  private func drawIcons() {
    guard themed, let client = opener as? KarnakSwiftClient else { return }
    let names = store.tabs.flatMap { [$0.icon, $0.selectedIcon].compactMap { $0 } }
    let style = client.tabBarStyle(
      .bar, dark: colorScheme == .dark, rtl: layoutDirection == .rightToLeft, icons: names)
    icons = KarnakTabIcons(style)
    minimize = style.minimize
  }

  @ViewBuilder private var tabView: some View {
    if #available(iOS 18, *) {
      TabView(selection: store.selection) {
        ForEach(store.tabs, id: \.id) { tab in
          Tab(value: tab.id, role: tab.id == store.searchTab ? .search : nil) {
            stack(tab)
          } label: {
            label(tab, store.selected == tab.id, icons)
          }
          .badge(badge(tab).text)
        }
      }
      .tabViewStyle(.sidebarAdaptable)
    } else {
      TabView(selection: store.selection) {
        ForEach(store.tabs, id: \.id) { tab in
          stack(tab)
            .tabItem { label(tab, store.selected == tab.id, icons) }
            .badge(badge(tab).text)
            .tag(tab.id)
        }
      }
    }
  }

  @ViewBuilder private func stack(_ tab: KarnakTab) -> some View {
    if tab.isAction {
      // An action item is never selected: its tab has nothing to show.
      Color.clear
    } else {
      // The theme's tint stays on the bar: under it the tab's content keeps the app's accent color.
      NavigationStack { root(tab).karnakTab(tab.id, of: store) }
        .modifier(ThemeTint(themed: themed, color: .accentColor))
    }
  }
}

/// `.tint(color)` on a themed tab view; on one whose labels are the app's, the tint the app set
/// above stays. `themed` never changes for a view, so neither does the view's identity.
private struct ThemeTint: ViewModifier {
  let themed: Bool
  let color: Color?

  func body(content: Content) -> some View {
    if themed { content.tint(color) } else { content }
  }
}

/// How the bar shrinks as the content scrolls, on iOS 26 (`tabBarMinimizeBehavior`); older iOS keeps it.
private struct MinimizeOnScroll: ViewModifier {
  let minimize: KarnakTabBarMinimize

  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content.tabBarMinimizeBehavior(behavior)
    } else {
      content
    }
  }

  @available(iOS 26, *)
  private var behavior: TabBarMinimizeBehavior {
    switch minimize {
    case .onScrollDown: .onScrollDown
    case .onScrollUp: .onScrollUp
    case .automatic: .automatic
    default: .never
    }
  }
}

extension KarnakTabView where TabLabel == KarnakTabLabel {
  /// A tab view whose tabs show their server label and theme icon (ADR 0045, D14): each
  /// `KarnakTab`'s `label` key from the string table and its theme `icon`, with the bar tinted
  /// by the theme's `navigation_bar`. A change in the dashboard reaches the bar without a release.
  ///
  /// ```swift
  /// KarnakTabView(tabs, badge: { tab in
  ///   tab.id == "cart" ? .companion.count(n: Int32(cart.count)) : .companion.none
  /// }) { tab in
  ///   TabRoot(tab.id)
  /// }
  /// ```
  public init(
    _ store: KarnakTabStore,
    badge: @escaping (KarnakTab) -> KarnakTabBadge = { _ in KarnakTabBadge.companion.none },
    @ViewBuilder root: @escaping (KarnakTab) -> Root
  ) {
    self.store = store
    self.root = root
    self.label = { tab, selected, icons in
      KarnakTabLabel(tab: tab, selected: selected, icons: icons)
    }
    self.badge = badge
    self.themed = true
  }
}

extension KarnakTabView
where TabLabel == KarnakTabLabel, Root == KarnakScreen<KarnakLoadingView, KarnakErrorView> {
  /// A themed tab view whose every tab is rooted at its Karnak screen: the tab's `start` from a server's tab list
  /// (ADR 0047), else the screen with the tab's id.
  ///
  /// ```swift
  /// KarnakTabView(tabs)
  /// ```
  public init(
    _ store: KarnakTabStore,
    badge: @escaping (KarnakTab) -> KarnakTabBadge = { _ in KarnakTabBadge.companion.none }
  ) {
    self.init(store, badge: badge) { tab in KarnakScreen(tab.start ?? tab.id) }
  }
}

extension View {
  /// Makes this view, the root of the `NavigationStack` of tab `tab`, the host stack of that tab:
  /// ``SwiftUI/View/karnakDestinations()`` on the tab's own stack, kept by `store`. For an app with
  /// its own `TabView`; ``KarnakTabView`` puts it there itself.
  ///
  /// What opens on the tab (a link whose pattern names it, an action item's `open_screen` while it is selected) runs
  /// on the hooks of the `.karnakHost` around this tab's `NavigationStack`. A tab that has not appeared yet is
  /// selected first, and its requests wait until it appears.
  public func karnakTab(_ tab: String, of store: KarnakTabStore) -> some View {
    modifier(KarnakTabStack(tab: tab, store: store, path: nil))
  }

  /// ``karnakTab(_:of:)`` for a tab whose app owns its path (`NavigationStack(path: $path)` with
  /// ``Swift/Array/performKarnakNavigation(_:navigator:rootScreen:)`` in the `onNavigation` of the
  /// `.karnakHost` around that stack): `store` reads `path` for the tab's depth and pops it, so a tap on the
  /// selected tab pops the path to its root before it asks for a scroll, and a link pops it as well. Every Karnak entry a pop removes is reported, so its opener hears `cancelled`. Under a
  /// `.karnakHost` with neither `onNavigation` nor `onOpenScreen`, what the store opens on the tab (a link, an action
  /// item) goes on `path` too.
  /// A screen opened with `karnak.open(_:params:)` goes on the tab's host stack, above the path, and is popped first.
  ///
  /// ```swift
  /// NavigationStack(path: $homePath) {
  ///   HomeView()
  ///     .karnakTab("home", of: tabs, path: $homePath)
  ///     .navigationDestination(for: Route.self) { route in RouteView(route) }
  /// }
  /// .karnakHost(karnak, onNavigation: { homePath.performKarnakNavigation($0, navigator: karnak.navigator) })
  /// ```
  ///
  /// - Parameters:
  ///   - tab: The tab's id.
  ///   - store: The tabs.
  ///   - path: The tab's path, the one its `NavigationStack` is bound to.
  public func karnakTab<Element: KarnakPathElement>(
    _ tab: String, of store: KarnakTabStore, path: Binding<[Element]>
  ) -> some View {
    modifier(KarnakTabStack(tab: tab, store: store) { opener in TabPath(path, opener: opener) })
  }
}

private struct KarnakTabStack: ViewModifier {
  let tab: String
  let store: KarnakTabStore
  /// The app's path of the tab, made with the opener its pops report to; nil when the store's host stack is the tab's.
  let path: (@MainActor ((any HostStackOpener)?) -> TabPath)?
  @Environment(\.karnakStackOpener) private var opener
  @Environment(\.karnakHostCallbacks) private var callbacks

  func body(content: Content) -> some View {
    if let stack = store.stack(tab) {
      content
        .karnakDestinations()
        .environment(\.karnakStack, KarnakStackLevel(stack: stack, depth: 0))
        .onAppear { store.attach(opener, callbacks: callbacks, path: path?(opener), to: tab) }
    } else {
      content
    }
  }
}
