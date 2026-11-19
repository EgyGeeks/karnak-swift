import KarnakCore
import SwiftUI

/// `tabs` (`docs/renderer-contract.md`, `ResolvedTabs`; ADR 0044): the strip (``TabStripView``) over the panels. As on
/// iOS's own views, only the strip changes tabs: a swipe on a panel scrolls the panel's content, never to the next tab.
/// A panel is built the first time its tab is shown and is kept while the screen lives, hidden (and out of VoiceOver
/// and hit testing) while another tab is shown, so it keeps its state and scroll position; the panels share the
/// height left below the strip. A tap on a tab shows its panel and reports `pageChange` with its position as the
/// person's; the engine then writes `current`, and a tree that moves `current` (a `set_value`) shows that tab.
struct TabsView: View {
  let tabs: ResolvedTabs
  let placement: ChildPlacement
  /// The shown tab's position, from the engine's `current` and moved at once by a tap.
  @State private var shown: Int
  /// The keys of the panels shown so far, which stay built.
  @State private var built: Set<String>
  /// The `current` of the tree drawn last: the shown tab follows the engine only when a new tree moves it.
  @State private var followed: Int
  @Environment(\.karnakActions) private var actions
  @Environment(\.karnakComponents) private var components

  init(tabs: ResolvedTabs, placement: ChildPlacement) {
    self.tabs = tabs
    self.placement = placement
    let start = Int(tabs.current)
    _shown = State(initialValue: start)
    _followed = State(initialValue: start)
    _built = State(
      initialValue: Set(tabs.panels.children.indices.contains(start) ? [panelKey(tabs, start)] : [])
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      TabStripView(tabs: tabs, shown: shown, pick: pick)
      panels
    }
    .onChange(of: tabs.current) { follow(Int(tabs.current)) }
    .onAppear { report(shown, initial: true, byUser: false) }
  }

  private var panels: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(tabs.panels.children.enumerated()), id: \.element.key.value) { index, panel in
        if built.contains(panel.key.value), let node = components.drawnNode(panel) {
          let isShown = index == shown
          NodeView(node: node, placement: .pagerPage).equatable()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // A container first, so `accessibilityHidden(false)` on the shown panel un-hides nothing beneath it
            // (AGENTS.md, SwiftUI accessibility).
            .accessibilityElement(children: .contain)
            .accessibilityHidden(!isShown)
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipped()
  }

  /// A tap on the tab at `index`: shows its panel and reports it as the person's.
  private func pick(_ index: Int) {
    guard index != shown, tabs.panels.children.indices.contains(index) else { return }
    show(index)
    report(index, initial: false, byUser: true)
  }

  /// Shows the tab the engine moved `current` to; a tap the engine has just recorded is already shown.
  private func follow(_ target: Int) {
    guard followed != target else { return }
    followed = target
    guard target != shown, tabs.panels.children.indices.contains(target) else { return }
    show(target)
  }

  private func show(_ index: Int) {
    built.insert(panelKey(tabs, index))
    shown = index
  }

  private func report(_ index: Int, initial: Bool, byUser: Bool) {
    guard let handle = tabs.events[pageChangeEvent], tabs.panels.children.indices.contains(index)
    else { return }
    actions.event(
      handle,
      payload: PageChangeReporter.payload(
        index: index, key: panelKey(tabs, index), initial: initial),
      byUser: byUser)
  }
}

/// The key of the panel at `index` of `tabs`.
private func panelKey(_ tabs: ResolvedTabs, _ index: Int) -> String {
  tabs.panels.children[index].key.value
}

/// The event a tap and a settled swipe raise, as the tabs' `actions` name it (`docs/protocol.md`, Component events).
private let pageChangeEvent = "pageChange"
