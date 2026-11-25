import KarnakCore
import SwiftUI

/// One row of a scrolling list that pins rows or lets tabs flow (`docs/renderer-contract.md`, Scroll effects), from the
/// engine's items (`ResolvedList.lazyItems`): a child drawn whole, the strip of flowing tabs, or their shown panel.
enum ListEntry: Identifiable {
  case row(ResolvedNode)
  case strip(ResolvedTabs)
  case panel(ResolvedTabs, key: String)

  var id: String {
    switch self {
    case .row(let node): node.key.value
    case .strip(let tabs): tabs.key.value
    case .panel(_, let key): key
    }
  }
}

/// A run of rows under the pinned row before them (`pin`), or the rows before the first pinned one (no `pin`). As
/// `LazyVStack` section headers, a pinned row sticks while its section scrolls beneath it, and the next pinned row
/// pushes it up.
struct ListSection: Identifiable {
  let pin: ListEntry?
  var rows: [ListEntry]

  var id: String { pin?.id ?? "start" }

  /// The keys of the section's rows, its pinned one first.
  var keys: [String] { (pin.map { [$0.id] } ?? []) + rows.map(\.id) }

  /// The sections of `list`'s items. The renderer draws every grid whole (#1969), so no item is a grid row; a custom
  /// child the host doesn't draw takes its fallback's place, or none.
  @MainActor
  static func of(_ list: ResolvedList, components: ComponentRegistry) -> [ListSection] {
    var sections = [ListSection(pin: nil, rows: [])]
    var tabs: [String: ResolvedTabs] = [:]
    for item in list.lazyItems(columns: WholeGrids()) {
      guard let entry = entry(of: item, tabs: &tabs, components: components) else { continue }
      if item.pinned {
        sections.append(ListSection(pin: entry, rows: []))
      } else {
        sections[sections.count - 1].rows.append(entry)
      }
    }
    return sections.filter { $0.pin != nil || !$0.rows.isEmpty }
  }

  @MainActor
  private static func entry(
    of item: LazyItem, tabs: inout [String: ResolvedTabs], components: ComponentRegistry
  ) -> ListEntry? {
    switch item {
    case let whole as LazyItem.Whole:
      return components.drawnNode(whole.node).map(ListEntry.row)
    case let strip as LazyItem.TabStrip:
      tabs[strip.tabs.key.value] = strip.tabs
      return .strip(strip.tabs)
    case let panel as LazyItem.TabPanel:
      return tabs[panel.tabs.value].map { .panel($0, key: item.key) }
    default:
      return nil
    }
  }

  /// Should a scrolling list draw its rows in sections: one of them pins, or is tabs whose panels flow.
  static func needed(by list: ResolvedList) -> Bool {
    list.children.contains { $0.layout.pinned || ($0 as? ResolvedTabs)?.flows == true }
  }
}

/// Draws every grid whole: the renderer has no grid rows yet (#1969).
private final class WholeGrids: NSObject, GridColumnCount {
  func count(grid: ResolvedGrid, boxes: [ResolvedLayout]) -> KotlinInt? { nil }
}

/// Where the strips and panels of flowing tabs are laid out in the list's scroll view, and the scroll view itself: what
/// a tab chosen under its stuck strip needs to bring its panel's start under the strip. Written from geometry
/// callbacks and never observed, so a scroll redraws nothing.
@MainActor
final class FlowingFrames {
  var strips: [String: CGRect] = [:]
  var panelTops: [String: CGFloat] = [:]
  weak var scroll: ScrollContext?

  /// A tab of the flowing tabs keyed `key` was chosen while their strip, pinned at `inset`, may be stuck: scrolls the
  /// list so the panel starts just under the strip, rather than part way down its content (the panel's start had
  /// scrolled up beneath the strip). A strip is drawn at the inset once its laid-out top is above it.
  func bringPanelUnderStrip(_ key: String, inset: CGFloat) {
    guard let strip = strips[key], let panelTop = panelTops[key] else { return }
    let stripBottom = max(strip.minY, inset) + strip.height
    if panelTop < stripBottom { scroll?.shift(by: panelTop - stripBottom) }
  }
}

/// The sections of a scrolling list (`ListSection`): each pinned row a section header, drawn at the list's pin inset
/// once it reaches it, over the rows that scroll beneath it.
struct ListSectionsView: View {
  let sections: [ListSection]
  /// How far below the list's top a pinned row sticks, in points.
  let inset: CGFloat
  /// The list's spacing, which the panel of flowing tabs takes back to meet its strip.
  let spacing: CGFloat
  let choices: TabChoices
  let frames: FlowingFrames

  var body: some View {
    ForEach(sections) { section in
      if let pin = section.pin {
        Section {
          rows(of: section)
        } header: {
          entry(pin).modifier(PinnedRow(inset: inset, key: pin.id, frames: frames))
        }
      } else {
        Section { rows(of: section) }
      }
    }
  }

  private func rows(of section: ListSection) -> some View {
    ForEach(section.rows) { entry($0) }
  }

  @ViewBuilder
  private func entry(_ entry: ListEntry) -> some View {
    switch entry {
    case .row(let node):
      ListRow(node: node)
        .modifier(RowAnchorModifier(key: node.key.value))
        .scrollAnchor(node.layout.scrollAnchor)
    case .strip(let tabs):
      FlowingStrip(tabs: tabs, choices: choices) {
        if tabs.layout.pinned { frames.bringPanelUnderStrip(tabs.key.value, inset: inset) }
      }
      .scrollAnchor(tabs.layout.scrollAnchor)
    case .panel(let tabs, let key):
      FlowingPanel(tabs: tabs, choices: choices)
        .modifier(RowAnchorModifier(key: key))
        .onGeometryChange(for: CGFloat.self) {
          $0.frame(in: .scrollView).minY
        } action: {
          frames.panelTops[tabs.key.value] = $0
        }
        // The list's spacing goes before the tabs only: the panel meets its strip.
        .padding(.top, -spacing)
    }
  }
}

/// A section header drawn at the list's pin inset once it reaches it: moved down by what its laid-out top lacks of the
/// inset, in its visual effect only, so the move reads no state and costs no layout. A header sits at the scroll view's
/// top while it is stuck, so it is then drawn at the inset; below the inset it is where it is laid out. Its laid-out
/// frame is kept for ``ListSectionsView``'s strip under which a panel is brought.
private struct PinnedRow: ViewModifier {
  let inset: CGFloat
  let key: String
  let frames: FlowingFrames

  func body(content: Content) -> some View {
    content
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .scrollView)
      } action: {
        frames.strips[key] = $0
      }
      .visualEffect { [inset] effect, proxy in
        effect.offset(y: max(0, inset - proxy.frame(in: .scrollView).minY))
      }
      .zIndex(1)
  }
}

/// The strip of flowing tabs as its own row: the tab shown is the list's ``TabChoices``, and a tap chooses it, reports
/// it and then calls `chosen`.
private struct FlowingStrip: View {
  let tabs: ResolvedTabs
  let choices: TabChoices
  let chosen: () -> Void
  @Environment(\.karnakActions) private var actions

  var body: some View {
    TabStripView(tabs: tabs, shown: choices.shown(tabs)) { index in
      guard index != choices.shown(tabs), tabs.panels.children.indices.contains(index) else {
        return
      }
      choices.choose(index, of: tabs, actions: actions)
      chosen()
    }
    .frame(maxWidth: .infinity)
    // The tabs' own fill goes behind the strip and the panel, so a pinned strip is opaque over the rows beneath it (#3529).
    .background(tabs.layout.background.map(resolvedColor) ?? .clear)
    .onAppear { choices.reportInitial(tabs, actions: actions) }
  }
}

/// The shown panel of flowing tabs as its own row, at its own height.
private struct FlowingPanel: View {
  let tabs: ResolvedTabs
  let choices: TabChoices
  @Environment(\.karnakComponents) private var components

  var body: some View {
    if let node = tabs.drawnPanel(choices.shown(tabs), in: components) {
      ListRow(node: node)
        .background(tabs.layout.background.map(resolvedColor) ?? .clear)
    }
  }
}

/// The shown tab of each `tabs` whose panels flow in a list, kept by the list, as their strip and panel are separate
/// rows that come and go as it scrolls: a tab chosen stays chosen, and the first report is sent once. A tap shows its
/// tab at once and reports `pageChange`; the engine then writes the tabs' `current`, and the tab a new tree holds wins
/// over the one chosen before it.
@Observable @MainActor
final class TabChoices {
  /// Tab `index`, chosen while the tree's `current` was `over`.
  private struct Choice {
    let over: Int
    let index: Int
  }

  private var chosen: [String: Choice] = [:]
  @ObservationIgnored private var reported: Set<String> = []

  /// The tab shown of `tabs`: the one a person chose while the tree held the same `current`, else `current`.
  func shown(_ tabs: ResolvedTabs) -> Int {
    let current = Int(tabs.current)
    guard let choice = chosen[tabs.key.value], choice.over == current,
      tabs.panels.children.indices.contains(choice.index)
    else { return current }
    return choice.index
  }

  /// Shows tab `index` of `tabs` and reports it as the person's.
  func choose(_ index: Int, of tabs: ResolvedTabs, actions: ActionSink) {
    chosen[tabs.key.value] = Choice(over: Int(tabs.current), index: index)
    reported.insert(tabs.key.value)
    reportPageChange(of: tabs, index: index, initial: false, byUser: true, to: actions)
  }

  /// Reports the shown tab of `tabs` once, with `initial: true`, unless a report was sent already.
  func reportInitial(_ tabs: ResolvedTabs, actions: ActionSink) {
    guard reported.insert(tabs.key.value).inserted else { return }
    reportPageChange(of: tabs, index: shown(tabs), initial: true, byUser: false, to: actions)
  }
}
