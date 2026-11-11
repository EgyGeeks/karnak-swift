import KarnakCore
import SwiftUI

/// The named coordinate space of a carousel's content, which scrolls with it: its items report where they are in it.
private let carouselContentSpace = "karnakCarouselContent"

/// The carousel's lazy row: a horizontal `ScrollView` of a `LazyHStack` whose slots are built by key, so an item keeps
/// its state and the scroll keeps its place when an update keeps the keys. With `snap: item`, a scroll settles on an
/// item at the leading content padding edge (scroll targets and content margins). Which item is current is read from
/// the scroll offset and where the built items are in the content (``CarouselPosition``).
struct CarouselItems: View {
  let carousel: ResolvedCarousel
  let nodes: [ResolvedNode]
  let metrics: CarouselMetrics
  @Binding var current: Int
  @State private var position = CarouselPosition()
  @State private var contentWidth: CGFloat = 0
  @Environment(\.layoutDirection) private var direction
  @Environment(\.karnakActions) private var actions
  @State private var reporter = PageChangeReporter()

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let height = max(0, proxy.size.height - metrics.padding.top - metrics.padding.bottom)
      let slot = metrics.slotWidth(in: width)
      let rightToLeft = direction == .rightToLeft
      let snaps = carousel.snap
      ScrollView(.horizontal, showsIndicators: carousel.indicator == nil) {
        LazyHStack(alignment: .top, spacing: metrics.spacing) {
          ForEach(Array(nodes.enumerated()), id: \.element.key.value) { index, node in
            CarouselSlot(
              node: node, slot: slot, height: height, index: index, position: position)
          }
        }
        .carouselContent(metrics.padding, snaps: snaps)
        .coordinateSpace(name: carouselContentSpace)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.width
        } action: {
          contentWidth = $0
        }
        .background {
          CarouselScrollProbe(
            rightToLeft: rightToLeft, onChange: { position.scrolled($0) },
            onDragStart: { reporter.dragStarted() }, onDragEnd: { reporter.dragEnded() })
        }
      }
      .carouselSnap(metrics.padding, snaps: snaps)
      .environment(\.karnakReportsLabelledFrames, true)
    }
    .onAppear {
      position.onChange = {
        current = $0
        reporter.moved(to: $0)
      }
      position.onScroll = { reporter.scrolling() }
      reporter.send = { actions.event($0, payload: $1, byUser: $2) }
      configure()
      reporter.moved(to: current)
    }
    .onChange(of: pageTarget, initial: true) {
      reporter.update(handle: pageTarget.handle, keys: pageTarget.keys)
    }
    .onDisappear { reporter.cancel() }
    .onChange(of: nodes.count) { configure() }
    .onChange(of: contentWidth) { configure() }
    .onChange(of: direction) { configure() }
  }

  /// What the carousel reports to: its trigger, and its items' keys, which name the item in the report.
  private var pageTarget: PageTarget {
    PageTarget(
      handle: carousel.events[pageChangeEvent], keys: nodes.map(\.key.value))
  }

  private func configure() {
    position.configure(
      count: nodes.count, rightToLeft: direction == .rightToLeft, contentWidth: contentWidth,
      origin: carousel.snap ? 0 : metrics.padding.leading)
  }
}

/// One item in its slot: as wide as the carousel fixes it (the item fills it), else its own width; as tall as the item
/// area, with the item at the top, at its `align`. What does not fit is clipped at the slot's bounds, grown by the reach
/// of the item's own shadows so these are never cut.
struct CarouselSlot: View {
  let node: ResolvedNode
  let slot: CGFloat?
  let height: CGFloat
  let index: Int
  let position: CarouselPosition

  var body: some View {
    NodeView(node: node, placement: .carouselItem(node)).equatable()
      .frame(width: slot, height: height, alignment: alignment)
      .clipShape(Rectangle().inset(by: -shadowReach(of: node)))
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(carouselContentSpace))
      } action: {
        position.record(index, frame: $0)
      }
  }

  private var alignment: Alignment {
    switch node.layout.align {
    case .center: Alignment(horizontal: .leading, vertical: .center)
    case .end: .bottomLeading
    default: .topLeading
    }
  }
}

extension View {
  /// The content of the row: its vertical padding, and its horizontal padding unless the scroll view's content margins
  /// give it.
  @ViewBuilder
  fileprivate func carouselContent(_ padding: EdgeInsets, snaps: Bool) -> some View {
    if snaps {
      self.scrollTargetLayout().padding(.top, padding.top).padding(.bottom, padding.bottom)
    } else {
      self.padding(padding)
    }
  }

  /// Snapping on the leading content padding edge.
  @ViewBuilder
  fileprivate func carouselSnap(_ padding: EdgeInsets, snaps: Bool) -> some View {
    if snaps {
      self.scrollTargetBehavior(.viewAligned)
        .contentMargins(.leading, padding.leading, for: .scrollContent)
        .contentMargins(.trailing, padding.trailing, for: .scrollContent)
    } else {
      self
    }
  }
}

/// The carousel's event, as its `actions` names it (`docs/protocol.md`, Component events and node values).
private let pageChangeEvent = "pageChange"

/// The trigger of a carousel's `pageChange` and the keys of its items.
private struct PageTarget: Equatable {
  let handle: ActionHandle?
  let keys: [String]
}
