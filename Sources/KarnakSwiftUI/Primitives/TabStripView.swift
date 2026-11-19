import KarnakCore
import SwiftUI

/// The strip of a `tabs` (`docs/renderer-contract.md`, `ResolvedTabs`; ADR 0044). A `fixed` strip of plain labels is
/// the system segmented control, as iOS draws an in-screen switch between sibling views. A `scrollable` strip, or one
/// with a tab that has an icon or a badge, which a segmented control can't show, is the theme's underline strip: a
/// row of buttons in one VoiceOver container, the shown one read as selected, with the indicator bar under it. A
/// scrollable strip keeps the shown tab in view.
struct TabStripView: View {
  let tabs: ResolvedTabs
  /// The shown tab's position.
  let shown: Int
  /// A tap on the tab at a position.
  let pick: (Int) -> Void

  var body: some View {
    Group {
      if !tabs.scrollable && tabs.tabs.allSatisfy({ $0.option.icon == nil && $0.badge == nil }) {
        segmented
      } else {
        UnderlineStrip(tabs: tabs, shown: shown, pick: pick)
      }
    }
    .partBox(tabs.strip)
  }

  private var segmented: some View {
    Picker(tabs.semantics.label ?? "", selection: Binding(get: { shown }, set: pick)) {
      ForEach(Array(tabs.tabs.enumerated()), id: \.element.option.value) { index, tab in
        Text(tab.option.label.words).tag(index)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(maxWidth: .infinity)
  }
}

/// The theme's strip: each tab a button with its icon, label and badge, the indicator bar under the shown one, which
/// slides to the next as the shown tab changes.
private struct UnderlineStrip: View {
  let tabs: ResolvedTabs
  let shown: Int
  let pick: (Int) -> Void
  @Namespace private var indicator

  var body: some View {
    if tabs.scrollable {
      ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) { row(fills: false) }
          .onChange(of: shown, initial: true) {
            withAnimation { proxy.scrollTo(shown, anchor: .center) }
          }
      }
    } else {
      row(fills: true)
    }
  }

  private func row(fills: Bool) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(tabs.tabs.enumerated()), id: \.element.option.value) { index, tab in
        TabButton(tab: tab, fills: fills) { pick(index) }
          .overlay(alignment: .bottom) {
            if index == shown { bar.matchedGeometryEffect(id: "indicator", in: indicator) }
          }
          .id(index)
      }
    }
    .animation(.default, value: shown)
    .accessibilityElement(children: .contain)
  }

  private var bar: some View {
    Rectangle()
      .fill(tabs.indicator.background.map(resolvedColor) ?? .accentColor)
      .frame(height: points(dp: tabs.indicator.height?.floatValue ?? defaultIndicator))
      .clipShape(NodeShape(radius: points(dp: tabs.indicator.radius)))
      .opacity(Double(tabs.indicator.alpha))
      .accessibilityHidden(true)
  }
}

/// One tab: a button with its icon, label and badge in its `tab` box, styled for its own pressed and hovered states,
/// named by its label with the badge as its value (their texts are hidden from VoiceOver, as an input's texts are).
private struct TabButton: View {
  let tab: ResolvedTab
  let fills: Bool
  let pick: () -> Void
  @State private var pressed = false
  @State private var hovered = false

  var body: some View {
    let drawn = tab.option.styled(
      for: activeInteractions(pressed: pressed, hovered: hovered, focused: false))
    Button(action: pick) {
      HStack(spacing: tabGap) {
        if let icon = drawn.icon { VectorIconView(icon) }
        InputTextView(drawn.label)
        if let badge = tab.badge {
          InputTextView(badge.text).partBox(badge.box, alignment: .center)
        }
      }
      .frame(maxWidth: fills ? .infinity : nil)
      .partBox(drawn.row, alignment: .center)
    }
    .buttonStyle(PressTrackingStyle(pressed: $pressed))
    .disabled(!drawn.enabled)
    .onHover { hovered = $0 }
    .accessibilityLabel(drawn.label.words)
    .accessibilityValue(tab.badge?.text.words ?? "")
    .accessibilityAddTraits(drawn.selected ? [.isSelected, .isButton] : .isButton)
  }
}

/// Between a tab's icon, label and badge, in points.
private let tabGap: CGFloat = 6

/// The indicator's thickness when its part sets no height, in dp.
private let defaultIndicator: Float = 2
