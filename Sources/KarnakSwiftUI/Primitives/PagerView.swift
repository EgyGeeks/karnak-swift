import KarnakCore
import SwiftUI

/// `pager`: full-size pages turned one at a time, horizontally or vertically, with the dots the engine resolved
/// (`docs/renderer-contract.md`, Display primitives). The pages are a paging `ScrollView` (``PagerPages``) in a
/// ``KarnakCarouselLayout``: given a height (fixed, `fill` or stretched) the pages take it, less the dot row below a
/// horizontal pager; with a `wrap` height, or none proposed, they take the first page's, which a hidden ruler measures,
/// so a later, taller page is clipped instead of moving what is below. A vertical pager's dots are a column over its
/// trailing edge. The pager's size is its accessibility value (``accessibilitySemantics(of:)``).
struct PagerView: View {
  /// The pager.
  let pager: ResolvedPager
  /// Which axes of the pager's box its own parent sizes.
  let placement: ChildPlacement
  @State private var current: Int
  /// The pages' scroll view's length along the pager's axis, in points; 0 until it is measured.
  @State private var length: CGFloat = 0
  @Environment(\.karnakComponents) private var components

  init(pager: ResolvedPager, placement: ChildPlacement) {
    self.pager = pager
    self.placement = placement
    // The page the engine holds: the dots and the first `pageChange` start there, not at page 0.
    _current = State(initialValue: Int(pager.current))
  }

  var body: some View {
    let nodes = pager.children.compactMap { components.drawnNode($0) }
    let indicator = nodes.count > 1 ? pager.indicator : nil
    let below = pager.vertical ? nil : indicator
    KarnakCarouselLayout(
      metrics: CarouselMetrics(
        itemWidth: .wrap, spacing: 0, padding: EdgeInsets(),
        dotsBlock: below.map { points(dp: $0.spacing + $0.dotSize) } ?? 0,
        dotsSpacing: below.map { points(dp: $0.spacing) } ?? 0),
      wrapsHeight: placement.wraps(.vertical, of: pager.layout)
    ) {
      PagerPages(pager: pager, nodes: nodes, current: $current, length: $length)
        .overlay(alignment: .trailing) {
          if pager.vertical, let indicator {
            dots(indicator, count: nodes.count)
              .frame(width: points(dp: indicator.dotSize))
              .padding(.trailing, points(dp: indicator.spacing))
          }
        }
        .carouselRole(.items)
      if let first = nodes.first {
        // Never placed: measured for a `wrap` height only, so hidden, out of accessibility, hit testing, the frame
        // observer and floating anchors, and with no viewport, so no `appear` fires for the copy.
        NodeView(node: first, placement: .pagerPage).equatable()
          // A peek takes room from each side of the pages' area along the axis: a horizontal pager's page is narrower
          // (its text wraps at that width) and a vertical `wrap` area is taller than its first page by two peeks.
          .padding(
            pager.vertical ? .vertical : .horizontal, points(dp: pager.effectivePeek(extent: Float(length))))
          .hidden()
          .offeringNoFloatingAnchors()
          .accessibilityHidden(true)
          .allowsHitTesting(false)
          .environment(\.karnakFrameObserver, nil)
          .environment(\.karnakViewport, nil)
          .carouselRole(.ruler)
      }
      if let below {
        dots(below, count: nodes.count).carouselRole(.dots)
      }
    }
  }

  private func dots(_ indicator: ResolvedCarouselIndicator, count: Int) -> CarouselDots {
    CarouselDots(
      key: pager.key.value, indicator: indicator, count: count, current: current, vertical: pager.vertical)
  }
}

/// The pages: a `ScrollView` along the pager's axis of a lazy stack whose pages are built by key, each the size of the
/// scroll view (`containerRelativeFrame`), with SwiftUI's paging, so one swipe or fling turns exactly one page. The page
/// in view is read from the scroll view itself (``PagerPosition``), so a scroll no finger made counts too; the dots
/// move to the page the paging chose when a finger lifts, and `pageChange` is reported once the scroll settles
/// (``PageChangeReporter``).
///
/// With a `peek` or a `spacing` the scroll view has `contentMargins` of the peek on the paging axis, the lazy stack the
/// spacing, and each page is the scroll view's length less two peeks (measured, so it is the same on every OS), so a
/// page is one page plus a gap from the next; ``PagerTargetBehavior`` then pages by that step. A pager with neither
/// is drawn and paged exactly as it was.
struct PagerPages: View {
  let pager: ResolvedPager
  let nodes: [ResolvedNode]
  @Binding var current: Int
  /// The scroll view's length along the pager's axis, in points; 0 until it is measured.
  @Binding var length: CGFloat
  @State private var position = PagerPosition()
  @State private var reporter = PageChangeReporter()
  /// The key of the page the scroll view is turned to when the engine moves the pager (``follow(_:)``); it starts
  /// on the engine's page.
  @State private var scrolledKey: String?
  /// The `current` of the tree drawn last: the pager turns only when a new tree moves it.
  @State private var followed: Int
  /// The pages' area in global coordinates: what a node in a page can be near in (``NearArea``).
  @State private var nearClip = CGRect.null
  /// The clip of a pager around this one, which this one's narrows.
  @Environment(\.karnakNearClip) private var outerClip
  @Environment(\.layoutDirection) private var direction
  @Environment(\.karnakActions) private var actions

  init(pager: ResolvedPager, nodes: [ResolvedNode], current: Binding<Int>, length: Binding<CGFloat>) {
    self.pager = pager
    self.nodes = nodes
    _current = current
    _length = length
    let start = Int(pager.current)
    _followed = State(initialValue: start)
    _scrolledKey = State(initialValue: start > 0 && nodes.indices.contains(start) ? nodes[start].key.value : nil)
  }

  var body: some View {
    scrollView
      .environment(\.karnakNearClip, outerClip.map { $0.intersection(nearClip) } ?? nearClip)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { nearClip = $0 }
      .contentMargins(pager.vertical ? .vertical : .horizontal, peek, for: .scrollContent)
      .onGeometryChange(for: CGFloat.self) { pager.vertical ? $0.size.height : $0.size.width } action: {
        length = $0
      }
      .scrollTargetBehavior(
        PagerTargetBehavior(vertical: pager.vertical, step: step) { [position] in
          position.released(toward: $0)
        })
      .environment(\.karnakReportsLabelledFrames, true)
      .onAppear {
        reporter.send = { actions.event($0, payload: $1, byUser: $2) }
        position.onScroll = { [reporter] in reporter.moved(to: $0) }
        position.onShown = { current = $0 }
        reporter.moved(to: current)
      }
      .onChange(of: pageTarget, initial: true) {
        reporter.update(handle: pageTarget.handle, keys: pageTarget.keys)
        position.configure(count: pageTarget.keys.count)
      }
      .scrollPosition(id: $scrolledKey)
      .onChange(of: pager.current, initial: true) { follow(Int(pager.current)) }
      .onDisappear { reporter.cancel() }
  }

  /// Turns the pages to `target`, the page the engine holds (``ResolvedPager/current``), when a new tree moves it: a
  /// tab's `set_value` (ADR 0040, D7); the pager starts on it (`init`). A page beside the one shown slides in; one
  /// further away is jumped to, so the pages between are never laid out on the way and their `visible` sources stay
  /// waiting. A swipe the engine has just recorded is already shown, so it moves nothing.
  private func follow(_ target: Int) {
    guard followed != target else { return }
    followed = target
    guard target != current, nodes.indices.contains(target) else { return }
    let key = nodes[target].key.value
    if abs(target - current) == 1 {
      withAnimation { scrolledKey = key }
    } else {
      scrolledKey = key
    }
  }

  /// A peek or a spacing, so pages are no longer a scroll view's length apart.
  private var hasGap: Bool { pager.peek > 0 || pager.spacing > 0 }

  /// The peek the scroll view's length allows, in points (``ResolvedPager/effectivePeek(extent:)``).
  private var peek: CGFloat {
    hasGap ? points(dp: pager.effectivePeek(extent: Float(length))) : 0
  }

  /// A page's length along the axis, once the scroll view is measured.
  private var pageLength: CGFloat { max(length - 2 * peek, 0) }

  /// The distance between two pages, `nil` for the plain paging of a pager with no peek or spacing.
  private var step: CGFloat? {
    hasGap && length > 0 ? pageLength + points(dp: pager.spacing) : nil
  }

  /// What the pager reports to: its trigger, and its pages' keys, which name the page in the report.
  private var pageTarget: PageTarget {
    PageTarget(handle: pager.events[pageChangeEvent], keys: nodes.map(\.key.value))
  }

  @ViewBuilder private var scrollView: some View {
    if pager.vertical {
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: points(dp: pager.spacing)) { pages }.scrollTargetLayout().background { probe }
      }
    } else {
      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(spacing: points(dp: pager.spacing)) { pages }.scrollTargetLayout().background { probe }
      }
    }
  }

  private var pages: some View {
    ForEach(nodes, id: \.key.value) { node in
      pageFrame(NodeView(node: node, placement: .pagerPage).equatable())
        .clipped()
        .accessibilityElement(children: .contain)
        .id(node.key.value)
    }
  }

  /// The page's size: the scroll view's on both axes, or, with a peek, its length less two peeks along the axis.
  @ViewBuilder private func pageFrame(_ page: some View) -> some View {
    if step != nil {
      if pager.vertical {
        page.frame(height: pageLength).containerRelativeFrame(.horizontal)
      } else {
        page.frame(width: pageLength).containerRelativeFrame(.vertical)
      }
    } else {
      page.containerRelativeFrame([.horizontal, .vertical])
    }
  }

  /// Tells the reporter when a finger drags the pages and when it lifts, so a settle is a person's and a page held
  /// halfway is not reported.
  private var probe: some View {
    CarouselScrollProbe(
      rightToLeft: direction == .rightToLeft, vertical: pager.vertical,
      onChange: { position.scrolled($0) },
      onDragStart: {
        position.dragStarted()
        reporter.dragStarted()
      },
      onDragEnd: { reporter.dragEnded() })
  }
}

extension ChildPlacement {
  /// A page of a pager: it is given the page's size on both axes.
  static let pagerPage = ChildPlacement(acceptsProposal: [.horizontal, .vertical])
}

/// The event of a carousel and a pager, as their `actions` name it (`docs/protocol.md`, Component events).
private let pageChangeEvent = "pageChange"
