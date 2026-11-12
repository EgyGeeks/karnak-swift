import SwiftUI

/// Which page of a pager is in view (`docs/renderer-contract.md`, Display primitives, `pager`), read from the scroll
/// view itself, whatever moved it: the page it rests on, which `pageChange` reports once the scroll settles, and the
/// page the dots show. The dots show the page a scroll is heading for: the nearest one while it moves, and the page
/// the paging chose as soon as a finger lifts (``released(toward:)``), held until the scroll gets there, so a fling
/// moves them at its release.
@MainActor
final class PagerPosition {
  private var count = 0
  private var dragged = false
  /// The page the scroll is nearest to now, and the one it was nearest to when the finger went down.
  private var nearest = 0
  /// Where the scroll is now, in pages.
  private var exact: CGFloat = 0
  private var from = 0
  private var target: Int?
  private var shown: Int?
  /// Receives the page the scroll is nearest to each time it moves: the page it rests on once it settles.
  var onScroll: (Int) -> Void = { _ in }
  /// Receives the page the dots show when it changes.
  var onShown: (Int) -> Void = { _ in }

  /// How many pages the pager has.
  func configure(count: Int) {
    self.count = count
  }

  /// The scroll view moved, along the pager's axis from its start edge.
  func scrolled(_ extent: CarouselScrollExtent) {
    guard count > 1, extent.overflows else { return }
    let exact = extent.offset * CGFloat(count - 1) / extent.maximum
    self.exact = exact
    let nearest = clamped(Int(exact.rounded()))
    self.nearest = nearest
    onScroll(nearest)
    if let target {
      // Held until the scroll arrives on it.
      guard arrived(at: target) else { return }
      self.target = nil
    }
    show(nearest)
  }

  /// The paging chose `page`; returns the page the scroll goes to. After a drag, that is where the lifted finger sends
  /// it: one page at most from the page the drag started on, since SwiftUI's paging lets a fast fling carry over
  /// several, and the dots move to it now. SwiftUI asks the paging at other times too (a resize, a layout), which is no
  /// release, and its choice stands.
  @discardableResult
  func released(toward page: Int) -> Int {
    guard dragged else { return page }
    dragged = false
    let turned = clamped(min(max(page, from - 1), from + 1))
    // A finger that lifts where the scroll already rests sends it nowhere: no scroll is coming to clear a hold.
    target = arrived(at: turned) ? nil : turned
    show(turned)
    return turned
  }

  /// A finger went down: what it lifts toward is not known yet, and it turns at most one page from here.
  func dragStarted() {
    dragged = true
    from = nearest
    target = nil
  }

  private func arrived(at page: Int) -> Bool {
    abs(exact - CGFloat(page)) < 0.01
  }

  private func show(_ page: Int) {
    guard page != shown else { return }
    shown = page
    onShown(page)
  }

  private func clamped(_ page: Int) -> Int {
    min(max(page, 0), max(count - 1, 0))
  }
}

/// SwiftUI's paging, with the page it chose handed to `turn`, which says the page the scroll goes to instead. A pager
/// with a peek or a spacing has pages a `step` apart rather than a scroll view's length, which SwiftUI's paging does
/// not know: the page is then the one nearest where the scroll would come to rest. A scroll target's rectangle starts
/// where the first page rests, inside the content's margin (the peek), so page `n` rests at `n * step`.
struct PagerTargetBehavior: ScrollTargetBehavior {
  /// The pages run top to bottom.
  let vertical: Bool
  /// The distance between two pages along the axis; `nil` for the plain paging of pages a scroll view's length apart.
  var step: CGFloat?
  /// Receives the index of the page the paging chose and returns the one to go to.
  let turn: @MainActor (Int) -> Int

  func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
    if step == nil {
      PagingScrollTargetBehavior.paging.updateTarget(&target, context: context)
    }
    let length = step ?? (vertical ? context.containerSize.height : context.containerSize.width)
    guard length > 0 else { return }
    let start = vertical ? target.rect.minY : target.rect.minX
    let chosen = Self.page(startingAt: start, length: length)
    let page = MainActor.assumeIsolated { turn(chosen) }
    guard page != chosen || step != nil else { return }
    let rest = Self.rest(of: page, length: length)
    if vertical {
      target.rect.origin.y = rest
    } else {
      target.rect.origin.x = rest
    }
  }

  /// The page a scroll proposed to rest at `start` is nearest, pages `length` apart from 0.
  static func page(startingAt start: CGFloat, length: CGFloat) -> Int {
    Int((start / length).rounded())
  }

  /// Where a scroll rests on `page`.
  static func rest(of page: Int, length: CGFloat) -> CGFloat {
    CGFloat(page) * length
  }
}
