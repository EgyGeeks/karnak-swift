import SwiftUI
import UIKit

extension EnvironmentValues {
  /// Whether a carousel may use the scroll targets of iOS 17 to snap. A test turns it off to draw the carousel as it is
  /// on iOS 16, the package's floor, where it scrolls freely.
  @Entry var karnakCarouselSnaps = true
}

/// Which item of a carousel is current (`docs/renderer-contract.md`, Display primitives, `carousel`), from where the
/// items that have been built are in the content and how far the scroll view has scrolled. An item's place in the
/// content doesn't change as the carousel scrolls, so what it reported stays true after it is no longer built. It holds
/// no state that draws: it publishes the index only when it changes, so a scroll that stays on an item redraws nothing.
@MainActor
final class CarouselPosition {
  private var frames: [Int: CGRect] = [:]
  private var scroll: CGFloat = 0
  private var overflows = false
  private var atEnd = false
  private var count = 0
  private var rightToLeft = false
  private var contentWidth: CGFloat = 0
  private var origin: CGFloat = 0
  private var current = 0
  /// Receives the current item when it changes.
  var onChange: ((Int) -> Void)?

  /// The carousel's shape: how many items it has (an item that left is forgotten), the width of its content, which a
  /// right-to-left carousel counts from the right edge, and where its first item starts along the content (the leading
  /// padding, unless the scroll view's margins give it).
  func configure(count: Int, rightToLeft: Bool, contentWidth: CGFloat, origin: CGFloat) {
    self.count = count
    self.rightToLeft = rightToLeft
    self.contentWidth = contentWidth
    self.origin = origin
    frames = frames.filter { $0.key < count }
    publish()
  }

  /// Where item `index` is in the content, in the content's own coordinates.
  func record(_ index: Int, frame: CGRect) {
    frames[index] = frame
    publish()
  }

  /// How the scroll view stands: how far it has scrolled, whether the items overflow it, and whether it is at the end.
  func scrolled(_ extent: CarouselScrollExtent) {
    scroll = extent.offset
    overflows = extent.overflows
    atEnd = extent.atEnd
    publish()
  }

  private func publish() {
    let offsets = frames.mapValues {
      (rightToLeft ? contentWidth - $0.maxX : $0.minX) - origin
    }
    let next = currentCarouselItem(
      offsets: offsets, scroll: scroll, count: count, overflows: overflows, atEnd: atEnd)
    guard next != current else { return }
    current = next
    onChange?(next)
  }
}

/// The scroll view's own offset for a distance `logical` along the content from its start edge: the content of a
/// right-to-left carousel starts at the right edge, so it counts back from the maximum.
func carouselPhysicalOffset(logical: CGFloat, maximum: CGFloat, rightToLeft: Bool) -> CGFloat {
  rightToLeft ? maximum - logical : logical
}

/// How far a horizontal scroll view has scrolled, along its content from the start edge, and how far it can.
struct CarouselScrollExtent: Equatable {
  var offset: CGFloat
  var maximum: CGFloat

  var overflows: Bool { maximum > 0.5 }
  var atEnd: Bool { overflows && offset >= maximum - 1 }
}

/// Finds the horizontal scroll view it sits in and reports how far it has scrolled, each time it changes: a zero-size
/// view in the scroll view's background, as ``ScrollProbe`` finds the host's.
struct CarouselScrollProbe: UIViewRepresentable {
  /// Whether the layout runs right to left, where the content starts at the right edge.
  let rightToLeft: Bool
  /// Receives the extent when the scroll view scrolls, resizes or its content changes size.
  let onChange: (CarouselScrollExtent) -> Void

  func makeUIView(context: Context) -> CarouselScrollProbeView {
    let view = CarouselScrollProbeView()
    view.isUserInteractionEnabled = false
    view.isAccessibilityElement = false
    return view
  }

  func updateUIView(_ view: CarouselScrollProbeView, context: Context) {
    view.rightToLeft = rightToLeft
    view.onChange = onChange
    view.report()
  }
}

/// The view behind ``CarouselScrollProbe``.
final class CarouselScrollProbeView: UIView {
  var rightToLeft = false
  var onChange: ((CarouselScrollExtent) -> Void)?
  private var observations: [NSKeyValueObservation] = []
  private var last: CarouselScrollExtent?

  private var scrollView: UIScrollView? {
    var ancestor = superview
    while let view = ancestor {
      if let scroll = view as? UIScrollView { return scroll }
      ancestor = view.superview
    }
    return nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    observations = []
    guard let scroll = scrollView else { return }
    observations = [
      scroll.observe(\.contentOffset) { [weak self] _, _ in self?.reportOnMain() },
      scroll.observe(\.contentSize) { [weak self] _, _ in self?.reportOnMain() },
      scroll.observe(\.bounds) { [weak self] _, _ in self?.reportOnMain() },
    ]
    report()
  }

  /// A key-value observation arrives on the main thread, as UIKit changes the scroll view there.
  private nonisolated func reportOnMain() {
    MainActor.assumeIsolated { report() }
  }

  /// Reads the scroll view again and reports it when it changed.
  func report() {
    guard let scroll = scrollView else { return }
    let insets = scroll.adjustedContentInset
    let maximum = max(
      0, scroll.contentSize.width + insets.left + insets.right - scroll.bounds.width)
    let physical = scroll.contentOffset.x + insets.left
    // Along the content from the start edge: the content of a right-to-left carousel starts at the right edge.
    let extent = CarouselScrollExtent(
      offset: carouselPhysicalOffset(logical: physical, maximum: maximum, rightToLeft: rightToLeft),
      maximum: maximum)
    guard extent != last else { return }
    last = extent
    onChange?(extent)
  }
}
